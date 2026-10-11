@testable import XTools
@testable import XToolsCore
import Foundation
import Testing

struct RegexRangePresentationTests {
    @Test func partialNumericAndNamedCapturesUseExactUTF16Units() throws {
        let source = "e\u{301}"
        let match = try #require(RegexMatcher.analyze(pattern: #"(?<letter>e)\u0301"#, in: source).matches.first)
        let numeric = try #require(match.captures.first)
        let named = try #require(match.groups.first)
        #expect(numeric.value == "e")
        for capture in [numeric, named] {
            let range = capture.displayRange
            #expect(range.label == "[0, 1) UTF-16")
            #expect(range.start == 0 && range.end == 1 && range.unitSuffix == " UTF-16")
        }
        let full = match.displayRange
        #expect(full.label == "[0, 1)")
    }

    @Test func partialMatchesIncludeLeadingAndTrailingScalarBoundaries() throws {
        let source = "e\u{301}"
        for (pattern, expected) in [("e", "[0, 1) UTF-16"), (#"\u0301"#, "[1, 2) UTF-16")] {
            let match = try #require(RegexMatcher.analyze(pattern: pattern, in: source).matches.first)
            let range = match.displayRange
            #expect(range.label == expected)
        }
    }

    @Test func zeroWidthUsesRealPositionAndRemainsEmpty() throws {
        let source = "e\u{301}"
        for (pattern, expected) in [(#"(?=\u0301)"#, "[1, 1) UTF-16"), ("$", "[1, 1)")] {
            let match = try #require(RegexMatcher.analyze(pattern: pattern, in: source).matches.first)
            #expect(match.value.isEmpty)
            let range = match.displayRange
            #expect(range.label == expected)
            #expect(range.start == range.end)
        }
    }

    @Test func completeEmojiAndASCIIKeepCharacterOffsets() throws {
        let source = "a👩‍💻b"
        let match = try #require(RegexMatcher.analyze(pattern: "(?<emoji>👩‍💻)", in: source).matches.first)
        #expect(match.utf16Range == NSRange(location: 1, length: 5))
        let range = match.displayRange
        #expect(range.label == "[1, 2)")
        #expect(try #require(match.groups.first).displayRange.label == "[1, 2)")
        let ascii = try #require(RegexMatcher.analyze(pattern: "b", in: "ab").matches.first)
        #expect(ascii.displayRange.label == "[1, 2)")
    }

    @Test func manuallyConstructedLegacyValuesKeepTheirSuppliedCharacterOffsets() {
        let capture = RegexMatcher.Capture(name: "legacy", value: "👩‍💻", start: 3, end: 4)
        #expect(capture.displayRange.label == "[3, 4)")
        let match = RegexMatcher.Match(value: "👩‍💻", index: 3, end: 4, captures: [capture], groups: [], utf16Range: nil)
        #expect(match.displayRange.label == "[3, 4)")
    }

    @Test func copiedSummaryUsesTheSameUnitsAsVisibleRanges() throws {
        let partial = try RegexMatcher.analyze(pattern: #"(?<letter>e)\u0301"#, in: "e\u{301}")
        #expect(RegexMatcher.summaryText(for: partial) == "匹配到 1 处\n\n匹配 #1：范围 [0, 1)；文本 e\u{301}\n  捕获 1：范围 [0, 1) UTF-16；文本 e\n  命名组 letter：范围 [0, 1) UTF-16；文本 e")
        let emoji = try RegexMatcher.analyze(pattern: "(?<emoji>👩‍💻)", in: "a👩‍💻b")
        #expect(RegexMatcher.summaryText(for: emoji) == "匹配到 1 处\n\n匹配 #1：范围 [1, 2)；文本 👩‍💻\n  捕获 1：范围 [1, 2)；文本 👩‍💻\n  命名组 emoji：范围 [1, 2)；文本 👩‍💻")
    }
}
