import Testing

/// Guards the page-level workspace semantics for the final Web/Image migration batch.
/// Mixed JWT/User-Agent pages intentionally keep their outer scroll owner while
/// their individual surfaces opt into semantic input/output contracts.
struct WebImageSharedSurfaceSourceContractTests {
    @Test func webPagesNameTheCorrectWorkspaceShellOrPreserveMixedScrolling() throws {
        let basicAuth = try readSource("Sources/XTools/ToolPages/Web/BasicAuthGeneratorPage.swift")
        let jwt = try readSource("Sources/XTools/ToolPages/Web/JWTParserPage.swift")
        let keycode = try readSource("Sources/XTools/ToolPages/Web/KeycodeInfoPage.swift")
        let userAgent = try readSource("Sources/XTools/ToolPages/Web/UserAgentParserPage.swift")

        contains(basicAuth, "workspaceSemantic: .securityTransformWorkspace", "Basic Auth must use the security transform shell")
        contains(keycode, "workspaceSemantic: .fixedInputWorkspace", "Keycode capture must use a bounded fixed-input shell")
        contains(jwt, "layout: .scroll", "JWT mixed generate/parse content must retain page-level scrolling")
        contains(userAgent, "layout: .scroll", "User-Agent input and result must retain page-level scrolling")
        contains(userAgent, "workspaceSemantic: .longTextNaturalInput", "User-Agent input must use the natural text surface")
        contains(userAgent, "IndexWorkspaceResultSurface", "User-Agent result must use the shared result surface")
    }

    @Test func imageAndConverterPagesKeepSemanticPreviewAndTransformSurfaces() throws {
        // Favicon/灰度合并进「图片处理」Hub 后，页面壳断言改锚 Hub 文件。
        let imageHub = try readSource("Sources/XTools/ToolPages/Image/ImageHubPage.swift")
        let converter = try readSource("Sources/XTools/ToolPages/Workbench/Converter/IndexConverterPage.swift")

        contains(imageHub, "workspaceSemantic: .imagePreviewStage", "The image hub must use the shared image preview stage")
        contains(converter, "workspaceSemantic: .copyTransformWorkspace", "Generic converters must use the shared copy-transform shell")
        contains(converter, "IndexTextConversionWorkbench(", "Generic converters must render through the shared input/output workbench")
    }
}
