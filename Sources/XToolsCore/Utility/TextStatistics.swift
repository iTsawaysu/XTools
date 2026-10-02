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
        var endsWithLineBreak = false
        for character in input {
            if characters.isMultiple(of: 1_024), shouldCancel() { throw CancellationError() }
            characters += 1
            if !character.isWhitespace { nonWhitespaceCharacters += 1 }
            if character.isNewline { lineBreaks += 1 }
            endsWithLineBreak = character.isNewline
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
            // 对齐 wc：末尾换行是行终止符而非新行（"a\n" = 1 行、"\n" = 0 行、
            // 空文本 = 0 行）；无末尾换行时最后一行仍需计数。
            lines: wcStyleLineCount(isEmpty: input.isEmpty, inputCount: input.count, lineBreaks: lineBreaks, endsWithLineBreak: endsWithLineBreak),
            sentences: sentences,
            bytes: bytes
        )
    }

    /// wc 风格行数：仅一个换行符的输入（空行内容）为 0 行；以换行结尾时
    /// 末尾换行不另起一行；不以换行结尾时最后一行仍计数。
    private static func wcStyleLineCount(
        isEmpty: Bool,
        inputCount: Int,
        lineBreaks: Int,
        endsWithLineBreak: Bool
    ) -> Int {
        if isEmpty { return 0 }
        if !endsWithLineBreak { return lineBreaks + 1 }
        return inputCount == 1 ? 0 : lineBreaks
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
