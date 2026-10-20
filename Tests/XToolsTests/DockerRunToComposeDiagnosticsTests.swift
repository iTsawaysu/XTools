import Testing
import XToolsCore
@testable import XTools

struct DockerRunToComposeDiagnosticsTests {
    @Test func inputBeyondPageBudgetStopsBeforeConversionAndRecoversWhenShortened() {
        let overBudget = String(repeating: "a", count: 200_001)
        let blocked = IndexDockerWorkspaceContent.binding(for: .init(
            input: overBudget,
            direction: .runToCompose
        ))

        #expect(blocked.output.isEmpty)
        #expect(blocked.error == "输入内容过长，最多支持 200000 个字符。")
        #expect(blocked.warning == nil)

        let recovered = IndexDockerWorkspaceContent.binding(for: .init(
            input: "docker run alpine",
            direction: .runToCompose
        ))
        #expect(recovered.error == nil)
        #expect(recovered.output.contains("image: alpine"))
    }

    @Test func inputAtPageBudgetStillConverts() {
        let prefix = "docker run --label note="
        let suffix = " alpine"
        let atBudget = prefix
            + String(repeating: "a", count: 200_000 - prefix.count - suffix.count)
            + suffix
        #expect(atBudget.count == 200_000)

        let result = IndexDockerWorkspaceContent.binding(for: .init(
            input: atBudget,
            direction: .runToCompose
        ))

        #expect(result.error == nil)
        #expect(result.output.contains("image: alpine"))
    }

    @Test func whitespaceOnlyInputReturnsQuietEmptyBinding() {
        let result = IndexDockerWorkspaceContent.binding(for: .init(
            input: " \n\t ",
            direction: .composeToRun
        ))

        #expect(result == FormatBinding())
    }

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
        #expect(result.diagnostic?.details.contains { $0.contains("--token") } == true)
        #expect(result.diagnostic?.details.allSatisfy { !$0.contains(secret) } == true)
    }
}
