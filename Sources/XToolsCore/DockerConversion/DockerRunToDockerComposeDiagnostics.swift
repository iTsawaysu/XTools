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

    public static func warningDetails(for warnings: [DockerRunToDockerComposeService.Warning]) -> [String] {
        var details: [String] = []
        for warning in warnings.prefix(256) {
            let option = safeOptionName(warning.option)
            switch warning.kind {
            case .notTranslatable:
                details.append("\(option)：Compose 无法等价表达，未写入结果。")
            case .notImplemented:
                details.append("\(option)：暂不支持转换，未写入结果。")
            case .unknownFlag:
                details.append("\(option)：未识别的选项，未写入结果。")
            }
        }
        if warnings.count > details.count {
            details.append("另有 \(warnings.count - details.count) 项转换提示，未展开显示。")
        }
        return details
    }

    static func safeOptionName(_ option: String) -> String {
        let name = String(option.prefix { $0 != "=" })
        guard name.utf8.count <= 96,
              name.range(of: #"^--?[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil else {
            return "未知选项"
        }
        return name
    }
}
