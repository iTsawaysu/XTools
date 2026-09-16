import SwiftUI

enum StructuredSyntaxHighlighter {
    static func xml(line: String) -> AttributedString {
        highlightDelimited(line: line, delimiters: ["<", ">", "/", "="])
    }

    static func yaml(line: String) -> AttributedString {
        var out = AttributedString(line)
        out.foregroundColor = ToolTheme.textPrimary
        out.appKit.foregroundColor = ToolTheme.SynNSColor.textPrimary

        if let colon = line.firstIndex(of: ":") {
            let keyLength = line.distance(from: line.startIndex, to: colon)
            color(&out, start: 0, length: keyLength, ToolTheme.synKey, nsColor: ToolTheme.SynNSColor.key)
            color(&out, start: keyLength, length: 1, ToolTheme.synPunctuation, nsColor: ToolTheme.SynNSColor.punctuation)
        }

        highlightQuotedSegments(in: &out, line: line)
        highlightLiterals(
            in: &out,
            line: line,
            literals: ["true", "false", "null", "yes", "no"],
            color: ToolTheme.synBool,
            nsColor: ToolTheme.SynNSColor.bool
        )
        return out
    }

    static func sql(line: String) -> AttributedString {
        var out = AttributedString(line)
        out.foregroundColor = ToolTheme.textPrimary
        out.appKit.foregroundColor = ToolTheme.SynNSColor.textPrimary

        highlightQuotedSegments(in: &out, line: line)
        highlightDelimitedCharacters(
            in: &out,
            line: line,
            characters: [",", "(", ")", "*", "=", ";"],
            nsColor: ToolTheme.SynNSColor.punctuation
        )
        highlightLiterals(
            in: &out,
            line: line,
            literals: [
                "select", "from", "where", "join", "left", "right", "inner", "outer",
                "with", "as", "insert", "update", "delete", "create", "alter", "drop",
                "group", "order", "by", "having", "limit", "offset", "values", "set",
                "and", "or", "not", "null", "is", "in", "case", "when", "then", "else", "end"
            ],
            color: ToolTheme.synKey,
            nsColor: ToolTheme.SynNSColor.key
        )
        return out
    }

    private static func highlightDelimited(line: String, delimiters: Set<Character>) -> AttributedString {
        var out = AttributedString(line)
        out.foregroundColor = ToolTheme.textPrimary
        out.appKit.foregroundColor = ToolTheme.SynNSColor.textPrimary
        highlightDelimitedCharacters(in: &out, line: line, characters: delimiters, nsColor: ToolTheme.SynNSColor.punctuation)
        highlightQuotedSegments(in: &out, line: line)
        return out
    }

    private static func highlightDelimitedCharacters(
        in output: inout AttributedString,
        line: String,
        characters: Set<Character>,
        nsColor: NSColor? = nil
    ) {
        for (offset, character) in line.enumerated() where characters.contains(character) {
            color(&output, start: offset, length: 1, ToolTheme.synPunctuation, nsColor: nsColor)
        }
    }

    private static func highlightQuotedSegments(in output: inout AttributedString, line: String) {
        var quoteStart: Int?
        for (offset, character) in line.enumerated() {
            guard character == "\"" || character == "'" else { continue }
            if let start = quoteStart {
                color(
                    &output,
                    start: start,
                    length: offset - start + 1,
                    ToolTheme.synString,
                    nsColor: ToolTheme.SynNSColor.string
                )
                quoteStart = nil
            } else {
                quoteStart = offset
            }
        }
    }

    private static func highlightLiterals(
        in output: inout AttributedString,
        line: String,
        literals: Set<String>,
        color literalColor: Color = ToolTheme.synBool,
        nsColor: NSColor? = nil
    ) {
        var cursor = line.startIndex
        while cursor < line.endIndex {
            while cursor < line.endIndex && !isWordChar(line[cursor]) {
                cursor = line.index(after: cursor)
            }
            guard cursor < line.endIndex else { break }
            let wordStart = cursor
            while cursor < line.endIndex && isWordChar(line[cursor]) {
                cursor = line.index(after: cursor)
            }
            let word = String(line[wordStart..<cursor]).lowercased()
            if literals.contains(word) {
                let start = line.distance(from: line.startIndex, to: wordStart)
                let length = line.distance(from: wordStart, to: cursor)
                color(&output, start: start, length: length, literalColor, nsColor: nsColor)
            }
        }
    }

    private static func isWordChar(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func color(
        _ output: inout AttributedString,
        start: Int,
        length: Int,
        _ color: Color,
        nsColor: NSColor? = nil
    ) {
        guard length > 0,
              let lower = output.characters.index(output.startIndex, offsetBy: start, limitedBy: output.endIndex),
              let upper = output.characters.index(lower, offsetBy: length, limitedBy: output.endIndex) else {
            return
        }
        output[lower..<upper].foregroundColor = color
        if let nsColor {
            output[lower..<upper].appKit.foregroundColor = nsColor
        }
    }
}
