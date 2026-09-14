import XToolsCore
import Testing

struct JSONHighlightingTests {
    @Test func tokensDistinguishObjectKeysFromStringValues() {
        let line = #"  "name": "Ada""#

        let tokens = JSONHighlighting.tokens(in: line)

        #expect(tokens == [
            JSONHighlightToken(kind: .key, start: 2, length: 6),
            JSONHighlightToken(kind: .punctuation, start: 8, length: 1),
            JSONHighlightToken(kind: .string, start: 10, length: 5)
        ])
    }

    @Test func tokensKeepEscapedQuotesInsideStringValues() {
        let line = #""quote": "He said \"hi\"""#

        #expect(snapshots(for: line) == [
            TokenSnapshot(kind: .key, text: #""quote""#),
            TokenSnapshot(kind: .punctuation, text: ":"),
            TokenSnapshot(kind: .string, text: #""He said \"hi\"""#)
        ])
    }

    @Test func tokensScanLooseJSONNumbers() {
        let line = #"[0, -12.5e+6, 7E-2]"#

        #expect(snapshots(for: line) == [
            TokenSnapshot(kind: .punctuation, text: "["),
            TokenSnapshot(kind: .number, text: "0"),
            TokenSnapshot(kind: .punctuation, text: ","),
            TokenSnapshot(kind: .number, text: "-12.5e+6"),
            TokenSnapshot(kind: .punctuation, text: ","),
            TokenSnapshot(kind: .number, text: "7E-2"),
            TokenSnapshot(kind: .punctuation, text: "]")
        ])
    }

    @Test func tokensScanLiteralKeywords() {
        let line = #"[true, false, null]"#

        #expect(snapshots(for: line) == [
            TokenSnapshot(kind: .punctuation, text: "["),
            TokenSnapshot(kind: .literal, text: "true"),
            TokenSnapshot(kind: .punctuation, text: ","),
            TokenSnapshot(kind: .literal, text: "false"),
            TokenSnapshot(kind: .punctuation, text: ","),
            TokenSnapshot(kind: .literal, text: "null"),
            TokenSnapshot(kind: .punctuation, text: "]")
        ])
    }

    @Test func tokensScanStructuralPunctuation() {
        let line = "{}[]:,"

        #expect(snapshots(for: line) == [
            TokenSnapshot(kind: .punctuation, text: "{"),
            TokenSnapshot(kind: .punctuation, text: "}"),
            TokenSnapshot(kind: .punctuation, text: "["),
            TokenSnapshot(kind: .punctuation, text: "]"),
            TokenSnapshot(kind: .punctuation, text: ":"),
            TokenSnapshot(kind: .punctuation, text: ",")
        ])
    }

    @Test func malformedUnclosedStringDegradesToPartialHighlighting() {
        let line = #"  "unterminated"#

        #expect(JSONHighlighting.tokens(in: line) == [
            JSONHighlightToken(kind: .string, start: 2, length: 13)
        ])
    }

    @Test func tokenOffsetsAreCharacterBasedWithUnicodeText() {
        let line = #"你 "键": "值🙂", "n": 1"#

        let tokens = JSONHighlighting.tokens(in: line)

        #expect(tokens == [
            JSONHighlightToken(kind: .key, start: 2, length: 3),
            JSONHighlightToken(kind: .punctuation, start: 5, length: 1),
            JSONHighlightToken(kind: .string, start: 7, length: 4),
            JSONHighlightToken(kind: .punctuation, start: 11, length: 1),
            JSONHighlightToken(kind: .key, start: 13, length: 3),
            JSONHighlightToken(kind: .punctuation, start: 16, length: 1),
            JSONHighlightToken(kind: .number, start: 18, length: 1)
        ])
    }

    private struct TokenSnapshot: Equatable {
        let kind: JSONHighlightToken.Kind
        let text: String
    }

    private func snapshots(for line: String) -> [TokenSnapshot] {
        JSONHighlighting.tokens(in: line).map { token in
            let start = line.index(line.startIndex, offsetBy: token.start)
            let end = line.index(start, offsetBy: token.length)
            return TokenSnapshot(kind: token.kind, text: String(line[start..<end]))
        }
    }
}
