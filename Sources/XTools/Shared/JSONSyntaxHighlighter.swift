import SwiftUI
import XToolsCore

// MARK: - JSONSyntaxHighlighter

/// Turns a (already pretty-printed) JSON string into a colored `AttributedString`
/// using the shared content-only syntax palette: key / string / number /
/// bool-null / punctuation. Pure presentation — does not validate or reformat.
enum JSONSyntaxHighlighter {
    /// Highlight one line of JSON. Designed for the per-line gutter path in
    /// `IndexOutputSurface`, where each visual row is colored independently.
    /// Pretty-printed JSON keeps each token on a single line, so line-local
    /// scanning is accurate in practice.
    static func highlight(line: String) -> AttributedString {
        var out = AttributedString(line)
        out.foregroundColor = ToolTheme.textPrimary

        for token in JSONHighlighting.tokens(in: line) {
            guard let range = attributedRange(for: token, in: out) else {
                continue
            }

            out[range].foregroundColor = color(for: token.kind)
        }
        return out
    }

    static func highlight(line: String, segments: [DiffTextSegment]) -> AttributedString {
        var out = highlight(line: line)
        var cursor = out.startIndex

        for segment in segments {
            let characterCount = segment.text.count
            guard characterCount > 0 else {
                continue
            }

            let end = out.characters.index(cursor, offsetBy: characterCount, limitedBy: out.endIndex) ?? out.endIndex
            let range = cursor..<end

            switch segment.kind {
            case .unchanged:
                break
            case .added:
                out[range].backgroundColor = ToolTheme.successSoft
                out[range].underlineStyle = .single
            case .removed:
                out[range].backgroundColor = ToolTheme.errorSoft
                out[range].underlineStyle = .single
            }

            cursor = end

            if cursor == out.endIndex {
                break
            }
        }

        return out
    }

    private static func attributedRange(
        for token: JSONHighlightToken,
        in string: AttributedString
    ) -> Range<AttributedString.Index>? {
        guard token.length > 0,
              let start = string.characters.index(
                string.startIndex,
                offsetBy: token.start,
                limitedBy: string.endIndex
              ),
              let end = string.characters.index(
                start,
                offsetBy: token.length,
                limitedBy: string.endIndex
              ) else {
            return nil
        }

        return start..<end
    }

    private static func color(for kind: JSONHighlightToken.Kind) -> Color {
        switch kind {
        case .key:
            return ToolTheme.synKey
        case .string:
            return ToolTheme.synString
        case .number:
            return ToolTheme.synNumber
        case .literal:
            return ToolTheme.synBool
        case .punctuation:
            return ToolTheme.synPunctuation
        }
    }
}
