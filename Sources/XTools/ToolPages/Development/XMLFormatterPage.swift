import XToolsCore
import SwiftUI

struct IndexXMLFormatPage: View {
    private static let key = ToolWorkspaceKey<IndexTextTransformWorkspaceModel>(toolID: "xml-formatter") { _ in
        IndexTextTransformWorkspaceModel()
    }

    var body: some View {
        ToolWorkspaceHost(key: Self.key) { workspace, _ in
            IndexXMLFormatWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

private struct IndexXMLFormatWorkspaceContent: View {
    private static let maxHighlightedOutputCharacters = 200_000

    @ObservedObject var workspace: IndexTextTransformWorkspaceModel
    @ObservedObject var execution: IndexFormatExecutionSession
    @State private var formatAttempt = 0

    var body: some View {
        IndexPage("XML 格式化", subtitle: "格式化 XML，自动缩进。", workspaceSemantic: .structuredEditorTransform) {
            IndexFormatWorkbench<EmptyView>(
                inputTitle: "输入",
                outputTitle: "输出",
                input: $workspace.input,
                output: execution.binding.output,
                inputPlaceholder: #"<root><item id="1">a</item></root>"#,
                diagnostic: execution.binding.error ?? execution.binding.warning,
                diagnosticTone: execution.binding.error == nil ? .warning : .error,
                formatAttempt: formatAttempt,
                outputLineNumbers: true,
                outputColorize: outputColorizer,
                clearDisabled: workspace.input.isEmpty && execution.binding.output.isEmpty && execution.binding.error == nil && execution.binding.warning == nil,
                onFormat: format,
                onClear: workspace.clear
            )
        }
    }

    private var outputColorizer: ((String) -> AttributedString)? {
        if execution.binding.output.count > Self.maxHighlightedOutputCharacters {
            return nil
        }
        return { StructuredSyntaxHighlighter.xml(line: $0) }
    }

    private func format() {
        guard !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            execution.invalidate()
            return
        }

        formatAttempt += 1
        execution.schedule(snapshot: workspace.input, delay: .zero) { input in
            FormatRunner.run(input, produce: { try XMLFormatting.format($0) })
                .binding(text: { $0 })
        }
    }
}
