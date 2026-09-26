import Foundation
import Testing
@testable import XTools

struct SyntaxViewportHighlightingTests {
    // MARK: - YAML tokens

    @Test func yamlColorsKeyBeforeTopLevelColon() {
        let tokens = StructuredSyntaxHighlighter.yamlTokens(line: "image: nginx:alpine")
        let key = tokens.first { $0.kind == .key }
        #expect(key != nil, "image must color as a key")
        #expect(key?.start == 0)
        #expect(key?.length == 5)
        #expect(tokens.contains { $0.kind == .punctuation && $0.start == 5 })
    }

    @Test func yamlListPortPairNeverColorsAsKey() {
        let tokens = StructuredSyntaxHighlighter.yamlTokens(line: "  - 8080:80")
        #expect(!tokens.contains { $0.kind == .key }, "8080:80 has no top-level key colon and must not color as a key")
        #expect(tokens.contains { $0.kind == .punctuation && $0.length == 1 && $0.start == 2 }, "list dash colors as punctuation")
    }

    @Test func yamlQuotedPortColorsAsString() {
        let tokens = StructuredSyntaxHighlighter.yamlTokens(line: "  - \"80:80\"")
        #expect(tokens.contains { $0.kind == .string })
    }

    @Test func yamlCommentColorsToLineEnd() {
        let tokens = StructuredSyntaxHighlighter.yamlTokens(line: "restart: always # keep it running")
        let comment = tokens.first { $0.kind == .comment }
        #expect(comment != nil)
        #expect(comment?.start == 16)
    }

    @Test func yamlValueLiteralsAndNumbers() {
        let enabled = StructuredSyntaxHighlighter.yamlTokens(line: "enabled: true")
        #expect(enabled.contains { $0.kind == .literal })

        let count = StructuredSyntaxHighlighter.yamlTokens(line: "count: 42")
        #expect(count.contains { $0.kind == .number })
    }

    @Test func yamlQuotedKeyColorsAsKey() {
        let tokens = StructuredSyntaxHighlighter.yamlTokens(line: "\"a: b\": value")
        let key = tokens.first { $0.kind == .key }
        #expect(key != nil, "quoted keys still color as keys; the colon inside quotes must not split them")
        #expect(key?.length == 6)
    }

    // MARK: - SQL tokens

    @Test func sqlKeywordsAreCaseInsensitive() {
        let tokens = StructuredSyntaxHighlighter.sqlTokens(line: "select id from users")
        #expect(tokens.filter { $0.kind == .key }.count == 2)
    }

    @Test func sqlLineCommentColorsToLineEnd() {
        let tokens = StructuredSyntaxHighlighter.sqlTokens(line: "select 1 -- trailing note")
        let comment = tokens.first { $0.kind == .comment }
        #expect(comment != nil)
        #expect(comment?.start == 9)
    }

    @Test func sqlBlockCommentStaysLineLocal() {
        let tokens = StructuredSyntaxHighlighter.sqlTokens(line: "select /* inline */ 1")
        let comment = tokens.first { $0.kind == .comment }
        #expect(comment != nil)
        #expect(comment?.length == 12)
    }

    @Test func sqlNumbersAndStrings() {
        let tokens = StructuredSyntaxHighlighter.sqlTokens(line: "where age > 30 and name = 'bob'")
        #expect(tokens.contains { $0.kind == .number })
        #expect(tokens.contains { $0.kind == .string })
    }

    @Test func sqlDashInsideIdentifierIsNotComment() {
        let tokens = StructuredSyntaxHighlighter.sqlTokens(line: "select user-id from t")
        #expect(!tokens.contains { $0.kind == .comment })
    }

    // MARK: - XML tokens

    @Test func xmlTagNameAttributeAndValueColor() {
        let tokens = StructuredSyntaxHighlighter.xmlTokens(line: #"<user id="123" role="admin">"#)
        #expect(tokens.contains { $0.kind == .key && $0.length == 4 }, "tag name colors as key")
        #expect(tokens.contains { $0.kind == .attribute && $0.length == 2 }, "attribute name colors")
        #expect(tokens.filter { $0.kind == .string }.count == 2, "both quoted values color as strings")
    }

    @Test func xmlClosingTagColorsName() {
        let tokens = StructuredSyntaxHighlighter.xmlTokens(line: "</user>")
        #expect(tokens.contains { $0.kind == .key && $0.length == 4 })
        #expect(tokens.filter { $0.kind == .punctuation }.count == 3, "</user> has three punctuation characters")
    }

    @Test func xmlCommentColorsWholeDeclaration() {
        let tokens = StructuredSyntaxHighlighter.xmlTokens(line: "<!-- keep this -->")
        let comment = tokens.first { $0.kind == .comment }
        #expect(comment?.length == 18)
    }

    @Test func xmlSelfClosingTagAndHeader() {
        let selfClosing = StructuredSyntaxHighlighter.xmlTokens(line: #"<ssl enabled="true"/>"#)
        #expect(selfClosing.contains { $0.kind == .attribute })
        #expect(selfClosing.contains { $0.kind == .string })

        let header = StructuredSyntaxHighlighter.xmlTokens(line: #"<?xml version="1.0"?>"#)
        #expect(header.contains { $0.kind == .key && $0.length == 3 })
        #expect(header.contains { $0.kind == .string })
    }

    // MARK: - JSON tokens

    @Test func jsonTokensPassThroughCoreHighlighting() {
        let tokens = JSONSyntaxHighlighter.tokens(line: #"  "name": "XTools""#)
        #expect(tokens.contains { $0.kind == .key })
        #expect(tokens.contains { $0.kind == .string })
    }

    // MARK: - Grapheme-to-UTF-16 mapping

    @Test func utf16RangeMapHandlesExtendedGraphemeClusters() {
        let line = "A👨‍👩‍👧‍👦e\u{301}🇨🇳Z"
        let ranges = IndexSyntaxUTF16RangeMap(line: line)
        let lineRange = NSRange(location: 40, length: (line as NSString).length)

        let familyAndCombiningMark = IndexSyntaxToken(start: 1, length: 2, kind: .string)
        #expect(
            ranges.range(for: familyAndCombiningMark, in: lineRange)
                == NSRange(location: 41, length: 13)
        )

        let flag = IndexSyntaxToken(start: 3, length: 1, kind: .string)
        #expect(ranges.range(for: flag, in: lineRange) == NSRange(location: 54, length: 4))
    }

    @Test func utf16RangeMapPreservesOverlappingOutOfOrderTokenRanges() {
        let line = "A😀BC"
        let ranges = IndexSyntaxUTF16RangeMap(line: line)
        let lineRange = NSRange(location: 100, length: (line as NSString).length)
        let tokens = [
            IndexSyntaxToken(start: 2, length: 2, kind: .key),
            IndexSyntaxToken(start: 0, length: 3, kind: .string),
            IndexSyntaxToken(start: 1, length: 1, kind: .number),
        ]

        let mapped = tokens.compactMap { ranges.range(for: $0, in: lineRange) }
        #expect(mapped == [
            NSRange(location: 103, length: 2),
            NSRange(location: 100, length: 4),
            NSRange(location: 101, length: 2),
        ])
    }

    @Test func utf16RangeMapRejectsInvalidAndOverflowingRanges() {
        let ranges = IndexSyntaxUTF16RangeMap(line: "abc")
        let lineRange = NSRange(location: 10, length: 3)

        #expect(ranges.range(for: .init(start: -1, length: 1, kind: .key), in: lineRange) == nil)
        #expect(ranges.range(for: .init(start: 0, length: -1, kind: .key), in: lineRange) == nil)
        #expect(ranges.range(for: .init(start: 0, length: 0, kind: .key), in: lineRange) == nil)
        #expect(ranges.range(for: .init(start: 4, length: 1, kind: .key), in: lineRange) == nil)
        #expect(ranges.range(for: .init(start: 1, length: Int.max, kind: .key), in: lineRange) == nil)
        #expect(ranges.range(for: .init(start: Int.max, length: 1, kind: .key), in: lineRange) == nil)
        #expect(ranges.range(
            for: .init(start: 1, length: 1, kind: .key),
            in: NSRange(location: Int.max - 1, length: 3)
        ) == nil)
        #expect(ranges.range(
            for: .init(start: 2, length: 1, kind: .key),
            in: NSRange(location: Int.max - 1, length: 3)
        ) == nil)
    }

    @Test func utf16RangeMapMatchesRealJSONTokenizerCharacterSlices() throws {
        let line = #"{"emoji":"👨‍👩‍👧‍👦é","flag":"🇨🇳"}"#
        let tokens = JSONSyntaxHighlighter.tokens(line: line)
        let ranges = IndexSyntaxUTF16RangeMap(line: line)
        let lineRange = NSRange(location: 0, length: (line as NSString).length)
        #expect(!tokens.isEmpty)

        for token in tokens {
            let mapped = try #require(ranges.range(for: token, in: lineRange))
            let start = try #require(line.index(line.startIndex, offsetBy: token.start, limitedBy: line.endIndex))
            let end = try #require(line.index(start, offsetBy: token.length, limitedBy: line.endIndex))
            #expect((line as NSString).substring(with: mapped) == String(line[start..<end]))
        }
    }

    // MARK: - Viewport line-span math

    @Test func lineSpanCoversVisibleRangePlusMargin() {
        // 5 lines of length 6 each (including newline): ranges 0..<6, 6..<12, …
        let lineRanges = (0..<5).map { NSRange(location: $0 * 6, length: 6) }

        let span = IndexViewportHighlightMath.lineSpan(
            covering: NSRange(location: 13, length: 5),
            lineRanges: lineRanges,
            margin: 1
        )
        #expect(span == 1..<4, "visible lines 2–3 expand to 1..<4 with margin 1")
    }

    @Test func lineSpanClampsAtDocumentEdges() {
        let lineRanges = (0..<5).map { NSRange(location: $0 * 6, length: 6) }

        let top = IndexViewportHighlightMath.lineSpan(
            covering: NSRange(location: 0, length: 3),
            lineRanges: lineRanges,
            margin: 2
        )
        #expect(top == 0..<3, "margin clamps to the document start")

        let bottom = IndexViewportHighlightMath.lineSpan(
            covering: NSRange(location: 26, length: 4),
            lineRanges: lineRanges,
            margin: 2
        )
        #expect(bottom == 2..<5, "margin clamps to the document end")
    }

    @Test func lineSpanHandlesEmptyDocument() {
        let span = IndexViewportHighlightMath.lineSpan(
            covering: NSRange(location: 0, length: 0),
            lineRanges: [],
            margin: 4
        )
        #expect(span.isEmpty)
    }

    @Test func lineSpanSingleLineDocument() {
        let span = IndexViewportHighlightMath.lineSpan(
            covering: NSRange(location: 0, length: 0),
            lineRanges: [NSRange(location: 0, length: 10)],
            margin: 4
        )
        #expect(span == 0..<1)
    }

    @Test func lineSpanMatchesPreviousScanForOrderedRanges() {
        var seed: UInt64 = 0xA02
        func draw(_ count: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int((seed >> 32) % UInt64(count))
        }

        let edgeCases = [
            [NSRange](),
            [NSRange(location: 0, length: 0)],
            [NSRange(location: 0, length: 3), NSRange(location: 3, length: 0), NSRange(location: 3, length: 2)],
            [NSRange(location: 2, length: 2), NSRange(location: 8, length: 1), NSRange(location: 9, length: 0)],
        ]
        for ranges in edgeCases {
            for location in 0..<14 {
                for length in [0, 1, 4] {
                    for margin in [0, 1, 3] {
                        expectSameSpan(NSRange(location: location, length: length), ranges, margin)
                    }
                }
            }
        }

        for _ in 0..<300 {
            var ranges: [NSRange] = []
            var position = 0
            for _ in 0..<draw(80) {
                position += draw(4)
                let length = draw(8)
                ranges.append(NSRange(location: position, length: length))
                position += length
            }
            for _ in 0..<16 {
                let visible = NSRange(location: draw(position + 10), length: draw(10))
                expectSameSpan(visible, ranges, draw(8) - 2)
            }
        }
    }

    private func expectSameSpan(_ visible: NSRange, _ ranges: [NSRange], _ margin: Int) {
        let actual = IndexViewportHighlightMath.lineSpan(covering: visible, lineRanges: ranges, margin: margin)
        let expected = previousLineSpan(covering: visible, lineRanges: ranges, margin: margin)
        #expect(actual == expected)
    }

    private func previousLineSpan(covering visible: NSRange, lineRanges: [NSRange], margin: Int) -> Range<Int> {
        guard !lineRanges.isEmpty else { return 0..<0 }
        func clamped(_ first: Int, _ last: Int) -> Range<Int> {
            let lower = max(0, first - margin)
            let upper = min(lineRanges.count - 1, last + margin)
            guard lower <= upper else { return 0..<0 }
            return lower..<upper + 1
        }
        if visible.length == 0 && visible.location == 0 && lineRanges.count > 1 {
            return clamped(0, 0)
        }

        var first = lineRanges.count - 1
        for (index, range) in lineRanges.enumerated() where visible.location < NSMaxRange(range) {
            first = index
            break
        }
        var last = 0
        let upperBound = max(visible.location, visible.location + visible.length - 1)
        for (index, range) in lineRanges.enumerated() where upperBound >= range.location {
            last = index
        }
        return clamped(first, last)
    }
}
