import Foundation

/// TextKit 1 typesets a whole paragraph even for a small visible-rect request.
/// Only the read-only preview is bounded; its owner retains the complete output.
struct IndexCodePreviewPlan {
    let displayedText: String
    let previewCharacterCount: Int?

    static func make(text: String, permitsFullText: Bool) -> Self {
        let source = text as NSString
        let limit = IndexSyntaxHighlightBudget.maximumLineUTF16
        guard !permitsFullText, source.length > limit else {
            return Self(displayedText: text, previewCharacterCount: nil)
        }
        var cursor = 0
        while cursor < source.length {
            let range = source.paragraphRange(for: NSRange(location: cursor, length: 0))
            if range.length > limit {
                var boundary = min(limit, source.length)
                if boundary > 0, (0xD800...0xDBFF).contains(source.character(at: boundary - 1)) {
                    boundary -= 1
                }
                // Dropping the last candidate grapheme is deliberate: it may
                // continue beyond the bounded candidate. Never scan that tail.
                let candidate = source.substring(to: boundary)
                let prefix = candidate.isEmpty ? "" : String(candidate.dropLast())
                return Self(displayedText: prefix, previewCharacterCount: prefix.count)
            }
            cursor = NSMaxRange(range)
        }
        return Self(displayedText: text, previewCharacterCount: nil)
    }
}
