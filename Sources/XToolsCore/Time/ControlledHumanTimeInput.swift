import Foundation

public enum HumanDateTimeSegment: CaseIterable, Equatable, Hashable, Sendable {
    case year
    case month
    case day
    case hour
    case minute
    case second

    public static let allCases: [HumanDateTimeSegment] = [
        .year,
        .month,
        .day,
        .hour,
        .minute,
        .second
    ]

    public var digitCount: Int {
        switch self {
        case .year:
            return 4
        case .month, .day, .hour, .minute, .second:
            return 2
        }
    }

    public var next: HumanDateTimeSegment {
        switch self {
        case .year:
            return .month
        case .month:
            return .day
        case .day:
            return .hour
        case .hour:
            return .minute
        case .minute:
            return .second
        case .second:
            return .second
        }
    }

    public var previous: HumanDateTimeSegment {
        switch self {
        case .year:
            return .year
        case .month:
            return .year
        case .day:
            return .month
        case .hour:
            return .day
        case .minute:
            return .hour
        case .second:
            return .minute
        }
    }
}

public enum ControlledHumanTimePasteResult: Equatable, Sendable {
    case accepted(Date)
    case rejected
}

public struct ControlledHumanTimeInput: Equatable, Sendable {
    public private(set) var components: HumanDateTimeComponents?
    public private(set) var activeSegment: HumanDateTimeSegment
    public private(set) var draft: String
    private var didAutoAdvanceAfterDigit: Bool

    public init() {
        self.components = nil
        self.activeSegment = .year
        self.draft = ""
        self.didAutoAdvanceAfterDigit = false
    }

    public init(components: HumanDateTimeComponents) {
        self.components = Self.normalized(components)
        self.activeSegment = .year
        self.draft = ""
        self.didAutoAdvanceAfterDigit = false
    }

    public init(date: Date, timeZone: TimeZone) {
        self.init(components: HumanDateTimeConversion.components(from: date, timeZone: timeZone))
    }

    public var isEmpty: Bool {
        components == nil && draft.isEmpty
    }

    public var isFirstSegment: Bool {
        activeSegment == HumanDateTimeSegment.allCases.first
    }

    public var isLastSegment: Bool {
        activeSegment == HumanDateTimeSegment.allCases.last
    }

    public var displayText: String {
        guard let components else { return "" }

        return [
            displayText(for: .year, value: components.year),
            "-",
            displayText(for: .month, value: components.month),
            "-",
            displayText(for: .day, value: components.day),
            " ",
            displayText(for: .hour, value: components.hour),
            ":",
            displayText(for: .minute, value: components.minute),
            ":",
            displayText(for: .second, value: components.second)
        ].joined()
    }

    public func displayRange(for segment: HumanDateTimeSegment) -> Range<Int>? {
        guard components != nil else { return nil }

        var cursor = 0
        for current in HumanDateTimeSegment.allCases {
            let text = displayText(for: current, value: value(for: current))
            let range = cursor..<(cursor + text.count)
            if current == segment {
                return range
            }
            cursor = range.upperBound
            cursor += separator(after: current)?.count ?? 0
        }
        return nil
    }

    public func segment(containingDisplayOffset offset: Int) -> HumanDateTimeSegment {
        guard components != nil else { return .year }

        for segment in HumanDateTimeSegment.allCases {
            guard let range = displayRange(for: segment) else { continue }
            if offset < range.lowerBound || offset < range.upperBound {
                return segment
            }
        }
        return .second
    }

    public mutating func replace(with date: Date, timeZone: TimeZone) {
        components = HumanDateTimeConversion.components(from: date, timeZone: timeZone)
        activeSegment = .year
        draft = ""
        didAutoAdvanceAfterDigit = false
    }

    public mutating func clear() {
        components = nil
        activeSegment = .year
        draft = ""
        didAutoAdvanceAfterDigit = false
    }

    public mutating func select(_ segment: HumanDateTimeSegment) {
        activeSegment = segment
        draft = ""
        didAutoAdvanceAfterDigit = false
    }

    public mutating func movePrevious() {
        select(activeSegment.previous)
    }

    public mutating func moveNext() {
        select(activeSegment.next)
    }

    public mutating func inputCharacter(
        _ character: Character,
        timeZone: TimeZone,
        editingSeed: Date = Date()
    ) -> Date? {
        if character == "-" || character == "/" || character == " " || character == ":" || character == "T" || character == "t" {
            return inputSeparator(timeZone: timeZone)
        }
        return inputDigit(character, timeZone: timeZone, editingSeed: editingSeed)
    }

    public mutating func inputDigit(
        _ digit: Character,
        timeZone: TimeZone,
        editingSeed: Date = Date()
    ) -> Date? {
        guard let value = asciiDigitValue(digit) else { return nil }
        ensureComponentsForEditing(timeZone: timeZone, editingSeed: editingSeed)
        didAutoAdvanceAfterDigit = false

        if draft.count >= activeSegment.digitCount {
            draft = ""
        }

        draft.append(String(value))

        guard draft.count >= activeSegment.digitCount else { return nil }
        let date = commitActiveSegment(timeZone: timeZone, advance: true)
        didAutoAdvanceAfterDigit = true
        return date
    }

    public mutating func inputSeparator(timeZone: TimeZone) -> Date? {
        if didAutoAdvanceAfterDigit && draft.isEmpty {
            didAutoAdvanceAfterDigit = false
            return nil
        }

        didAutoAdvanceAfterDigit = false
        let date = commitActiveSegment(timeZone: timeZone)
        activeSegment = activeSegment.next
        return date
    }

    public mutating func deleteBackward() {
        if draft.isEmpty {
            activeSegment = activeSegment.previous
        } else {
            draft.removeLast()
        }
        didAutoAdvanceAfterDigit = false
    }

    @discardableResult
    public mutating func commitActiveSegment(timeZone: TimeZone, advance: Bool = false) -> Date? {
        guard var nextComponents = components else {
            draft = ""
            didAutoAdvanceAfterDigit = false
            return nil
        }

        guard !draft.isEmpty else {
            if advance {
                activeSegment = activeSegment.next
            }
            didAutoAdvanceAfterDigit = false
            return nil
        }

        assignDraft(to: &nextComponents)
        nextComponents = Self.normalized(nextComponents)
        components = nextComponents
        draft = ""
        if advance {
            activeSegment = activeSegment.next
        }
        didAutoAdvanceAfterDigit = false

        return HumanDateTimeConversion.date(from: nextComponents, timeZone: timeZone)
    }

    public mutating func paste(_ text: String, timeZone: TimeZone) -> ControlledHumanTimePasteResult {
        guard let date = HumanDateTimeConversion.date(fromText: text, timeZone: timeZone) else {
            return .rejected
        }

        replace(with: date, timeZone: timeZone)
        return .accepted(date)
    }

    public static func lastDay(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = clamp(year, to: 1...9999)
        components.month = clamp(month, to: 1...12)
        components.day = 1

        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return 31
        }
        return range.count
    }

    private mutating func ensureComponentsForEditing(timeZone: TimeZone, editingSeed: Date) {
        if components == nil {
            components = HumanDateTimeConversion.components(from: editingSeed, timeZone: timeZone)
        }
    }

    private func displayText(for segment: HumanDateTimeSegment, value: Int) -> String {
        if segment == activeSegment && !draft.isEmpty {
            return draft
        }
        return String(format: "%0\(segment.digitCount)d", value)
    }

    private func value(for segment: HumanDateTimeSegment) -> Int {
        guard let components else { return 0 }

        switch segment {
        case .year:
            return components.year
        case .month:
            return components.month
        case .day:
            return components.day
        case .hour:
            return components.hour
        case .minute:
            return components.minute
        case .second:
            return components.second
        }
    }

    private func separator(after segment: HumanDateTimeSegment) -> String? {
        switch segment {
        case .year, .month:
            return "-"
        case .day:
            return " "
        case .hour, .minute:
            return ":"
        case .second:
            return nil
        }
    }

    private mutating func assignDraft(to components: inout HumanDateTimeComponents) {
        let value = Int(draft) ?? 0

        switch activeSegment {
        case .year:
            components.year = Self.clamp(value, to: 1...9999)
            components.day = min(components.day, Self.lastDay(year: components.year, month: components.month))
        case .month:
            components.month = Self.clamp(value, to: 1...12)
            components.day = min(components.day, Self.lastDay(year: components.year, month: components.month))
        case .day:
            components.day = Self.clamp(value, to: 1...Self.lastDay(year: components.year, month: components.month))
        case .hour:
            components.hour = Self.clamp(value, to: 0...23)
        case .minute:
            components.minute = Self.clamp(value, to: 0...59)
        case .second:
            components.second = Self.clamp(value, to: 0...59)
        }
    }

    private static func normalized(_ components: HumanDateTimeComponents) -> HumanDateTimeComponents {
        var normalized = components
        normalized.year = clamp(normalized.year, to: 1...9999)
        normalized.month = clamp(normalized.month, to: 1...12)
        normalized.day = clamp(normalized.day, to: 1...lastDay(year: normalized.year, month: normalized.month))
        normalized.hour = clamp(normalized.hour, to: 0...23)
        normalized.minute = clamp(normalized.minute, to: 0...59)
        normalized.second = clamp(normalized.second, to: 0...59)
        return normalized
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func asciiDigitValue(_ character: Character) -> Character? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              (48...57).contains(scalar.value) else {
            return nil
        }
        return Character(scalar)
    }
}
