import Foundation

public struct HumanDateTimeComponents: Equatable, Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    public var hour: Int
    public var minute: Int
    public var second: Int

    public init(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
    }
}

public enum HumanDateTimeConversion {
    public static func date(fromText text: String, timeZone: TimeZone) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        return isoDate(from: value)
            ?? fixedFormatter(timeZone: timeZone).date(from: value)
    }

    public static func date(from components: HumanDateTimeComponents, timeZone: TimeZone) -> Date? {
        guard (1...9999).contains(components.year),
              (1...12).contains(components.month),
              (1...31).contains(components.day),
              (0...23).contains(components.hour),
              (0...59).contains(components.minute),
              (0...59).contains(components.second) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var dateComponents = DateComponents()
        dateComponents.calendar = calendar
        dateComponents.timeZone = timeZone
        dateComponents.year = components.year
        dateComponents.month = components.month
        dateComponents.day = components.day
        dateComponents.hour = components.hour
        dateComponents.minute = components.minute
        dateComponents.second = components.second

        guard let date = calendar.date(from: dateComponents) else { return nil }

        let resolved = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard resolved.year == components.year,
              resolved.month == components.month,
              resolved.day == components.day,
              resolved.hour == components.hour,
              resolved.minute == components.minute,
              resolved.second == components.second else {
            return nil
        }

        return date
    }

    public static func components(from date: Date, timeZone: TimeZone) -> HumanDateTimeComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        return HumanDateTimeComponents(
            year: components.year ?? 1,
            month: components.month ?? 1,
            day: components.day ?? 1,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0
        )
    }

    public static func string(from date: Date, timeZone: TimeZone) -> String {
        fixedFormatter(timeZone: timeZone).string(from: date)
    }

    private static func fixedFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        return formatter
    }

    private static func isoDate(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
