import Foundation
import NaturalLanguage

public enum TextStatistics {
    public struct Stats: Equatable, Sendable {
        public let characters: Int
        public let nonWhitespaceCharacters: Int
        public let words: Int
        public let lines: Int
        public let sentences: Int
        public let bytes: Int

        public static let zero = Stats(
            characters: 0,
            nonWhitespaceCharacters: 0,
            words: 0,
            lines: 0,
            sentences: 0,
            bytes: 0
        )

        public init(
            characters: Int,
            nonWhitespaceCharacters: Int,
            words: Int,
            lines: Int,
            sentences: Int,
            bytes: Int
        ) {
            self.characters = characters
            self.nonWhitespaceCharacters = nonWhitespaceCharacters
            self.words = words
            self.lines = lines
            self.sentences = sentences
            self.bytes = bytes
        }
    }

    public static func analyze(_ input: String) -> Stats {
        Stats(
            characters: input.count,
            nonWhitespaceCharacters: input.filter { !$0.isWhitespace }.count,
            words: countTokens(in: input, unit: .word),
            lines: input.isEmpty ? 0 : input.components(separatedBy: .newlines).count,
            sentences: countTokens(in: input, unit: .sentence),
            bytes: input.data(using: .utf8)?.count ?? 0
        )
    }

    private static func countTokens(in input: String, unit: NLTokenUnit) -> Int {
        let tokenizer = NLTokenizer(unit: unit)
        tokenizer.string = input

        var count = 0
        tokenizer.enumerateTokens(in: input.startIndex..<input.endIndex) { range, _ in
            let token = String(input[range])
            guard token.rangeOfCharacter(from: .alphanumerics) != nil else {
                return true
            }
            count += 1
            return true
        }
        return count
    }
}
