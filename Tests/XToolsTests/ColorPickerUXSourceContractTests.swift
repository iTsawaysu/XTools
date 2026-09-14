import Foundation
@testable import XTools
import Testing

struct ColorPickerUXSourceContractTests {
    @Test func colorPagePrioritizesCommonFormatsAndKeepsAdvancedSpacesBounded() throws {
        let source = try readSource("Sources/XTools/ToolPages/Image/ColorPickerPage.swift")

        contains(source, "IndexPanel(\"转换结果\")", "Color results must share one scan-friendly workspace")
        contains(source, "resultRows(commonValues, emptyText: IndexEmptyStateCopy.autoShow(\"有效 CSS 颜色\"))", "Common CSS formats must remain visible by default")
        contains(source, "private var advancedValues: [CSSColorFormattedValue] { perceptualValues + extendedValues }", "All advanced values must remain available in their existing order")
        contains(source, "resultRows(advancedValues, emptyText: IndexEmptyStateCopy.autoShow(\"有效 CSS 颜色\"))", "Advanced formats must extend the same result-list grammar")
        doesNotContain(source, "IndexPanel(\"常用格式\")", "Common formats must not require a separate panel")
        doesNotContain(source, "IndexPanel(\"感知与设备无关\")", "Perceptual formats must not occupy the default page hierarchy")
        doesNotContain(source, "IndexPanel(\"扩展 color() 空间\")", "Extended formats must not create another panel")
        doesNotContain(source, "advancedFormatGroup(", "Advanced rows must not return to isolated theory-first section headings")
    }

    @Test func advancedColorHeaderUsesTheWholeRowAndSharedDisclosureMotion() throws {
        let source = try readSource("Sources/XTools/ToolPages/Image/ColorPickerPage.swift")

        contains(source, "@State private var showsAdvancedFormats = false", "Advanced expansion must remain ephemeral view state")
        contains(source, "IndexDisclosure(", "Advanced disclosure must delegate to the shared IndexDisclosure component")
        contains(source, "isExpanded: $showsAdvancedFormats", "Advanced disclosure must bind the ephemeral expansion state")
        contains(source, "collapsedSummary: advancedFormatsSummary", "Advanced disclosure must surface the collapsed summary through the shared header")
        contains(source, ".inline()", "Advanced disclosure must stay nested inside the results panel as an inline region")
        doesNotContain(source, "DisclosureGroup(", "The page must not return to the arrow-only DisclosureGroup interaction")
        doesNotContain(source, "private struct ColorAdvancedFormatsHeader", "The page must not hand-roll a local disclosure header")
        // ToolDisclosureBody 通过 preference 测量内容高度再裁剪展开；LazyVStack
        // 依赖外层滚动视口做行复用，在自测量容器里首帧高度失真，表现为展开后
        // 布局错乱、要滚动一次才恢复（2026-09 用户报告）。行数有限，禁止懒加载。
        doesNotContain(source, "LazyVStack(", "Disclosure-measured result rows must use eager VStack so the disclosure measures a stable first-frame height")
    }

    @Test func hslControlsStayDirectAndDiscloseWideGamutMappingOnlyWhenNeeded() throws {
        let source = try readSource("Sources/XTools/ToolPages/Image/ColorPickerPage.swift")
        let controls = sourceSlice(
            source,
            from: "private var hslControls: some View",
            to: "private var advancedFormatsDisclosure: some View"
        )

        contains(controls, "title: \"色相\"", "Hue must use a direct localized label")
        contains(controls, "title: \"饱和度\"", "Saturation must use a direct localized label")
        contains(controls, "title: \"亮度\"", "Lightness must use a direct localized label")
        contains(controls, "title: \"Alpha\"", "Opacity must live in the same editing workspace")
        contains(controls, ".indexSurface(.field, fill: ToolTheme.editorBackground", "The editing model must read as one coherent native control surface")
        contains(controls, "超出 sRGB；HSL 调整将从映射后的显示颜色开始。", "Wide-gamut HSL editing must disclose its mapped starting point concisely")
        doesNotContain(controls, "Text(\"HSL 调整\")", "The sliders must not repeat an inert editing-model heading")
        doesNotContain(controls, "Text(\"sRGB\")", "The sliders must not repeat inert color-space metadata for ordinary sRGB colors")
        doesNotContain(source, "Text(\"sRGB HSL 编辑\")", "The ambiguous implementation-oriented caption must not return")
    }

    @Test func colorResultsStayCompactCopyableAndImmediate() throws {
        let source = try readSource("Sources/XTools/ToolPages/Image/ColorPickerPage.swift")
        let row = sourceSlice(
            source,
            from: "private struct ColorFormatResultRow: View",
            to: "private var valueText: some View"
        )

        doesNotContain(row, "IndexSurfaceRow", "Result rows must not add nested card surfaces inside the result panel")
        contains(row, "HStack(alignment: .center, spacing: 10)", "Every result must use one stable format-value-action row")
        contains(row, "IndexCopyButton(text: value.text, title: \"复制 \\(value.label)\"", "Every compact result row must retain format-specific copy")
        contains(source, "ColorFormatResultRow(value: value, valueMotion: .immediate)", "Live color values must keep immediate updates while sliders move")
        contains(source, "IndexBadge(\"映射到 sRGB\", tone: .warning)", "Mapped legacy formats must remain visibly honest")
    }
}
