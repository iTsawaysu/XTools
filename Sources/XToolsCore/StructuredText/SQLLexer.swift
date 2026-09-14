import Foundation

enum SQLToken: Equatable {
    case word(String)
    case number(String)
    case stringLiteral(String)
    case comment(String)
    case symbol(String)

    var rawValue: String {
        switch self {
        case .word(let value), .number(let value), .stringLiteral(let value), .comment(let value), .symbol(let value):
            return value
        }
    }
}

struct SQLPositionedToken: Equatable {
    let token: SQLToken
    let offset: Int
}

struct SQLLexer {
    private let input: String
    private let characters: [Character]
    private var index = 0

    init(_ input: String) {
        self.input = input
        self.characters = Array(input)
    }

    mutating func tokenize() throws -> [SQLToken] {
        try tokenizeWithPositions().map(\.token)
    }

    mutating func tokenizeWithPositions() throws -> [SQLPositionedToken] {
        var tokens: [SQLPositionedToken] = []

        while let character = peek() {
            let startOffset = index

            if character.isWhitespace {
                advance()
            } else if character == "'" || character == "\"" || character == "`" {
                tokens.append(SQLPositionedToken(token: .stringLiteral(try readQuoted(until: character)), offset: startOffset))
            } else if character == "$", startsDollarQuotedLiteral() {
                throw SQLFormatting.ValidationError.unsupportedDialectLiteral(
                    diagnostic(
                        message: "暂不支持 PostgreSQL dollar-quoted 字符串",
                        offset: startOffset,
                        suggestion: "请先改用普通单引号字符串，或在 PostgreSQL 客户端/专用 SQL 格式化器中处理；本工具不会拆开 $$...$$ 或 $tag$...$tag$ 后伪成功。"
                    )
                )
            } else if character == "[" {
                tokens.append(SQLPositionedToken(token: .stringLiteral(try readBracketIdentifier()), offset: startOffset))
            } else if character == "-", peek(offset: 1) == "-" {
                tokens.append(SQLPositionedToken(token: .comment(readLineComment()), offset: startOffset))
            } else if character == "/", peek(offset: 1) == "*" {
                tokens.append(SQLPositionedToken(token: .comment(try readBlockComment()), offset: startOffset))
            } else if character.isLetter || character == "_" || startsAtPrefixedWord() {
                tokens.append(SQLPositionedToken(token: .word(readWord()), offset: startOffset))
            } else if character.isNumber {
                tokens.append(SQLPositionedToken(token: .number(readNumber()), offset: startOffset))
            } else {
                tokens.append(SQLPositionedToken(token: .symbol(readSymbol()), offset: startOffset))
            }
        }

        return tokens
    }

    private func startsDollarQuotedLiteral() -> Bool {
        guard peek() == "$" else { return false }

        if peek(offset: 1) == "$" {
            return true
        }

        guard let firstTagCharacter = peek(offset: 1),
              isDollarQuoteTagStart(firstTagCharacter) else {
            return false
        }

        var cursor = 2
        while let character = peek(offset: cursor), isDollarQuoteTagContinuation(character) {
            cursor += 1
        }

        return peek(offset: cursor) == "$"
    }

    private func isDollarQuoteTagStart(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private func isDollarQuoteTagContinuation(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private func startsAtPrefixedWord() -> Bool {
        guard peek() == "@", let next = peek(offset: 1) else { return false }
        return next.isLetter || next.isNumber || next == "_" || next == "@"
    }

    private func peek(offset: Int = 0) -> Character? {
        let position = index + offset
        guard characters.indices.contains(position) else { return nil }
        return characters[position]
    }

    private mutating func advance(_ amount: Int = 1) {
        index += amount
    }

    private mutating func readQuoted(until quote: Character) throws -> String {
        let startOffset = index
        var value = String(quote)
        advance()

        while let character = peek() {
            value.append(character)
            advance()

            if character == quote {
                if peek() == quote {
                    value.append(quote)
                    advance()
                    continue
                }
                return value
            }

            if character == "\\", let escaped = peek() {
                value.append(escaped)
                advance()
            }
        }

        throw SQLFormatting.ValidationError.unterminatedString(
            diagnostic(
                message: "字符串字面量没有闭合",
                offset: startOffset,
                suggestion: "补上结尾的 \(quote)，或检查字符串内部的转义和引号。"
            )
        )
    }

    private mutating func readBracketIdentifier() throws -> String {
        let startOffset = index
        var value = "["
        advance()

        while let character = peek() {
            value.append(character)
            advance()

            if character == "]" {
                return value
            }
        }

        throw SQLFormatting.ValidationError.unterminatedString(
            diagnostic(
                message: "方括号标识符没有闭合",
                offset: startOffset,
                suggestion: "补上 ]，或改用普通标识符。"
            )
        )
    }

    private mutating func readLineComment() -> String {
        var value = ""
        while let character = peek(), character != "\n" {
            value.append(character)
            advance()
        }
        return value
    }

    private mutating func readBlockComment() throws -> String {
        let startOffset = index
        var value = "/*"
        advance(2)

        while let character = peek() {
            if character == "*", peek(offset: 1) == "/" {
                value.append("*/")
                advance(2)
                return value
            }

            value.append(character)
            advance()
        }

        throw SQLFormatting.ValidationError.unterminatedBlockComment(
            diagnostic(
                message: "块注释没有闭合",
                offset: startOffset,
                suggestion: "补上 */，或删除未完成的块注释。"
            )
        )
    }

    private mutating func readWord() -> String {
        var value = ""
        while let character = peek(), character.isLetter || character.isNumber || character == "_" || character == "$" || character == "@" {
            value.append(character)
            advance()
        }
        return value
    }

    private mutating func readNumber() -> String {
        var value = ""
        while let character = peek(), character.isNumber || character == "." {
            value.append(character)
            advance()
        }
        return value
    }

    private mutating func readSymbol() -> String {
        let threeCharacterSymbols = ["->>", "#>>"]
        if let first = peek(), let second = peek(offset: 1), let third = peek(offset: 2) {
            let value = "\(first)\(second)\(third)"
            if threeCharacterSymbols.contains(value) {
                advance(3)
                return value
            }
        }

        let twoCharacterSymbols = [
            "<=", ">=", "<>", "!=", "||", "::", "->", "=>",
            "@>", "<@", "#>", "?&", "?|", "&&", "<<", ">>"
        ]
        if let first = peek(), let second = peek(offset: 1) {
            let value = "\(first)\(second)"
            if twoCharacterSymbols.contains(value) {
                advance(2)
                return value
            }
        }

        let value = String(peek() ?? " ")
        advance()
        return value
    }

    private func diagnostic(message: String, offset: Int, suggestion: String?) -> FormatDiagnostic {
        let boundedOffset = max(0, min(offset, input.count))
        let stringIndex = input.index(input.startIndex, offsetBy: boundedOffset)

        return FormatDiagnostic(
            formatName: "SQL",
            message: message,
            input: input,
            index: stringIndex,
            suggestion: suggestion
        )
    }
}
