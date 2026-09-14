import XToolsCore
import Foundation
import Testing

struct ControlledDateInputTests {
    @Test func acceptsFullFormattedTypingWithoutSkippingSegments() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var input = ControlledDateInput(components: DateOnlyComponents(year: 2026, month: 7, day: 6))

        input.select(.year)
        var committed: Date?
        for character in "2024-02-29" {
            if let date = input.inputCharacter(character, timeZone: utc) {
                committed = date
            }
        }

        #expect(input.components == DateOnlyComponents(year: 2024, month: 2, day: 29))
        #expect(committed == Self.date(2024, 2, 29, timeZone: utc))
        #expect(input.displayText == "2024-02-29")
    }

    @Test func directTypingClampsOverflowAndAdvancesSegments() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var input = ControlledDateInput(components: DateOnlyComponents(year: 2026, month: 7, day: 6))

        input.select(.year)
        for character in "2024" {
            _ = input.inputCharacter(character, timeZone: utc)
        }

        #expect(input.components == DateOnlyComponents(year: 2024, month: 7, day: 6))
        #expect(input.activeSegment == .month)
        #expect(input.displayText == "2024-07-06")

        for character in "18" {
            _ = input.inputCharacter(character, timeZone: utc)
        }

        #expect(input.components == DateOnlyComponents(year: 2024, month: 12, day: 6))
        #expect(input.activeSegment == .day)
        #expect(input.displayText == "2024-12-06")

        var committed: Date?
        for character in "99" {
            if let date = input.inputCharacter(character, timeZone: utc) {
                committed = date
            }
        }

        #expect(input.components == DateOnlyComponents(year: 2024, month: 12, day: 31))
        #expect(input.activeSegment == .day)
        #expect(input.displayText == "2024-12-31")
        #expect(committed == Self.date(2024, 12, 31, timeZone: utc))
    }

    @Test func directTypingClampsLeapAndCommonYearFebruaryOverflow() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var leapYear = ControlledDateInput(components: DateOnlyComponents(year: 2024, month: 2, day: 1))

        leapYear.select(.day)
        for character in "99" {
            _ = leapYear.inputCharacter(character, timeZone: utc)
        }

        #expect(leapYear.components == DateOnlyComponents(year: 2024, month: 2, day: 29))
        #expect(leapYear.displayText == "2024-02-29")

        var commonYear = ControlledDateInput(components: DateOnlyComponents(year: 2026, month: 2, day: 1))

        commonYear.select(.day)
        for character in "99" {
            _ = commonYear.inputCharacter(character, timeZone: utc)
        }

        #expect(commonYear.components == DateOnlyComponents(year: 2026, month: 2, day: 28))
        #expect(commonYear.displayText == "2026-02-28")
    }

    @Test func directTypingClampsYearLowerBound() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var input = ControlledDateInput(components: DateOnlyComponents(year: 2026, month: 7, day: 6))

        input.select(.year)
        for character in "0000" {
            _ = input.inputCharacter(character, timeZone: utc)
        }

        #expect(input.components == DateOnlyComponents(year: 1, month: 7, day: 6))
        #expect(input.displayText == "0001-07-06")
    }

    @Test func separatorOffsetsSelectNearestRightSegment() {
        let input = ControlledDateInput(components: DateOnlyComponents(year: 2026, month: 7, day: 6))

        #expect(input.segment(containingDisplayOffset: -1) == .year)
        #expect(input.segment(containingDisplayOffset: 0) == .year)
        #expect(input.segment(containingDisplayOffset: 3) == .year)
        #expect(input.segment(containingDisplayOffset: 4) == .month)
        #expect(input.segment(containingDisplayOffset: 5) == .month)
        #expect(input.segment(containingDisplayOffset: 7) == .day)
        #expect(input.segment(containingDisplayOffset: 8) == .day)
        #expect(input.segment(containingDisplayOffset: Int.max) == .day)
    }

    @Test func emptyInputUsesEditingSeedWhenTypingStarts() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let seed = Self.date(2024, 5, 6, timeZone: utc)
        var input = ControlledDateInput()

        #expect(input.inputCharacter("2", timeZone: utc, editingSeed: seed) == nil)

        #expect(input.components == DateOnlyComponents(year: 2024, month: 5, day: 6))
        #expect(input.displayText == "2-05-06")
    }

    @Test func deleteBackwardMovesToPreviousSegmentWhenDraftIsEmpty() {
        var input = ControlledDateInput(components: DateOnlyComponents(year: 2026, month: 7, day: 6))

        input.select(.day)
        input.deleteBackward()

        #expect(input.activeSegment == .month)
        #expect(input.components == DateOnlyComponents(year: 2026, month: 7, day: 6))

        _ = input.inputDigit("1", timeZone: TimeZone(secondsFromGMT: 0)!)
        input.deleteBackward()

        #expect(input.activeSegment == .month)
        #expect(input.components == DateOnlyComponents(year: 2026, month: 7, day: 6))
        #expect(input.displayText == "2026-07-06")
    }

    @Test func ignoresNonDateTypingCharacters() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var input = ControlledDateInput(components: DateOnlyComponents(year: 2026, month: 7, day: 6))

        input.select(.month)
        #expect(input.inputCharacter("x", timeZone: utc) == nil)

        #expect(input.components == DateOnlyComponents(year: 2026, month: 7, day: 6))
        #expect(input.displayText == "2026-07-06")
    }

    @Test func pasteAcceptsDateOnlyFormatsAndRejectsMalformedValues() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var input = ControlledDateInput()

        #expect(input.paste("2026/7/6", timeZone: utc) == .accepted(Self.date(2026, 7, 6, timeZone: utc)))
        #expect(input.components == DateOnlyComponents(year: 2026, month: 7, day: 6))

        let lastComponents = input.components
        #expect(input.paste("2026.07.06", timeZone: utc) == .rejected)
        #expect(input.components == lastComponents)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: year,
            month: month,
            day: day
        ))!
    }
}
