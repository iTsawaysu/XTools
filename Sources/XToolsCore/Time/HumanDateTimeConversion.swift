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
    /// 文本/分量解析失败原因。`.nonexistentLocalTime` 表示格式与数值合法，
    /// 但该本地墙钟时间因夏令时切换被跳过（spring-forward 空洞）；回退式
    /// 歧义时间（一个本地时间出现两次）由系统的双遍历 Calendar 解析，不属失败。
    public enum ParseFailure: Equatable, Sendable {
        case unrecognizedFormat
        case invalidComponents
        case nonexistentLocalTime
    }

    public enum ParseResult: Equatable, Sendable {
        case date(Date)
        case failure(ParseFailure)
    }

    public static func parseResult(fromText text: String, timeZone: TimeZone) -> ParseResult {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .failure(.unrecognizedFormat) }

        if let date = isoDate(from: value) {
            return .date(date)
        }

        guard let components = fixedFormatComponents(from: value) else {
            return .failure(.unrecognizedFormat)
        }

        switch parseResult(from: components, timeZone: timeZone) {
        case .date(let date):
            return .date(date)
        case .failure(.nonexistentLocalTime):
            return .failure(.nonexistentLocalTime)
        case .failure:
            // 数值非法（如 2 月 30 日）对文本粘贴而言等同格式不识别。
            return .failure(.unrecognizedFormat)
        }
    }

    public static func date(fromText text: String, timeZone: TimeZone) -> Date? {
        guard case .date(let date) = parseResult(fromText: text, timeZone: timeZone) else {
            return nil
        }
        return date
    }

    public static func parseResult(
        from components: HumanDateTimeComponents,
        timeZone: TimeZone
    ) -> ParseResult {
        guard (1...9999).contains(components.year),
              (1...12).contains(components.month),
              (1...31).contains(components.day),
              (0...23).contains(components.hour),
              (0...59).contains(components.minute),
              (0...59).contains(components.second) else {
            return .failure(.invalidComponents)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var dateComponents = DateComponents()
        dateComponents.calendar = calendar
        dateComponents.timeZone = timeZone
        dateComponents.year = components.year
        dateComponents.month = components.month
        dateComponents.day = 1

        // 日历日合法性（2 月 30 日等）与“本地时间不存在”是两类失败：
        // 前者归入 invalidComponents，后者才是夏令时空洞。
        guard let firstOfMonth = calendar.date(from: dateComponents),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth),
              dayRange.contains(components.day) else {
            return .failure(.invalidComponents)
        }

        dateComponents.day = components.day
        dateComponents.hour = components.hour
        dateComponents.minute = components.minute
        dateComponents.second = components.second

        guard dateComponents.isValidDate(in: calendar) else {
            return .failure(.nonexistentLocalTime)
        }

        guard let date = calendar.date(from: dateComponents) else {
            return .failure(.invalidComponents)
        }

        let resolved = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard resolved.year == components.year,
              resolved.month == components.month,
              resolved.day == components.day,
              resolved.hour == components.hour,
              resolved.minute == components.minute,
              resolved.second == components.second else {
            return .failure(.nonexistentLocalTime)
        }

        return .date(date)
    }

    public static func date(from components: HumanDateTimeComponents, timeZone: TimeZone) -> Date? {
        guard case .date(let date) = parseResult(from: components, timeZone: timeZone) else {
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

    /// 解析受支持的本地固定格式：`yyyy-MM-dd`（时间视为当地 00:00:00）、
    /// `yyyy-MM-dd HH:mm:ss` 与无时区 ISO `yyyy-MM-ddTHH:mm:ss`（按所选时区）。
    /// 带时区的 ISO 由 isoDate(from:) 先行处理。仅做形状校验，数值合法性
    /// （含夏令时空洞）交给 parseResult(from:timeZone:)。
    private static func fixedFormatComponents(from value: String) -> HumanDateTimeComponents? {
        let datePart: String
        var timePart: String?

        if let spaceIndex = value.firstIndex(of: " ") {
            datePart = String(value[..<spaceIndex])
            timePart = String(value[value.index(after: spaceIndex)...])
        } else if let separatorIndex = value.firstIndex(of: "T") {
            datePart = String(value[..<separatorIndex])
            timePart = String(value[value.index(after: separatorIndex)...])
        } else {
            datePart = value
        }

        let dateNumbers = datePart.split(separator: "-", omittingEmptySubsequences: false)
        guard dateNumbers.count == 3,
              dateNumbers[0].count == 4,
              dateNumbers[1].count == 2,
              dateNumbers[2].count == 2,
              let year = Int(dateNumbers[0]),
              let month = Int(dateNumbers[1]),
              let day = Int(dateNumbers[2]) else {
            return nil
        }

        var hour = 0
        var minute = 0
        var second = 0
        if let timePart {
            let timeNumbers = timePart.split(separator: ":", omittingEmptySubsequences: false)
            guard timeNumbers.count == 3,
                  timeNumbers[0].count == 2,
                  timeNumbers[1].count == 2,
                  timeNumbers[2].count == 2,
                  let parsedHour = Int(timeNumbers[0]),
                  let parsedMinute = Int(timeNumbers[1]),
                  let parsedSecond = Int(timeNumbers[2]) else {
                return nil
            }
            hour = parsedHour
            minute = parsedMinute
            second = parsedSecond
        }

        return HumanDateTimeComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
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
