import XToolsCore
import AppKit

@MainActor
enum IndexDiffTextLayoutGeometry {
    static func defaultLineHeight(for textView: NSTextView) -> CGFloat {
        guard let layoutManager = textView.layoutManager else {
            return 16
        }

        return layoutManager.defaultLineHeight(
            for: textView.font ?? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        )
    }

    static func documentHeight(for textView: NSTextView) -> CGFloat {
        IndexTextKitGeometry.measuredTextHeight(for: textView)
    }

    static func lineBlockRects(for textView: NSTextView, visibleRect: NSRect? = nil) -> [Int: NSRect] {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return [:]
        }

        layoutManager.ensureLayout(for: textContainer)
        let nsText = textView.string as NSString
        let ranges = IndexDiffSourceText.lineRanges(in: textView.string)
        let origin = textView.textContainerOrigin
        let fallbackHeight = defaultLineHeight(for: textView)
        var result: [Int: NSRect] = [:]
        var previousMaxY = textView.textContainerInset.height

        // Line numbers are 1-based; iterating one line before and after the
        // visible window keeps the fallback-height chain (previousMaxY)
        // seeded while skipping the off-screen bulk of long documents.
        let firstLine = visibleRect.flatMap {
            visibleLineWindow(in: ranges, textView: textView, layoutManager: layoutManager, textContainer: textContainer, visibleRect: $0)
        }?.lowerBound ?? 1

        for (index, contentRange) in ranges.enumerated() {
            let lineNumber = index + 1
            guard lineNumber >= max(1, firstLine - 1) else { continue }
            let layoutRange = lineLayoutRange(for: contentRange, in: nsText)
            var blockRect = NSRect.null

            if layoutRange.length > 0 {
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: layoutRange,
                    actualCharacterRange: nil
                )
                if glyphRange.length > 0 {
                    layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragmentRect, _, _, _, _ in
                        var rect = fragmentRect
                        rect.origin.x += origin.x
                        rect.origin.y += origin.y
                        blockRect = blockRect.isNull ? rect : blockRect.union(rect)
                    }
                }
            }

            if blockRect.isNull {
                blockRect = NSRect(
                    x: origin.x,
                    y: previousMaxY,
                    width: max(1, textView.bounds.width),
                    height: fallbackHeight
                )
            }

            result[lineNumber] = blockRect
            previousMaxY = blockRect.maxY
        }

        return result
    }

    /// Maps the on-screen visible rect to a 1-based closed line-number range
    /// by asking TextKit which glyphs are actually visible.
    private static func visibleLineWindow(
        in ranges: [NSRange],
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        visibleRect: NSRect
    ) -> ClosedRange<Int>? {
        let origin = textView.textContainerOrigin
        let containerRect = NSRect(
            x: visibleRect.minX - origin.x,
            y: visibleRect.minY - origin.y,
            width: visibleRect.width,
            height: visibleRect.height
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        guard glyphRange.length > 0 else { return nil }

        var characterRange = NSRange(location: 0, length: 0)
        layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: &characterRange)
        let visibleStart = characterRange.location
        let visibleEnd = characterRange.location + characterRange.length

        var first: Int?
        var last: Int?
        for (index, lineRange) in ranges.enumerated() {
            let lineStart = lineRange.location
            // Empty lines are zero-length; treat them as a point so they stay
            // drawable when their newline sits on the visible boundary.
            let lineEnd = lineRange.location + max(lineRange.length, 1)
            if lineEnd < visibleStart || lineStart > visibleEnd { continue }
            if first == nil { first = index + 1 }
            last = index + 1
        }

        guard let first, let last else { return nil }
        return first...last
    }

    private static func lineLayoutRange(for contentRange: NSRange, in nsText: NSString) -> NSRange {
        guard nsText.length > 0 else {
            return NSRange(location: 0, length: 0)
        }

        if contentRange.length > 0 {
            return contentRange
        }

        if contentRange.location >= nsText.length {
            return NSRange(location: nsText.length, length: 0)
        }

        return nsText.lineRange(for: NSRange(location: contentRange.location, length: 0))
    }
}

enum IndexDiffSourceText {
    static func lineRanges(in text: String) -> [NSRange] {
        DiffSourceText.lineRanges(in: text)
    }
}
