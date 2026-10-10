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

extension DateOnlySegment: SegmentedFieldSegment {}

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

/// 纯日期（yyyy-MM-dd）分段受控输入。游标状态机由
/// SegmentedFieldState 承载；本类型保留段值 clamp 与显示格式化。
public struct ControlledDateInput: Equatable, Sendable {
    public private(set) var components: DateOnlyComponents?
    var state: SegmentedFieldState<DateOnlySegment>

    private typealias FieldState = SegmentedFieldState<DateOnlySegment>

    public init() {
        self.components = nil
        self.state = FieldState()
    }

    public init(components: DateOnlyComponents) {
        self.components = Self.normalized(components)
        self.state = FieldState()
    }

    public init(date: Date, timeZone: TimeZone) {
        self.init(components: Self.components(from: date, timeZone: timeZone))
    }

    public var isEmpty: Bool {
        components == nil && state.draft.isEmpty
    }

    public var activeSegment: DateOnlySegment {
        state.activeSegment
    }

    public var draft: String {
        state.draft
    }

    public var isFirstSegment: Bool {
        state.isFirstSegment
    }

    public var isLastSegment: Bool {
        state.isLastSegment
    }

    public var displayText: String {
        guard let components else { return "" }

        return [
            state.digitText(for: .year, value: components.year),
            "-",
            state.digitText(for: .month, value: components.month),
            "-",
            state.digitText(for: .day, value: components.day)
        ].joined()
    }

    public func displayRange(for segment: DateOnlySegment) -> Range<Int>? {
        state.displayRange(
            for: segment,
            hasComponents: components != nil,
            value: value(for:),
            separatorLength: { $0 == .day ? 0 : 1 }
        )
    }

    public func segment(containingDisplayOffset offset: Int) -> DateOnlySegment {
        state.segment(
            atDisplayOffset: offset,
            hasComponents: components != nil,
            value: value(for:),
            separatorLength: { $0 == .day ? 0 : 1 }
        )
    }

    public mutating func replace(with date: Date, timeZone: TimeZone) {
        components = Self.components(from: date, timeZone: timeZone)
        state.reset()
    }

    public mutating func clear() {
        components = nil
        state.reset()
    }

    public mutating func select(_ segment: DateOnlySegment) {
        state.select(segment)
    }

    public mutating func movePrevious() {
        state.movePrevious()
    }

    public mutating func moveNext() {
        state.moveNext()
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
        let outcome = state.appendDigit(digit)
        guard outcome != .ignored else { return nil }
        ensureComponentsForEditing(timeZone: timeZone, editingSeed: editingSeed)
        guard outcome == .filled else { return nil }
        let date = commitActiveSegment(timeZone: timeZone, advance: true)
        state.noteAutoAdvanceAfterDigit()
        return date
    }

    public mutating func inputSeparator(timeZone: TimeZone) -> Date? {
        guard state.beginSeparatorInput() else { return nil }
        let date = commitActiveSegment(timeZone: timeZone)
        state.advanceToNextSegment()
        return date
    }

    public mutating func deleteBackward() {
        state.deleteBackward()
    }

    @discardableResult
    public mutating func commitActiveSegment(timeZone: TimeZone, advance: Bool = false) -> Date? {
        state.commitActiveSegment(
            components: &components,
            timeZone: timeZone,
            advance: advance,
            assignDraft: Self.assignDraft,
            normalized: Self.normalized,
            resolve: Self.resolveDate
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
        let clampedMonth = FieldState.clamp(month, to: 1...12)
        switch clampedMonth {
        case 1, 3, 5, 7, 8, 10, 12:
            return 31
        case 4, 6, 9, 11:
            return 30
        case 2:
            let clampedYear = FieldState.clamp(year, to: 1...9999)
            let isLeap = (clampedYear % 4 == 0 && clampedYear % 100 != 0) || (clampedYear % 400 == 0)
            return isLeap ? 29 : 28
        default:
            return 31
        }
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
        let year = FieldState.clamp(components.year, to: 1...9999)
        let month = FieldState.clamp(components.month, to: 1...12)
        let day = FieldState.clamp(components.day, to: 1...lastDay(year: year, month: month))
        return DateOnlyComponents(year: year, month: month, day: day)
    }

    private mutating func ensureComponentsForEditing(timeZone: TimeZone, editingSeed: Date) {
        if components == nil {
            components = Self.components(from: editingSeed, timeZone: timeZone)
        }
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

    private static func assignDraft(
        _ segment: DateOnlySegment,
        _ draft: String,
        to components: inout DateOnlyComponents
    ) {
        let value = Int(draft) ?? 0

        switch segment {
        case .year:
            components.year = FieldState.clamp(value, to: 1...9999)
            components.day = min(components.day, lastDay(year: components.year, month: components.month))
        case .month:
            components.month = FieldState.clamp(value, to: 1...12)
            components.day = min(components.day, lastDay(year: components.year, month: components.month))
        case .day:
            components.day = FieldState.clamp(value, to: 1...lastDay(year: components.year, month: components.month))
        }
    }

    private static func resolveDate(_ components: DateOnlyComponents, timeZone: TimeZone) -> Date? {
        DateOnlyConversion.date(
            fromText: "\(components.year)-\(components.month)-\(components.day)",
            timeZone: timeZone
        )
    }
}
