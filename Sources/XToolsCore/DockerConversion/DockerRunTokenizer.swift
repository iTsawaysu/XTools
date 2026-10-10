import Foundation

extension DockerRunToDockerComposeService {
    struct ShellToken {
        struct Evaluation {
            let offset: Int
            let currentDirectorySpelling: String?
        }

        let value: String
        let evaluations: [Evaluation]

        func resolvedValue(for field: String, droppingPrefix prefix: Int = 0) throws -> String {
            guard !evaluations.isEmpty else {
                if prefix == 0 { return value }
                return String(value.unicodeScalars.dropFirst(prefix))
            }
            let scalars = Array(value.unicodeScalars)
            var result = ""
            var cursor = prefix
            for evaluation in evaluations {
                guard evaluation.offset >= cursor,
                      let spelling = evaluation.currentDirectorySpelling else {
                    throw DockerRunToDockerComposeError.unresolvedShellExpression(field)
                }
                let start = evaluation.offset
                let end = start + spelling.unicodeScalars.count
                let before = String(String.UnicodeScalarView(scalars[prefix..<start]))
                let suffix = end < scalars.count ? scalars[end] : nil
                let isSourcePrefix = field == "--volume" && before.isEmpty
                    || field == "--mount" && ["source=", "src="].contains(
                        before.split(separator: ",", omittingEmptySubsequences: false).last
                            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                    )
                guard isSourcePrefix, suffix == nil || suffix == "/" || suffix == ":" || suffix == "," else {
                    throw DockerRunToDockerComposeError.unresolvedShellExpression(field)
                }
                result += String(String.UnicodeScalarView(scalars[cursor..<start]))
                result += suffix == "/" ? "." : "./"
                cursor = end
            }
            result += String(String.UnicodeScalarView(scalars[cursor...]))
            return result
        }
    }

    /// Compose scalar commands use shellwords escaping; pasted docker run text
    /// keeps its existing Windows-path-friendly backslash behavior by default.
    static func tokenize(_ command: String, composeShellwords: Bool = false) throws -> [String] {
        try tokenizeWithOrigins(command, composeShellwords: composeShellwords).map(\.value)
    }

    static func tokenizeWithOrigins(_ command: String, composeShellwords: Bool = false) throws -> [ShellToken] {
        var state = TokenizerState(chars: Array(command.unicodeScalars), composeShellwords: composeShellwords)

        while state.index < state.chars.count {
            let character = state.chars[state.index]

            if state.quote != nil {
                try consumeQuotedScalar(character, into: &state)
            } else if character == "\\" {
                try consumeUnquotedBackslash(character, into: &state)
            } else if character == "\"" || character == "'" {
                state.tokenStarted = true
                state.quote = character
                state.index += 1
            } else if isTokenSeparator(character, composeShellwords: state.composeShellwords) {
                state.finishStartedToken()
                state.index += 1
            } else {
                state.recordEvaluation()
                state.append(character)
                state.tokenStarted = true
                state.index += 1
            }
        }

        if state.quote != nil {
            throw DockerRunToDockerComposeError.unterminatedQuote
        }

        state.finishTrailingToken()

        return state.tokens
    }

    /// tokenizeWithOrigins 的扫描状态：字符游标、当前 token 累积与 shell 求值记录。
    private struct TokenizerState {
        let chars: [Unicode.Scalar]
        let composeShellwords: Bool
        var tokens: [ShellToken] = []
        var current = ""
        var scalarCount = 0
        var evaluations: [ShellToken.Evaluation] = []
        var quote: Unicode.Scalar?
        var tokenStarted = false
        var index = 0

        mutating func append(_ scalar: Unicode.Scalar) {
            current.unicodeScalars.append(scalar)
            scalarCount += 1
        }

        mutating func recordEvaluation() {
            guard !composeShellwords, quote != "'" else { return }
            let scalar = chars[index]
            if scalar == "`" {
                evaluations.append(.init(offset: scalarCount, currentDirectorySpelling: nil))
                return
            }
            guard scalar == "$", index + 1 < chars.count else { return }
            let next = chars[index + 1]
            let startsName = isShellNameStart(next)
            // ANSI-C and locale quotes are Shell syntax when unquoted; this
            // lightweight converter cannot treat their leading dollar as data.
            let startsShellQuote = quote == nil && (next == "\"" || next == "'")
            guard startsName || startsShellQuote || "{($?!#@*-0123456789".unicodeScalars.contains(next) else { return }
            var spelling: String?
            for candidate in ["$(pwd)", "${PWD}", "$PWD"] {
                let expected = Array(candidate.unicodeScalars)
                guard chars[index...].starts(with: expected) else { continue }
                let end = index + expected.count
                if candidate == "$PWD", end < chars.count,
                   isShellNameStart(chars[end]) || ("0"..."9").contains(chars[end]) { continue }
                spelling = candidate
                break
            }
            evaluations.append(.init(offset: scalarCount, currentDirectorySpelling: spelling))
        }

        /// 分隔符处把已累积的字符收进 token 并复位累积状态。
        mutating func finishStartedToken() {
            guard tokenStarted else { return }
            tokens.append(ShellToken(value: current, evaluations: evaluations))
            current = ""
            scalarCount = 0
            evaluations = []
            tokenStarted = false
        }

        /// 输入耗尽时收尾最后一个 token（不再复位状态）。
        mutating func finishTrailingToken() {
            if tokenStarted {
                tokens.append(ShellToken(value: current, evaluations: evaluations))
            }
        }
    }

    /// 引号内的字符：闭引号结束引用；双引号内仅 POSIX 允许的反斜杠转义生效。
    private static func consumeQuotedScalar(_ character: Unicode.Scalar, into state: inout TokenizerState) throws {
        guard let activeQuote = state.quote else { return }
        if character == activeQuote {
            state.quote = nil
        } else if activeQuote == "\"", character == "\\" {
            let next = state.index + 1 < state.chars.count ? state.chars[state.index + 1] : nil
            if state.composeShellwords, let next {
                state.append(next)
                state.index += 2
                return
            }
            // In double quotes, POSIX shells only consume a backslash
            // before $, `, ", \\, or a line continuation. Other
            // backslashes are literal command data.
            if let next, next == "$" || next == "`" || next == "\"" || next == "\\" {
                state.append(next)
                state.index += 2
                return
            }
            if next == "\n" {
                state.index += 2
                return
            }
            state.append(character)
        } else {
            state.recordEvaluation()
            state.append(character)
        }
        state.index += 1
    }

    /// 引号外的反斜杠：转义下一个字符、行继续或保留字面反斜杠。
    private static func consumeUnquotedBackslash(_ character: Unicode.Scalar, into state: inout TokenizerState) throws {
        state.tokenStarted = true
        let next = state.index + 1 < state.chars.count ? state.chars[state.index + 1] : nil

        if state.composeShellwords {
            guard let next else { throw DockerRunToDockerComposeError.unterminatedQuote }
            state.append(next)
            state.index += 2
            return
        }

        // An unquoted escaped newline is a line continuation.
        if next == "\n" {
            state.index += 2
            return
        }
        // Preserve ordinary backslashes in unquoted Windows paths.
        // Only shell separators and quote delimiters consume the
        // backslash in this lightweight command-input grammar.
        if let next, next == "\"" || next == "'" || next == "\\" || next == "$" || next == "`" || Character(next).isWhitespace {
            state.append(next)
            state.index += 2
            return
        }
        state.append(character)
        state.index += 1
    }

    /// 分隔符判定：compose 侧沿用 shellwords 的空白定义，粘贴输入用 isWhitespace。
    private static func isTokenSeparator(_ character: Unicode.Scalar, composeShellwords: Bool) -> Bool {
        composeShellwords
            ? (character == " " || character == "\t" || character == "\n" || character == "\r")
            : Character(character).isWhitespace
    }

    static func isShellNameStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }
}
