import Foundation

extension DockerRunToDockerComposeService {
    static func tokenize(_ command: String) throws -> [String] {
        let chars = Array(command)
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var tokenStarted = false
        var index = 0

        while index < chars.count {
            let character = chars[index]

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else if activeQuote == "\"", character == "\\" {
                    let next = index + 1 < chars.count ? chars[index + 1] : nil
                    // In double quotes, POSIX shells only consume a backslash
                    // before $, `, ", \\, or a line continuation. Other
                    // backslashes are literal command data.
                    if let next, next == "$" || next == "`" || next == "\"" || next == "\\" {
                        current.append(next)
                        index += 2
                        continue
                    }
                    if next == "\n" {
                        index += 2
                        continue
                    }
                    current.append(character)
                } else {
                    current.append(character)
                }
                index += 1
                continue
            }

            if character == "\\" {
                tokenStarted = true
                let next = index + 1 < chars.count ? chars[index + 1] : nil

                // An unquoted escaped newline is a line continuation.
                if next == "\n" {
                    index += 2
                    continue
                }
                // Preserve ordinary backslashes in unquoted Windows paths.
                // Only shell separators and quote delimiters consume the
                // backslash in this lightweight command-input grammar.
                if let next, next == "\"" || next == "'" || next == "\\" || next.isWhitespace {
                    current.append(next)
                    index += 2
                    continue
                }
                current.append(character)
                index += 1
                continue
            }

            if character == "\"" || character == "'" {
                tokenStarted = true
                quote = character
                index += 1
                continue
            }

            if character.isWhitespace {
                if tokenStarted {
                    tokens.append(current)
                    current = ""
                    tokenStarted = false
                }
                index += 1
                continue
            }

            current.append(character)
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
