import Foundation

public enum DockerRunToDockerComposeError: LocalizedError {
    case invalidCommand
    case multipleCommands
    case missingImage
    case missingOptionValue(String)
    case unterminatedQuote

    public var errorDescription: String? {
        switch self {
        case .invalidCommand:
            return "无法识别 docker run 命令：输入必须以 docker run 开头。"
        case .multipleCommands:
            return "一次只能转换一条 docker run 命令。"
        case .missingImage:
            return "docker run 命令缺少镜像名称。"
        case .missingOptionValue(let option):
            return "选项 `\(option)` 缺少参数值。"
        case .unterminatedQuote:
            return "命令包含未闭合的引号。"
        }
    }
}
