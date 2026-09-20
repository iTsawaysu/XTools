import XToolsCore
import SwiftUI

@MainActor
final class XMLFormatterToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<XMLFormatterToolWorkspaceModel>(toolID: "xml-formatter") { preferences in
        XMLFormatterToolWorkspaceModel(preferences: preferences)
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

struct IndexXMLFormatPage: View {
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
    @State private var formatAttempt = 0

    var body: some View {
        IndexPage("XML 格式化", subtitle: "格式化与压缩 XML，支持 2/4 空格缩进与 Minify。", workspaceSemantic: .structuredEditorTransform) {
            IndexFormatWorkbench(
                inputTitle: "输入",
                outputTitle: "输出",
                input: $workspace.input,
                output: execution.binding.output,
                inputPlaceholder: #"<root><item id="1">a</item></root>"#,
                diagnostic: execution.binding.error ?? execution.binding.warning,
                diagnosticTone: execution.binding.error == nil ? .warning : .error,
                diagnosticDetail: execution.diagnostic,
                formatAttempt: formatAttempt,
                outputLineNumbers: true,
                outputSyntax: .xml,
                isRunning: execution.isRunning,
                isOutputFresh: execution.isOutputFresh,
                clearDisabled: workspace.input.isEmpty && execution.binding.output.isEmpty && execution.binding.error == nil && execution.binding.warning == nil,
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

        formatAttempt += 1
        let indentWidth = workspace.formatMode == .four ? 4 : 2
        let minify = workspace.formatMode == .compact
        let snapshot = (input: workspace.input, indentWidth: indentWidth, minify: minify)
        execution.schedule(snapshot: snapshot, delay: .zero) { snapshot in
            FormatRunner.run(snapshot.input) {
                try XMLFormatting.format($0, indentWidth: snapshot.indentWidth, minify: snapshot.minify)
            }
            .binding(text: { $0 })
        }
    }
}
