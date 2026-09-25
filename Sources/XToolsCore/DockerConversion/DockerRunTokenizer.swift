import Foundation

extension DockerRunToDockerComposeService {
    /// Compose scalar commands use shellwords escaping; pasted docker run text
    /// keeps its existing Windows-path-friendly backslash behavior by default.
    static func tokenize(_ command: String, composeShellwords: Bool = false) throws -> [String] {
        let chars = Array(command.unicodeScalars)
        var tokens: [String] = []
        var current = ""
        var quote: Unicode.Scalar?
        var tokenStarted = false
        var index = 0

        while index < chars.count {
            let character = chars[index]

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else if activeQuote == "\"", character == "\\" {
                    let next = index + 1 < chars.count ? chars[index + 1] : nil
                    if composeShellwords, let next {
                        current.unicodeScalars.append(next)
                        index += 2
                        continue
                    }
                    // In double quotes, POSIX shells only consume a backslash
                    // before $, `, ", \\, or a line continuation. Other
                    // backslashes are literal command data.
                    if let next, next == "$" || next == "`" || next == "\"" || next == "\\" {
                        current.unicodeScalars.append(next)
                        index += 2
                        continue
                    }
                    if next == "\n" {
                        index += 2
                        continue
                    }
                    current.unicodeScalars.append(character)
                } else {
                    current.unicodeScalars.append(character)
                }
                index += 1
                continue
            }

            if character == "\\" {
                tokenStarted = true
                let next = index + 1 < chars.count ? chars[index + 1] : nil

                if composeShellwords {
                    guard let next else { throw DockerRunToDockerComposeError.unterminatedQuote }
                    current.unicodeScalars.append(next)
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
                if let next, next == "\"" || next == "'" || next == "\\" || Character(next).isWhitespace {
                    current.unicodeScalars.append(next)
                    index += 2
                    continue
                }
                current.unicodeScalars.append(character)
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
                    tokens.append(current)
                    current = ""
                    tokenStarted = false
                }
                index += 1
                continue
            }

            current.unicodeScalars.append(character)
            tokenStarted = true
            index += 1
        }

        if quote != nil {
            throw DockerRunToDockerComposeError.unterminatedQuote
        }

        if tokenStarted {
            tokens.append(current)
        }

        return tokens
    }
}
