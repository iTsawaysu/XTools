import Foundation

extension DockerRunToDockerComposeService {
    static func tokenize(_ command: String) throws -> [String] {
        let chars = Array(command)
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var index = 0

        while index < chars.count {
            let character = chars[index]

            if escaped {
                current.append(character)
                escaped = false
                index += 1
                continue
            }

            if character == "\\" {
                let next = index + 1 < chars.count ? chars[index + 1] : nil

                // Handle line continuation: backslash followed by newline
                if next == "\n" {
                    index += 2
                    continue
                }

                if quote != nil || next == "\"" || next == "'" || next?.isWhitespace == true {
                    escaped = true
                    index += 1
                    continue
                }

                current.append(character)
                index += 1
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                index += 1
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                index += 1
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                index += 1
                continue
            }

            current.append(character)
            index += 1
        }

        if quote != nil {
            throw DockerRunToDockerComposeError.unterminatedQuote
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
