import Foundation

public enum DateOnlySegment: CaseIterable, Equatable, Hashable, Sendable {
    case year
    case month
    case day

    public static let allCases: [DateOnlySegment] = [.year, .month, .day]

    public var digitCount: Int {
        switch self {
        case .year:
            return 4
        case .month, .day:
            return 2
        }
    }

    public var next: DateOnlySegment {
        switch self {
        case .year:
            return .month
        case .month:
            return .day
        case .day:
            return .day
        }
    }

    public var previous: DateOnlySegment {
        switch self {
        case .year:
            return .year
        case .month:
            return .year
        case .day:
            return .month
        }
    }
}

public struct DateOnlyComponents: Equatable, Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

public enum ControlledDatePasteResult: Equatable, Sendable {
    case accepted(Date)
    case rejected
}

public struct ControlledDateInput: Equatable, Sendable {
    public private(set) var components: DateOnlyComponents?
    public private(set) var activeSegment: DateOnlySegment
    public private(set) var draft: String

    private var didAutoAdvanceAfterDigit: Bool

    public init() {
        self.components = nil
        self.activeSegment = .year
        self.draft = ""
        self.didAutoAdvanceAfterDigit = false
    }

    public init(components: DateOnlyComponents) {
        self.components = Self.normalized(components)
        self.activeSegment = .year
        self.draft = ""
        self.didAutoAdvanceAfterDigit = false
    }

    public init(date: Date, timeZone: TimeZone) {
        self.init(components: Self.components(from: date, timeZone: timeZone))
    }

    public var isEmpty: Bool {
        components == nil && draft.isEmpty
    }

    public var isFirstSegment: Bool {
        activeSegment == DateOnlySegment.allCases.first
    }

    public var isLastSegment: Bool {
        activeSegment == DateOnlySegment.allCases.last
    }

    public var displayText: String {
        guard let components else { return "" }

        return [
            displayText(for: .year, value: components.year),
            "-",
            displayText(for: .month, value: components.month),
            "-",
            displayText(for: .day, value: components.day)
        ].joined()
    }

    public func displayRange(for segment: DateOnlySegment) -> Range<Int>? {
        guard components != nil else { return nil }

        var cursor = 0
        for current in DateOnlySegment.allCases {
            let text = displayText(for: current, value: value(for: current))
            let range = cursor..<(cursor + text.count)
            if current == segment {
                return range
            }
            cursor = range.upperBound
            cursor += current == .day ? 0 : 1
        }
        return nil
    }

    public func segment(containingDisplayOffset offset: Int) -> DateOnlySegment {
        guard components != nil else { return .year }

        for segment in DateOnlySegment.allCases {
            guard let range = displayRange(for: segment) else { continue }
            if offset < range.lowerBound || offset < range.upperBound {
                return segment
            }
        }
        return .day
    }

    public mutating func replace(with date: Date, timeZone: TimeZone) {
        components = Self.components(from: date, timeZone: timeZone)
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

    public mutating func select(_ segment: DateOnlySegment) {
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
        if character == "-" || character == "/" {
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

        return DateOnlyConversion.date(
            fromText: "\(nextComponents.year)-\(nextComponents.month)-\(nextComponents.day)",
            timeZone: timeZone
        )
    }

    public mutating func paste(_ text: String, timeZone: TimeZone) -> ControlledDatePasteResult {
        guard let date = DateOnlyConversion.date(fromText: text, timeZone: timeZone) else {
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

    private static func components(from date: Date, timeZone: TimeZone) -> DateOnlyComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return DateOnlyComponents(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    private static func normalized(_ components: DateOnlyComponents) -> DateOnlyComponents {
        let year = clamp(components.year, to: 1...9999)
        let month = clamp(components.month, to: 1...12)
        let day = clamp(components.day, to: 1...lastDay(year: year, month: month))
        return DateOnlyComponents(year: year, month: month, day: day)
    }

    private mutating func ensureComponentsForEditing(timeZone: TimeZone, editingSeed: Date) {
        if components == nil {
            components = Self.components(from: editingSeed, timeZone: timeZone)
        }
    }

    private func displayText(for segment: DateOnlySegment, value: Int) -> String {
        if segment == activeSegment && !draft.isEmpty {
            return draft
        }
        return String(format: "%0\(segment.digitCount)d", value)
    }

    private func value(for segment: DateOnlySegment) -> Int {
        guard let components else { return 0 }

        switch segment {
        case .year:
            return components.year
        case .month:
            return components.month
        case .day:
            return components.day
        }
    }

    private mutating func assignDraft(to components: inout DateOnlyComponents) {
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
        }
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func asciiDigitValue(_ character: Character) -> Int? {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1,
              ("0"..."9").contains(scalar) else {
            return nil
        }
        return Int(scalar.value - UnicodeScalar("0").value)
    }
}
