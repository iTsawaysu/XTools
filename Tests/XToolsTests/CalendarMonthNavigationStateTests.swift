@testable import XTools
import Foundation
import Testing

struct CalendarMonthNavigationStateTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func initialSelectionNormalizesToTheFirstDayOfItsMonth() {
        let state = IndexCalendarMonthNavigationState(
            selection: date(2026, 7, 15),
            calendar: calendar
        )

        #expect(state.displayedMonth == date(2026, 7, 1))
        #expect(state.direction == .forward)
        #expect(state.generation == 0)
    }

    @Test func navigationTracksDirectionGenerationAndLatestMonth() {
        var state = IndexCalendarMonthNavigationState(
            selection: date(2026, 7, 15),
            calendar: calendar
        )

        state.navigate(by: 1, calendar: calendar)
        #expect(state.displayedMonth == date(2026, 8, 1))
        #expect(state.direction == .forward)
        #expect(state.generation == 1)

        state.navigate(by: -1, calendar: calendar)
        #expect(state.displayedMonth == date(2026, 7, 1))
        #expect(state.direction == .backward)
        #expect(state.generation == 2)

        state.navigate(by: 1, calendar: calendar)
        #expect(state.displayedMonth == date(2026, 8, 1))
        #expect(state.direction == .forward)
        #expect(state.generation == 3)
    }

    @Test func zeroNavigationAndSameMonthResetDoNotManufactureTransitions() {
        var state = IndexCalendarMonthNavigationState(
            selection: date(2026, 7, 15),
            calendar: calendar
        )

        state.navigate(by: 0, calendar: calendar)
        state.reset(to: date(2026, 7, 28), calendar: calendar)

        #expect(state.displayedMonth == date(2026, 7, 1))
        #expect(state.direction == .forward)
        #expect(state.generation == 0)
    }

    @Test func resetAndNavigationCrossYearBoundariesDeterministically() {
        var state = IndexCalendarMonthNavigationState(
            selection: date(2026, 12, 31),
            calendar: calendar
        )

        state.navigate(by: 1, calendar: calendar)
        #expect(state.displayedMonth == date(2027, 1, 1))
        #expect(state.generation == 1)

        state.reset(to: date(2025, 2, 14), calendar: calendar)
        #expect(state.displayedMonth == date(2025, 2, 1))
        #expect(state.direction == .backward)
        #expect(state.generation == 2)
    }

    @Test func daySlotsAlwaysFillSixWeeksWithStableLeadingAndTrailingGaps() {
        let july = IndexCalendarMonthNavigationState(
            selection: date(2026, 7, 1),
            calendar: calendar
        ).daySlots(calendar: calendar)

        #expect(july.count == 42)
        #expect(july.prefix(3).allSatisfy { $0 == nil })
        #expect(july[3] == date(2026, 7, 1))
        #expect(july[33] == date(2026, 7, 31))
        #expect(july.suffix(8).allSatisfy { $0 == nil })

        let february = IndexCalendarMonthNavigationState(
            selection: date(2026, 2, 20),
            calendar: calendar
        ).daySlots(calendar: calendar)

        #expect(february.count == 42)
        #expect(february[0] == date(2026, 2, 1))
        #expect(february[27] == date(2026, 2, 28))
        #expect(february.suffix(14).allSatisfy { $0 == nil })
    }
}
