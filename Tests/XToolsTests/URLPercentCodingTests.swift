import XToolsCore
import Testing

struct URLPercentCodingTests {
    @Test func encodeLeavesRFC3986UnreservedCharactersUntouched() {
        #expect(URLPercentCoding.encodeComponent("AZaz09-._~") == "AZaz09-._~")
    }

    @Test func encodePercentEncodesUTF8BytesAndReservedCharacters() {
        #expect(URLPercentCoding.encodeComponent("路径?q=值") == "%E8%B7%AF%E5%BE%84%3Fq%3D%E5%80%BC")
        #expect(URLPercentCoding.encodeComponent("a b+c/d") == "a%20b%2Bc%2Fd")
    }

    @Test func decodeRestoresPercentEncodedUTF8AndLeavesPlusLiteral() throws {
        #expect(try URLPercentCoding.decode("%E8%B7%AF%E5%BE%84%3Fq%3D%E5%80%BC") == "路径?q=值")
        #expect(try URLPercentCoding.decode("a%20b%2Bc") == "a b+c")
        #expect(try URLPercentCoding.decode("a+b") == "a+b")
    }

    @Test func decodeRejectsInvalidPercentSequencesAndInvalidUTF8() {
        #expect(throws: URLPercentCoding.CodingError.incompletePercentEscape) {
            _ = try URLPercentCoding.decode("%")
        }
        #expect(throws: URLPercentCoding.CodingError.incompletePercentEscape) {
            _ = try URLPercentCoding.decode("%2")
        }
        #expect(throws: URLPercentCoding.CodingError.invalidPercentEscape) {
            _ = try URLPercentCoding.decode("%GG")
        }
        #expect(throws: URLPercentCoding.CodingError.invalidUTF8) {
            _ = try URLPercentCoding.decode("%FF")
        }
    }

    @Test func codingErrorsUseFactualMessages() {
        let errors: [URLPercentCoding.CodingError] = [
            .incompletePercentEscape,
            .invalidPercentEscape,
            .invalidUTF8,
        ]

        for error in errors {
            ToolDiagnosticContract.expectFactual(error.errorDescription ?? "")
        }
    }

    @Test func modeBackfillUsesCurrentValidPercentEncodedOutput() throws {
        let backfill = ConverterModeBackfill.currentValidOutput(
            input: "路径?q=值",
            currentMode: "enc",
            hasError: false
        ) { input, mode in
            mode == "enc" ? URLPercentCoding.encodeComponent(input) : try URLPercentCoding.decode(input)
        }

        #expect(backfill == "%E8%B7%AF%E5%BE%84%3Fq%3D%E5%80%BC")
        #expect(try URLPercentCoding.decode(backfill ?? "") == "路径?q=值")
    }

    @Test func modeBackfillRejectsEmptyOrErroredOutput() throws {
        let emptyOutput = ConverterModeBackfill.currentValidOutput(
            input: "路径",
            currentMode: "enc",
            hasError: false
        ) { _, _ in "" }

        let visibleError = ConverterModeBackfill.currentValidOutput(
            input: "路径",
            currentMode: "enc",
            hasError: true
        ) { input, _ in
            URLPercentCoding.encodeComponent(input)
        }

        let throwingConversion = ConverterModeBackfill.currentValidOutput(
            input: "%",
            currentMode: "dec",
            hasError: false
        ) { input, _ in
            try URLPercentCoding.decode(input)
        }

        #expect(emptyOutput == nil)
        #expect(visibleError == nil)
        #expect(throwingConversion == nil)
    }
}
