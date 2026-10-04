import Foundation
import Testing

@testable import XTools

/// 图像工具代表页面的 Clay surface / 状态反馈契约。
///
/// 这些检查保护图片工作区在后续页面迁移中继续遵循同一套语义：
/// 页面外层负责滚动，图片预览由共享 stage 承载，空态和动作使用共享词汇。
struct ImagePageUXSourceContractTests {
    private let pages = [
        "Sources/XTools/ToolPages/Image/ImageConverterPage.swift",
        "Sources/XTools/ToolPages/Image/ImageCompressorPage.swift",
        "Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift",
        "Sources/XTools/ToolPages/Image/ColorPickerPage.swift",
    ]

    @Test func imagePagesUseSharedStateAndActionGrammar() throws {
        for path in pages {
            let source = try readSource(path)
            doesNotContain(source, "ProgressView(", "(path) must use the shared progress components")
            doesNotContain(source, ".buttonStyle(.plain)", "(path) must use the shared button styles")
            doesNotContain(source, ".buttonStyle(.bordered", "(path) must not add native bordered button chrome")
            doesNotContain(source, ".textFieldStyle(.roundedBorder)", "(path) must use the shared field surface")
        }
    }

    @Test func imagePreviewPagesKeepCanonicalEmptyStateAndPreviewSurface() throws {
        // 格式转换/压缩合并进「图片处理」Hub 后，页面壳断言改锚 Hub 文件；
        // 空态/进度分支收敛进共享 ImageUploadPendingState 后，空态文案断言
        // 改锚共享文件，页面断言改锚共享占位装配。
        let imageHub = try readSource("Sources/XTools/ToolPages/Image/ImageHubPage.swift")
        let uploadSupport = try readSource("Sources/XTools/ToolPages/Image/ImageWorkflowSupport.swift")
        let converter = try readSource("Sources/XTools/ToolPages/Image/ImageConverterPage.swift")
        let compressor = try readSource("Sources/XTools/ToolPages/Image/ImageCompressorPage.swift")
        let watermark = try readSource("Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift")

        contains(imageHub, "workspaceSemantic: .imagePreviewStage", "Image hub must keep the image preview workspace semantic")
        contains(imageHub, "case .watermark: IndexImageWatermarkSegment()", "Image watermark must live in the image hub as a segment")

        contains(uploadSupport, "IndexEmptyStateCopy.autoGenerate(\"图片\")", "The shared upload pending state must use canonical generated-content copy")
        for source in [converter, watermark] {
            contains(source, "ImageUploadPendingState(", "Image upload empty states must mount the shared pending state")
            contains(source, "IndexImagePreviewStage", "Image pages must render previews through the shared stage")
            contains(source, "fileInputPanelClient", "Image pages must use the sheet-based file input client")
            contains(source, "fileOutputPanelClient", "Image pages must use the sheet-based file output client")
        }
        contains(compressor, "IndexImageComparisonCard(", "Image compressor must render both previews through the shared comparison card")
        contains(compressor, "fileInputPanelClient", "Image compressor must use the sheet-based file input client")
        contains(compressor, "fileOutputPanelClient", "Image compressor must use the sheet-based file output panel client")
    }

    @Test func colorPickerUsesNaturalHeightSemanticAndSharedSpacing() throws {
        let source = try readSource("Sources/XTools/ToolPages/Image/ColorPickerPage.swift")
        contains(source, "workspaceSemantic: .naturalHeightShortResultPanel", "Color conversion must use a page-scrolled natural-height result semantic")
        contains(source, "ToolMetrics.Spacing.lg", "Color picker layout must use named spacing tokens")
        contains(source, "ToolMetrics.Spacing.md", "Color picker controls must use named spacing tokens")
        contains(source, "ToolMetrics.Spacing.sm", "Color picker result rows must use named spacing tokens")
    }
}
