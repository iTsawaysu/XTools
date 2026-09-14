import Foundation

public enum DateOnlyConversion {
    public static func date(fromText text: String, timeZone: TimeZone = .current) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let normalized = value.replacingOccurrences(of: "/", with: "-")
        let parts = normalized.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              !parts.contains(where: \.isEmpty),
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components) else { return nil }

        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year,
              resolved.month == month,
              resolved.day == day else {
            return nil
        }

        return calendar.startOfDay(for: date)
    }

    public static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.string(from: date)
    }
}
