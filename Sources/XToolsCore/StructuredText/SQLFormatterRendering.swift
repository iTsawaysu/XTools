import Foundation

extension SQLFormatter {
    mutating func handleSymbol(_ value: String) {
        switch value {
        case ",":
            if inlineParenthesesDepth > 0 {
                appendRaw(", ")
            } else if listIndentLevel != nil {
                handleListComma()
            } else {
                appendRaw(", ")
            }

        case ";":
            appendRaw(";")
            flushLine()
            resetStatementState()
            if index < tokens.count - 1 {
                lines.append("")
            }

        case ".":
            appendRaw(".")

        case "(":
            if nextTokenStartsQuery || (inCreateTable && !createTableParenOpened) {
                appendOpeningQueryParenthesis()
                if inCreateTable {
                    createTableParenOpened = true
                }
            } else {
                appendInlineOpeningParenthesis()
            }

        case ")":
            if overDepth > 0 {
                overDepth -= 1
                flushLine()
                setIndent(max(0, currentIndentLevel - 1))
                appendRaw(")")
            } else if inlineParenthesesDepth > 0 {
                inlineParenthesesDepth -= 1
                trimTrailingSpace()
                appendRaw(")")
            } else {
                flushLine()
                blockIndentLevel = max(0, blockIndentLevel - 1)
                setIndent(blockIndentLevel)
                appendRaw(")")
                inCreateTable = false
                createTableParenOpened = false
            }

        case "=", ">", "<", ">=", "<=", "<>", "!=", "||", "::", "->", "=>", "+", "-", "*", "/":
            appendOperator(value)

        default:
            appendWord(value, normalized: nil)
        }
    }

    mutating func startClause(_ text: String, indent: Int) {
        flushLine()
        setIndent(indent)
        appendWord(text, normalized: text.uppercased())
    }

    mutating func handleListComma() {
        switch options.commaStyle {
        case .trailing:
            appendRaw(",")
            flushLine()
            setIndent(listIndentLevel ?? blockIndentLevel)
        case .leading:
            flushLine()
            let spaces = max(0, ((listIndentLevel ?? blockIndentLevel) * options.indentWidth) - 2)
            currentAbsoluteIndent = spaces
            currentIndentLevel = listIndentLevel ?? blockIndentLevel
            pendingLeadingComma = true
        }
    }

    mutating func appendOpeningQueryParenthesis() {
        if current.trimmingCharacters(in: .whitespaces).isEmpty {
            appendRaw("(")
        } else {
            appendRaw(" (")
        }
        flushLine()
        blockIndentLevel += 1
        if inCreateTable {
            listIndentLevel = blockIndentLevel
        } else {
            listIndentLevel = nil
        }
        conditionIndentLevel = nil
        setIndent(blockIndentLevel)
    }

    mutating func appendInlineOpeningParenthesis() {
        let needsSpace = Self.inlineParenPrefixWords.contains(lastWordNormalized ?? "")

        if lastWordNormalized == "OVER" {
            appendRaw(" (")
            overDepth += 1
        } else {
            appendRaw(needsSpace ? " (" : "(")
            inlineParenthesesDepth += 1
        }
    }

    mutating func appendWord(_ value: String, normalized: String?) {
        if pendingLeadingComma {
            appendRaw(", ")
            pendingLeadingComma = false
        } else if needsSpaceBeforeWord {
            appendRaw(" ")
        }

        appendRaw(value)
        if let normalized {
            lastWordNormalized = normalized
        }
    }

    mutating func appendOperator(_ value: String) {
        if Self.unspacedOperators.contains(value) {
            trimTrailingSpace()
            appendRaw(value)
            return
        }

        trimTrailingSpace()
        appendRaw(" \(value) ")
        lastWordNormalized = nil
    }

    mutating func appendRaw(_ value: String) {
        if current.isEmpty {
            current = indentPrefix()
        }
        current += value
    }

    mutating func flushLine() {
        let line = current.trimmingTrailingWhitespace()
        if !line.isEmpty {
            lines.append(line)
        }
        current = ""
        currentAbsoluteIndent = nil
        pendingLeadingComma = false
    }

    mutating func setIndent(_ level: Int) {
        currentIndentLevel = max(0, level)
        currentAbsoluteIndent = nil
    }

    mutating func resetStatementState() {
        blockIndentLevel = 0
        listIndentLevel = nil
        conditionIndentLevel = nil
        currentIndentLevel = 0
        betweenDepth = 0
        overDepth = 0
        inlineParenthesesDepth = 0
        caseBaseIndents.removeAll()
        inCreateTable = false
        createTableParenOpened = false
    }

    mutating func trimTrailingSpace() {
        while current.last == " " {
            current.removeLast()
        }
    }

    var needsSpaceBeforeWord: Bool {
        guard let last = current.last else { return false }
        return last != " " && last != "(" && last != "." && last != "\n"
    }

    func indentPrefix() -> String {
        let count = currentAbsoluteIndent ?? (currentIndentLevel * options.indentWidth)
        return String(repeating: " ", count: count)
    }

    func formattedKeyword(_ keyword: SQLKeyword) -> String {
        switch options.keywordCase {
        case .upper:
            return keyword.normalized
        case .lower:
            return keyword.normalized.lowercased()
        }
    }

    var nextTokenStartsQuery: Bool {
        guard let next = peekWord(at: index + 1) else { return false }
        let normalized = next.uppercased()
        return normalized == "SELECT" || normalized == "WITH"
    }

    func peekKeyword() -> SQLKeyword? {
        guard let first = peekWord(at: index) else { return nil }
        let firstUpper = first.uppercased()

        for length in stride(from: min(3, tokens.count - index), through: 2, by: -1) {
            let words = (0..<length).compactMap { peekWord(at: index + $0) }
            guard words.count == length else { continue }
            let normalized = words.map { $0.uppercased() }.joined(separator: " ")
            if Self.multiWordKeywords.contains(normalized) {
                return SQLKeyword(raw: words.joined(separator: " "), normalized: normalized, length: length)
            }
        }

        guard Self.singleWordKeywords.contains(firstUpper) else { return nil }
        return SQLKeyword(raw: first, normalized: firstUpper, length: 1)
    }

    func peekWord(at position: Int) -> String? {
        guard tokens.indices.contains(position), case .word(let value) = tokens[position] else {
            return nil
        }
        return value
    }

    static let inlineParenPrefixWords: Set<String> = ["IN", "EXISTS", "VALUES"]
    static let unspacedOperators: Set<String> = ["::", "->", "->>", "#>", "#>>"]

    static let singleWordKeywords: Set<String> = [
        "SELECT", "WITH", "FROM", "WHERE", "GROUP", "BY", "HAVING", "ORDER", "LIMIT",
        "OFFSET", "FETCH", "JOIN", "LEFT", "RIGHT", "INNER", "FULL", "CROSS", "OUTER",
        "ON", "AND", "OR", "UNION", "ALL", "EXCEPT", "INTERSECT", "INSERT", "INTO",
        "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP",
        "CASE", "WHEN", "THEN", "ELSE", "END", "AS", "IS", "NOT", "NULL", "TRUE",
        "FALSE", "EXISTS", "IN", "LIKE", "BETWEEN", "DISTINCT", "OVER", "PARTITION",
        "DESC", "ASC", "RETURNING", "BEGIN", "COMMIT", "ROLLBACK"
    ]

    static let multiWordKeywords: Set<String> = [
        "GROUP BY", "ORDER BY", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "FULL JOIN",
        "CROSS JOIN", "LEFT OUTER JOIN", "RIGHT OUTER JOIN", "FULL OUTER JOIN",
        "UNION ALL", "INSERT INTO", "DELETE FROM", "CREATE TABLE", "ALTER TABLE",
        "IS NOT", "ON UPDATE", "ON DELETE", "ON CONFLICT", "SET NULL", "SET DEFAULT"
    ]
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var copy = self
        while let last = copy.last, last == " " || last == "\t" {
            copy.removeLast()
        }
        return copy
    }
}
