import XToolsCore
import SwiftUI

@MainActor
final class DockerConversionToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<DockerConversionToolWorkspaceModel>(toolID: "docker-run-to-docker-compose-converter") { preferences in
        DockerConversionToolWorkspaceModel(preferences: preferences)
    }

    enum Direction: String, CaseIterable, Sendable {
        case runToCompose = "run-to-compose"
        case composeToRun = "compose-to-run"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .runToCompose:
                return "Run → Compose"
            case .composeToRun:
                return "Compose → Run"
            }
        }
    }

    @Published var input = "" {
        didSet {
            guard input != oldValue else { return }
            execution.sourceDidChange()
        }
    }
    @Published var direction: Direction {
        didSet {
            guard direction != oldValue else { return }
            execution.sourceDidChange()
            preferences.set(direction.rawValue, for: TextDevelopmentToolPreferenceKeys.dockerConversionDirection)
        }
    }

    let execution = IndexFormatExecutionSession()
    private let preferences: ToolPreferenceStore

    var output: String { execution.binding.output }
    var error: String? { execution.binding.error }
    var warning: String? { execution.binding.warning }

    init(preferences: ToolPreferenceStore = ToolPreferenceStore(defaults: .standard)) {
        self.preferences = preferences
        direction = Direction(rawValue: preferences.value(for: TextDevelopmentToolPreferenceKeys.dockerConversionDirection)) ?? .runToCompose
    }

    func clear() {
        execution.invalidate()
        input = ""
    }
}

struct IndexDockerPage: View {
    var body: some View {
        ToolWorkspaceHost(key: DockerConversionToolWorkspaceModel.key) { workspace, _ in
            IndexDockerWorkspaceContent(
                workspace: workspace,
                execution: workspace.execution
            )
        }
    }
}

private struct IndexDockerWorkspaceContent: View {
    nonisolated private static let maxInputCharacters = 200_000

    @ObservedObject var workspace: DockerConversionToolWorkspaceModel
    @ObservedObject var execution: IndexFormatExecutionSession
    @State private var formatAttempt = 0

    var body: some View {
        IndexPage("Docker Run ↔ Compose", subtitle: "docker run 命令与 Compose YAML 双向转换。", workspaceSemantic: .structuredEditorTransform) {
            IndexFormatWorkbench(
                inputTitle: "输入",
                outputTitle: "输出",
                input: $workspace.input,
                output: execution.binding.output,
                inputPlaceholder: inputPlaceholder,
                diagnostic: execution.binding.error ?? execution.binding.warning,
                diagnosticTone: execution.binding.error == nil ? .warning : .error,
                formatAttempt: formatAttempt,
                outputLineNumbers: true,
                outputSyntax: workspace.direction == .runToCompose ? .yaml : nil,
                actionTitle: "转换",
                isRunning: execution.isRunning,
                isOutputFresh: execution.isOutputFresh,
                clearDisabled: workspace.input.isEmpty && execution.binding.output.isEmpty && execution.binding.error == nil && execution.binding.warning == nil,
                onFormat: convert,
                onClear: workspace.clear,
                leadingControl: {
                    IndexSegmentedControl(
                        items: DockerConversionToolWorkspaceModel.Direction.allCases.map { ($0.id, $0.label) },
                        selection: Binding(
                            get: { workspace.direction.id },
                            set: { raw in
                                guard let direction = DockerConversionToolWorkspaceModel.Direction(rawValue: raw) else { return }
                                workspace.direction = direction
                                if !execution.binding.output.isEmpty {
                                    convert()
                                }
                            }
                        ),
                        density: .compact
                    )
                    .help("切换转换方向")
                    .fixedSize(horizontal: true, vertical: false)
                }
            )
        }
    }

    private var inputPlaceholder: String {
        switch workspace.direction {
        case .runToCompose:
            return "docker run -d -p 8080:80 -e ENV=prod --name web nginx:latest"
        case .composeToRun:
            return "services:\n  web:\n    image: nginx:latest\n    ports:\n      - 8080:80"
        }
    }

    private func convert() {
        guard !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            execution.invalidate()
            return
        }

        formatAttempt += 1
        let snapshot = Snapshot(input: workspace.input, direction: workspace.direction)
        execution.schedule(snapshot: snapshot, delay: .zero) { snapshot in
            Self.binding(for: snapshot)
        }
    }

    private struct Snapshot: Sendable {
        let input: String
        let direction: DockerConversionToolWorkspaceModel.Direction
    }

    nonisolated private static func binding(for snapshot: Snapshot) -> FormatBinding {
        let trimmed = snapshot.input.trimmingCharacters(in: .whitespacesAndNewlines)
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

        switch snapshot.direction {
        case .runToCompose:
            return runToComposeBinding(trimmed)
        case .composeToRun:
            return composeToRunBinding(trimmed)
        }
    }

    nonisolated private static func runToComposeBinding(_ input: String) -> FormatBinding {
        do {
            let result = try DockerRunToDockerComposeService.convert(input)
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

    nonisolated private static func composeToRunBinding(_ input: String) -> FormatBinding {
        do {
            let result = try DockerComposeToRunService.convert(input)
            let body = result.commands
                .map { "# 服务命令\n\($0)" }
                .joined(separator: "\n\n")
            return FormatBinding(
                output: body,
                error: nil,
                warning: DockerComposeToRunDiagnostics.warningMessage(for: result.warnings)
            )
        } catch let error as DockerComposeToRunError {
            return FormatBinding(error: DockerComposeToRunDiagnostics.message(for: error))
        } catch {
            return FormatBinding(error: DockerComposeToRunDiagnostics.message(for: .invalidYAML))
        }
    }
}
