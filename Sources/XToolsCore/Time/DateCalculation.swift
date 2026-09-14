import Foundation

public enum DateCalcEngine {
    public enum Unit: String, CaseIterable, Identifiable, Sendable {
        case day, weekOfYear, month, year

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .day: return "天"
            case .weekOfYear: return "周"
            case .month: return "月"
            case .year: return "年"
            }
        }

        var component: Calendar.Component {
            switch self {
            case .day: return .day
            case .weekOfYear: return .weekOfYear
            case .month: return .month
            case .year: return .year
            }
        }
    }

    public struct Totals {
        public let days: Int
        public let weeks: Int
        public let hours: Int
        public let minutes: Int
    }

    public struct Breakdown {
        public let years: Int
        public let months: Int
        public let days: Int
        public let hours: Int
        public let minutes: Int
    }

    /// Whole-unit signed deltas. Days are counted between calendar-day boundaries.
    /// When `includeEndDate` is true, the visible span counts both boundary days.
    public static func totals(from: Date, to: Date, calendar: Calendar, includeEndDate: Bool = false) -> Totals {
        let dayComps = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: from),
            to: calendar.startOfDay(for: to)
        )
        let rawDays = dayComps.day ?? 0
        let adjustment = includeEndDate ? inclusiveDayAdjustment(rawDays: rawDays, from: from, to: to, calendar: calendar) : 0
        let days = rawDays + adjustment
        let hours = (calendar.dateComponents([.hour], from: from, to: to).hour ?? 0) + (adjustment * 24)
        let minutes = (calendar.dateComponents([.minute], from: from, to: to).minute ?? 0) + (adjustment * 24 * 60)

        return Totals(days: days, weeks: days / 7, hours: hours, minutes: minutes)
    }

    /// Absolute calendar breakdown between the two instants regardless of order.
    /// Inclusive mode is day-oriented and counts both boundary days.
    public static func breakdown(from: Date, to: Date, calendar: Calendar, includeEndDate: Bool = false) -> Breakdown {
        let lo: Date
        let hi: Date
        if includeEndDate {
            lo = calendar.startOfDay(for: min(from, to))
            hi = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(from, to))) ?? max(from, to)
        } else {
            lo = min(from, to)
            hi = max(from, to)
        }
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: lo, to: hi)

        return Breakdown(
            years: components.year ?? 0,
            months: components.month ?? 0,
            days: components.day ?? 0,
            hours: components.hour ?? 0,
            minutes: components.minute ?? 0
        )
    }

    public static func add(value: Int, unit: Unit, to date: Date, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.setValue(value, for: unit.component)
        return calendar.date(byAdding: components, to: date) ?? date
    }

    private static func inclusiveDayAdjustment(rawDays: Int, from: Date, to: Date, calendar: Calendar) -> Int {
        if calendar.isDate(from, inSameDayAs: to) {
            return 1
        }
        return rawDays >= 0 ? 1 : -1
    }
}
