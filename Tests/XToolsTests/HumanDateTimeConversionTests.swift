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

    @Test func parsesDateOnlyAsLocalMidnight() {
        let shanghai = TimeZone(secondsFromGMT: 8 * 3600)!

        // 纯日期 → 当地 00:00:00（此前直接判为无法识别）。
        #expect(HumanDateTimeConversion.date(fromText: "2026-10-02", timeZone: shanghai) == Self.instant("2026-10-01T16:00:00Z"))
        #expect(HumanDateTimeConversion.date(fromText: "2026-10-02", timeZone: TimeZone(secondsFromGMT: 0)!) == Self.instant("2026-10-02T00:00:00Z"))
        #expect(HumanDateTimeConversion.date(fromText: "2026-02-30", timeZone: shanghai) == nil)
    }

    @Test func parsesTimezonelessISOInSelectedTimeZone() {
        let shanghai = TimeZone(secondsFromGMT: 8 * 3600)!

        // 无时区 ISO → 当前选中时区；带时区 ISO 的既有语义不变。
        #expect(HumanDateTimeConversion.date(fromText: "2026-10-02T10:00:00", timeZone: shanghai) == Self.instant("2026-10-02T02:00:00Z"))
        #expect(HumanDateTimeConversion.date(fromText: "2026-10-02T10:00:00", timeZone: TimeZone(secondsFromGMT: 0)!) == Self.instant("2026-10-02T10:00:00Z"))
        #expect(HumanDateTimeConversion.date(fromText: "2026-10-02T10:00:00Z", timeZone: shanghai) == Self.instant("2026-10-02T10:00:00Z"))
    }

    @Test func distinguishesNonexistentDSTGapFromFormatAndComponentFailures() {
        let newYork = TimeZone(identifier: "America/New_York")!

        // 2026-03-08 02:30 America/New_York 因春季拨快被跳过（DST 空洞）。
        #expect(
            HumanDateTimeConversion.parseResult(fromText: "2026-03-08 02:30:00", timeZone: newYork)
                == .failure(.nonexistentLocalTime)
        )
        #expect(
            HumanDateTimeConversion.parseResult(
                from: HumanDateTimeComponents(year: 2026, month: 3, day: 8, hour: 2, minute: 30, second: 0),
                timeZone: newYork
            ) == .failure(.nonexistentLocalTime)
        )

        // 格式不识别与非法日历日保持原有失败类别。
        #expect(
            HumanDateTimeConversion.parseResult(fromText: "2026-03-08 02:30", timeZone: newYork)
                == .failure(.unrecognizedFormat)
        )
        #expect(
            HumanDateTimeConversion.parseResult(
                from: HumanDateTimeComponents(year: 2026, month: 2, day: 30, hour: 1, minute: 0, second: 0),
                timeZone: newYork
            ) == .failure(.invalidComponents)
        )

        // 回退式歧义时间（2026-11-01 01:30 出现两次）由系统解析，不算失败。
        let ambiguous = HumanDateTimeConversion.parseResult(
            from: HumanDateTimeComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 30, second: 0),
            timeZone: newYork
        )
        if case .failure = ambiguous {
            Issue.record("fall-back ambiguous local time should resolve via the two-pass calendar")
        }

        // 正常时间不回归：空洞前后的一小时均可解析。
        #expect(
            HumanDateTimeConversion.parseResult(fromText: "2026-03-08 01:30:00", timeZone: newYork)
                == .date(Self.instant("2026-03-08T06:30:00Z"))
        )
        #expect(
            HumanDateTimeConversion.parseResult(fromText: "2026-03-08 03:30:00", timeZone: newYork)
                == .date(Self.instant("2026-03-08T07:30:00Z"))
        )
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

        // 纯日期粘贴 → 当地 00:00:00；无时区 ISO 粘贴 → 选中时区。
        #expect(input.paste("2026-07-03", timeZone: utc) == .accepted(Self.instant("2026-07-03T00:00:00Z")))
        #expect(input.components == HumanDateTimeComponents(year: 2026, month: 7, day: 3, hour: 0, minute: 0, second: 0))
        #expect(input.paste("2026-07-03T06:30:46", timeZone: utc) == .accepted(Self.instant("2026-07-03T06:30:46Z")))

        let lastComponents = input.components
        #expect(input.paste("2026-07-06 123231231210:58:51123213123", timeZone: utc) == .rejected)
        #expect(input.components == lastComponents)
    }

    @Test func controlledInputReportsNonexistentDSTGapForPasteAndTypedCommit() {
        let newYork = TimeZone(identifier: "America/New_York")!
        var input = ControlledHumanTimeInput()

        // 粘贴空洞时间：与“格式不识别”区分开，且不吞掉已有分量。
        #expect(input.paste("2026-03-08 02:30:00", timeZone: newYork) == .rejectedNonexistentLocalTime)
        #expect(input.components == nil)

        // 键入到空洞小时后提交：commit 仍返回 nil，但携带可诊断的失败原因。
        input = ControlledHumanTimeInput(
            components: HumanDateTimeComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 59, second: 0)
        )
        input.select(.hour)
        #expect(input.inputDigit("0", timeZone: newYork) == nil)
        #expect(input.inputDigit("2", timeZone: newYork) == nil)
        #expect(input.components?.hour == 2)
        #expect(input.lastCommitFailure == .nonexistentLocalTime)

        // 改回存在的小时后恢复，诊断清除。（03:59 EDT = 07:59Z）
        input.select(.hour)
        #expect(input.inputDigit("0", timeZone: newYork) == nil)
        #expect(input.inputDigit("3", timeZone: newYork) == Self.instant("2026-03-08T07:59:00Z"))
        #expect(input.lastCommitFailure == nil)

        // 普通失败提交后不残留空洞诊断。
        input.select(.day)
        #expect(input.inputDigit("3", timeZone: newYork) == nil)
        #expect(input.inputDigit("1", timeZone: newYork) == Self.instant("2026-03-31T07:59:00Z"))
        #expect(input.lastCommitFailure == nil)
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
