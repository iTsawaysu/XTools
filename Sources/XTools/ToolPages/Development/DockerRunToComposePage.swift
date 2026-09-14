import XToolsCore
import SwiftUI

struct IndexDockerPage: View {
    private static let key = ToolWorkspaceKey<IndexTextTransformWorkspaceModel>(
        toolID: "docker-run-to-docker-compose-converter"
    ) { _ in
        IndexTextTransformWorkspaceModel()
    }

    var body: some View {
        ToolWorkspaceHost(key: Self.key) { workspace, _ in
            IndexDockerWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

private struct IndexDockerWorkspaceContent: View {
    nonisolated private static let maxInputCharacters = 200_000
    nonisolated private static let maxHighlightedOutputCharacters = 200_000

    @ObservedObject var workspace: IndexTextTransformWorkspaceModel
    @ObservedObject var execution: IndexFormatExecutionSession
    @State private var formatAttempt = 0

    var body: some View {
        IndexPage("Docker Run → Compose", subtitle: "把 docker run 命令转换为 compose YAML。", workspaceSemantic: .structuredEditorTransform) {
            IndexFormatWorkbench<EmptyView>(
                inputTitle: "输入",
                outputTitle: "输出",
                input: $workspace.input,
                output: execution.binding.output,
                inputPlaceholder: "docker run -d -p 8080:80 -e ENV=prod --name web nginx:latest",
                diagnostic: execution.binding.error ?? execution.binding.warning,
                diagnosticTone: execution.binding.error == nil ? .warning : .error,
                formatAttempt: formatAttempt,
                outputLineNumbers: true,
                outputColorize: outputColorizer,
                actionTitle: "转换",
                clearDisabled: workspace.input.isEmpty && execution.binding.output.isEmpty && execution.binding.error == nil && execution.binding.warning == nil,
                onFormat: convert,
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

    private func convert() {
        guard !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            execution.invalidate()
            return
        }

        formatAttempt += 1
        let snapshot = workspace.input
        execution.schedule(snapshot: snapshot, delay: .zero) { input in
            Self.binding(for: input)
        }
    }

    nonisolated private static func binding(for input: String) -> FormatBinding {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return FormatBinding()
        }

        guard trimmed.count <= maxInputCharacters else {
            return FormatBinding(
                error: DockerRunToDockerComposeDiagnostics.inputTooLongMessage(
                    maxCharacters: maxInputCharacters
                )
            )
        }

        do {
            let result = try DockerRunToDockerComposeService.convert(trimmed)
            return FormatBinding(
                output: result.yaml,
                error: result.yaml.isEmpty
                    ? DockerRunToDockerComposeDiagnostics.emptyOutputMessage
                    : nil,
                warning: DockerRunToDockerComposeDiagnostics.warningMessage(for: result.warnings)
            )
        } catch let error as DockerRunToDockerComposeError {
            return FormatBinding(error: error.errorDescription ?? "无法转换 docker run 命令。")
        } catch {
            return FormatBinding(error: DockerRunToDockerComposeDiagnostics.fallbackErrorMessage)
        }
    }
}
