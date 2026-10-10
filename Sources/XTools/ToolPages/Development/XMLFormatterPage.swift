import XToolsCore
import SwiftUI

@MainActor
final class XMLFormatterToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<XMLFormatterToolWorkspaceModel>(toolID: "formatter", slot: "xml") { preferences in
        XMLFormatterToolWorkspaceModel(preferences: preferences)
    }

    typealias FormatMode = FormatterIndentMode

    @Published var input = "" {
        didSet {
            guard !JSONExactTextIdentity.isExactlyEqual(input, oldValue) else { return }
            execution.sourceDidChange()
        }
    }
    @Published var formatMode: FormatMode {
        didSet {
            guard formatMode != oldValue else { return }
            execution.sourceDidChange()
            preferences.set(formatMode.id, for: TextDevelopmentToolPreferenceKeys.xmlIndent)
        }
    }

    let execution = IndexFormatExecutionSession()
    private let preferences: ToolPreferenceStore

    var output: String { execution.binding.output }
    var error: String? { execution.binding.error }
    var warning: String? { execution.binding.warning }

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        let saved = preferences.value(for: TextDevelopmentToolPreferenceKeys.xmlIndent)
        formatMode = FormatMode(rawValue: saved) ?? .two
    }

    func clear() {
        execution.invalidate()
        input = ""
    }
}

/// 「格式化」Hub 的 XML 分段。workspace key 沿用 toolID "xml-formatter"，
/// 输入与执行状态由 ToolWorkspaceRepository 保活，分段切换不丢。
struct IndexXMLFormatterSegment: View {
    var body: some View {
        ToolWorkspaceHost(key: XMLFormatterToolWorkspaceModel.key) { workspace, _ in
            IndexXMLFormatWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

private struct IndexXMLFormatWorkspaceContent: View {
    @ObservedObject var workspace: XMLFormatterToolWorkspaceModel
    @ObservedObject var execution: IndexFormatExecutionSession

    var body: some View {
        IndexFormatWorkbench(
            inputTitle: "输入",
            outputTitle: "输出",
            input: $workspace.input,
            output: execution.binding.output,
            inputPlaceholder: #"<root><item id="1">a</item></root>"#,
            diagnostic: execution.binding.error ?? execution.binding.warning,
            diagnosticTone: execution.binding.error == nil ? .warning : .error,
            diagnosticDetail: execution.diagnostic,
            diagnosticMarker: execution.diagnosticMarker,
            outputLineNumbers: true,
            outputSyntax: .xml,
            isRunning: execution.isRunning,
            isOutputFresh: execution.isOutputFresh,
            clearDisabled: workspace.input.isEmpty && !execution.hasClearableContent,
            onFormat: format,
            onClear: workspace.clear,
            leadingControl: {
                IndexSegmentedControl(
                    items: XMLFormatterToolWorkspaceModel.FormatMode.allCases.map { ($0.id, $0.label) },
                    selection: formatModeSelection,
                    density: .compact
                )
            }
        )
    }

    private var formatModeSelection: Binding<String> {
        Binding(
            get: { workspace.formatMode.id },
            set: { value in
                guard let newMode = XMLFormatterToolWorkspaceModel.FormatMode(rawValue: value) else { return }
                workspace.formatMode = newMode
                if !execution.binding.output.isEmpty {
                    format()
                }
            }
        )
    }

    private func format() {
        guard !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            execution.invalidate()
            return
        }

        let indentWidth = workspace.formatMode == .four ? 4 : 2
        let minify = workspace.formatMode == .compact
        let snapshot = (input: workspace.input, indentWidth: indentWidth, minify: minify)
        execution.schedule(snapshot: snapshot, sourceText: snapshot.input, delay: .zero, cooperativeCancellation: true) { snapshot in
            FormatRunner.run(snapshot.input) {
                try XMLFormatting.format($0, indentWidth: snapshot.indentWidth, minify: snapshot.minify)
            }
            .binding(text: { $0 })
        }
    }
}
