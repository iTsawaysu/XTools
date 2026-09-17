import Foundation

public enum SQLFormatting {
    public enum KeywordCase: String, CaseIterable, Sendable {
        case upper
        case lower
    }

    public enum CommaStyle: String, CaseIterable, Sendable {
        case trailing
        case leading
    }

    public struct Options: Equatable, Sendable {
        public var keywordCase: KeywordCase
        public var indentWidth: Int
        public var commaStyle: CommaStyle
        public var minify: Bool

        public init(
            keywordCase: KeywordCase = .upper,
            indentWidth: Int = 2,
            commaStyle: CommaStyle = .trailing,
            minify: Bool = false
        ) {
            self.keywordCase = keywordCase
            self.indentWidth = max(2, min(8, indentWidth))
            self.commaStyle = commaStyle
            self.minify = minify
        }
    }

    public enum ValidationError: Error, Equatable, LocalizedError {
        case emptyInput(FormatDiagnostic)
        case missingStatementKeyword(FormatDiagnostic)
        case incompleteStatement(FormatDiagnostic)
        case unbalancedParentheses(FormatDiagnostic)
        case unterminatedString(FormatDiagnostic)
        case unterminatedBlockComment(FormatDiagnostic)
        case unsupportedDialectLiteral(FormatDiagnostic)

        public var errorDescription: String? {
            diagnostic.workspaceMessage
        }

        public var diagnostic: FormatDiagnostic {
            switch self {
            case .emptyInput(let diagnostic),
                 .missingStatementKeyword(let diagnostic),
                 .incompleteStatement(let diagnostic),
                 .unbalancedParentheses(let diagnostic),
                 .unterminatedString(let diagnostic),
                 .unterminatedBlockComment(let diagnostic),
                 .unsupportedDialectLiteral(let diagnostic):
                return diagnostic
            }
        }
    }

    public static func validate(_ input: String) throws {
        var lexer = SQLLexer(input)
        let tokens = try lexer.tokenizeWithPositions()
        try validate(tokens, input: input)
    }

    public static func format(_ input: String, options: Options = Options()) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var lexer = SQLLexer(trimmed)
        let positionedTokens = try lexer.tokenizeWithPositions()
        try validate(positionedTokens, input: trimmed)

        var formatter = SQLFormatter(tokens: positionedTokens.map(\.token), options: options)
        return formatter.render()
    }

    private static func validate(_ tokens: [SQLPositionedToken], input: String) throws {
        guard !tokens.isEmpty else {
            throw ValidationError.emptyInput(
                FormatDiagnostic(
                    formatName: "SQL",
                    message: "SQL 不能为空",
                    suggestion: "输入 SELECT、INSERT、UPDATE、DELETE 等 SQL 语句后再格式化。"
                )
            )
        }

        var openParentheses: [SQLPositionedToken] = []
        var hasStatementKeyword = false

        for positionedToken in tokens {
            switch positionedToken.token {
            case .symbol("("):
                openParentheses.append(positionedToken)
            case .symbol(")"):
                guard !openParentheses.isEmpty else {
                    throw ValidationError.unbalancedParentheses(
                        diagnostic(
                            input: input,
                            offset: positionedToken.offset,
                            message: "右括号没有对应的左括号",
                            suggestion: "删除这个 )，或在前面补上对应的 (。"
                        )
                    )
                }
                _ = openParentheses.removeLast()
            case .word(let value):
                if statementKeywords.contains(value.uppercased()) {
                    hasStatementKeyword = true
                }
            default:
                break
            }
        }

        if let unmatchedOpening = openParentheses.last {
            throw ValidationError.unbalancedParentheses(
                diagnostic(
                    input: input,
                    offset: unmatchedOpening.offset,
                    message: "左括号没有对应的右括号",
                    suggestion: "补上对应的 )，或删除多余的 (。"
                )
            )
        }

        if let standaloneClauseDiagnostic = standaloneClauseDiagnostic(in: tokens, input: input) {
            throw ValidationError.incompleteStatement(standaloneClauseDiagnostic)
        }

        guard hasStatementKeyword else {
            throw ValidationError.missingStatementKeyword(
                diagnostic(
                    input: input,
                    offset: firstNonWhitespaceOffset(in: input),
                    message: "未找到可识别的 SQL 语句关键字",
                    suggestion: "确认语句以 SELECT、WITH、INSERT、UPDATE、DELETE、CREATE 等关键字开头。"
                )
            )
        }

        try validateObviousSelectStructure(tokens, input: input)
    }

    private static func validateObviousSelectStructure(_ tokens: [SQLPositionedToken], input: String) throws {
        var statementStart = tokens.startIndex
        var depth = 0

        for index in tokens.indices {
            switch tokens[index].token {
            case .symbol("("):
                depth += 1
            case .symbol(")"):
                depth = max(0, depth - 1)
            case .symbol(";") where depth == 0:
                try validateSelectStatement(tokens[statementStart..<index], input: input)
                statementStart = tokens.index(after: index)
            default:
                break
            }
        }

        if statementStart < tokens.endIndex {
            try validateSelectStatement(tokens[statementStart..<tokens.endIndex], input: input)
        }
    }

    private static func validateSelectStatement(
        _ tokens: ArraySlice<SQLPositionedToken>,
        input: String
    ) throws {
        guard let selectIndex = firstTopLevelKeywordIndex("SELECT", in: tokens) else {
            return
        }

        guard hasTopLevelExpression(after: selectIndex, in: tokens) else {
            throw ValidationError.incompleteStatement(
                diagnostic(
                    input: input,
                    offset: tokens[selectIndex].offset,
                    message: "SELECT 缺少要查询的列或表达式",
                    suggestion: "在 SELECT 后补上列名、表达式或 *。"
                )
            )
        }

        try validateFromClauses(in: tokens, input: input)
        try validateOrderByClauses(in: tokens, input: input)
    }

    private static func validateFromClauses(
        in tokens: ArraySlice<SQLPositionedToken>,
        input: String
    ) throws {
        for index in tokens.indices where isTopLevelKeyword("FROM", at: index, in: tokens) {
            guard hasTopLevelExpression(after: index, in: tokens) else {
                throw ValidationError.incompleteStatement(
                    diagnostic(
                        input: input,
                        offset: tokens[index].offset,
                        message: "FROM 缺少表名或子查询",
                        suggestion: "在 FROM 后补上表名、视图名或子查询。"
                    )
                )
            }
        }
    }

    private static func validateOrderByClauses(
        in tokens: ArraySlice<SQLPositionedToken>,
        input: String
    ) throws {
        for index in tokens.indices where isTopLevelKeyword("ORDER", at: index, in: tokens) {
            guard let nextIndex = nextSignificantTopLevelIndex(after: index, in: tokens),
                  isKeyword("BY", tokens[nextIndex].token),
                  hasTopLevelExpression(after: nextIndex, in: tokens) else {
                throw ValidationError.incompleteStatement(
                    diagnostic(
                        input: input,
                        offset: tokens[index].offset,
                        message: "ORDER BY 缺少排序表达式",
                        suggestion: "在 ORDER BY 后补上列名或排序表达式。"
                    )
                )
            }
        }
    }

    private static func firstTopLevelKeywordIndex(
        _ keyword: String,
        in tokens: ArraySlice<SQLPositionedToken>
    ) -> ArraySlice<SQLPositionedToken>.Index? {
        tokens.indices.first { isTopLevelKeyword(keyword, at: $0, in: tokens) }
    }

    private static func hasTopLevelExpression(
        after index: ArraySlice<SQLPositionedToken>.Index,
        in tokens: ArraySlice<SQLPositionedToken>
    ) -> Bool {
        guard let nextIndex = nextSignificantTopLevelIndex(after: index, in: tokens) else {
            return false
        }

        return !isClauseBoundary(tokens[nextIndex].token)
    }

    private static func nextSignificantTopLevelIndex(
        after index: ArraySlice<SQLPositionedToken>.Index,
        in tokens: ArraySlice<SQLPositionedToken>
    ) -> ArraySlice<SQLPositionedToken>.Index? {
        var depth = 0
        var current = tokens.index(after: index)

        while current < tokens.endIndex {
            let token = tokens[current].token

            switch token {
            case .symbol("("):
                if depth == 0 {
                    return current
                }
                depth += 1
            case .symbol(")"):
                depth = max(0, depth - 1)
            case .comment:
                break
            default:
                if depth == 0 {
                    return current
                }
            }

            current = tokens.index(after: current)
        }

        return nil
    }

    private static func isTopLevelKeyword(
        _ keyword: String,
        at index: ArraySlice<SQLPositionedToken>.Index,
        in tokens: ArraySlice<SQLPositionedToken>
    ) -> Bool {
        var depth = 0
        var current = tokens.startIndex

        while current <= index {
            switch tokens[current].token {
            case .symbol("("):
                depth += 1
            case .symbol(")"):
                depth = max(0, depth - 1)
            default:
                break
            }

            if current == index {
                return depth == 0 && isKeyword(keyword, tokens[current].token)
            }

            current = tokens.index(after: current)
        }

        return false
    }

    private static func isKeyword(_ keyword: String, _ token: SQLToken) -> Bool {
        guard case .word(let value) = token else { return false }
        return value.uppercased() == keyword
    }

    private static func isClauseBoundary(_ token: SQLToken) -> Bool {
        switch token {
        case .symbol(";"):
            return true
        case .word(let value):
            return selectClauseBoundaries.contains(value.uppercased())
        default:
            return false
        }
    }

    private static func diagnostic(input: String, offset: Int, message: String, suggestion: String?) -> FormatDiagnostic {
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

    private static func standaloneClauseDiagnostic(in tokens: [SQLPositionedToken], input: String) -> FormatDiagnostic? {
        let slice = tokens[tokens.startIndex..<tokens.endIndex]
        guard let firstIndex = nextSignificantTopLevelIndex(before: slice.endIndex, in: slice, startingAt: slice.startIndex) else {
            return nil
        }

        if isTopLevelKeyword("ORDER", at: firstIndex, in: slice),
           let byIndex = nextSignificantTopLevelIndex(after: firstIndex, in: slice),
           isKeyword("BY", slice[byIndex].token) {
            return diagnostic(
                input: input,
                offset: slice[firstIndex].offset,
                message: "ORDER BY 前缺少可排序的查询语句，且没有提供排序表达式",
                suggestion: "先写 SELECT ... FROM ... 查询语句，再在 ORDER BY 后补上列名或排序表达式。"
            )
        }

        return nil
    }

    private static func nextSignificantTopLevelIndex(
        before endIndex: ArraySlice<SQLPositionedToken>.Index,
        in tokens: ArraySlice<SQLPositionedToken>,
        startingAt startIndex: ArraySlice<SQLPositionedToken>.Index
    ) -> ArraySlice<SQLPositionedToken>.Index? {
        var depth = 0
        var current = startIndex

        while current < endIndex {
            let token = tokens[current].token

            switch token {
            case .symbol("("):
                depth += 1
            case .symbol(")"):
                depth = max(0, depth - 1)
            case .comment:
                break
            default:
                if depth == 0 {
                    return current
                }
            }

            current = tokens.index(after: current)
        }

        return nil
    }

    private static func firstNonWhitespaceOffset(in input: String) -> Int {
        input.firstIndex(where: { !$0.isWhitespace }).map { input.distance(from: input.startIndex, to: $0) } ?? 0
    }

    private static let statementKeywords: Set<String> = [
        "SELECT", "WITH", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER",
        "DROP", "MERGE", "TRUNCATE", "EXPLAIN", "BEGIN", "COMMIT", "ROLLBACK"
    ]

    private static let selectClauseBoundaries: Set<String> = [
        "FROM", "WHERE", "GROUP", "ORDER", "HAVING", "LIMIT", "OFFSET",
        "UNION", "EXCEPT", "INTERSECT"
    ]
}
