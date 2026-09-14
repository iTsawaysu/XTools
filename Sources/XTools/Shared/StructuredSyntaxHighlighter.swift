import SwiftUI

enum StructuredSyntaxHighlighter {
    static func xml(line: String) -> AttributedString {
        highlightDelimited(line: line, delimiters: ["<", ">", "/", "="])
    }

    static func yaml(line: String) -> AttributedString {
        var out = AttributedString(line)
        out.foregroundColor = ToolTheme.textPrimary

        if let colon = line.firstIndex(of: ":") {
            let keyLength = line.distance(from: line.startIndex, to: colon)
            color(&out, start: 0, length: keyLength, ToolTheme.synKey)
            color(&out, start: keyLength, length: 1, ToolTheme.synPunctuation)
        }

        highlightQuotedSegments(in: &out, line: line)
        highlightLiterals(in: &out, line: line, literals: ["true", "false", "null", "yes", "no"])
        return out
    }

    static func sql(line: String) -> AttributedString {
        var out = AttributedString(line)
        out.foregroundColor = ToolTheme.textPrimary

        highlightQuotedSegments(in: &out, line: line)
        highlightDelimitedCharacters(in: &out, line: line, characters: [",", "(", ")", "*", "=", ";"])
        highlightLiterals(
            in: &out,
            line: line,
            literals: [
                "select", "from", "where", "join", "left", "right", "inner", "outer",
                "with", "as", "insert", "update", "delete", "create", "alter", "drop",
                "group", "order", "by", "having", "limit", "offset", "values", "set",
                "and", "or", "not", "null", "is", "in", "case", "when", "then", "else", "end"
            ],
            color: ToolTheme.synKey
        )
        return out
    }

    private static func highlightDelimited(line: String, delimiters: Set<Character>) -> AttributedString {
        var out = AttributedString(line)
        out.foregroundColor = ToolTheme.textPrimary
        highlightDelimitedCharacters(in: &out, line: line, characters: delimiters)
        highlightQuotedSegments(in: &out, line: line)
        return out
    }

    private static func highlightDelimitedCharacters(
        in output: inout AttributedString,
        line: String,
        characters: Set<Character>
    ) {
        for (offset, character) in line.enumerated() where characters.contains(character) {
            color(&output, start: offset, length: 1, ToolTheme.synPunctuation)
        }
    }

    private static func highlightQuotedSegments(in output: inout AttributedString, line: String) {
        var quoteStart: Int?
        for (offset, character) in line.enumerated() {
            guard character == "\"" || character == "'" else { continue }
            if let start = quoteStart {
                color(&output, start: start, length: offset - start + 1, ToolTheme.synString)
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
        color literalColor: Color = ToolTheme.synBool
    ) {
        let words = line.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
        for word in words {
            let token = String(word).lowercased()
            guard literals.contains(token),
                  let range = line.range(of: String(word)) else { continue }
            let start = line.distance(from: line.startIndex, to: range.lowerBound)
            color(&output, start: start, length: word.count, literalColor)
        }
    }

    private static func color(
        _ output: inout AttributedString,
        start: Int,
        length: Int,
        _ color: Color
    ) {
        guard length > 0,
              let lower = output.characters.index(output.startIndex, offsetBy: start, limitedBy: output.endIndex),
              let upper = output.characters.index(lower, offsetBy: length, limitedBy: output.endIndex) else {
            return
        }
        output[lower..<upper].foregroundColor = color
    }
}
