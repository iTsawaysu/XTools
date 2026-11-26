import XToolsCore
import Foundation
import Testing

struct TimestampInterpreterTests {
    // MARK: - Integer seconds input

    @Test func readsIntegerUnixSecondsOnly() {
        #expect(TimestampInterpreter.evaluate("1718900000") == .valid(1_718_900_000))
        #expect(TimestampInterpreter.evaluate("0") == .valid(0))
        #expect(TimestampInterpreter.evaluate("-1718900000") == .valid(-1_718_900_000))
    }

    @Test func typedInputStatesDistinguishEditingFormatAndRangeFailures() {
        #expect(TimestampInterpreter.evaluate("  ") == .empty)
        #expect(TimestampInterpreter.evaluate("-") == .incomplete)
        #expect(TimestampInterpreter.evaluate("1718900000") == .valid(1_718_900_000))
        #expect(TimestampInterpreter.evaluate("1718900000.5") == .invalid(.nonIntegerFormat))
        #expect(TimestampInterpreter.evaluate("+1") == .invalid(.nonIntegerFormat))
        // 12 位越界秒（恰好超上限一位）：按毫秒时间戳形态提示。
        #expect(TimestampInterpreter.evaluate("253402300800") == .invalid(.outOfRangePossiblyMilliseconds))
    }

    @Test func outOfRangeValuesShapedLikeMillisecondsCarryMillisecondHint() {
        // 12–14 位纯数字按秒解释越界 → 附毫秒提示，帮助 13 位毫秒粘贴者。
        #expect(TimestampInterpreter.evaluate("1718900000000") == .invalid(.outOfRangePossiblyMilliseconds))
        #expect(TimestampInterpreter.evaluate("17189000000000") == .invalid(.outOfRangePossiblyMilliseconds))
        #expect(TimestampInterpreter.evaluate("-999999999999") == .invalid(.outOfRangePossiblyMilliseconds))

        // 其他长度的越界保持原语义；12 位以内的合法秒不受影响。
        #expect(TimestampInterpreter.evaluate("-62135596801") == .invalid(.outOfRange))
        #expect(TimestampInterpreter.evaluate("999999999999999999999999") == .invalid(.outOfRange))
        #expect(TimestampInterpreter.evaluate("253402300799") == .valid(253_402_300_799))

        let message = TimestampInterpreter.ValidationIssue.outOfRangePossiblyMilliseconds.errorDescription ?? ""
        #expect(message.contains("毫秒"))
        ToolDiagnosticContract.expectFactual(message)
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

    @Test func distinguishesIncompleteAndNonIntegerInput() {
        #expect(TimestampInterpreter.evaluate("") == .empty)
        #expect(TimestampInterpreter.evaluate("-") == .incomplete)
        for text in ["+1", "abc", "1718900000.5", ".5", "123.", "1e3", "--1"] {
            #expect(TimestampInterpreter.evaluate(text) == .invalid(.nonIntegerFormat))
        }
    }

    @Test func rejectsNonFiniteValues() {
        #expect(TimestampInterpreter.evaluate("inf") == .invalid(.nonIntegerFormat))
        #expect(TimestampInterpreter.evaluate("nan") == .invalid(.nonIntegerFormat))
    }

    @Test func rejectsValuesOutsideSupportedHumanDateRange() {
        #expect(TimestampInterpreter.evaluate("-62135596800") == .valid(-62_135_596_800))
        #expect(TimestampInterpreter.evaluate("253402300799") == .valid(253_402_300_799))
        #expect(TimestampInterpreter.evaluate("-62135596801") == .invalid(.outOfRange))
        #expect(TimestampInterpreter.evaluate("253402300800") == .invalid(.outOfRangePossiblyMilliseconds))
        #expect(TimestampInterpreter.evaluate("1718900000000") == .invalid(.outOfRangePossiblyMilliseconds))
        #expect(TimestampInterpreter.evaluate("999999999999999999999999") == .invalid(.outOfRange))
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

    @Test func renderingRejectsAnUnrepresentableIntegerWithoutTrapping() {
        let upperBoundary = Double(Int64.max)
        #expect(TimestampInterpreter.wholeSecondText(for: Date(timeIntervalSince1970: upperBoundary)) == nil)
        #expect(TimestampInterpreter.wholeSecondText(for: Date(timeIntervalSince1970: upperBoundary.nextDown)) == "9223372036854774784")
        #expect(TimestampInterpreter.wholeSecondText(for: Date(timeIntervalSince1970: Double(Int64.min))) == "-9223372036854775808")
        #expect(TimestampInterpreter.millisecondText(for: Date(timeIntervalSince1970: upperBoundary / 1_000)) == nil)
        #expect(TimestampInterpreter.wholeSecondText(for: Date(timeIntervalSince1970: -123.987)) == "-123")
    }
}
