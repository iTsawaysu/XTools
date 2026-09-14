import Foundation

struct SQLKeyword {
    let raw: String
    let normalized: String
    let length: Int
}

struct SQLFormatter {
    let tokens: [SQLToken]
    let options: SQLFormatting.Options
    var index = 0
    var lines: [String] = []
    var current = ""
    var currentIndentLevel = 0
    var currentAbsoluteIndent: Int?
    var blockIndentLevel = 0
    var listIndentLevel: Int?
    var conditionIndentLevel: Int?
    var inlineParenthesesDepth = 0
    var caseBaseIndents: [Int] = []
    var pendingLeadingComma = false
    var lastWordNormalized: String?
    var betweenDepth = 0
    var overDepth = 0
    var inCreateTable = false
    var createTableParenOpened = false

    init(tokens: [SQLToken], options: SQLFormatting.Options) {
        self.tokens = tokens
        self.options = options
    }

    mutating func render() -> String {
        while index < tokens.count {
            if let keyword = peekKeyword() {
                index += keyword.length
                handleKeyword(keyword)
            } else {
                consume(tokens[index])
                index += 1
            }
        }

        flushLine()
        return lines.joined(separator: "\n")
    }

    private mutating func handleKeyword(_ keyword: SQLKeyword) {
        let text = formattedKeyword(keyword)

        switch keyword.normalized {
        case "WITH":
            listIndentLevel = nil
            conditionIndentLevel = nil
            startClause(text, indent: blockIndentLevel)

        case "SELECT":
            conditionIndentLevel = nil
            startClause(text, indent: blockIndentLevel)
            // Only flush if DISTINCT doesn't follow.
            if peekWord(at: index)?.uppercased() != "DISTINCT" {
                flushLine()
                listIndentLevel = blockIndentLevel + 1
                setIndent(listIndentLevel ?? blockIndentLevel)
            }

        case "DISTINCT":
            appendWord(text, normalized: keyword.normalized)
            flushLine()
            listIndentLevel = blockIndentLevel + 1
            setIndent(listIndentLevel ?? blockIndentLevel)

        case "FROM":
            listIndentLevel = nil
            conditionIndentLevel = nil
            startClause(text, indent: blockIndentLevel)
            flushLine()
            listIndentLevel = blockIndentLevel + 1
            setIndent(listIndentLevel ?? blockIndentLevel)

        case "WHERE":
            listIndentLevel = nil
            startClause(text, indent: blockIndentLevel)
            flushLine()
            conditionIndentLevel = blockIndentLevel + 1
            setIndent(conditionIndentLevel ?? blockIndentLevel)

        case "GROUP BY", "ORDER BY":
            conditionIndentLevel = nil
            startClause(text, indent: blockIndentLevel)
            flushLine()
            listIndentLevel = blockIndentLevel + 1
            setIndent(listIndentLevel ?? blockIndentLevel)

        case "HAVING", "LIMIT", "OFFSET", "FETCH", "RETURNING":
            listIndentLevel = nil
            conditionIndentLevel = nil
            startClause(text, indent: blockIndentLevel)

        case "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "FULL JOIN", "CROSS JOIN",
             "LEFT OUTER JOIN", "RIGHT OUTER JOIN", "FULL OUTER JOIN":
            listIndentLevel = nil
            conditionIndentLevel = nil
            startClause(text, indent: blockIndentLevel + 1)

        case "ON":
            listIndentLevel = nil
            conditionIndentLevel = nil
            appendWord(text, normalized: keyword.normalized)

        case "AND", "OR":
            if betweenDepth > 0 && keyword.normalized == "AND" {
                betweenDepth -= 1
                appendWord(text, normalized: keyword.normalized)
            } else {
                listIndentLevel = nil
                flushLine()
                setIndent(conditionIndentLevel ?? blockIndentLevel + 1)
                appendWord(text, normalized: keyword.normalized)
            }

        case "UNION", "UNION ALL", "EXCEPT", "INTERSECT":
            listIndentLevel = nil
            conditionIndentLevel = nil
            startClause(text, indent: blockIndentLevel)
            flushLine()

        case "INSERT INTO", "UPDATE", "DELETE FROM", "ALTER TABLE":
            listIndentLevel = nil
            conditionIndentLevel = nil
            startClause(text, indent: blockIndentLevel)

        case "CREATE TABLE":
            listIndentLevel = nil
            conditionIndentLevel = nil
            startClause(text, indent: blockIndentLevel)
            inCreateTable = true

        case "ON UPDATE", "ON DELETE", "ON CONFLICT":
            appendWord(text, normalized: keyword.normalized)

        case "SET NULL", "SET DEFAULT":
            appendWord(text, normalized: keyword.normalized)

        case "BETWEEN":
            betweenDepth += 1
            appendWord(text, normalized: keyword.normalized)

        case "OVER":
            appendWord(text, normalized: keyword.normalized)

        case "PARTITION":
            if overDepth > 0 {
                flushLine()
                setIndent(currentIndentLevel + 1)
                appendWord(text, normalized: keyword.normalized)
            } else {
                appendWord(text, normalized: keyword.normalized)
            }

        case "VALUES", "SET":
            conditionIndentLevel = nil
            startClause(text, indent: blockIndentLevel)
            flushLine()
            listIndentLevel = blockIndentLevel + 1
            setIndent(listIndentLevel ?? blockIndentLevel)

        case "CASE":
            appendWord(text, normalized: keyword.normalized)
            flushLine()
            caseBaseIndents.append(currentIndentLevel)
            setIndent(currentIndentLevel + 1)

        case "WHEN", "ELSE":
            flushLine()
            setIndent((caseBaseIndents.last ?? blockIndentLevel) + 1)
            appendWord(text, normalized: keyword.normalized)

        case "END":
            flushLine()
            let baseIndent = caseBaseIndents.popLast() ?? blockIndentLevel
            setIndent(baseIndent)
            appendWord(text, normalized: keyword.normalized)

        default:
            appendWord(text, normalized: keyword.normalized)
        }
    }

    private mutating func consume(_ token: SQLToken) {
        switch token {
        case .word(let value):
            appendWord(value, normalized: value.uppercased())
        case .number(let value), .stringLiteral(let value):
            appendWord(value, normalized: nil)
        case .comment(let value):
            flushLine()
            appendWord(value, normalized: nil)
            flushLine()
        case .symbol(let value):
            handleSymbol(value)
        }
    }
}
