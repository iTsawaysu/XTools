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

    static func lineBlockRects(for textView: NSTextView) -> [Int: NSRect] {
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

        for (index, contentRange) in ranges.enumerated() {
            let lineNumber = index + 1
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
    static func sourceLines(in text: String) -> [String] {
        DiffSourceText.sourceLines(in: text)
    }

    static func lineRanges(in text: String) -> [NSRange] {
        DiffSourceText.lineRanges(in: text)
    }
}
