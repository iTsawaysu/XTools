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
        // The non-cancelling public path cannot throw CancellationError.
        try! analyze(input, shouldCancel: { false })
    }

    public static func analyze(
        _ input: String,
        shouldCancel: @escaping @Sendable () -> Bool
    ) throws -> Stats {
        if shouldCancel() { throw CancellationError() }
        var characters = 0
        var nonWhitespaceCharacters = 0
        var lineBreaks = 0
        for character in input {
            if characters.isMultiple(of: 1_024), shouldCancel() { throw CancellationError() }
            characters += 1
            if !character.isWhitespace { nonWhitespaceCharacters += 1 }
            if character.isNewline { lineBreaks += 1 }
        }
        if shouldCancel() { throw CancellationError() }

        let words = try countTokens(in: input, unit: .word, shouldCancel: shouldCancel)
        let sentences = try countTokens(in: input, unit: .sentence, shouldCancel: shouldCancel)
        if shouldCancel() { throw CancellationError() }
        let bytes = input.utf8.count
        if shouldCancel() { throw CancellationError() }
        return Stats(
            characters: characters,
            nonWhitespaceCharacters: nonWhitespaceCharacters,
            words: words,
            lines: input.isEmpty ? 0 : lineBreaks + 1,
            sentences: sentences,
            bytes: bytes
        )
    }

    private static func countTokens(
        in input: String,
        unit: NLTokenUnit,
        shouldCancel: @escaping @Sendable () -> Bool
    ) throws -> Int {
        let tokenizer = NLTokenizer(unit: unit)
        tokenizer.string = input

        let alphanumerics = CharacterSet.alphanumerics
        var count = 0
        var cancelled = false
        tokenizer.enumerateTokens(in: input.startIndex..<input.endIndex) { range, _ in
            if shouldCancel() {
                cancelled = true
                return false
            }
            let token = input[range]
            guard token.unicodeScalars.contains(where: { alphanumerics.contains($0) }) else {
                return true
            }
            count += 1
            return true
        }
        if cancelled || shouldCancel() { throw CancellationError() }
        return count
    }
}
