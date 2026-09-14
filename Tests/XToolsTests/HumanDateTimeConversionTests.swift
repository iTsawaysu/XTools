import XToolsCore
import Foundation
import Testing

struct HumanDateTimeConversionTests {
    @Test func parsesFixedHumanTimeUsingSelectedTimeZone() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let shanghai = TimeZone(secondsFromGMT: 8 * 3600)!

        #expect(HumanDateTimeConversion.date(fromText: "2026-07-03 06:30:46", timeZone: utc) == Self.instant("2026-07-03T06:30:46Z"))
        #expect(HumanDateTimeConversion.date(fromText: "2026-07-03 06:30:46", timeZone: shanghai) == Self.instant("2026-07-02T22:30:46Z"))
    }

    @Test func parsesISOInstantsWithoutReinterpretingTheirOffset() {
        let shanghai = TimeZone(secondsFromGMT: 8 * 3600)!

        #expect(HumanDateTimeConversion.date(fromText: "2026-07-03T06:30:46Z", timeZone: shanghai) == Self.instant("2026-07-03T06:30:46Z"))
        #expect(HumanDateTimeConversion.date(fromText: "2026-07-03T06:30:46+02:00", timeZone: shanghai) == Self.instant("2026-07-03T04:30:46Z"))
    }

    @Test func convertsBetweenInstantsAndEditableComponents() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let components = HumanDateTimeComponents(year: 2026, month: 7, day: 3, hour: 6, minute: 30, second: 46)

        #expect(HumanDateTimeConversion.components(from: Self.instant("2026-07-03T06:30:46Z"), timeZone: utc) == components)
        #expect(HumanDateTimeConversion.date(from: components, timeZone: utc) == Self.instant("2026-07-03T06:30:46Z"))
    }

    @Test func rejectsInvalidEditableComponents() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let invalidDate = HumanDateTimeComponents(year: 2026, month: 2, day: 31, hour: 6, minute: 30, second: 46)
        let invalidMonth = HumanDateTimeComponents(year: 2026, month: 13, day: 1, hour: 0, minute: 0, second: 0)
        let invalidTime = HumanDateTimeComponents(year: 2026, month: 7, day: 3, hour: 24, minute: 0, second: 0)
        let invalidMinute = HumanDateTimeComponents(year: 2026, month: 7, day: 3, hour: 6, minute: 99, second: 0)
        let invalidSecond = HumanDateTimeComponents(year: 2026, month: 7, day: 3, hour: 6, minute: 30, second: 99)

        #expect(HumanDateTimeConversion.date(from: invalidDate, timeZone: utc) == nil)
        #expect(HumanDateTimeConversion.date(from: invalidMonth, timeZone: utc) == nil)
        #expect(HumanDateTimeConversion.date(from: invalidTime, timeZone: utc) == nil)
        #expect(HumanDateTimeConversion.date(from: invalidMinute, timeZone: utc) == nil)
        #expect(HumanDateTimeConversion.date(from: invalidSecond, timeZone: utc) == nil)
    }

    @Test func controlledInputKeepsIncompleteSegmentDraftLocal() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var input = ControlledHumanTimeInput(
            components: HumanDateTimeComponents(year: 2026, month: 7, day: 3, hour: 6, minute: 30, second: 46)
        )

        input.select(.second)
        #expect(input.inputDigit("7", timeZone: utc) == nil)
        #expect(input.components?.second == 46)
        #expect(input.displayText == "2026-07-03 06:30:7")

        #expect(input.commitActiveSegment(timeZone: utc) == Self.instant("2026-07-03T06:30:07Z"))
        #expect(input.components?.second == 7)
        #expect(input.displayText == "2026-07-03 06:30:07")
    }

    @Test func controlledInputClampsOverflowingSegmentsOnCommit() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var input = ControlledHumanTimeInput(
            components: HumanDateTimeComponents(year: 2026, month: 7, day: 3, hour: 6, minute: 30, second: 46)
        )

        input.select(.month)
        #expect(input.inputDigit("1", timeZone: utc) == nil)
        #expect(input.inputDigit("9", timeZone: utc) == Self.instant("2026-12-03T06:30:46Z"))
        #expect(input.components?.month == 12)

        input.select(.hour)
        #expect(input.inputDigit("2", timeZone: utc) == nil)
        #expect(input.inputDigit("9", timeZone: utc) == Self.instant("2026-12-03T23:30:46Z"))
        #expect(input.components?.hour == 23)

        input.select(.minute)
        #expect(input.inputDigit("9", timeZone: utc) == nil)
        #expect(input.inputDigit("9", timeZone: utc) == Self.instant("2026-12-03T23:59:46Z"))
        #expect(input.components?.minute == 59)

        input.select(.second)
        #expect(input.inputDigit("9", timeZone: utc) == nil)
        #expect(input.inputDigit("9", timeZone: utc) == Self.instant("2026-12-03T23:59:59Z"))
        #expect(input.components?.second == 59)
    }

    @Test func controlledInputClampsDayOverflowWithoutHiddenWantedDay() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var commonYear = ControlledHumanTimeInput(
            components: HumanDateTimeComponents(year: 2026, month: 1, day: 31, hour: 0, minute: 0, second: 0)
        )

        commonYear.select(.month)
        #expect(commonYear.inputDigit("0", timeZone: utc) == nil)
        #expect(commonYear.inputDigit("2", timeZone: utc) == Self.instant("2026-02-28T00:00:00Z"))
        #expect(commonYear.components == HumanDateTimeComponents(year: 2026, month: 2, day: 28, hour: 0, minute: 0, second: 0))

        commonYear.select(.month)
        #expect(commonYear.inputDigit("0", timeZone: utc) == nil)
        #expect(commonYear.inputDigit("3", timeZone: utc) == Self.instant("2026-03-28T00:00:00Z"))
        #expect(commonYear.components?.day == 28)

        var leapYear = ControlledHumanTimeInput(
            components: HumanDateTimeComponents(year: 2024, month: 1, day: 31, hour: 0, minute: 0, second: 0)
        )
        leapYear.select(.month)
        #expect(leapYear.inputDigit("0", timeZone: utc) == nil)
        #expect(leapYear.inputDigit("2", timeZone: utc) == Self.instant("2024-02-29T00:00:00Z"))
        #expect(leapYear.components?.day == 29)
    }

    @Test func controlledInputParsesAcceptedPasteFormatsAndRejectsMalformedPaste() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let shanghai = TimeZone(secondsFromGMT: 8 * 3600)!
        var input = ControlledHumanTimeInput()

        #expect(input.paste("2026-07-03T06:30:46Z", timeZone: shanghai) == .accepted(Self.instant("2026-07-03T06:30:46Z")))
        #expect(input.components == HumanDateTimeComponents(year: 2026, month: 7, day: 3, hour: 14, minute: 30, second: 46))

        #expect(input.paste("2026-07-03 06:30:46", timeZone: utc) == .accepted(Self.instant("2026-07-03T06:30:46Z")))
        #expect(input.components == HumanDateTimeComponents(year: 2026, month: 7, day: 3, hour: 6, minute: 30, second: 46))

        let lastComponents = input.components
        #expect(input.paste("2026-07-06 123231231210:58:51123213123", timeZone: utc) == .rejected)
        #expect(input.components == lastComponents)
    }

    @Test func controlledInputAcceptsFullFormattedTypingWithoutSkippingSegments() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var input = ControlledHumanTimeInput(
            components: HumanDateTimeComponents(year: 2026, month: 7, day: 6, hour: 22, minute: 8, second: 8)
        )

        input.select(.year)
        var committed: Date?
        for character in "2026-07-06 08:08:08" {
            if let date = input.inputCharacter(character, timeZone: utc) {
                committed = date
            }
        }

        #expect(input.components == HumanDateTimeComponents(year: 2026, month: 7, day: 6, hour: 8, minute: 8, second: 8))
        #expect(committed == Self.instant("2026-07-06T08:08:08Z"))
    }

    @Test func controlledInputCommitsFinalSecondSegmentImmediately() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var input = ControlledHumanTimeInput(
            components: HumanDateTimeComponents(year: 2026, month: 7, day: 6, hour: 8, minute: 9, second: 10)
        )

        input.select(.second)
        #expect(input.inputCharacter("5", timeZone: utc) == nil)
        #expect(input.inputCharacter("6", timeZone: utc) == Self.instant("2026-07-06T08:09:56Z"))
        #expect(input.components == HumanDateTimeComponents(year: 2026, month: 7, day: 6, hour: 8, minute: 9, second: 56))
        #expect(input.activeSegment == .second)
    }

    @Test func controlledInputSeparatorOffsetsSelectNearestRightSegment() {
        let input = ControlledHumanTimeInput(
            components: HumanDateTimeComponents(year: 2026, month: 7, day: 6, hour: 8, minute: 9, second: 10)
        )

        #expect(input.segment(containingDisplayOffset: -1) == .year)
        #expect(input.segment(containingDisplayOffset: 0) == .year)
        #expect(input.segment(containingDisplayOffset: 3) == .year)
        #expect(input.segment(containingDisplayOffset: 4) == .month)
        #expect(input.segment(containingDisplayOffset: 7) == .day)
        #expect(input.segment(containingDisplayOffset: 10) == .hour)
        #expect(input.segment(containingDisplayOffset: 13) == .minute)
        #expect(input.segment(containingDisplayOffset: 16) == .second)
        #expect(input.segment(containingDisplayOffset: Int.max) == .second)
    }

    @Test func controlledInputUsesEditingSeedWhenEmptyTypingStarts() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let seed = Self.instant("2024-05-06T07:08:09Z")
        var input = ControlledHumanTimeInput()

        #expect(input.inputCharacter("2", timeZone: utc, editingSeed: seed) == nil)

        #expect(input.components == HumanDateTimeComponents(year: 2024, month: 5, day: 6, hour: 7, minute: 8, second: 9))
        #expect(input.displayText == "2-05-06 07:08:09")
    }

    @Test func controlledInputDeleteBackwardMovesToPreviousSegmentWhenDraftIsEmpty() {
        var input = ControlledHumanTimeInput(
            components: HumanDateTimeComponents(year: 2026, month: 7, day: 6, hour: 8, minute: 9, second: 10)
        )

        input.select(.minute)
        input.deleteBackward()

        #expect(input.activeSegment == .hour)
        #expect(input.components == HumanDateTimeComponents(year: 2026, month: 7, day: 6, hour: 8, minute: 9, second: 10))

        _ = input.inputDigit("1", timeZone: TimeZone(secondsFromGMT: 0)!)
        input.deleteBackward()

        #expect(input.activeSegment == .hour)
        #expect(input.components == HumanDateTimeComponents(year: 2026, month: 7, day: 6, hour: 8, minute: 9, second: 10))
        #expect(input.displayText == "2026-07-06 08:09:10")
    }

    private static func instant(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
