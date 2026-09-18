import SwiftUI

/// Stateless per-line tokenizers for YAML / SQL / XML plus the
/// `AttributedString` projections used by SwiftUI `Text` output paths.
/// Token output (character offsets) is the single source of truth; the
/// attributed wrappers and the AppKit viewer both render from it.
enum StructuredSyntaxHighlighter {
    // MARK: - AttributedString projections

    static func xml(line: String) -> AttributedString {
        attributed(line: line, tokens: xmlTokens(line: line))
    }

    static func yaml(line: String) -> AttributedString {
        attributed(line: line, tokens: yamlTokens(line: line))
    }

    static func sql(line: String) -> AttributedString {
        attributed(line: line, tokens: sqlTokens(line: line))
    }

    private static func attributed(line: String, tokens: [IndexSyntaxToken]) -> AttributedString {
        var out = AttributedString(line)
        out.foregroundColor = ToolTheme.textPrimary
        out.appKit.foregroundColor = ToolTheme.SynNSColor.textPrimary

        for token in tokens {
            guard let range = characterRange(start: token.start, length: token.length, in: &out) else {
                continue
            }
            out[range].foregroundColor = foregroundColor(for: token.kind)
            out[range].appKit.foregroundColor = token.kind.nsColor
        }
        return out
    }

    private static func foregroundColor(for kind: IndexSyntaxToken.Kind) -> Color {
        switch kind {
        case .key:
            return ToolTheme.synKey
        case .attribute, .literal:
            return ToolTheme.synBool
        case .string:
            return ToolTheme.synString
        case .number:
            return ToolTheme.synNumber
        case .punctuation:
            return ToolTheme.synPunctuation
        case .comment:
            return ToolTheme.textTertiary
        }
    }

    private static func characterRange(
        start: Int,
        length: Int,
        in output: inout AttributedString
    ) -> Range<AttributedString.Index>? {
        guard length > 0,
              let lower = output.characters.index(output.startIndex, offsetBy: start, limitedBy: output.endIndex),
              let upper = output.characters.index(lower, offsetBy: length, limitedBy: output.endIndex) else {
            return nil
        }
        return lower..<upper
    }

    // MARK: - YAML tokens

    static func yamlTokens(line: String) -> [IndexSyntaxToken] {
        var tokens: [IndexSyntaxToken] = []
        let characters = Array(line)

        // A comment starts at `#` only when it opens the line or follows
        // whitespace, outside quotes.
        if let commentStart = yamlCommentStart(in: characters) {
            if commentStart > 0 {
                appendYamlContent(in: Array(characters[..<commentStart]), into: &tokens)
            }
            tokens.append(IndexSyntaxToken(
                start: commentStart,
                length: characters.count - commentStart,
                kind: .comment
            ))
            return tokens
        }

        appendYamlContent(in: characters, into: &tokens)
        return tokens
    }

    private static func appendYamlContent(in characters: [Character], into tokens: inout [IndexSyntaxToken]) {
        var index = skipIndent(characters, from: 0)

        // List marker: leading `-` followed by whitespace.
        if index < characters.count, characters[index] == "-",
           index + 1 < characters.count, characters[index + 1] == " " || characters[index + 1] == "\t" {
            tokens.append(IndexSyntaxToken(start: index, length: 1, kind: .punctuation))
            index = skipIndent(characters, from: index + 1)
        }

        guard index < characters.count else { return }

        // Key: the content before the first top-level `:` followed by
        // whitespace or end of line. `- 8080:80` has no such colon, so the
        // port pair never colors as a key.
        if let colon = yamlKeyColon(in: characters, from: index) {
            let keyLength = colon - index
            if keyLength > 0 {
                tokens.append(IndexSyntaxToken(start: index, length: keyLength, kind: .key))
            }
            tokens.append(IndexSyntaxToken(start: colon, length: 1, kind: .punctuation))
            appendScalarTokens(in: characters, from: colon + 1, into: &tokens)
        } else {
            appendScalarTokens(in: characters, from: index, into: &tokens)
        }
    }

    private static func yamlCommentStart(in characters: [Character]) -> Int? {
        var inSingleQuote = false
        var inDoubleQuote = false

        for (offset, character) in characters.enumerated() {
            switch character {
            case "'" where !inDoubleQuote:
                inSingleQuote.toggle()
            case "\"" where !inSingleQuote:
                inDoubleQuote.toggle()
            case "#" where !inSingleQuote && !inDoubleQuote:
                if offset == 0 || characters[offset - 1] == " " || characters[offset - 1] == "\t" {
                    return offset
                }
            default:
                break
            }
        }
        return nil
    }

    private static func skipIndent(_ characters: [Character], from start: Int) -> Int {
        var index = start
        while index < characters.count, characters[index] == " " || characters[index] == "\t" {
            index += 1
        }
        return index
    }

    private static func yamlKeyColon(in characters: [Character], from start: Int) -> Int? {
        var inSingleQuote = false
        var inDoubleQuote = false

        var index = start
        while index < characters.count {
            let character = characters[index]
            if character == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
            } else if character == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
            } else if character == ":" && !inSingleQuote && !inDoubleQuote {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                if next == nil || next == " " || next == "\t" {
                    return index
                }
            }
            index += 1
        }
        return nil
    }

    private static let yamlFlowPunctuation: Set<Character> = [",", "[", "]", "{", "}"]

    /// Scans a value region for quoted strings, literals, numbers, and flow
    /// punctuation.
    private static func appendScalarTokens(
        in characters: [Character],
        from start: Int,
        into tokens: inout [IndexSyntaxToken]
    ) {
        var index = start
        var wordStart: Int?
        var quote: Character?

        func flushWord(endingAt end: Int) {
            guard let begin = wordStart, end > begin else {
                wordStart = nil
                return
            }
            let word = String(characters[begin..<end])
            let length = end - begin
            if yamlLiterals.contains(word.lowercased()) {
                tokens.append(IndexSyntaxToken(start: begin, length: length, kind: .literal))
            } else if isNumberScalar(word) {
                tokens.append(IndexSyntaxToken(start: begin, length: length, kind: .number))
            }
            wordStart = nil
        }

        while index <= characters.count {
            let character: Character? = index < characters.count ? characters[index] : nil

            if let open = quote {
                if character == open {
                    tokens.append(IndexSyntaxToken(
                        start: wordStart ?? index,
                        length: index - (wordStart ?? index) + 1,
                        kind: .string
                    ))
                    wordStart = nil
                    quote = nil
                }
            } else if character == "'" || character == "\"" {
                flushWord(endingAt: index)
                quote = character
                wordStart = index
            } else if character == nil || character == " " || character == "\t" {
                flushWord(endingAt: index)
            } else if let scalar = character, yamlFlowPunctuation.contains(scalar) {
                flushWord(endingAt: index)
                tokens.append(IndexSyntaxToken(start: index, length: 1, kind: .punctuation))
            } else if wordStart == nil {
                wordStart = index
            }
            index += 1
        }
    }

    private static let yamlLiterals: Set<String> = [
        "true", "false", "null", "yes", "no", "on", "off", "~"
    ]

    private static func isNumberScalar(_ word: String) -> Bool {
        guard let first = word.first, first.isNumber || first == "-" || first == "+" || first == "." else {
            return false
        }
        var decimalPoints = 0
        for (offset, scalar) in word.enumerated() where scalar == "." {
            decimalPoints += 1
            if offset == 0 || offset == word.count - 1 {
                return false
            }
        }
        guard decimalPoints <= 1 else { return false }
        return word.drop { $0 == "-" || $0 == "+" }.allSatisfy { $0.isNumber || $0 == "." }
    }

    // MARK: - SQL tokens

    static func sqlTokens(line: String) -> [IndexSyntaxToken] {
        var tokens: [IndexSyntaxToken] = []
        appendSqlContent(in: Array(line), into: &tokens)
        return tokens
    }

    private static let sqlKeywords: Set<String> = [
        "select", "from", "where", "join", "left", "right", "inner", "outer", "full",
        "cross", "with", "recursive", "as", "insert", "update", "delete", "create",
        "alter", "drop", "group", "order", "by", "having", "limit", "offset", "values",
        "set", "and", "or", "not", "null", "is", "in", "case", "when", "then", "else",
        "end", "union", "all", "distinct", "on", "using", "exists", "between", "like",
        "asc", "desc", "truncate"
    ]

    private static let sqlPunctuation: Set<Character> = [",", "(", ")", "*", "=", ";", "."]

    private static let sqlLiteralWords: Set<String> = ["true", "false", "null"]

    private static func appendSqlContent(in characters: [Character], into tokens: inout [IndexSyntaxToken]) {
        // Line-local SQL scanning: quotes switch to string tokens, `--` and
        // `/*` open comments (block comments stay line-local), words classify
        // against the keyword/literal sets, digits form numbers.
        var index = 0
        var wordStart: Int?
        var quote: Character?

        func flushWord(endingAt end: Int) {
            guard let begin = wordStart, end > begin else {
                wordStart = nil
                return
            }
            let word = String(characters[begin..<end])
            let length = end - begin
            let lowercased = word.lowercased()
            if sqlKeywords.contains(lowercased) {
                tokens.append(IndexSyntaxToken(start: begin, length: length, kind: .key))
            } else if sqlLiteralWords.contains(lowercased) {
                tokens.append(IndexSyntaxToken(start: begin, length: length, kind: .literal))
            } else if isNumberScalar(word) {
                tokens.append(IndexSyntaxToken(start: begin, length: length, kind: .number))
            }
            wordStart = nil
        }

        while index < characters.count {
            let character = characters[index]

            if let open = quote {
                if character == open {
                    tokens.append(IndexSyntaxToken(
                        start: wordStart ?? index,
                        length: index - (wordStart ?? index) + 1,
                        kind: .string
                    ))
                    wordStart = nil
                    quote = nil
                }
                index += 1
                continue
            }

            if character == "'" || character == "\"" {
                flushWord(endingAt: index)
                quote = character
                wordStart = index
                index += 1
                continue
            }

            if character == "-", index + 1 < characters.count, characters[index + 1] == "-" {
                flushWord(endingAt: index)
                tokens.append(IndexSyntaxToken(
                    start: index,
                    length: characters.count - index,
                    kind: .comment
                ))
                return
            }

            if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                flushWord(endingAt: index)
                var end = index + 2
                while end < characters.count {
                    if characters[end] == "*", end + 1 < characters.count, characters[end + 1] == "/" {
                        end += 2
                        break
                    }
                    end += 1
                }
                tokens.append(IndexSyntaxToken(
                    start: index,
                    length: min(end, characters.count) - index,
                    kind: .comment
                ))
                index = min(end, characters.count)
                continue
            }

            if sqlPunctuation.contains(character) {
                flushWord(endingAt: index)
                tokens.append(IndexSyntaxToken(start: index, length: 1, kind: .punctuation))
                index += 1
                continue
            }

            if character == " " || character == "\t" {
                flushWord(endingAt: index)
                index += 1
                continue
            }

            if wordStart == nil {
                wordStart = index
            }
            index += 1
        }
        flushWord(endingAt: characters.count)
    }

    // MARK: - XML tokens

    static func xmlTokens(line: String) -> [IndexSyntaxToken] {
        var tokens: [IndexSyntaxToken] = []
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            guard characters[index] == "<" else {
                index += 1
                continue
            }

            if matches(characters, at: index + 1, "!--") {
                let start = index
                index += 4
                while index < characters.count, !matches(characters, at: index, "-->") {
                    index += 1
                }
                let end = min(index + 3, characters.count)
                tokens.append(IndexSyntaxToken(start: start, length: end - start, kind: .comment))
                index = end
                continue
            }

            let isClosing = index + 1 < characters.count && characters[index + 1] == "/"

            tokens.append(IndexSyntaxToken(start: index, length: 1, kind: .punctuation))
            index += 1
            if isClosing {
                tokens.append(IndexSyntaxToken(start: index, length: 1, kind: .punctuation))
                index += 1
            }
            if index < characters.count, characters[index] == "?" || characters[index] == "!" {
                tokens.append(IndexSyntaxToken(start: index, length: 1, kind: .punctuation))
                index += 1
            }

            // Tag or declaration name.
            let nameStart = index
            while index < characters.count,
                  characters[index].isLetter || characters[index].isNumber
                    || characters[index] == "_" || characters[index] == "-"
                    || characters[index] == ":" || characters[index] == "." {
                index += 1
            }
            if index > nameStart {
                tokens.append(IndexSyntaxToken(
                    start: nameStart,
                    length: index - nameStart,
                    kind: .key
                ))
            }

            // Attributes until the tag closes. `>` inside quoted values never
            // terminates the tag.
            while index < characters.count {
                let character = characters[index]
                if character == ">" {
                    tokens.append(IndexSyntaxToken(start: index, length: 1, kind: .punctuation))
                    index += 1
                    break
                }
                if character == "/" && index + 1 < characters.count && characters[index + 1] == ">" {
                    tokens.append(IndexSyntaxToken(start: index, length: 2, kind: .punctuation))
                    index += 2
                    break
                }
                if character == "?" && index + 1 < characters.count && characters[index + 1] == ">" {
                    tokens.append(IndexSyntaxToken(start: index, length: 2, kind: .punctuation))
                    index += 2
                    break
                }
                if character == " " || character == "\t" {
                    index += 1
                    continue
                }
                if character == "=" {
                    tokens.append(IndexSyntaxToken(start: index, length: 1, kind: .punctuation))
                    index += 1
                    continue
                }
                if character == "'" || character == "\"" {
                    let quoteStart = index
                    index += 1
                    while index < characters.count, characters[index] != character {
                        index += 1
                    }
                    index = min(index + 1, characters.count)
                    tokens.append(IndexSyntaxToken(start: quoteStart, length: index - quoteStart, kind: .string))
                    continue
                }

                let attributeStart = index
                while index < characters.count {
                    let scalar = characters[index]
                    if scalar == " " || scalar == "\t" || scalar == "=" || scalar == ">"
                        || (scalar == "/" && index + 1 < characters.count && characters[index + 1] == ">") {
                        break
                    }
                    index += 1
                }
                if index > attributeStart {
                    tokens.append(IndexSyntaxToken(start: attributeStart, length: index - attributeStart, kind: .attribute))
                }
            }
        }

        return tokens
    }

    private static func matches(_ characters: [Character], at index: Int, _ literal: String) -> Bool {
        let scalars = Array(literal)
        guard index + scalars.count <= characters.count else { return false }
        for offset in scalars.indices where characters[index + offset] != scalars[offset] {
            return false
        }
        return true
    }
}
