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

extension HumanDateTimeSegment: SegmentedFieldSegment {}

public enum ControlledHumanTimePasteResult: Equatable, Sendable {
    case accepted(Date)
    case rejected
    /// 粘贴文本格式合法，但该本地时间因夏令时切换不存在。
    case rejectedNonexistentLocalTime
}

/// 日期时间（yyyy-MM-dd HH:mm:ss）分段受控输入。游标状态机由
/// SegmentedFieldState 承载；本类型保留段值 clamp、夏令时诊断与显示格式化。
public struct ControlledHumanTimeInput: Equatable, Sendable {
    public private(set) var components: HumanDateTimeComponents?
    var state: SegmentedFieldState<HumanDateTimeSegment>
    /// 最近一次 commitActiveSegment 的失败原因；成功或无草稿时为 nil。
    /// UI 据此把“静默 nil”区分为可解释诊断（夏令时空洞）。
    public private(set) var lastCommitFailure: HumanDateTimeConversion.ParseFailure?

    private typealias FieldState = SegmentedFieldState<HumanDateTimeSegment>

    public init() {
        self.components = nil
        self.state = FieldState()
        self.lastCommitFailure = nil
    }

    public init(components: HumanDateTimeComponents) {
        self.components = Self.normalized(components)
        self.state = FieldState()
        self.lastCommitFailure = nil
    }

    public init(date: Date, timeZone: TimeZone) {
        self.init(components: HumanDateTimeConversion.components(from: date, timeZone: timeZone))
    }

    public var isEmpty: Bool {
        components == nil && state.draft.isEmpty
    }

    public var activeSegment: HumanDateTimeSegment {
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
            state.digitText(for: .day, value: components.day),
            " ",
            state.digitText(for: .hour, value: components.hour),
            ":",
            state.digitText(for: .minute, value: components.minute),
            ":",
            state.digitText(for: .second, value: components.second)
        ].joined()
    }

    public func displayRange(for segment: HumanDateTimeSegment) -> Range<Int>? {
        state.displayRange(
            for: segment,
            hasComponents: components != nil,
            value: value(for:),
            separatorLength: { separator(after: $0)?.count ?? 0 }
        )
    }

    public func segment(containingDisplayOffset offset: Int) -> HumanDateTimeSegment {
        state.segment(
            atDisplayOffset: offset,
            hasComponents: components != nil,
            value: value(for:),
            separatorLength: { separator(after: $0)?.count ?? 0 }
        )
    }

    public mutating func replace(with date: Date, timeZone: TimeZone) {
        components = HumanDateTimeConversion.components(from: date, timeZone: timeZone)
        state.reset()
        lastCommitFailure = nil
    }

    public mutating func clear() {
        components = nil
        state.reset()
        lastCommitFailure = nil
    }

    public mutating func select(_ segment: HumanDateTimeSegment) {
        state.select(segment)
        lastCommitFailure = nil
    }

    public mutating func movePrevious() {
        select(state.activeSegment.previous)
    }

    public mutating func moveNext() {
        select(state.activeSegment.next)
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
        lastCommitFailure = nil
        var failure: HumanDateTimeConversion.ParseFailure?
        let date = state.commitActiveSegment(
            components: &components,
            timeZone: timeZone,
            advance: advance,
            assignDraft: Self.assignDraft,
            normalized: Self.normalized,
            resolve: { resolved, zone in
                switch HumanDateTimeConversion.parseResult(from: resolved, timeZone: zone) {
                case .date(let date):
                    return date
                case .failure(let parseFailure):
                    failure = parseFailure
                    return nil
                }
            }
        )
        lastCommitFailure = failure
        return date
    }

    public mutating func paste(_ text: String, timeZone: TimeZone) -> ControlledHumanTimePasteResult {
        switch HumanDateTimeConversion.parseResult(fromText: text, timeZone: timeZone) {
        case .date(let date):
            replace(with: date, timeZone: timeZone)
            return .accepted(date)
        case .failure(.nonexistentLocalTime):
            return .rejectedNonexistentLocalTime
        case .failure:
            return .rejected
        }
    }

    public static func lastDay(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = FieldState.clamp(year, to: 1...9999)
        components.month = FieldState.clamp(month, to: 1...12)
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

    private static func assignDraft(
        _ segment: HumanDateTimeSegment,
        _ draft: String,
        to components: inout HumanDateTimeComponents
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
        case .hour:
            components.hour = FieldState.clamp(value, to: 0...23)
        case .minute:
            components.minute = FieldState.clamp(value, to: 0...59)
        case .second:
            components.second = FieldState.clamp(value, to: 0...59)
        }
    }

    private static func normalized(_ components: HumanDateTimeComponents) -> HumanDateTimeComponents {
        var normalized = components
        normalized.year = FieldState.clamp(normalized.year, to: 1...9999)
        normalized.month = FieldState.clamp(normalized.month, to: 1...12)
        normalized.day = FieldState.clamp(normalized.day, to: 1...lastDay(year: normalized.year, month: normalized.month))
        normalized.hour = FieldState.clamp(normalized.hour, to: 0...23)
        normalized.minute = FieldState.clamp(normalized.minute, to: 0...59)
        normalized.second = FieldState.clamp(normalized.second, to: 0...59)
        return normalized
    }
}
