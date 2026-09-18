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
}
