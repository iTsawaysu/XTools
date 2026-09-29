import Foundation

/// Bounds synchronous tokenization before constructing Character arrays or
/// UTF-16 maps. A 32 Ki-unit line admits the existing 16 Ki-unit dense JSON
/// fixture; larger logical lines remain complete, selectable plain text.
/// Per-pass limits prevent many short visible lines from defeating the bound.
enum IndexSyntaxHighlightBudget {
    static let maximumLineUTF16 = 32_768
    static let maximumLineTokens = 8_192
    static let maximumPassUTF16 = 65_536
    static let maximumPassTokens = 16_384
}
