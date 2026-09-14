import XToolsCore
import Foundation
import Testing

struct DateCalcEngineTests {
    @Test func totalsUseCalendarDaysAndExactClockUnits() {
        let calendar = gregorianUTC()
        let from = date(calendar, 2026, 1, 1, 20, 0)
        let to = date(calendar, 2026, 1, 2, 5, 30)
        let totals = DateCalcEngine.totals(from: from, to: to, calendar: calendar)

        #expect(totals.days == 1) // crossing midnight counts as one calendar day
        #expect(totals.weeks == 0) // whole weeks truncate toward zero
        #expect(totals.hours == 9)
        #expect(totals.minutes == 570)
    }

    @Test func totalsPreserveSignWhenDatesAreReversed() {
        let calendar = gregorianUTC()
        let from = date(calendar, 2026, 1, 15, 12, 0)
        let to = date(calendar, 2026, 1, 1, 12, 0)
        let totals = DateCalcEngine.totals(from: from, to: to, calendar: calendar)

        #expect(totals.days == -14)
        #expect(totals.weeks == -2)
        #expect(totals.hours == -336)
        #expect(totals.minutes == -20_160)
    }

    @Test func breakdownIsOrderIndependent() {
        let calendar = gregorianUTC()
        let earlier = date(calendar, 2024, 1, 31, 10, 15)
        let later = date(calendar, 2025, 3, 2, 12, 45)

        let forward = DateCalcEngine.breakdown(from: earlier, to: later, calendar: calendar)
        let reversed = DateCalcEngine.breakdown(from: later, to: earlier, calendar: calendar)

        #expect(forward.years == 1)
        #expect(forward.months == 1)
        #expect(forward.days == 2)
        #expect(forward.hours == 2)
        #expect(forward.minutes == 30)
        #expect(reversed.years == forward.years)
        #expect(reversed.months == forward.months)
        #expect(reversed.days == forward.days)
        #expect(reversed.hours == forward.hours)
        #expect(reversed.minutes == forward.minutes)
    }

    @Test func addSupportsEveryDisplayedUnit() {
        let calendar = gregorianUTC()
        let base = date(calendar, 2026, 1, 31, 0, 0)

        #expect(
            components(calendar, DateCalcEngine.add(value: 3, unit: .day, to: base, calendar: calendar)).day
            == 3
        )
        #expect(
            components(calendar, DateCalcEngine.add(value: 2, unit: .weekOfYear, to: base, calendar: calendar)).day
            == 14
        )
        #expect(
            components(calendar, DateCalcEngine.add(value: 1, unit: .month, to: base, calendar: calendar)).month
            == 2
        )
        #expect(
            components(calendar, DateCalcEngine.add(value: -1, unit: .year, to: base, calendar: calendar)).year
            == 2025
        )
    }

    @Test func addHandlesLeapDayAndMonthEndUsingCalendarRules() {
        let calendar = gregorianUTC()
        let leapDay = date(calendar, 2024, 2, 29, 0, 0)
        let januaryEnd = date(calendar, 2024, 1, 31, 0, 0)

        let nextYear = DateCalcEngine.add(value: 1, unit: .year, to: leapDay, calendar: calendar)
        let nextMonth = DateCalcEngine.add(value: 1, unit: .month, to: januaryEnd, calendar: calendar)

        #expect(components(calendar, nextYear).year == 2025)
        #expect(components(calendar, nextYear).month == 2)
        #expect(components(calendar, nextYear).day == 28)
        #expect(components(calendar, nextMonth).month == 2)
        #expect(components(calendar, nextMonth).day == 29)
    }

    @Test func totalsDistinguishCalendarDaysFromDSTClockHours() {
        let calendar = gregorianNewYork()
        let from = date(calendar, 2026, 3, 8, 0, 0)
        let to = date(calendar, 2026, 3, 9, 0, 0)
        let totals = DateCalcEngine.totals(from: from, to: to, calendar: calendar)

        #expect(totals.days == 1)
        #expect(totals.hours == 23)
        #expect(totals.minutes == 23 * 60)
    }

    @Test func totalsCanIncludeEndDateWithoutChangingDefaultBehavior() {
        let calendar = gregorianUTC()
        let from = date(calendar, 2026, 1, 1, 0, 0)
        let to = date(calendar, 2026, 12, 31, 0, 0)

        let exclusive = DateCalcEngine.totals(from: from, to: to, calendar: calendar)
        let inclusive = DateCalcEngine.totals(from: from, to: to, calendar: calendar, includeEndDate: true)

        #expect(exclusive.days == 364)
        #expect(inclusive.days == 365)
        #expect(inclusive.hours == exclusive.hours + 24)
        #expect(inclusive.minutes == exclusive.minutes + (24 * 60))
    }

    @Test func totalsInclusiveModePreservesReverseDirection() {
        let calendar = gregorianUTC()
        let from = date(calendar, 2026, 1, 10, 0, 0)
        let to = date(calendar, 2026, 1, 1, 0, 0)

        let totals = DateCalcEngine.totals(from: from, to: to, calendar: calendar, includeEndDate: true)

        #expect(totals.days == -10)
        #expect(totals.weeks == -1)
        #expect(totals.hours == -240)
    }

    @Test func breakdownInclusiveModeCountsBoundaryDays() {
        let calendar = gregorianUTC()
        let sameDay = date(calendar, 2026, 7, 6, 0, 0)
        let endOfYear = date(calendar, 2026, 12, 31, 0, 0)
        let startOfYear = date(calendar, 2026, 1, 1, 0, 0)

        let oneDay = DateCalcEngine.breakdown(from: sameDay, to: sameDay, calendar: calendar, includeEndDate: true)
        let fullYear = DateCalcEngine.breakdown(from: startOfYear, to: endOfYear, calendar: calendar, includeEndDate: true)

        #expect(oneDay.years == 0)
        #expect(oneDay.months == 0)
        #expect(oneDay.days == 1)
        #expect(fullYear.years == 1)
        #expect(fullYear.months == 0)
        #expect(fullYear.days == 0)
    }

    private func gregorianUTC() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func gregorianNewYork() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func components(_ calendar: Calendar, _ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: date)
    }
}
