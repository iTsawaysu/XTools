import XToolsCore
import XToolsDesign
import SwiftUI

@MainActor
final class JSONFormatterToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<JSONFormatterToolWorkspaceModel>(toolID: "formatter", slot: "json") { preferences in
        JSONFormatterToolWorkspaceModel(preferences: preferences)
    }

    typealias FormatMode = FormatterIndentMode

    @Published var input = "" {
        didSet {
            guard !JSONExactTextIdentity.isExactlyEqual(input, oldValue) else { return }
            execution.sourceDidChange()
        }
    }
    @Published var escape: Bool = false {
        didSet {
            guard escape != oldValue else { return }
            execution.sourceDidChange()
            if escape && unescape { unescape = false }
            preferences.set(escape, for: TextDevelopmentToolPreferenceKeys.jsonEscape)
        }
    }
    @Published var unescape: Bool = false {
        didSet {
            guard unescape != oldValue else { return }
            execution.sourceDidChange()
            if unescape && escape { escape = false }
            preferences.set(unescape, for: TextDevelopmentToolPreferenceKeys.jsonUnescape)
        }
    }
    @Published var formatMode: FormatMode {
        didSet {
            guard formatMode != oldValue else { return }
            execution.sourceDidChange()
            preferences.set(formatMode.id, for: TextDevelopmentToolPreferenceKeys.jsonIndent)
        }
    }
    @Published var sortKeys: Bool = false {
        didSet {
            guard sortKeys != oldValue else { return }
            execution.sourceDidChange()
            preferences.set(sortKeys, for: TextDevelopmentToolPreferenceKeys.jsonSortKeys)
        }
    }

    let execution = IndexFormatExecutionSession()
    private let preferences: ToolPreferenceStore

    var output: String { execution.binding.output }
    var error: String? { execution.binding.error }
    var warning: String? { execution.binding.warning }

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        let saved = preferences.value(for: TextDevelopmentToolPreferenceKeys.jsonIndent)
        formatMode = FormatMode(rawValue: saved) ?? .four
        unescape = preferences.value(for: TextDevelopmentToolPreferenceKeys.jsonUnescape)
        escape = preferences.value(for: TextDevelopmentToolPreferenceKeys.jsonEscape)
        sortKeys = preferences.value(for: TextDevelopmentToolPreferenceKeys.jsonSortKeys)
    }

    func clear() {
        execution.invalidate()
        input = ""
    }
}

/// 「格式化」Hub 的 JSON 分段。workspace key 沿用 toolID "json-formatter"，
/// 输入与执行状态由 ToolWorkspaceRepository 保活，分段切换不丢。
struct IndexJSONFormatterSegment: View {
    var body: some View {
        ToolWorkspaceHost(key: JSONFormatterToolWorkspaceModel.key) { workspace, _ in
            IndexJSONFormatterWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

/// Prototype v3 (Clay 收敛) body, page-rollout B2 统一壳形态：即时参数
/// （缩进分段 + 处理选项菜单）进弹性参数区，清空归输入 pane 尾 ActionBar、
/// 复制归输出 pane 尾 ActionBar（⇧⌘C 由 IOPair 代理持有、页面只在 IOPair
/// 声明一次），显式格式化走壳级 primaryAction（⌘↩）；运行中/结果过期状态
/// 由输出 pane 头附件承载，诊断（错误/警告/拖入拒判）走 preference 单轨到
/// 纸顶 banner（详情 popover 与「定位」跳转随载荷保留）。Formatting is
/// explicit — button or Command-Return; indent applies at the next format.
private struct IndexJSONFormatterWorkspaceContent: View {
    private struct Snapshot: Sendable {
        let input: String
        let mode: JSONFormatterToolWorkspaceModel.FormatMode
        let sortKeys: Bool
        let unescape: Bool
        let escape: Bool
    }

    /// 输出 pane 标题（AX 过期态插值与 pane 头同源）。
    private let outputTitle = "输出"

    @ObservedObject var workspace: JSONFormatterToolWorkspaceModel
    @ObservedObject var execution: IndexFormatExecutionSession
    /// 壳层「定位」请求（banner「定位」钮 → 环境值递增）：作为输入编辑器的
    /// 一次性导航 token 消费（0 = 仅描边不跳转）。
    @Environment(\.workbenchDiagnosticLocateRequest) private var diagnosticNavigationToken
    /// 输入 pane 的文本文件拖入会话（旧壳能力随行）。
    @StateObject private var droppedFile = IndexDroppedTextFile()
    /// 输出呼吸代际：显式格式化落地新鲜、非空、无错结果时 +1，输出 pane
    /// accent 描边脉冲一次（toolOutputBreath）。
    @State private var outputBreathGeneration = 0

    private var diagnosticText: String? {
        execution.binding.error ?? execution.binding.warning
    }

    private var diagnosticTone: ToolFeedbackTone {
        execution.binding.error == nil ? .warning : .error
    }

    /// 旧壳 hasDiagnostic 门控：运行中/结果过期时不投递诊断（banner 让位
    /// 行内状态，错误描边同步静默）。
    private var showsDiagnostic: Bool {
        !execution.isRunning && execution.isOutputFresh && diagnosticText != nil
    }

    private var hasStaleResult: Bool {
        !execution.isOutputFresh && (!execution.binding.output.isEmpty || diagnosticText != nil)
    }

    /// 旧壳 formatButton 门控：运行中或输入为空白时禁用主操作。
    private var formatEnabled: Bool {
        !execution.isRunning
            && !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        WorkbenchSurface(
            title: nil,
            primaryAction: WorkbenchPrimaryAction(
                title: "格式化",
                help: "格式化（⌘↩）",
                enabled: formatEnabled,
                perform: format
            ),
            shape: .inputOutput,
            parameters: { parameterFlow },
            content: {
                WorkbenchIOPair(
                    leadingTitle: "输入",
                    trailingTitle: outputTitle,
                    leadingActions: [
                        .clear(
                            enabled: !(workspace.input.isEmpty && !execution.hasClearableContent),
                            onPerform: workspace.clear
                        )
                    ],
                    trailingActions: [
                        .copy(text: execution.binding.output, help: "复制全部 (⇧⌘C)", enabled: execution.isOutputFresh)
                    ],
                    leadingAccessory: { stdinBadge },
                    leading: { inputPane },
                    trailingAccessory: { stdoutCluster },
                    trailing: { outputPane }
                )
                // 诊断单轨：拖入拒判优先（旧壳状态槽同序），其后是错误/警告；
                // 详情与「定位」标记随载荷透传给纸顶 banner（定位 token 由
                // 壳经环境下发，输入编辑器消费）。
                .indexWorkspaceDiagnostic(
                    droppedFile.rejection?.message ?? (showsDiagnostic ? diagnosticText : nil),
                    tone: droppedFile.rejection == nil ? diagnosticTone : .error,
                    detail: droppedFile.rejection == nil && showsDiagnostic ? execution.diagnostic : nil,
                    isLocatable: showsDiagnostic && execution.diagnosticMarker != nil
                )
            }
        )
        .onChange(of: workspace.sortKeys) {
            if !execution.binding.output.isEmpty {
                format()
            }
        }
        .onChange(of: workspace.unescape) {
            if !execution.binding.output.isEmpty {
                format()
            }
        }
        .onChange(of: workspace.escape) {
            if !execution.binding.output.isEmpty {
                format()
            }
        }
        .onChange(of: execution.isOutputFresh) {
            guard execution.isOutputFresh, !execution.binding.output.isEmpty, execution.binding.error == nil else {
                return
            }
            outputBreathGeneration += 1
        }
    }

    // MARK: - 弹性参数区

    /// 缩进分段与「处理选项 ▾」菜单（转义/去转义/Key 排序）：即时参数进
    /// 参数区，互斥仍由 escapeSelection/unescapeSelection 保证，状态变化
    /// 沿工作区 didSet 自动重跑格式化。
    private var parameterFlow: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterGroup {
                WorkbenchParameterItem {
                    IndexSegmentedControl(
                        items: JSONFormatterToolWorkspaceModel.FormatMode.allCases.map { ($0.id, $0.label) },
                        selection: formatModeSelection,
                        density: .compact
                    )
                }
                WorkbenchParameterItem {
                    IndexOptionsMenu(
                        menuTitle: "处理选项",
                        triggerTitle: "处理选项",
                        options: [
                            IndexOptionsMenuOption(
                                id: "escape",
                                title: "转义",
                                help: "转义为字符串",
                                isOn: escapeSelection
                            ),
                            IndexOptionsMenuOption(
                                id: "unescape",
                                title: "去转义",
                                help: "去除转义",
                                isOn: unescapeSelection
                            ),
                            IndexOptionsMenuOption(
                                id: "sort-keys",
                                title: "Key 排序",
                                help: "按字典序排序所有键",
                                isOn: $workspace.sortKeys
                            ),
                        ],
                        dividersBefore: ["sort-keys"]
                    )
                }
            }
        }
    }

    // MARK: - 内容区 pane

    private var stdinBadge: some View {
        IndexBadge("STDIN", tone: .neutral, isCapsule: true)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// 输出 pane 头附件：STDOUT 徽章 + 运行中/结果过期行内状态。
    private var stdoutCluster: some View {
        HStack(spacing: ToolMetrics.Spacing.fine) {
            IndexBadge("STDOUT", tone: .neutral, isCapsule: true)
                .fixedSize(horizontal: true, vertical: false)
            outputStatus
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var outputStatus: some View {
        if execution.isRunning {
            IndexInlineDiagnosticStatus(message: "正在格式化…", showsSpinner: true)
        } else if hasStaleResult {
            IndexInlineDiagnosticStatus(message: "输入已更改，请重新格式化。")
        }
    }

    /// 输入 pane 内容：受控 AppKit 编辑器填满 pane（行号槽与语法标记随行），
    /// 文本文件拖入接收后触发一次显式格式化（旧壳 onFormat?() 等价）。
    private var inputPane: some View {
        IndexWorkspaceTextArea(
            placeholder: #"{"name":"XTools","tags":["dev","macos"]}"#,
            text: $workspace.input,
            fillsHeight: true,
            autoFocus: true,
            diagnosticMarker: showsDiagnostic ? execution.diagnosticMarker : nil,
            diagnosticNavigationToken: diagnosticNavigationToken,
            embedsFlat: true,
            lineNumbers: true,
            onFileDrop: { content in
                workspace.input = content
                format()
            },
            droppedFile: droppedFile,
            workspaceSemantic: .structuredEditorTransform
        )
        .workbenchInputDropSupport(text: $workspace.input, droppedFile: droppedFile)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("输入")
        // 焦点契约（阶段③ C3）：页面首个输入 = 输入编辑器。
        .workbenchFocusTarget()
    }

    private var outputPane: some View {
        IndexOutputSurface(
            text: execution.binding.output,
            lineNumbers: true,
            syntax: .json,
            fillsHeight: true,
            embedsFlat: true
        )
        .toolOutputBreath(generation: outputBreathGeneration)
        .accessibilityLabel(hasStaleResult ? "\(outputTitle)，结果已过期" : outputTitle)
    }

    private var formatModeSelection: Binding<String> {
        Binding(
            get: { workspace.formatMode.id },
            set: { value in
                guard let newMode = JSONFormatterToolWorkspaceModel.FormatMode(rawValue: value) else { return }
                workspace.formatMode = newMode
                if !execution.binding.output.isEmpty {
                    format()
                }
            }
        )
    }

    /// 去除转义与转义为字符串语义互斥：两个联动开关，点亮一个自动熄灭
    /// 另一个，再次点按可取消回到「不处理」。互斥由 UI 层保证，底层两
    /// 个布尔值与格式化管线保持不变。
    private var unescapeSelection: Binding<Bool> {
        Binding(
            get: { workspace.unescape },
            set: { on in
                workspace.unescape = on
                if on { workspace.escape = false }
            }
        )
    }

    private var escapeSelection: Binding<Bool> {
        Binding(
            get: { workspace.escape },
            set: { on in
                workspace.escape = on
                if on { workspace.unescape = false }
            }
        )
    }

    private func format() {
        guard !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            execution.invalidate()
            return
        }

        let snapshot = Snapshot(
            input: workspace.input,
            mode: workspace.formatMode,
            sortKeys: workspace.sortKeys,
            unescape: workspace.unescape,
            escape: workspace.escape
        )
        execution.schedule(snapshot: snapshot, sourceText: snapshot.unescape ? nil : snapshot.input, delay: .zero, cooperativeCancellation: true) { snapshot in
            return FormatRunner.run(snapshot.input) { raw -> JSONFormatting.FormattingResult in
                let value = snapshot.unescape ? try JSONFormatting.unescapeJSONChecked(raw) : raw
                // Unescaping may produce empty/whitespace text. Preserve the
                // original quiet-empty behavior after this transformation.
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return JSONFormatting.FormattingResult(text: "")
                }
                let formattedResult: JSONFormatting.FormattingResult
                switch snapshot.mode {
                case .two:
                    formattedResult = try JSONFormatting.formatResult(
                        value,
                        sortKeys: snapshot.sortKeys,
                        indentWidth: 2
                    )
                case .four:
                    formattedResult = try JSONFormatting.formatResult(
                        value,
                        sortKeys: snapshot.sortKeys,
                        indentWidth: 4
                    )
                case .compact:
                    formattedResult = try JSONFormatting.minifyResult(
                        value,
                        sortKeys: snapshot.sortKeys
                    )
                }

                if snapshot.escape {
                    let escaped = try JSONFormatting.escapeJSONChecked(formattedResult.text)
                    return JSONFormatting.FormattingResult(
                        text: escaped,
                        warning: formattedResult.warning,
                        duplicateKeys: formattedResult.duplicateKeys
                    )
                }
                return formattedResult
            }
            .binding(text: { $0.text }, warning: { $0.warning })
        }
    }
}
