import Testing
@testable import XTools

/// F8 防回归守卫（架构扫描发现 F1：json-diff 等 9 个遗留 ID 令
/// `evictHeavyPayloads(for:)` 永远无法命中，大载荷离开工具后不释放）。
///
/// `ToolWorkspaceRepository.evictHeavyPayloads(for:)` 以**注册表 ID** 淘汰，
/// 因此每个 `ToolWorkspaceKey` 声明点的 toolID 必须能在
/// `ToolRegistry.default` 中解析。slot 是 Hub 分段语义（如 "json"/"text"），
/// 不是注册表身份，无需校验。
///
/// 新增工具页时，请把它的 workspace key 声明点加入 `declaredKeys`
/// （与 `rg "ToolWorkspaceKey<" Sources/XTools` 保持同步）。
@MainActor
struct ToolWorkspaceKeyRegistryAlignmentTests {
    @Test func everyDeclaredWorkspaceKeyResolvesARegisteredTool() {
        let registry = ToolRegistry.default

        // (声明点, toolID) —— 逐个引用 Sources 中的静态 key，防止有人把
        // toolID 改回遗留字符串（如 "json-diff"）而测试仍然通过。
        let declaredKeys: [(owner: String, toolID: ToolID)] = [
            // 转换器
            ("EncodingHubWorkspaceModel.key", EncodingHubWorkspaceModel.key.toolID),
            ("Base64FileWorkflowSession.workspaceKey", Base64FileWorkflowSession.workspaceKey.toolID),
            ("IntegerBaseToolWorkspaceModel.key", IntegerBaseToolWorkspaceModel.key.toolID),
            ("CaseConverterToolWorkspaceModel.key", CaseConverterToolWorkspaceModel.key.toolID),
            ("RomanNumeralToolWorkspaceModel.key", RomanNumeralToolWorkspaceModel.key.toolID),
            // 开发
            ("FormatterHubWorkspaceModel.key", FormatterHubWorkspaceModel.key.toolID),
            ("JSONFormatterToolWorkspaceModel.key", JSONFormatterToolWorkspaceModel.key.toolID),
            ("XMLFormatterToolWorkspaceModel.key", XMLFormatterToolWorkspaceModel.key.toolID),
            ("YAMLPrettifyToolWorkspaceModel.key", YAMLPrettifyToolWorkspaceModel.key.toolID),
            ("SQLPrettifyToolWorkspaceModel.key", SQLPrettifyToolWorkspaceModel.key.toolID),
            ("DiffHubWorkspaceModel.key", DiffHubWorkspaceModel.key.toolID),
            ("IndexJSONDiffSegment.key", IndexJSONDiffSegment.key.toolID),
            ("IndexTextDiffSegment.key", IndexTextDiffSegment.key.toolID),
            ("RegexToolWorkspaceModel.key", RegexToolWorkspaceModel.key.toolID),
            ("HTMLToMarkdownToolWorkspaceModel.key", HTMLToMarkdownToolWorkspaceModel.key.toolID),
            ("DockerConversionToolWorkspaceModel.key", DockerConversionToolWorkspaceModel.key.toolID),
            ("CrontabToolWorkspaceModel.key", CrontabToolWorkspaceModel.key.toolID),
            ("ChmodToolWorkspaceModel.key", ChmodToolWorkspaceModel.key.toolID),
            ("RandomPortToolWorkspaceModel.key", RandomPortToolWorkspaceModel.key.toolID),
            ("SourceControlWorkspaceModel.key", SourceControlWorkspaceModel.key.toolID),
            // 加密与生成
            ("GeneratorHubWorkspaceModel.key", GeneratorHubWorkspaceModel.key.toolID),
            ("TokenGeneratorToolWorkspaceModel.key", TokenGeneratorToolWorkspaceModel.key.toolID),
            ("UUIDGeneratorToolWorkspaceModel.key", UUIDGeneratorToolWorkspaceModel.key.toolID),
            ("PasswordGeneratorToolWorkspaceModel.key", PasswordGeneratorToolWorkspaceModel.key.toolID),
            ("HashTextToolWorkspaceModel.key", HashTextToolWorkspaceModel.key.toolID),
            ("TextEncryptionToolWorkspaceModel.key", TextEncryptionToolWorkspaceModel.key.toolID),
            ("StringObfuscatorToolWorkspaceModel.key", StringObfuscatorToolWorkspaceModel.key.toolID),
            // 图片
            ("ImageHubWorkspaceModel.key", ImageHubWorkspaceModel.key.toolID),
            ("ImageConverterToolWorkspaceModel.key", ImageConverterToolWorkspaceModel.key.toolID),
            ("ImageCompressorToolWorkspaceModel.key", ImageCompressorToolWorkspaceModel.key.toolID),
            ("ImageWatermarkToolWorkspaceModel.key", ImageWatermarkToolWorkspaceModel.key.toolID),
            ("ImageProcessedOutputSession.grayscaleWorkspaceKey", ImageProcessedOutputSession.grayscaleWorkspaceKey.toolID),
            ("FaviconOutputSetSession.workspaceKey", FaviconOutputSetSession.workspaceKey.toolID),
            ("ColorToolWorkspaceModel.key", ColorToolWorkspaceModel.key.toolID),
            // Web
            ("JWTToolWorkspaceModel.key", JWTToolWorkspaceModel.key.toolID),
            ("BasicAuthToolWorkspaceModel.key", BasicAuthToolWorkspaceModel.key.toolID),
            ("HTTPStatusToolWorkspaceModel.key", HTTPStatusToolWorkspaceModel.key.toolID),
            ("UserAgentToolWorkspaceModel.key", UserAgentToolWorkspaceModel.key.toolID),
            ("KeycodeToolWorkspaceModel.key", KeycodeToolWorkspaceModel.key.toolID),
            // 时间
            ("DateTimeToolWorkspaceModel.key", DateTimeToolWorkspaceModel.key.toolID),
            ("DateCalcToolWorkspaceModel.key", DateCalcToolWorkspaceModel.key.toolID),
            ("ChronometerToolWorkspaceModel.key", ChronometerToolWorkspaceModel.key.toolID),
            // 实用
            ("MathToolWorkspaceModel.key", MathToolWorkspaceModel.key.toolID),
            ("TextStatisticsWorkspaceModel.key", TextStatisticsWorkspaceModel.key.toolID),
            ("EmojiToolWorkspaceModel.key", EmojiToolWorkspaceModel.key.toolID),
            ("FileTypeDetectorSession.workspaceKey", FileTypeDetectorSession.workspaceKey.toolID),
        ]

        for declared in declaredKeys {
            #expect(
                registry.tool(for: declared.toolID) != nil,
                Comment(
                    rawValue: "\(declared.owner) 的 toolID \"\(declared.toolID.rawValue)\" 无法在 ToolRegistry.default 解析："
                        + "evictHeavyPayloads(for:) 将永远无法命中该工具，大载荷离开工具后不会释放（F1 复发）"
                )
            )
        }
    }
}
