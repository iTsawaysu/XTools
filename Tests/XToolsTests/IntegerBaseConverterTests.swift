import XToolsCore
import Testing

struct IntegerBaseConverterTests {
    // MARK: - Successful conversions

    @Test func convertsDecimalToAllBases() {
        let result = IntegerBaseConverter.conversions(input: "255", fromBase: 10)
        #expect(result?.binary == "11111111")
        #expect(result?.octal == "377")
        #expect(result?.decimal == "255")
        #expect(result?.hex == "FF") // upper-cased to match display
    }

    @Test func convertsFromNonDecimalSourceBase() {
        // hex FF -> 255 in every representation
        let fromHex = IntegerBaseConverter.conversions(input: "FF", fromBase: 16)
        #expect(fromHex?.decimal == "255")
        #expect(fromHex?.binary == "11111111")

        // binary 1010 -> 10
        let fromBinary = IntegerBaseConverter.conversions(input: "1010", fromBase: 2)
        #expect(fromBinary?.decimal == "10")
        #expect(fromBinary?.hex == "A")
    }

    @Test func trimsWhitespaceBeforeParsing() {
        let result = IntegerBaseConverter.conversions(input: "  42  ", fromBase: 10)
        #expect(result?.decimal == "42")
    }

    @Test func convertsNumbersLargerThanPlatformInt() {
        let result = IntegerBaseConverter.conversions(input: "18446744073709551616", fromBase: 10)

        #expect(result?.decimal == "18446744073709551616")
        #expect(result?.hex == "10000000000000000")
        #expect(result?.binary == "10000000000000000000000000000000000000000000000000000000000000000")
    }

    @Test func preservesNegativeSignForNonZeroValues() {
        let result = IntegerBaseConverter.conversions(input: "-FF", fromBase: 16)

        #expect(result?.decimal == "-255")
        #expect(result?.binary == "-11111111")
        #expect(result?.octal == "-377")
        #expect(result?.hex == "-FF")
    }

    @Test func normalizesLeadingZerosAndPlusSign() {
        let result = IntegerBaseConverter.conversions(input: "+000f", fromBase: 16)

        #expect(result?.decimal == "15")
        #expect(result?.hex == "F")
        #expect(IntegerBaseConverter.conversions(input: "-0", fromBase: 10)?.decimal == "0")
    }

    // MARK: - Nil results

    @Test func returnsNilForEmptyInput() {
        #expect(IntegerBaseConverter.conversions(input: "", fromBase: 10) == nil)
        #expect(IntegerBaseConverter.conversions(input: "   ", fromBase: 10) == nil)
    }

    @Test func returnsNilForDigitsOutsideSourceRadix() {
        // "9" is not a valid binary digit
        #expect(IntegerBaseConverter.conversions(input: "9", fromBase: 2) == nil)
        // "G" is not a valid hex digit
        #expect(IntegerBaseConverter.conversions(input: "G", fromBase: 16) == nil)
        // "abc" is not decimal
        #expect(IntegerBaseConverter.conversions(input: "abc", fromBase: 10) == nil)
    }

    @Test func returnsNilForInvalidSignsAndUnsupportedBases() {
        #expect(IntegerBaseConverter.conversions(input: "-", fromBase: 10) == nil)
        #expect(IntegerBaseConverter.conversions(input: "+", fromBase: 10) == nil)
        #expect(IntegerBaseConverter.conversions(input: "10", fromBase: 3) == nil)
    }

    @Test func classifiesValidationFailuresWithoutEchoingInput() {
        #expect(throws: IntegerBaseConverter.ValidationIssue.emptyInput) {
            try IntegerBaseConverter.validatedConversions(input: "   ", fromBase: 10)
        }
        #expect(throws: IntegerBaseConverter.ValidationIssue.signWithoutDigits) {
            try IntegerBaseConverter.validatedConversions(input: "+", fromBase: 10)
        }
        #expect(throws: IntegerBaseConverter.ValidationIssue.unsupportedBase) {
            try IntegerBaseConverter.validatedConversions(input: "10", fromBase: 3)
        }

        let terminalLog = """
        Ran osascript -e 'tell application "System Events" to tell process "XTools" to set frontmost to true'
        screencapture -x -v -V2 -D1 /tmp/flat-disclosure-collapse.mov
        execution error: System Events got an error: Invalid index. (-1719)
        """
        var issue: IntegerBaseConverter.ValidationIssue?
        do {
            _ = try IntegerBaseConverter.prepare(input: terminalLog, fromBase: 10)
        } catch let e as IntegerBaseConverter.ValidationIssue {
            issue = e
        } catch {}

        #expect(issue == .invalidDigit(base: 10))
        let message = issue?.errorDescription ?? ""
        #expect(message == "十进制数只能包含 0–9，可在开头使用正负号。")
        ToolDiagnosticContract.expectFactual(message, sensitiveInputs: [terminalLog])
    }

    @Test func validationMessagesDescribeEachSupportedBase() {
        let expected = [
            2: "二进制数只能包含 0 和 1，可在开头使用正负号。",
            8: "八进制数只能包含 0–7，可在开头使用正负号。",
            10: "十进制数只能包含 0–9，可在开头使用正负号。",
            16: "十六进制数只能包含 0–9、A–F，可在开头使用正负号。",
        ]

        for (base, message) in expected {
            var issue: IntegerBaseConverter.ValidationIssue?
            do {
                _ = try IntegerBaseConverter.prepare(input: "not-a-number", fromBase: base)
            } catch let e as IntegerBaseConverter.ValidationIssue {
                issue = e
            } catch {}
            #expect(issue?.errorDescription == message)
            ToolDiagnosticContract.expectFactual(issue?.errorDescription ?? "")
        }
    }
}

struct IntegerBaseConverterBoundaryTests {
    @Test func preparesNamedSendableConversionsWithoutChangingValues() throws {
        let prepared = try IntegerBaseConverter.prepare(input: "-000FF", fromBase: 16)
        let result = IntegerBaseConverter.conversions(from: prepared)

        #expect(prepared.digitCount == 5)
        #expect(result == IntegerBaseConverter.Conversions(
            binary: "-11111111",
            octal: "-377",
            decimal: "-255",
            hex: "-FF"
        ))
    }

    @Test func maximumDigitBoundaryIgnoresOuterWhitespaceAndSign() throws {
        let accepted = "  +" + String(repeating: "1", count: IntegerBaseConverter.maximumInputDigitCount) + "  "
        let prepared = try IntegerBaseConverter.prepare(input: accepted, fromBase: 2)

        #expect(prepared.digitCount == IntegerBaseConverter.maximumInputDigitCount)

        let rejected = "-" + String(repeating: "1", count: IntegerBaseConverter.maximumInputDigitCount + 1)
        #expect {
            _ = try IntegerBaseConverter.prepare(input: rejected, fromBase: 2)
        } throws: { error in
            error as? IntegerBaseConverter.ValidationIssue
                == .inputTooLong(maxDigits: IntegerBaseConverter.maximumInputDigitCount)
        }
    }

    @Test func inputTooLongDiagnosticIsFactual() {
        let issue = IntegerBaseConverter.ValidationIssue.inputTooLong(
            maxDigits: IntegerBaseConverter.maximumInputDigitCount
        )

        #expect(issue.errorDescription == "输入数值最多支持 4096 位数字。")
        ToolDiagnosticContract.expectFactual(issue.errorDescription ?? "")
    }
}
