import XToolsCore
import SwiftUI
import XToolsDesign

@MainActor
final class YAMLPrettifyToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<YAMLPrettifyToolWorkspaceModel>(toolID: "formatter", slot: "yaml") { preferences in
        YAMLPrettifyToolWorkspaceModel(preferences: preferences)
    }

    @Published var input = "" {
        didSet {
            guard !JSONExactTextIdentity.isExactlyEqual(input, oldValue) else { return }
            execution.sourceDidChange()
        }
    }
    @Published var sortKeys: Bool = false {
        didSet {
            guard sortKeys != oldValue else { return }
            execution.sourceDidChange()
            preferences.set(sortKeys, for: TextDevelopmentToolPreferenceKeys.yamlSortKeys)
        }
    }

    let execution = IndexFormatExecutionSession()
    private let preferences: ToolPreferenceStore

    var output: String { execution.binding.output }
    var error: String? { execution.binding.error }
    var warning: String? { execution.binding.warning }

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        sortKeys = preferences.value(for: TextDevelopmentToolPreferenceKeys.yamlSortKeys)
    }

    func clear() {
        execution.invalidate()
        input = ""
    }
}

/// 「格式化」Hub 的 YAML 分段。workspace key 沿用 toolID "yaml-prettify"，
/// 输入与执行状态由 ToolWorkspaceRepository 保活，分段切换不丢。
struct IndexYAMLPrettifySegment: View {
    var body: some View {
        ToolWorkspaceHost(key: YAMLPrettifyToolWorkspaceModel.key) { workspace, _ in
            IndexYAMLPrettifyWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

private struct IndexYAMLPrettifyWorkspaceContent: View {
    /// 输出 pane 标题（AX 过期态插值与 pane 头同源）。
    private let outputTitle = "输出"

    @ObservedObject var workspace: YAMLPrettifyToolWorkspaceModel
    @ObservedObject var execution: IndexFormatExecutionSession
    /// 壳层「定位」请求（banner「定位」钮 → 环境值递增）：作为输入编辑器的
    /// 一次性导航 token 消费（0 = 仅描边不跳转）。
    @Environment(\.workbenchDiagnosticLocateRequest) private var diagnosticNavigationToken
    /// 输入 pane 的文本文件拖入会话（旧壳能力随行）。
    @StateObject private var droppedFile = IndexDroppedTextFile()
    /// 输出呼吸代际：显式格式化落地新鲜、非空、无错结果时 +1。
    @State private var outputBreathGeneration = 0

    private var diagnosticText: String? {
        execution.binding.error ?? execution.binding.warning
    }

    private var diagnosticTone: ToolFeedbackTone {
        execution.binding.error == nil ? .warning : .error
    }

    /// 旧壳 hasDiagnostic 门控：运行中/结果过期时不投递诊断。
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
                // 诊断单轨：拖入拒判优先，其后是错误/警告；详情与「定位」
                // 标记随载荷透传给纸顶 banner。
                .indexWorkspaceDiagnostic(
                    droppedFile.rejection?.message ?? (showsDiagnostic ? diagnosticText : nil),
                    tone: droppedFile.rejection == nil ? diagnosticTone : .error,
                    detail: droppedFile.rejection == nil && showsDiagnostic ? execution.diagnostic : nil,
                    isLocatable: showsDiagnostic && execution.diagnosticMarker != nil
                )
            }
        )
        .onChange(of: workspace.sortKeys) {
            if !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

    /// Key 排序开关（即时参数，点亮即重跑）。
    private var parameterFlow: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterGroup {
                WorkbenchParameterItem {
                    IndexOptionSwitch(title: "Key 排序", style: .button, isOn: $workspace.sortKeys)
                }
            }
        }
    }

    // MARK: - 内容区 pane

    private var stdinBadge: some View {
        IndexBadge("STDIN", tone: .neutral, isCapsule: true)
            .fixedSize(horizontal: true, vertical: false)
    }

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

    private var inputPane: some View {
        IndexWorkspaceTextArea(
            placeholder: "key:   value\nlist:\n   - a\n   - b",
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
            syntax: .yaml,
            fillsHeight: true,
            embedsFlat: true
        )
        .toolOutputBreath(generation: outputBreathGeneration)
        .accessibilityLabel(hasStaleResult ? "\(outputTitle)，结果已过期" : outputTitle)
    }

    private func format() {
        guard !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            execution.invalidate()
            return
        }

        let options = YAMLPrettifier.Options(
            indent: 2,
            sortKeys: workspace.sortKeys
        )
        let snapshot = (input: workspace.input, options: options)
        execution.schedule(snapshot: snapshot, sourceText: snapshot.input, delay: .zero, cooperativeCancellation: true) { snapshot in
            FormatRunner.run(snapshot.input) {
                try YAMLPrettifier.formatValidated($0, options: snapshot.options)
            }
            .binding(text: { $0 })
        }
    }
}
