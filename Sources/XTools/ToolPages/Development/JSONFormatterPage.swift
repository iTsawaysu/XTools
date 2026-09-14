import XToolsCore
import SwiftUI

@MainActor
final class JSONFormatterToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<JSONFormatterToolWorkspaceModel>(toolID: "json-formatter") { preferences in
        JSONFormatterToolWorkspaceModel(preferences: preferences)
    }

    enum IndentOption: Int, CaseIterable, Sendable {
        case two = 2
        case four = 4

        var id: String { String(rawValue) }
        var label: String { "\(rawValue) 空格" }
    }

    @Published var input = ""
    @Published var indentOption: IndentOption {
        didSet { preferences.set(indentOption.id, for: TextDevelopmentToolPreferenceKeys.jsonIndent) }
    }

    let execution = IndexFormatExecutionSession()
    private let preferences: ToolPreferenceStore
    /// Session-scoped: the entry example seeds once per tool session and is
    /// never persisted or re-seeded after an explicit 清空.
    private(set) var hasSeededEntryExample = false

    var output: String { execution.binding.output }
    var error: String? { execution.binding.error }
    var warning: String? { execution.binding.warning }

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        indentOption = IndentOption(rawValue: Int(preferences.value(for: TextDevelopmentToolPreferenceKeys.jsonIndent)) ?? 4) ?? .four
    }

    func clear() {
        execution.invalidate()
        input = ""
    }

    /// Seeds the prototype entry example on first appearance; returns whether
    /// seeding happened so the page can format the first frame.
    func seedEntryExampleIfNeeded() -> Bool {
        guard !hasSeededEntryExample, input.isEmpty else { return false }
        hasSeededEntryExample = true
        input = Self.entryExample
        return true
    }

    static let entryExample = #"{"name":"XTools","version":"3.0","tools":36,"tags":["dev","macos"],"config":{"theme":"system","density":"compact"}}"#
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
        let indentWidth: Int
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
                    IndexSegmentedControl(
                        items: JSONFormatterToolWorkspaceModel.IndentOption.allCases.map { ($0.id, $0.label) },
                        selection: indentSelection,
                        density: .compact
                    )
                }
            )
        }
        .onAppear {
            if workspace.seedEntryExampleIfNeeded() {
                format()
            }
        }
    }

    private var indentSelection: Binding<String> {
        Binding(
            get: { workspace.indentOption.id },
            set: { value in
                workspace.indentOption = value == JSONFormatterToolWorkspaceModel.IndentOption.four.id ? .four : .two
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
        guard !workspace.input.isEmpty else {
            execution.invalidate()
            return
        }

        formatAttempt += 1
        let snapshot = Snapshot(
            input: workspace.input,
            indentWidth: workspace.indentOption.rawValue
        )
        execution.schedule(snapshot: snapshot, delay: .zero) { snapshot in
            FormatRunner.run(snapshot.input) { value -> JSONFormatting.FormattingResult in
                try JSONFormatting.formatResult(
                    value,
                    sortKeys: false,
                    indentWidth: snapshot.indentWidth
                )
            }
            .binding(text: { $0.text }, warning: { $0.warning })
        }
    }
}
