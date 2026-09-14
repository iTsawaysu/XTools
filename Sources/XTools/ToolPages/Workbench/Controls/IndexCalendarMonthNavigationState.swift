import Foundation

enum IndexCalendarMonthDirection: Equatable {
    case backward
    case forward
}

struct IndexCalendarMonthNavigationState: Equatable {
    private(set) var displayedMonth: Date
    private(set) var direction: IndexCalendarMonthDirection = .forward
    private(set) var generation = 0

    init(selection: Date, calendar: Calendar) {
        displayedMonth = Self.normalizedMonth(containing: selection, calendar: calendar)
    }

    mutating func reset(to selection: Date, calendar: Calendar) {
        let month = Self.normalizedMonth(containing: selection, calendar: calendar)
        guard month != displayedMonth else { return }

        direction = month < displayedMonth ? .backward : .forward
        displayedMonth = month
        generation &+= 1
    }

    mutating func navigate(by offset: Int, calendar: Calendar) {
        guard offset != 0,
              let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth)
        else {
            return
        }

        direction = offset < 0 ? .backward : .forward
        displayedMonth = Self.normalizedMonth(containing: month, calendar: calendar)
        generation &+= 1
    }

    func daySlots(calendar: Calendar) -> [Date?] {
        var slots: [Date?] = Array(repeating: nil, count: 42)
        guard let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return slots
        }

        let firstWeekdayIndex = calendar.component(.weekday, from: displayedMonth) - 1
        for day in dayRange {
            let slotIndex = firstWeekdayIndex + day - 1
            guard slots.indices.contains(slotIndex),
                  let date = calendar.date(byAdding: .day, value: day - 1, to: displayedMonth)
            else {
                continue
            }
            slots[slotIndex] = date
        }
        return slots
    }

    private static func normalizedMonth(containing date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
