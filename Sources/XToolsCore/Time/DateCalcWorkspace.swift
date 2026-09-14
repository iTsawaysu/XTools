import Foundation

public struct DateCalcWorkspace: Equatable, Sendable {
    // MARK: - Range side

    public var start: Date
    public var end: Date
    public var startInput: ControlledDateInput
    public var endInput: ControlledDateInput
    public var startInputError: String?
    public var endInputError: String?
    public var includeEndDate: Bool

    // MARK: - Add side

    public var base: Date
    public var baseInput: ControlledDateInput
    public var baseInputError: String?
    public var op: String
    public var amount: Int
    public var unit: DateCalcEngine.Unit

    public init(referenceDate: Date = Date()) {
        let calendar = Self.gregorianCalendar
        let today = calendar.startOfDay(for: referenceDate)
        self.start = today
        self.end = today
        self.base = today
        self.startInput = ControlledDateInput(date: today, timeZone: TimeZone.current)
        self.endInput = ControlledDateInput(date: today, timeZone: TimeZone.current)
        self.baseInput = ControlledDateInput(date: today, timeZone: TimeZone.current)
        self.startInputError = nil
        self.endInputError = nil
        self.includeEndDate = false
        self.baseInputError = nil
        self.op = "1"
        self.amount = 30
        self.unit = DateCalcEngine.Unit.day
    }

    // MARK: - Calendar

    private static var gregorianCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    public var cal: Calendar {
        Self.gregorianCalendar
    }

    // MARK: - Range derived

    public var totals: DateCalcEngine.Totals {
        DateCalcEngine.totals(from: start, to: end, calendar: cal, includeEndDate: includeEndDate)
    }

    public var breakdown: DateCalcEngine.Breakdown {
        DateCalcEngine.breakdown(from: start, to: end, calendar: cal, includeEndDate: includeEndDate)
    }

    public var breakdownStats: [(String, String)] {
        let b = breakdown
        return [("年", "\(b.years)"), ("月", "\(b.months)"), ("天", "\(b.days)")]
    }

    public var totalDaysText: String {
        "\(abs(totals.days)) 天"
    }

    public var direction: String {
        if cal.isDate(start, inSameDayAs: end) {
            return "同一天"
        }
        return end > start ? "结束日期在后" : "结束日期在前"
    }

    public var diffError: String? {
        combinedError(startInputError, endInputError)
    }

    // MARK: - Add derived

    public var resultDate: Date {
        DateCalcEngine.add(value: (op == "1" ? 1 : -1) * amount, unit: unit, to: base, calendar: cal)
    }

    public var resultDateText: String {
        DateOnlyConversion.string(from: resultDate)
    }

    public var resultWeekdayText: String {
        "周\(weekdaySymbol(for: resultDate))"
    }

    public var resultCopyText: String {
        "\(resultDateText) \(resultWeekdayText)"
    }

    // MARK: - Presets

    public enum DiffPreset: String, CaseIterable, Sendable {
        case next7Days
        case next30Days
        case thisMonth
        case thisYear

        public var title: String {
            switch self {
            case .next7Days: return "未来 7 天"
            case .next30Days: return "未来 30 天"
            case .thisMonth: return "本月"
            case .thisYear: return "今年"
            }
        }
    }

    public mutating func applyPreset(_ preset: DiffPreset) {
        switch preset {
        case .next7Days:
            let today = normalized(Date())
            let future = cal.date(byAdding: .day, value: 7, to: today) ?? today
            setDiffRange(start: today, end: future)
        case .next30Days:
            let today = normalized(Date())
            let future = cal.date(byAdding: .day, value: 30, to: today) ?? today
            setDiffRange(start: today, end: future)
        case .thisMonth:
            let today = normalized(Date())
            guard let interval = cal.dateInterval(of: .month, for: today),
                  let lastDay = cal.date(byAdding: .day, value: -1, to: interval.end) else {
                setDiffRange(start: today, end: today)
                return
            }
            setDiffRange(start: interval.start, end: lastDay)
        case .thisYear:
            let today = normalized(Date())
            guard let interval = cal.dateInterval(of: .year, for: today),
                  let lastDay = cal.date(byAdding: .day, value: -1, to: interval.end) else {
                setDiffRange(start: today, end: today)
                return
            }
            setDiffRange(start: interval.start, end: lastDay)
        }
    }

    // MARK: - Orchestration

    public mutating func setDiffRange(start: Date, end: Date) {
        let nextStart = normalized(start)
        let nextEnd = normalized(end)
        self.start = nextStart
        self.end = nextEnd
        startInput.replace(with: nextStart, timeZone: cal.timeZone)
        endInput.replace(with: nextEnd, timeZone: cal.timeZone)
        startInputError = nil
        endInputError = nil
    }

    public mutating func commitStartInputDate(_ date: Date) {
        start = normalized(date)
        startInputError = nil
    }

    public mutating func commitEndInputDate(_ date: Date) {
        end = normalized(date)
        endInputError = nil
    }

    public mutating func commitBaseInputDate(_ date: Date) {
        base = normalized(date)
        baseInputError = nil
    }

    public mutating func applyStartDate(_ date: Date) {
        let normalizedDate = normalized(date)
        start = normalizedDate
        startInput.replace(with: normalizedDate, timeZone: cal.timeZone)
        startInputError = nil
    }

    public mutating func applyEndDate(_ date: Date) {
        let normalizedDate = normalized(date)
        end = normalizedDate
        endInput.replace(with: normalizedDate, timeZone: cal.timeZone)
        endInputError = nil
    }

    public mutating func applyBaseDate(_ date: Date) {
        let normalizedDate = normalized(date)
        base = normalizedDate
        baseInput.replace(with: normalizedDate, timeZone: cal.timeZone)
        baseInputError = nil
    }

    public mutating func setStartToday() {
        applyStartDate(Date())
    }

    public mutating func setEndToday() {
        applyEndDate(Date())
    }

    public mutating func setBaseToday() {
        applyBaseDate(Date())
    }

    public mutating func markStartInvalidPaste() {
        startInputError = "开始日期格式无效，仅支持 yyyy-MM-dd"
    }

    public mutating func markEndInvalidPaste() {
        endInputError = "结束日期格式无效，仅支持 yyyy-MM-dd"
    }

    public mutating func markBaseInvalidPaste() {
        baseInputError = "基准日期格式无效，仅支持 yyyy-MM-dd"
    }

    // MARK: - Internals

    public func normalized(_ date: Date) -> Date {
        cal.startOfDay(for: date)
    }

    public func weekdaySymbol(for date: Date) -> String {
        let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
        let weekdayIndex = cal.component(.weekday, from: date)
        guard (1...7).contains(weekdayIndex) else { return "?" }
        return weekdaySymbols[weekdayIndex - 1]
    }

    public func combinedError(_ first: String?, _ second: String?) -> String? {
        let messages = [first, second].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        guard !messages.isEmpty else { return nil }
        return messages.joined(separator: "；")
    }
}
