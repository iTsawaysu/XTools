import Foundation

public enum DockerRunToDockerComposeDiagnostics {
    public static let emptyOutputMessage = "命令未包含可转换的服务配置。"
    public static let fallbackErrorMessage = "docker run 命令格式无效。"

    public static func inputTooLongMessage(maxCharacters: Int) -> String {
        "输入内容过长，最多支持 \(maxCharacters) 个字符。"
    }

    public static func warningMessage(
        for warnings: [DockerRunToDockerComposeService.Warning],
        maxOptionsPerGroup: Int = 3
    ) -> String? {
        _ = maxOptionsPerGroup
        guard !warnings.isEmpty else { return nil }
        return "部分 Docker 选项无法转换。"
    }
}
