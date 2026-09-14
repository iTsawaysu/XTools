import Foundation
import Testing

struct InteractiveGridListPolishSourceContractTests {
    @Test func emojiCollectionUsesReusableNativeCellsAndExclusiveMotionFeedback() throws {
        let emoji = try readSource("Sources/XTools/ToolPages/Utility/EmojiPickerPage.swift")
        let collection = try readSource("Sources/XTools/ToolPages/Utility/EmojiCollectionView.swift")

        contains(emoji, "private static let displayLimit = 200", "Emoji search must retain the bounded 200-cell rendering cap")
        contains(emoji, "IndexEmojiCollectionView(", "Emoji results must use the page-private native collection renderer")
        contains(collection, "struct IndexEmojiCollectionView: NSViewRepresentable", "Emoji results must have one reusable AppKit renderer boundary")
        contains(collection, "layout.itemSize = NSSize(width: 46, height: 46)", "Native cells must preserve the existing 46-point cell geometry")
        contains(collection, "layout.minimumInteritemSpacing = 4", "Native cells must preserve the existing horizontal grid spacing")
        contains(collection, "layout.minimumLineSpacing = 4", "Native cells must preserve the existing vertical grid spacing")
        contains(collection, "layer?.cornerRadius = ToolMetrics.CornerRadius.field", "Native cells must use the shared corner-radius token")
        contains(collection, "layer?.backgroundColor = fillColor.cgColor", "Native hover and press fills must animate on the reusable cell layer")
        contains(collection, "layer?.borderColor", "Native hover borders must share the reusable cell animation transaction")
        contains(collection, "ToolMotion.Scale.pressed", "Native cells must preserve the shared pressed scale")
        contains(collection, "ToolMotion.Duration.micro", "Native cells must preserve the 0.12-second feedback timing")
        contains(collection, "!reduceMotion", "Native feedback must settle immediately under Reduce Motion")
        contains(collection, "final class IndexEmojiCollectionDocumentView: NSCollectionView", "The native collection must own pointer tracking above reusable cells")
        contains(collection, ".mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect", "The collection pointer area must follow the visible key-window region")
        contains(collection, "collectionView.indexPathForItem(at:", "Hover must resolve through the active collection layout")
        contains(collection, "private var hoveredIndexPath: IndexPath?", "The coordinator must own one exclusive hover identity")
        contains(collection, "guard hoveredIndexPath != nextIndexPath else { return }", "Repeated pointer and scroll updates must not rewrite unchanged cell layers")
        contains(collection, "override func reflectScrolledClipView", "Scrolling must reconcile hover under a stationary pointer")
        occurrenceCount(collection, "NSTrackingArea(", 1, "Emoji rendering must keep one custom pointer tracking area instead of one per cell")
        contains(collection, "setAccessibilityRole(.button)", "Native cells must retain button accessibility semantics")
        contains(collection, "setAccessibilityHelp(\"按下以复制字符\")", "Native cells must retain copy accessibility help")
        contains(collection, "toolTip = helpText", "Native cells must retain catalog tooltips")
        contains(collection, "collectionView.delegate = nil", "Flat Emoji results must keep the native no-supplementary fast path")
        contains(collection, "collectionView.delegate = flowLayoutDelegate", "Special-symbol sections must opt into header layout only when needed")
        contains(collection, "collectionView.reloadData()", "Native reuse must refresh the immutable result snapshot immediately")
        occurrenceCount(emoji, "scrollResetIdentity: workspace.category", 2, "Both flat and sectioned Emoji results must reset only when the owning category changes")
        contains(collection, "private var lastScrollResetIdentity: String?", "The renderer must compare one opaque presentation identity instead of owning category state")
        contains(collection, "if shouldResetScroll, scrollView.contentView.bounds.minY > 0", "A category change already at the top must skip redundant clip-view scrolling")
        contains(collection, "scrollView.contentView.scroll(to: .zero)", "A changed category identity must synchronously reset the panel-local viewport")
        doesNotContain(collection, "animator().scroll", "Category reset must not add a visible scroll animation")
        doesNotContain(emoji + collection, "matchedGeometryEffect", "Emoji filtering and hover must not add matched geometry across cells")
    }

    @Test func emojiToneControlKeepsSharedButtonStylingAtCompactHeaderDensity() throws {
        let emoji = try readSource("Sources/XTools/ToolPages/Utility/EmojiPickerPage.swift")
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")

        contains(emoji, "IndexSegmentedControl(", "Emoji tone options must keep the shared segmented-button styling")
        contains(emoji, "density: .compact", "Emoji tone options must reduce header dominance with compact density")
        contains(controls, "enum Density", "The shared segmented control must expose an explicit density contract")
        contains(controls, "case compact", "The shared segmented control must provide a compact variant")
        contains(controls, "case .compact: 22", "Compact segments must leave visible vertical breathing room in a 34-point panel header")
        contains(controls, "case .compact: 9", "Compact segments must reduce horizontal dominance without changing button semantics")
        doesNotContain(emoji, "private struct EmojiSkinToneSegment", "Emoji must not fork a page-local copy of the shared segment style")
    }

    @Test func httpRowsKeepNativeListGeometryAndExposeSemanticCopyFeedback() throws {
        let http = try readSource("Sources/XTools/ToolPages/Web/HTTPStatusCodesPage.swift")

        contains(http, "List(filtered) { row in", "HTTP status results must keep native List virtualization")
        contains(http, ".listStyle(.plain)", "HTTP status results must keep the native plain-list path")
        contains(http, ".scrollContentBackground(.hidden)", "HTTP status results must keep the panel-local list surface")
        contains(http, "IndexHTTPStatusRow(row: row)", "HTTP status rows must isolate local hover state in a row view")
        contains(http, "private struct IndexHTTPStatusRow: View", "HTTP hover feedback must not be stored in a page-level row-state dictionary")
        contains(http, "@State private var isHovering = false", "Each visible HTTP row must own only its local hover state")
        contains(http, ".onHover { hovering in", "HTTP hover must update only the visible entered or exited row")
        contains(http, "withToolAnimation(ToolMotion.Preset.controlFeedback) { isHovering = hovering }", "HTTP row hover must use the shared control-feedback token")
        contains(http, "title: \"复制 \\(row.code) 状态码\"", "HTTP copy actions must expose a non-empty status-specific help and AX label")
        contains(http, "iconOnly: true", "HTTP copy actions must remain visually compact while exposing semantic copy text")
        doesNotContain(http, "LazyVStack(spacing: 0)", "HTTP status must not replace native List with eager row materialization")
        doesNotContain(http, "matchedGeometryEffect", "HTTP filters and rows must not animate identity across list updates")
    }
}
