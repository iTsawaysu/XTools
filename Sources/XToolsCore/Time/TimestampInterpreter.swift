import Foundation

public enum TimestampInterpreter {
    private static let minimumSupportedEpochSeconds = -62_135_596_800.0
    private static let maximumSupportedEpochSeconds = 253_402_300_799.0
    private static let decimalLocale = Locale(identifier: "en_US_POSIX")

    public enum InputState: Equatable {
        case empty
        case incomplete
        case valid(Double)
        case invalid(ValidationIssue)
    }

    public enum ValidationIssue: LocalizedError, Equatable {
        case nonIntegerFormat
        case outOfRange

        public var errorDescription: String? {
            switch self {
            case .nonIntegerFormat:
                return "Unix 时间戳只能包含整数秒，可在开头使用负号。"
            case .outOfRange:
                return "Unix 时间戳超出公元 1 年至 9999 年的支持范围。"
            }
        }
    }

    public static func evaluate(_ value: String) -> InputState {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed != "-" else { return .incomplete }
        guard isIntegerSecondsTimestamp(trimmed),
              let decimal = Decimal(string: trimmed, locale: decimalLocale) else {
            return .invalid(.nonIntegerFormat)
        }

        let seconds = NSDecimalNumber(decimal: decimal).doubleValue
        guard isSupportedEpochSeconds(seconds) else {
            return .invalid(.outOfRange)
        }
        return .valid(seconds)
    }

    /// The timestamp converter's current UI no longer accepts a millisecond
    /// input mode or fractional seconds. Empty text and a lone "-" are
    /// field-local incomplete edits and therefore return nil.
    public static func integerSeconds(fromTrimmed value: String) -> Double? {
        guard case .valid(let seconds) = evaluate(value) else { return nil }
        return seconds
    }

    public static func wholeSecondText(for date: Date) -> String? {
        integerText(date.timeIntervalSince1970)
    }

    public static func millisecondText(for date: Date) -> String? {
        integerText(date.timeIntervalSince1970 * 1000)
    }

    public static func canonicalWholeSecondDate(for date: Date) -> Date? {
        let wholeSeconds = date.timeIntervalSince1970.rounded(.towardZero)
        guard isSupportedEpochSeconds(wholeSeconds) else { return nil }
        return Date(timeIntervalSince1970: wholeSeconds)
    }

    private static func isIntegerSecondsTimestamp(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        var index = value.utf8.startIndex
        if value.utf8[index] == UInt8(ascii: "-") {
            value.utf8.formIndex(after: &index)
            guard index < value.utf8.endIndex else { return false }
        }
        while index < value.utf8.endIndex {
            let byte = value.utf8[index]
            guard byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") else {
                return false
            }
            value.utf8.formIndex(after: &index)
        }
        return true
    }

    private static func isSupportedEpochSeconds(_ value: Double) -> Bool {
        value.isFinite
            && value >= minimumSupportedEpochSeconds
            && value <= maximumSupportedEpochSeconds
    }

    private static func integerText(_ value: Double) -> String? {
        guard value.isFinite,
              value >= Double(Int64.min),
              value <= Double(Int64.max) else {
            return nil
        }
        return String(Int64(value.rounded(.towardZero)))
    }
}
