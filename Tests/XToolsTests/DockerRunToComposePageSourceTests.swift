import Foundation
import Testing
@testable import XTools

struct DockerRunToComposePageSourceTests {
    @Test func warningDetailDoesNotExposeUnknownOptionValues() {
        let secret = "private-secret-value"
        let result = IndexDockerWorkspaceContent.binding(for: .init(
            input: "docker run --token=\(secret) alpine",
            direction: .runToCompose
        ))

        #expect(result.output.contains("image: alpine"))
        #expect(result.warning == "部分 Docker 选项无法转换。")
        #expect(result.diagnostic?.suggestion == "部分命令行参数未能转换，请检查原命令与生成的 Compose 配置。")
        #expect(result.diagnostic?.suggestion?.contains(secret) == false)
        #expect(result.diagnostic?.message.contains(secret) == false)
    }

    @Test func dockerPageRoutesConversionWarningsAndTypedErrorsIntoWorkbenchDiagnostics() throws {
        let source = try String(
            contentsOfFile: "Sources/XTools/ToolPages/Development/DockerRunToComposePage.swift",
            encoding: .utf8
        )

        #expect(source.contains("@ObservedObject var workspace: DockerConversionToolWorkspaceModel"))
        #expect(source.contains("outputSyntax: workspace.direction == .runToCompose ? .yaml : nil"))
        #expect(source.contains("DockerComposeToRunDiagnostics.diagnostic(for:"))
        #expect(source.contains("diagnostic: execution.binding.error ?? execution.binding.warning"))
        #expect(source.contains("diagnosticTone: execution.binding.error == nil ? .warning : .error"))
        #expect(source.contains("DockerRunToDockerComposeError"))
        #expect(source.contains("DockerRunToDockerComposeDiagnostics.warningMessage(for: result.warnings)"))
        #expect(source.contains("DockerRunToDockerComposeDiagnostics.inputTooLongMessage"))
        #expect(source.contains("DockerRunToDockerComposeDiagnostics.emptyOutputMessage"))
        #expect(source.contains("DockerRunToDockerComposeDiagnostics.fallbackErrorMessage"))
        #expect(!source.contains("输入内容过长，已停止转换"))
        #expect(!source.contains("未生成 compose YAML"))
        #expect(!source.contains("无法转换这条 `docker run` 命令"))
        #expect(!source.contains("errorMessage = \"无效的 docker run 命令\""))
        #expect(!source.contains("catch {\n            output = \"\"\n            errorMessage = \"无效的 docker run 命令\"\n        }"))
    }
}
