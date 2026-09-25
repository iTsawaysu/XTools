import Foundation
import Testing
@testable import XToolsCore

struct FormatDiagnosticTests {
    @Test func CRLFKeepsSecondAndThirdLineExcerptsAligned() {
        let input = "first\r\nsecond\r\nthird"

        let second = diagnostic(at: input.range(of: "second")!.lowerBound, in: input)
        #expect(second.line == 2)
        #expect(second.column == 1)
        #expect(second.excerpt == "second")

        let third = diagnostic(at: input.range(of: "third")!.lowerBound, in: input)
        #expect(third.line == 3)
        #expect(third.column == 1)
        #expect(third.excerpt == "third")
    }

    @Test func mixedCRLFCRLFAndBlankLinesKeepExcerptLineNumbers() {
        let input = "one\r\ntwo\rthree\n\nfive"
        let five = diagnostic(at: input.firstIndex(of: "f")!, in: input)

        #expect(five.line == 5)
        #expect(five.column == 1)
        #expect(five.excerpt == "five")
    }

    @Test func columnsCountUnicodeGraphemesAndAllNewlineForms() {
        let input = "😀e\u{301}X\r\nY\rZ\nW"
        let x = diagnostic(at: input.firstIndex(of: "X")!, in: input)
        let y = diagnostic(at: input.firstIndex(of: "Y")!, in: input)
        let z = diagnostic(at: input.firstIndex(of: "Z")!, in: input)
        let w = diagnostic(at: input.firstIndex(of: "W")!, in: input)

        #expect(x.line == 1)
        #expect(x.column == 3)
        #expect(y.line == 2)
        #expect(y.column == 1)
        #expect(z.line == 3)
        #expect(z.column == 1)
        #expect(w.line == 4)
        #expect(w.column == 1)
    }

    @Test func SQLDiagnosticUsesCRLFPositionAndExcerpt() {
        let input = "SELECT 1\r\nFROM ("
        let error = #expect(throws: SQLFormatting.ValidationError.self) {
            try SQLFormatting.validate(input)
        }

        guard case .unbalancedParentheses(let diagnostic) = error else {
            Issue.record("Expected unmatched opening parenthesis diagnostic")
            return
        }

        #expect(diagnostic.line == 2)
        #expect(diagnostic.column == 6)
        #expect(diagnostic.excerpt == "FROM (")
    }

    @Test func JSONDiagnosticUsesCRLFPositionAndExcerpt() {
        let input = "{\r\n  \"a\": 1,\r\n}"
        let error = #expect(throws: JSONFormatting.FormattingError.self) {
            try JSONFormatting.format(input, sortKeys: false, indentWidth: 2)
        }

        guard case .invalidJSON(let diagnostic) = error else {
            Issue.record("Expected trailing comma diagnostic")
            return
        }

        #expect(diagnostic.line == 3)
        #expect(diagnostic.column == 1)
        #expect(diagnostic.excerpt == "}")
    }

    private func diagnostic(at index: String.Index, in input: String) -> FormatDiagnostic {
        return FormatDiagnostic(
            formatName: "test",
            message: "test",
            input: input,
            index: index
        )
    }
}
