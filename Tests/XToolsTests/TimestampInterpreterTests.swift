import XToolsCore
import Foundation
import Testing

struct TimestampInterpreterTests {
    // MARK: - Integer seconds input

    @Test func readsIntegerUnixSecondsOnly() {
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "1718900000") == 1_718_900_000)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "0") == 0)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "-1718900000") == -1_718_900_000)
    }

    @Test func typedInputStatesDistinguishEditingFormatAndRangeFailures() {
        #expect(TimestampInterpreter.evaluate("  ") == .empty)
        #expect(TimestampInterpreter.evaluate("-") == .incomplete)
        #expect(TimestampInterpreter.evaluate("1718900000") == .valid(1_718_900_000))
        #expect(TimestampInterpreter.evaluate("1718900000.5") == .invalid(.nonIntegerFormat))
        #expect(TimestampInterpreter.evaluate("+1") == .invalid(.nonIntegerFormat))
        #expect(TimestampInterpreter.evaluate("253402300800") == .invalid(.outOfRange))
    }

    @Test func timestampDiagnosticsAreFactualAndDoNotEchoPastedLogs() {
        let terminalLog = "Ran osascript -e System Events /tmp/capture.mov 89:145 execution error"
        guard case .invalid(let issue) = TimestampInterpreter.evaluate(terminalLog) else {
            Issue.record("expected invalid timestamp")
            return
        }

        let message = issue.errorDescription ?? ""
        #expect(message == "Unix 时间戳只能包含整数秒，可在开头使用负号。")
        ToolDiagnosticContract.expectFactual(message, sensitiveInputs: [terminalLog])
        ToolDiagnosticContract.expectFactual(
            TimestampInterpreter.ValidationIssue.outOfRange.errorDescription ?? ""
        )
    }

    // MARK: - Invalid input

    @Test func returnsNilForIncompleteOrNonIntegerInput() {
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "") == nil)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "-") == nil)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "+1") == nil)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "abc") == nil)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "1718900000.5") == nil)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: ".5") == nil)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "123.") == nil)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "1e3") == nil)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "--1") == nil)
    }

    @Test func returnsNilForNonFiniteValues() {
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "inf") == nil)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "nan") == nil)
    }

    @Test func rejectsValuesOutsideSupportedHumanDateRange() {
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "-62135596800") == -62_135_596_800)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "253402300799") == 253_402_300_799)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "-62135596801") == nil)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "253402300800") == nil)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "1718900000000") == nil)
        #expect(TimestampInterpreter.integerSeconds(fromTrimmed: "999999999999999999999999") == nil)
    }


    @Test func canonicalWholeSecondDateUsesTheExistingTowardZeroContract() {
        #expect(
            TimestampInterpreter.canonicalWholeSecondDate(
                for: Date(timeIntervalSince1970: 123.987)
            )?.timeIntervalSince1970 == 123
        )
        #expect(
            TimestampInterpreter.canonicalWholeSecondDate(
                for: Date(timeIntervalSince1970: -123.987)
            )?.timeIntervalSince1970 == -123
        )
        #expect(
            TimestampInterpreter.canonicalWholeSecondDate(
                for: Date(timeIntervalSince1970: 123)
            )?.timeIntervalSince1970 == 123
        )
    }

    @Test func canonicalWholeSecondDateRejectsNonFiniteAndUnsupportedInstants() {
        #expect(TimestampInterpreter.canonicalWholeSecondDate(for: Date(timeIntervalSince1970: .infinity)) == nil)
        #expect(TimestampInterpreter.canonicalWholeSecondDate(for: Date(timeIntervalSince1970: 253_402_300_800)) == nil)
        #expect(TimestampInterpreter.canonicalWholeSecondDate(for: Date(timeIntervalSince1970: -62_135_596_801)) == nil)
    }
}
