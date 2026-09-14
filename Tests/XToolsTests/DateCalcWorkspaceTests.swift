import XToolsCore
import Foundation
import Testing

struct DateCalcWorkspaceTests {
    private func fixedReference() -> Date {
        // 2026-07-15 local start-of-day (mid-month, mid-week-ish for presets)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 15
        return calendar.startOfDay(for: calendar.date(from: components)!)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.startOfDay(for: calendar.date(from: components)!)
    }

    @Test func defaultsMatchPageBaseline() {
        let reference = fixedReference()
        let session = DateCalcWorkspace(referenceDate: reference)
        #expect(session.start == reference)
        #expect(session.end == reference)
        #expect(session.base == reference)
        #expect(session.includeEndDate == false)
        #expect(session.op == "1")
        #expect(session.amount == 30)
        #expect(session.unit == .day)
        #expect(session.startInputError == nil)
        #expect(session.endInputError == nil)
        #expect(session.baseInputError == nil)
        #expect(session.totalDaysText == "0 天")
        #expect(session.direction == "同一天")
        #expect(session.diffError == nil)
    }

    @Test func setDiffRangeNormalizesAndClearsErrors() {
        var session = DateCalcWorkspace(referenceDate: fixedReference())
        session.startInputError = "stale"
        session.endInputError = "stale"
        let start = day(2026, 1, 1)
        let end = day(2026, 1, 10)
        session.setDiffRange(start: start, end: end)
        #expect(session.start == start)
        #expect(session.end == end)
        #expect(session.startInputError == nil)
        #expect(session.endInputError == nil)
        #expect(session.totalDaysText == "9 天")
        #expect(session.direction == "结束日期在后")
    }

    @Test func commitStartDoesNotReplaceControlledInput() {
        var session = DateCalcWorkspace(referenceDate: fixedReference())
        let before = session.startInput
        let next = day(2026, 3, 1)
        session.commitStartInputDate(next)
        #expect(session.start == next)
        #expect(session.startInputError == nil)
        #expect(session.startInput == before)
    }

    @Test func applyStartReplacesControlledInputAndClearsError() {
        var session = DateCalcWorkspace(referenceDate: fixedReference())
        session.startInputError = "stale"
        let next = day(2026, 4, 2)
        session.applyStartDate(next)
        #expect(session.start == next)
        #expect(session.startInputError == nil)
        #expect(session.startInput.displayText == DateOnlyConversion.string(from: next))
    }

    @Test func invalidPasteMessagesAreChineseGolden() {
        var session = DateCalcWorkspace(referenceDate: fixedReference())
        session.markStartInvalidPaste()
        session.markEndInvalidPaste()
        session.markBaseInvalidPaste()
        #expect(session.startInputError == "开始日期格式无效，仅支持 yyyy-MM-dd")
        #expect(session.endInputError == "结束日期格式无效，仅支持 yyyy-MM-dd")
        #expect(session.baseInputError == "基准日期格式无效，仅支持 yyyy-MM-dd")
        #expect(session.diffError == "开始日期格式无效，仅支持 yyyy-MM-dd；结束日期格式无效，仅支持 yyyy-MM-dd")
        ToolDiagnosticContract.expectFactual(session.startInputError ?? "")
        ToolDiagnosticContract.expectFactual(session.endInputError ?? "")
        ToolDiagnosticContract.expectFactual(session.baseInputError ?? "")
    }

    @Test func combinedErrorSkipsEmpty() {
        var session = DateCalcWorkspace(referenceDate: fixedReference())
        session.startInputError = ""
        session.endInputError = "结束日期格式无效，仅支持 yyyy-MM-dd"
        #expect(session.diffError == "结束日期格式无效，仅支持 yyyy-MM-dd")
    }

    @Test func inclusiveEndAddsOneDay() {
        var session = DateCalcWorkspace(referenceDate: fixedReference())
        session.setDiffRange(start: day(2026, 1, 1), end: day(2026, 1, 1))
        #expect(session.totals.days == 0)
        session.includeEndDate = true
        #expect(session.totals.days == 1)
        #expect(session.totalDaysText == "1 天")
    }

    @Test func directionWhenEndIsEarlier() {
        var session = DateCalcWorkspace(referenceDate: fixedReference())
        session.setDiffRange(start: day(2026, 5, 10), end: day(2026, 5, 1))
        #expect(session.direction == "结束日期在前")
        #expect(session.totalDaysText == "9 天")
    }

    @Test func addThirtyDaysProducesExpectedResult() {
        var session = DateCalcWorkspace(referenceDate: day(2026, 1, 1))
        session.op = "1"
        session.amount = 30
        session.unit = .day
        #expect(session.resultDateText == "2026-01-31")
        #expect(session.resultCopyText.hasPrefix("2026-01-31 周"))
    }

    @Test func subtractOneWeek() {
        var session = DateCalcWorkspace(referenceDate: day(2026, 1, 15))
        session.op = "-1"
        session.amount = 1
        session.unit = .weekOfYear
        #expect(session.resultDateText == "2026-01-08")
    }

    @Test func presetNext7Days() {
        let reference = day(2026, 7, 15)
        var session = DateCalcWorkspace(referenceDate: reference)
        session.applyPreset(.next7Days)
        #expect(session.start == session.normalized(Date()))
        let expectedEnd = session.cal.date(byAdding: .day, value: 7, to: session.start) ?? session.start
        #expect(session.end == expectedEnd)
        #expect(session.startInputError == nil)
    }

    @Test func presetNext30Days() {
        var session = DateCalcWorkspace(referenceDate: fixedReference())
        session.applyPreset(.next30Days)
        let expectedEnd = session.cal.date(byAdding: .day, value: 30, to: session.start) ?? session.start
        #expect(session.end == expectedEnd)
        #expect(session.totals.days == 30 || abs(session.totals.days) == 30)
    }

    @Test func presetThisMonth() {
        let reference = day(2026, 7, 15)
        var session = DateCalcWorkspace(referenceDate: reference)
        // Freeze "today" semantics: applyPreset uses Date() not referenceDate.
        // We still verify structure: start is month start, end is month last day for current calendar month of Date().
        session.applyPreset(.thisMonth)
        let today = session.normalized(Date())
        guard let interval = session.cal.dateInterval(of: .month, for: today),
              let lastDay = session.cal.date(byAdding: .day, value: -1, to: interval.end) else {
            Issue.record("calendar month interval unavailable")
            return
        }
        #expect(session.start == interval.start)
        #expect(session.end == lastDay)
    }

    @Test func presetThisYear() {
        var session = DateCalcWorkspace(referenceDate: fixedReference())
        session.applyPreset(.thisYear)
        let today = session.normalized(Date())
        guard let interval = session.cal.dateInterval(of: .year, for: today),
              let lastDay = session.cal.date(byAdding: .day, value: -1, to: interval.end) else {
            Issue.record("calendar year interval unavailable")
            return
        }
        #expect(session.start == interval.start)
        #expect(session.end == lastDay)
    }

    @Test func presetTitlesMatchVisibleChips() {
        #expect(DateCalcWorkspace.DiffPreset.next7Days.title == "未来 7 天")
        #expect(DateCalcWorkspace.DiffPreset.next30Days.title == "未来 30 天")
        #expect(DateCalcWorkspace.DiffPreset.thisMonth.title == "本月")
        #expect(DateCalcWorkspace.DiffPreset.thisYear.title == "今年")
        #expect(DateCalcWorkspace.DiffPreset.allCases.count == 4)
    }

    @Test func breakdownStatsLabelsAreChinese() {
        var session = DateCalcWorkspace(referenceDate: day(2024, 1, 1))
        session.setDiffRange(start: day(2024, 1, 1), end: day(2025, 3, 5))
        let labels = session.breakdownStats.map(\.0)
        #expect(labels == ["年", "月", "天"])
    }

    @Test func setTodayPathsClearErrors() {
        var session = DateCalcWorkspace(referenceDate: day(2020, 1, 1))
        session.startInputError = "stale"
        session.endInputError = "stale"
        session.baseInputError = "stale"
        session.setStartToday()
        session.setEndToday()
        session.setBaseToday()
        let today = session.normalized(Date())
        #expect(session.start == today)
        #expect(session.end == today)
        #expect(session.base == today)
        #expect(session.startInputError == nil)
        #expect(session.endInputError == nil)
        #expect(session.baseInputError == nil)
    }
}
