import AppKit
import Foundation

/// Per-line syntax token shared by the read-only code viewer. Offsets count
/// `String` characters (grapheme clusters), matching `JSONHighlightToken`;
/// AppKit surfaces convert them to UTF-16 ranges at apply time.
struct IndexSyntaxToken: Equatable {
    enum Kind: Equatable {
        case key
        case attribute
        case string
        case number
        case literal
        case punctuation
        case comment
    }

    let start: Int
    let length: Int
    let kind: Kind
}

/// Languages the shared code viewer can colorize viewport-lazily. Scanning is
/// stateless per line, so any visible window can be colored independently
/// without cross-line parser state.
enum IndexSyntaxKind {
    case json
    case yaml
    case sql
    case xml

    func tokens(line: String) -> [IndexSyntaxToken] {
        switch self {
        case .json:
            return JSONSyntaxHighlighter.tokens(line: line)
        case .yaml:
            return StructuredSyntaxHighlighter.yamlTokens(line: line)
        case .sql:
            return StructuredSyntaxHighlighter.sqlTokens(line: line)
        case .xml:
            return StructuredSyntaxHighlighter.xmlTokens(line: line)
        }
    }
}

extension IndexSyntaxToken.Kind {
    /// Content-only syntax palette stays sourced from `ToolTheme`; comments
    /// reuse the muted tertiary tone instead of introducing a new theme slot.
    var nsColor: NSColor {
        switch self {
        case .key:
            return ToolTheme.SynNSColor.key
        case .attribute:
            return ToolTheme.SynNSColor.bool
        case .string:
            return ToolTheme.SynNSColor.string
        case .number:
            return ToolTheme.SynNSColor.number
        case .literal:
            return ToolTheme.SynNSColor.bool
        case .punctuation:
            return ToolTheme.SynNSColor.punctuation
        case .comment:
            return NSColor(ToolTheme.textTertiary)
        }
    }
}

/// Pure line-span math behind viewport highlighting, isolated so the visible
/// window expansion is unit-testable without AppKit layout.
enum IndexViewportHighlightMath {
    /// Returns the logical-line index span covering `characterRange` plus
    /// `margin` lines on both sides, clamped to the available line count.
    static func lineSpan(
        covering characterRange: NSRange,
        lineRanges: [NSRange],
        margin: Int
    ) -> Range<Int> {
        guard !lineRanges.isEmpty else { return 0..<0 }
        guard characterRange.length > 0 || characterRange.location > 0 || lineRanges.count == 1 else {
            // Zero-length range at the very top still targets the first line.
            return clampedSpan(0, 0, lineRanges.count, margin)
        }

        var first = lineRanges.count - 1
        for (index, range) in lineRanges.enumerated() where characterRange.location < NSMaxRange(range) {
            first = index
            break
        }

        var last = 0
        let upperBound = max(characterRange.location, characterRange.location + characterRange.length - 1)
        for (index, range) in lineRanges.enumerated() where upperBound >= range.location {
            last = index
        }

        return clampedSpan(first, last, lineRanges.count, margin)
    }

    private static func clampedSpan(_ first: Int, _ last: Int, _ count: Int, _ margin: Int) -> Range<Int> {
        let lower = max(0, first - margin)
        let upper = min(count - 1, last + margin)
        guard lower <= upper else { return 0..<0 }
        return lower..<upper + 1
    }
}
