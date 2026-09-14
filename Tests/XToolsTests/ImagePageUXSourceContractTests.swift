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
        let converter = try readSource("Sources/XTools/ToolPages/Image/ImageConverterPage.swift")
        let compressor = try readSource("Sources/XTools/ToolPages/Image/ImageCompressorPage.swift")
        let watermark = try readSource("Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift")

        contains(converter, "workspaceSemantic: .imagePreviewStage", "Image converter must keep the image preview workspace semantic")
        contains(compressor, "workspaceSemantic: .imagePreviewStage", "Image compressor must keep the image preview workspace semantic")
        contains(watermark, "workspaceSemantic: .liveImagePreviewStage", "Image watermark must keep the live preview workspace semantic")

        for source in [converter, watermark] {
            contains(source, "IndexEmptyStateCopy.autoGenerate(\"图片\")", "Image upload empty states must use canonical generated-content copy")
            contains(source, "IndexImagePreviewStage", "Image pages must render previews through the shared stage")
            contains(source, "fileInputPanelClient", "Image pages must use the sheet-based file input client")
            contains(source, "fileOutputPanelClient", "Image pages must use the sheet-based file output client")
        }
        contains(compressor, "IndexImageComparisonCard(", "Image compressor must render both previews through the shared comparison card")
        contains(compressor, "IndexEmptyStateCopy.autoGenerate(\"图片\")", "Image compressor upload empty state must use canonical generated-content copy")
        contains(compressor, "fileInputPanelClient", "Image compressor must use the sheet-based file input client")
        contains(compressor, "fileOutputPanelClient", "Image compressor must use the sheet-based file output client")
    }

    @Test func colorPickerUsesNaturalHeightSemanticAndSharedSpacing() throws {
        let source = try readSource("Sources/XTools/ToolPages/Image/ColorPickerPage.swift")
        contains(source, "workspaceSemantic: .naturalHeightShortResultPanel", "Color conversion must use a page-scrolled natural-height result semantic")
        contains(source, "ToolMetrics.Spacing.lg", "Color picker layout must use named spacing tokens")
        contains(source, "ToolMetrics.Spacing.md", "Color picker controls must use named spacing tokens")
        contains(source, "ToolMetrics.Spacing.sm", "Color picker result rows must use named spacing tokens")
    }
}
