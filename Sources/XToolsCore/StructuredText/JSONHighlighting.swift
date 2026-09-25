import Foundation

public struct JSONHighlightToken: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case key
        case string
        case number
        case literal
        case punctuation
    }

    public let kind: Kind
    public let start: Int
    public let length: Int

    public init(kind: Kind, start: Int, length: Int) {
        self.kind = kind
        self.start = start
        self.length = length
    }
}

public enum JSONHighlighting {
    public static func tokens(in line: String) -> [JSONHighlightToken] {
        let characters = Array(line)
        var tokens: [JSONHighlightToken] = []
        var index = 0

        func append(_ kind: JSONHighlightToken.Kind, start: Int, end: Int) {
            guard start < end else {
                return
            }

            tokens.append(JSONHighlightToken(kind: kind, start: start, length: end - start))
        }

        while index < characters.count {
            let character = characters[index]

            if character.unicodeScalars.first?.value == 0x22 {
                var end = index + 1
                var escaped = false
                while end < characters.count {
                    let current = characters[end]
                    if escaped {
                        escaped = false
                    } else if current == "\\" {
                        escaped = true
                    } else if current.unicodeScalars.first?.value == 0x22 {
                        break
                    }
                    end += 1
                }

                let tokenEnd = end < characters.count ? end + 1 : characters.count
                var lookahead = tokenEnd
                while lookahead < characters.count,
                      characters[lookahead] == " " || characters[lookahead] == "\t" {
                    lookahead += 1
                }
                append(
                    lookahead < characters.count && characters[lookahead] == ":" ? .key : .string,
                    start: index,
                    end: tokenEnd
                )
                index = tokenEnd
                continue
            }

            if character == "-" || character.isNumber {
                var end = index + 1
                while end < characters.count {
                    let current = characters[end]
                    if current.isNumber || current == "." || current == "e" || current == "E" || current == "+" || current == "-" {
                        end += 1
                    } else {
                        break
                    }
                }
                append(.number, start: index, end: end)
                index = end
                continue
            }

            if character == "t" || character == "f" || character == "n" {
                let rest = String(characters[index...])
                if let keyword = ["true", "false", "null"].first(where: { rest.hasPrefix($0) }) {
                    append(.literal, start: index, end: index + keyword.count)
                    index += keyword.count
                    continue
                }
            }

            if "{}[]:,".contains(character) {
                append(.punctuation, start: index, end: index + 1)
            }

            index += 1
        }

        return tokens
    }
}
