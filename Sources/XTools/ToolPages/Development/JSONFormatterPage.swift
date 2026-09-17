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
            case .two: return "2 空格"
            case .four: return "4 空格"
            case .compact: return "压缩"
            }
        }
    }

    enum IndentOption: Int, CaseIterable, Sendable {
        case two = 2
        case four = 4

        var id: String { String(rawValue) }
        var label: String { "\(rawValue) 空格" }
    }

    var indentOption: IndentOption {
        get {
            switch formatMode {
            case .two: return .two
            case .four, .compact: return .four
            }
        }
        set {
            formatMode = newValue == .two ? .two : .four
        }
    }

    @Published var input = ""
    @Published var formatMode: FormatMode {
        didSet { preferences.set(formatMode.id, for: TextDevelopmentToolPreferenceKeys.jsonIndent) }
    }
    @Published var sortKeys: Bool = false

    let execution = IndexFormatExecutionSession()
    private let preferences: ToolPreferenceStore

    var output: String { execution.binding.output }
    var error: String? { execution.binding.error }
    var warning: String? { execution.binding.warning }

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        let saved = preferences.value(for: TextDevelopmentToolPreferenceKeys.jsonIndent)
        formatMode = FormatMode(rawValue: saved) ?? .four
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
/// diagnostic, and 复制 · 清空 · 格式化(⌘↩). Formatting is explicit — button or
/// Command-Return; indent applies at the next format. A failed format tints
/// the panel outline, rings it, and shakes once per attempt.
private struct IndexJSONFormatterWorkspaceContent: View {
    private static let maxHighlightedOutputCharacters = 200_000

    private struct Snapshot: Sendable {
        let input: String
        let mode: JSONFormatterToolWorkspaceModel.FormatMode
        let sortKeys: Bool
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
                formatAttempt: formatAttempt,
                outputLineNumbers: true,
                outputColorize: outputColorizer,
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
                        IndexOptionSwitch(title: "Key 排序", style: .embeddedSwitch, isOn: $workspace.sortKeys)
                    }
                }
            )
        }
        .onChange(of: workspace.sortKeys) { _ in
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

    private var outputColorizer: ((String) -> AttributedString)? {
        if execution.binding.output.count > Self.maxHighlightedOutputCharacters {
            return nil
        }
        return { JSONSyntaxHighlighter.highlight(line: $0) }
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
            sortKeys: workspace.sortKeys
        )
        execution.schedule(snapshot: snapshot, delay: .zero) { snapshot in
            FormatRunner.run(snapshot.input) { value -> JSONFormatting.FormattingResult in
                switch snapshot.mode {
                case .two:
                    return try JSONFormatting.formatResult(
                        value,
                        sortKeys: snapshot.sortKeys,
                        indentWidth: 2
                    )
                case .four:
                    return try JSONFormatting.formatResult(
                        value,
                        sortKeys: snapshot.sortKeys,
                        indentWidth: 4
                    )
                case .compact:
                    return try JSONFormatting.minifyResult(
                        value,
                        sortKeys: snapshot.sortKeys
                    )
                }
            }
            .binding(text: { $0.text }, warning: { $0.warning })
        }
    }
}
