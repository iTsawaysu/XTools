import XToolsCore
import SwiftUI

struct IndexYAMLPrettifyPage: View {
    private static let key = ToolWorkspaceKey<IndexTextTransformWorkspaceModel>(toolID: "yaml-prettify") { _ in
        IndexTextTransformWorkspaceModel()
    }

    var body: some View {
        ToolWorkspaceHost(key: Self.key) { workspace, _ in
            IndexYAMLPrettifyWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

private struct IndexYAMLPrettifyWorkspaceContent: View {
    private static let maxHighlightedOutputCharacters = 200_000

    @ObservedObject var workspace: IndexTextTransformWorkspaceModel
    @ObservedObject var execution: IndexFormatExecutionSession
    @State private var formatAttempt = 0

    var body: some View {
        IndexPage("YAML 格式化", subtitle: "规整 YAML 空白与键值间距。", workspaceSemantic: .structuredEditorTransform) {
            IndexFormatWorkbench<EmptyView>(
                inputTitle: "输入",
                outputTitle: "输出",
                input: $workspace.input,
                output: execution.binding.output,
                inputPlaceholder: "key:   value\nlist:\n   - a\n   - b",
                diagnostic: execution.binding.error,
                formatAttempt: formatAttempt,
                outputLineNumbers: true,
                outputColorize: outputColorizer,
                clearDisabled: workspace.input.isEmpty && execution.binding.output.isEmpty && execution.binding.error == nil,
                onFormat: format,
                onClear: workspace.clear
            )
        }
    }

    private var outputColorizer: ((String) -> AttributedString)? {
        if execution.binding.output.count > Self.maxHighlightedOutputCharacters {
            return nil
        }
        return { StructuredSyntaxHighlighter.yaml(line: $0) }
    }

    private func format() {
        guard !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            execution.invalidate()
            return
        }

        formatAttempt += 1
        execution.schedule(snapshot: workspace.input, delay: .zero) { input in
            FormatRunner.run(input, produce: YAMLPrettifier.formatValidated)
                .binding(text: { $0 })
        }
    }
}
