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
        /// 越界且位数形态像毫秒时间戳（12–14 位纯数字）：附毫秒提示而非泛化越界文案。
        case outOfRangePossiblyMilliseconds

        public var errorDescription: String? {
            switch self {
            case .nonIntegerFormat:
                return "Unix 时间戳只能包含整数秒，可在开头使用负号。"
            case .outOfRange:
                return "Unix 时间戳超出公元 1 年至 9999 年的支持范围。"
            case .outOfRangePossiblyMilliseconds:
                return "Unix 时间戳超出公元 1 年至 9999 年的支持范围；这可能是毫秒时间戳（本工具接受秒）。"
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
            return .invalid(
                looksLikeMillisecondTimestamp(trimmed)
                    ? .outOfRangePossiblyMilliseconds
                    : .outOfRange
            )
        }
        return .valid(seconds)
    }

#if DEBUG
    /// The timestamp converter's current UI no longer accepts a millisecond
    /// input mode or fractional seconds. Empty text and a lone "-" are
    /// field-local incomplete edits and therefore return nil.
    ///
    /// Test-only seam: production reads go through `evaluate`, which this
    /// helper wraps for direct unit access. Hidden from release builds.
    public static func integerSeconds(fromTrimmed value: String) -> Double? {
        guard case .valid(let seconds) = evaluate(value) else { return nil }
        return seconds
    }
#endif

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

    /// 12–14 位纯数字（允许负号）在按秒解释越界时，按毫秒时间戳形态提示。
    /// 12 位以内且 ≤ 上限的秒时间戳照常有效，其余长度保持原越界文案。
    private static func looksLikeMillisecondTimestamp(_ value: String) -> Bool {
        let digits = value.hasPrefix("-") ? String(value.dropFirst()) : value
        return (12...14).contains(digits.count)
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
