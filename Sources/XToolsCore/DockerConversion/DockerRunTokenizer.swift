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
        let chars = Array(command.unicodeScalars)
        var tokens: [ShellToken] = []
        var current = ""
        var scalarCount = 0
        var evaluations: [ShellToken.Evaluation] = []
        var quote: Unicode.Scalar?
        var tokenStarted = false
        var index = 0

        func append(_ scalar: Unicode.Scalar) {
            current.unicodeScalars.append(scalar)
            scalarCount += 1
        }

        func recordEvaluation() {
            guard !composeShellwords, quote != "'" else { return }
            let scalar = chars[index]
            if scalar == "`" {
                evaluations.append(.init(offset: scalarCount, currentDirectorySpelling: nil))
                return
            }
            guard scalar == "$", index + 1 < chars.count else { return }
            let next = chars[index + 1]
            let startsName = Self.isShellNameStart(next)
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
                   Self.isShellNameStart(chars[end]) || ("0"..."9").contains(chars[end]) { continue }
                spelling = candidate
                break
            }
            evaluations.append(.init(offset: scalarCount, currentDirectorySpelling: spelling))
        }

        while index < chars.count {
            let character = chars[index]

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else if activeQuote == "\"", character == "\\" {
                    let next = index + 1 < chars.count ? chars[index + 1] : nil
                    if composeShellwords, let next {
                        append(next)
                        index += 2
                        continue
                    }
                    // In double quotes, POSIX shells only consume a backslash
                    // before $, `, ", \\, or a line continuation. Other
                    // backslashes are literal command data.
                    if let next, next == "$" || next == "`" || next == "\"" || next == "\\" {
                        append(next)
                        index += 2
                        continue
                    }
                    if next == "\n" {
                        index += 2
                        continue
                    }
                    append(character)
                } else {
                    recordEvaluation()
                    append(character)
                }
                index += 1
                continue
            }

            if character == "\\" {
                tokenStarted = true
                let next = index + 1 < chars.count ? chars[index + 1] : nil

                if composeShellwords {
                    guard let next else { throw DockerRunToDockerComposeError.unterminatedQuote }
                    append(next)
                    index += 2
                    continue
                }

                // An unquoted escaped newline is a line continuation.
                if next == "\n" {
                    index += 2
                    continue
                }
                // Preserve ordinary backslashes in unquoted Windows paths.
                // Only shell separators and quote delimiters consume the
                // backslash in this lightweight command-input grammar.
                if let next, next == "\"" || next == "'" || next == "\\" || next == "$" || next == "`" || Character(next).isWhitespace {
                    append(next)
                    index += 2
                    continue
                }
                append(character)
                index += 1
                continue
            }

            if character == "\"" || character == "'" {
                tokenStarted = true
                quote = character
                index += 1
                continue
            }

            let isSeparator = composeShellwords
                ? (character == " " || character == "\t" || character == "\n" || character == "\r")
                : Character(character).isWhitespace
            if isSeparator {
                if tokenStarted {
                    tokens.append(ShellToken(value: current, evaluations: evaluations))
                    current = ""
                    scalarCount = 0
                    evaluations = []
                    tokenStarted = false
                }
                index += 1
                continue
            }

            recordEvaluation()
            append(character)
            tokenStarted = true
            index += 1
        }

        if quote != nil {
            throw DockerRunToDockerComposeError.unterminatedQuote
        }

        if tokenStarted {
            tokens.append(ShellToken(value: current, evaluations: evaluations))
        }

        return tokens
    }

    static func isShellNameStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }
}
