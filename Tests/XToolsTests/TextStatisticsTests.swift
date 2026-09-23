import XToolsCore
import Foundation
import Testing

struct TextStatisticsTests {
    @Test func zeroStatsCoverEveryPublishedMetric() {
        #expect(TextStatistics.Stats.zero.characters == 0)
        #expect(TextStatistics.Stats.zero.nonWhitespaceCharacters == 0)
        #expect(TextStatistics.Stats.zero.words == 0)
        #expect(TextStatistics.Stats.zero.lines == 0)
        #expect(TextStatistics.Stats.zero.sentences == 0)
        #expect(TextStatistics.Stats.zero.bytes == 0)
    }

    @Test func analyzesEmptyString() {
        let stats = TextStatistics.analyze("")
        #expect(stats.characters == 0)
        #expect(stats.words == 0)
        #expect(stats.lines == 0)
        #expect(stats.sentences == 0)
        #expect(stats.bytes == 0)
    }

    @Test func countsSingleWord() {
        let stats = TextStatistics.analyze("hello")
        #expect(stats.characters == 5)
        #expect(stats.nonWhitespaceCharacters == 5)
        #expect(stats.words == 1)
        #expect(stats.lines == 1)
    }

    @Test func countsMultipleWords() {
        let stats = TextStatistics.analyze("hello world test")
        #expect(stats.characters == 16)
        #expect(stats.nonWhitespaceCharacters == 14)
        #expect(stats.words == 3)
    }

    @Test func countsWordsUsingNaturalLanguageBoundaries() {
        let stats = TextStatistics.analyze("Hi world\n你好！")
        #expect(stats.words == 4)

        let chineseStats = TextStatistics.analyze("你好世界")
        #expect(chineseStats.words == 3)
    }

    @Test func countsLines() {
        let stats = TextStatistics.analyze("line1\nline2\nline3")
        #expect(stats.lines == 3)
        #expect(stats.words == 3)
    }

    @Test func countsLinesTreatingCRLFAsOneLineBreak() {
        // Regression: components(separatedBy: .newlines) split \r\n into two
        // separators and over-counted lines; grapheme-level counting treats
        // \r\n as a single line break.
        #expect(TextStatistics.analyze("line1\r\nline2").lines == 2)
        #expect(TextStatistics.analyze("line1\r\n\r\nline2").lines == 3)
    }

    @Test func countsSentences() {
        let stats = TextStatistics.analyze("Hello. How are you? Great!")
        #expect(stats.sentences == 3) // . ? !

        let chineseStats = TextStatistics.analyze("你好。真的吗？太好了！")
        #expect(chineseStats.sentences == 3) // 。？！

        // Regression: repeated terminators with no text between them are zero
        // sentences, not one per mark (previously climbed without bound).
        let repeated = TextStatistics.analyze("。。。。。")
        #expect(repeated.sentences == 0)

        // Trailing/duplicate terminators collapse around the single real segment.
        let trailing = TextStatistics.analyze("Hello..")
        #expect(trailing.sentences == 1)

        // A sentence without a trailing terminator still counts.
        let noTerminator = TextStatistics.analyze("还没写完")
        #expect(noTerminator.sentences == 1)
    }

    @Test func sentenceTokenizerDoesNotSplitEnglishAbbreviations() {
        let stats = TextStatistics.analyze("Mr. Smith went home. It was late.")
        #expect(stats.sentences == 2)
    }

    @Test func countsNonWhitespace() {
        let stats = TextStatistics.analyze("a b  c   d")
        #expect(stats.characters == 10)
        #expect(stats.nonWhitespaceCharacters == 4)
    }

    @Test func countsBytes() {
        let stats = TextStatistics.analyze("hello")
        #expect(stats.bytes == 5) // ASCII

        let unicodeStats = TextStatistics.analyze("你好")
        #expect(unicodeStats.bytes == 6) // UTF-8 (3 bytes × 2 chars)
    }
}
