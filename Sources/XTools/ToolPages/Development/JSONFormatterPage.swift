import XToolsCore
import SwiftUI

@MainActor
final class JSONFormatterToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<JSONFormatterToolWorkspaceModel>(toolID: "json-formatter") { preferences in
        JSONFormatterToolWorkspaceModel(preferences: preferences)
    }

    enum FormatMode: String, CaseIterable, Sendable {
        case two = "2"
        case four = "4"
        case compact = "compact"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .two: return "2"
            case .four: return "4"
            case .compact: return "压缩"
            }
        }
    }

    @Published var input = "" {
        didSet {
            guard input != oldValue else { return }
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
    }

    func clear() {
        execution.invalidate()
        input = ""
    }
}

struct IndexJSONFormatterPage: View {
    var body: some View {
        ToolWorkspaceHost(key: JSONFormatterToolWorkspaceModel.key) { workspace, _ in
            IndexJSONFormatterWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

/// Prototype v3 (Clay 收敛) body: one framed workbench whose toolbar carries
/// STDIN/STDOUT identities, the 2/4-space indent control, the inline
/// diagnostic, and 清空 · 复制 · 格式化(⌘↩). Formatting is explicit — button or
/// Command-Return; indent applies at the next format. A failed format tints
/// the panel outline, rings it, and shakes once per attempt.
private struct IndexJSONFormatterWorkspaceContent: View {
    private struct Snapshot: Sendable {
        let input: String
        let mode: JSONFormatterToolWorkspaceModel.FormatMode
        let sortKeys: Bool
        let unescape: Bool
        let escape: Bool
    }

    @ObservedObject var workspace: JSONFormatterToolWorkspaceModel
    @ObservedObject var execution: IndexFormatExecutionSession
    @State private var formatAttempt = 0

    var body: some View {
        IndexPage("JSON 格式化", subtitle: "格式化、压缩和验证 JSON，支持自定义选项。", workspaceSemantic: .structuredEditorTransform) {
            IndexFormatWorkbench(
                inputTitle: "输入",
                outputTitle: "输出",
                input: $workspace.input,
                output: execution.binding.output,
                inputPlaceholder: #"{"name":"XTools","tags":["dev","macos"]}"#,
                diagnostic: execution.binding.error ?? execution.binding.warning,
                diagnosticTone: execution.binding.error == nil ? .warning : .error,
                diagnosticDetail: execution.diagnostic,
                formatAttempt: formatAttempt,
                outputLineNumbers: true,
                outputSyntax: .json,
                isRunning: execution.isRunning,
                isOutputFresh: execution.isOutputFresh,
                clearDisabled: workspace.input.isEmpty && execution.binding.output.isEmpty && execution.binding.error == nil && execution.binding.warning == nil,
                onFormat: format,
                onClear: workspace.clear,
                leadingControl: {
                    HStack(spacing: 6) {
                        IndexSegmentedControl(
                            items: JSONFormatterToolWorkspaceModel.FormatMode.allCases.map { ($0.id, $0.label) },
                            selection: formatModeSelection,
                            density: .compact
                        )
                        IndexOptionSwitch(
                            title: "去转义",
                            help: "去除转义",
                            style: .button,
                            isOn: unescapeSelection
                        )
                        IndexOptionSwitch(
                            title: "转义",
                            help: "转义为字符串",
                            style: .button,
                            isOn: escapeSelection
                        )
                    }
                },
                outputControl: {
                    // Key 排序作用于输出结果，放输出侧；也为输入侧工具栏
                    // 留出 680pt 标准宽度预算。
                    IndexOptionSwitch(title: "Key 排序", style: .button, isOn: $workspace.sortKeys)
                }
            )
        }
        .onChange(of: workspace.sortKeys) { _ in
            if !execution.binding.output.isEmpty {
                format()
            }
        }
        .onChange(of: workspace.unescape) { _ in
            if !execution.binding.output.isEmpty {
                format()
            }
        }
        .onChange(of: workspace.escape) { _ in
            if !execution.binding.output.isEmpty {
                format()
            }
        }
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

        formatAttempt += 1
        let snapshot = Snapshot(
            input: workspace.input,
            mode: workspace.formatMode,
            sortKeys: workspace.sortKeys,
            unescape: workspace.unescape,
            escape: workspace.escape
        )
        execution.schedule(snapshot: snapshot, delay: .zero) { snapshot in
            var textToFormat = snapshot.input
            if snapshot.unescape {
                textToFormat = JSONFormatting.unescapeJSON(textToFormat)
            }
            return FormatRunner.run(textToFormat) { value -> JSONFormatting.FormattingResult in
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
                    let escaped = JSONFormatting.escapeJSON(formattedResult.text)
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
