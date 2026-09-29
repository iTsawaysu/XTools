import XToolsCore
import AppKit

/// Owned by one native editor. Character edits invalidate the source index;
/// scrolling and temporary syntax attributes never rescan the source text.
@MainActor
final class IndexDiffTextIndex: NSObject {
    private weak var storage: NSTextStorage?
    private var cachedRanges: [NSRange]?
    private(set) var revision = 0
    private(set) var rebuildCount = 0
    private struct HeightKey: Equatable {
        let width: CGFloat
        let font: NSFont?
        let inset: NSSize
    }
    private var heightKey: HeightKey?
    private var cachedHeight: CGFloat?

    init(storage: NSTextStorage?) {
        self.storage = storage
        super.init()
        if let storage {
            NotificationCenter.default.addObserver(
                self, selector: #selector(storageEdited(_:)),
                name: NSTextStorage.didProcessEditingNotification, object: storage
            )
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func storageEdited(_ notification: Notification) {
        guard let storage, storage.editedMask.contains(.editedCharacters) else { return }
        cachedRanges = nil
        cachedHeight = nil
        revision &+= 1
    }

    var ranges: [NSRange] {
        if let cachedRanges { return cachedRanges }
        let ranges = IndexDiffSourceText.lineRanges(in: storage?.string ?? "")
        cachedRanges = ranges
        rebuildCount += 1
        return ranges
    }

    func documentHeight(for view: NSTextView) -> CGFloat {
        let key = HeightKey(width: view.textContainer?.containerSize.width ?? 0,
                            font: view.font, inset: view.textContainerInset)
        if heightKey == key, let cachedHeight { return cachedHeight }
        let height = IndexTextKitGeometry.measuredTextHeight(for: view)
        heightKey = key
        cachedHeight = height
        return height
    }
}

@MainActor
protocol IndexDiffIndexedTextSurface: AnyObject {
    var diffTextIndex: IndexDiffTextIndex { get }
}

@MainActor
enum IndexDiffTextLayoutGeometry {
    static func defaultLineHeight(for textView: NSTextView) -> CGFloat {
        textView.layoutManager?.defaultLineHeight(
            for: textView.font ?? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        ) ?? 16
    }

    static func documentHeight(for textView: NSTextView) -> CGFloat {
        if let indexed = textView as? any IndexDiffIndexedTextSurface {
            return indexed.diffTextIndex.documentHeight(for: textView)
        }
        return IndexTextKitGeometry.measuredTextHeight(for: textView)
    }

    /// The shared outer scroller needs the full document height once per text
    /// revision/wrapping width. Reuse that measurement during scroll/layout.
    static func synchronizeTextGeometry(
        for textView: NSTextView, visibleWidth: CGFloat, minimumHeight: CGFloat,
        trailingReadingGuard: CGFloat
    ) {
        let width = max(1, floor(visibleWidth.isFinite ? visibleWidth : textView.bounds.width))
        if let container = textView.textContainer {
            let wrappingWidth = IndexTextKitGeometry.wrappingContainerWidth(
                for: textView, visibleWidth: width, trailingReadingGuard: trailingReadingGuard
            )
            if abs(container.containerSize.width - wrappingWidth) > 0.5 {
                container.containerSize = NSSize(width: wrappingWidth, height: CGFloat.greatestFiniteMagnitude)
            }
        }
        let height = max(minimumHeight.isFinite ? minimumHeight : 0, documentHeight(for: textView))
        if abs(textView.frame.width - width) > 0.01 || abs(textView.frame.height - height) > 0.01 {
            textView.setFrameSize(NSSize(width: width, height: height))
        }
    }

    static func lineRanges(for textView: NSTextView) -> [NSRange] {
        (textView as? any IndexDiffIndexedTextSurface)?.diffTextIndex.ranges
            ?? IndexDiffSourceText.lineRanges(in: textView.string)
    }

    static func lineBlockRects(for textView: NSTextView, visibleRect: NSRect? = nil) -> [Int: NSRect] {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return [:] }

        let ranges = lineRanges(for: textView)
        let span = visibleRect.map { visibleLineSpan(for: textView, ranges: ranges, visibleRect: $0) }
            ?? ranges.indices
        guard !span.isEmpty else { return [:] }
        let nsText = textView.string as NSString
        let origin = textView.textContainerOrigin
        let fallbackHeight = defaultLineHeight(for: textView)
        var result: [Int: NSRect] = [:]
        result.reserveCapacity(span.count)
        for index in span {
            let contentRange = ranges[index]
            let layoutRange = lineLayoutRange(for: contentRange, in: nsText)
            var blockRect = NSRect.null
            if layoutRange.length > 0 {
                // Layout only the requested logical lines; glyph and character
                // ranges are distinct for emoji, ligatures and combining text.
                layoutManager.ensureLayout(forCharacterRange: layoutRange)
                let glyphRange = layoutManager.glyphRange(forCharacterRange: layoutRange, actualCharacterRange: nil)
                layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragment, _, _, _, _ in
                    let rect = fragment.offsetBy(dx: origin.x, dy: origin.y)
                    blockRect = blockRect.isNull ? rect : blockRect.union(rect)
                }
            }
            if blockRect.isNull {
                // A terminal empty line uses TextKit's extra line fragment,
                // independent of how far the viewport is from the first line.
                let extra = layoutManager.extraLineFragmentRect
                let y = layoutManager.extraLineFragmentTextContainer === textContainer
                    ? extra.minY + origin.y
                    : result[index]?.maxY ?? origin.y
                blockRect = NSRect(x: origin.x, y: y, width: max(1, textView.bounds.width), height: fallbackHeight)
            }
            result[index + 1] = blockRect
        }
        return result
    }

    /// Zero-based logical lines, with one line of overscan at both boundaries.
    static func visibleLineSpan(for textView: NSTextView, ranges: [NSRange], visibleRect: NSRect) -> Range<Int> {
        guard !ranges.isEmpty, !visibleRect.isEmpty,
              let manager = textView.layoutManager,
              let container = textView.textContainer else { return 0..<0 }
        let origin = textView.textContainerOrigin
        let rect = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = manager.glyphRange(forBoundingRect: rect, in: container)
        guard glyphs.length > 0 else {
            if textView.string.isEmpty { return 0..<1 }
            if manager.extraLineFragmentRect.intersects(rect) { return max(0, ranges.count - 2)..<ranges.count }
            return 0..<0
        }
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        func line(containing location: Int) -> Int {
            var low = 0, high = ranges.count
            while low < high {
                let mid = low + (high - low) / 2
                if ranges[mid].location <= location { low = mid + 1 } else { high = mid }
            }
            return max(0, low - 1)
        }
        let first = line(containing: characters.location)
        let last = line(containing: max(characters.location, NSMaxRange(characters) - 1))
        return max(0, first - 1)..<min(ranges.count, last + 2)
    }

    private static func lineLayoutRange(for contentRange: NSRange, in text: NSString) -> NSRange {
        guard contentRange.length == 0, contentRange.location < text.length else { return contentRange }
        return text.lineRange(for: NSRange(location: contentRange.location, length: 0))
    }
}

enum IndexDiffSourceText {
    static func lineRanges(in text: String) -> [NSRange] { DiffSourceText.lineRanges(in: text) }
}
