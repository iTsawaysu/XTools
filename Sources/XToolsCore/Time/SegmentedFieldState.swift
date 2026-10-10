import Foundation

/// 分段受控输入（日期段 / 日期时间段）的段目录契约：段顺序（allCases）、
/// 相邻移动与段宽。段枚举定义与段值 clamp 规则由各输入自持。
/// allCases 必须非空，首尾元素即输入域的首尾段。
protocol SegmentedFieldSegment: CaseIterable, Equatable, Sendable
where AllCases == [Self] {
    /// 下一段；最后一段返回自身（键入不越出末段）。
    var next: Self { get }
    /// 上一段；第一段返回自身。
    var previous: Self { get }
    /// 该段允许的数字位数。
    var digitCount: Int { get }
}

/// 单个数字键入在共享状态机中的结果。
enum SegmentedFieldDigitOutcome: Equatable, Sendable {
    /// 键入的不是 ASCII 数字，状态不变。
    case ignored
    /// 数字已入草稿，当前段尚未满位，等待后续键入。
    case pending
    /// 草稿达到段宽上限，调用方应提交当前段并记录自动跳段。
    case filled
}

/// 分段受控输入共享的游标状态机：当前段、数字草稿，以及
/// “满位自动跳段后吞掉紧邻分隔符”标记。
/// 分量数据（components）、段值 clamp 与显示格式化由各输入自持，
/// 经钩子注入本状态机完成提交；日期与日期时间两条输入路径行为一致。
struct SegmentedFieldState<Segment: SegmentedFieldSegment>: Equatable, Sendable {
    private(set) var activeSegment: Segment
    private(set) var draft: String
    private var didAutoAdvanceAfterDigit: Bool

    init() {
        // 段目录非空是 SegmentedFieldSegment 的不变量。
        self.activeSegment = Segment.allCases.first!
        self.draft = ""
        self.didAutoAdvanceAfterDigit = false
    }

    var isFirstSegment: Bool {
        activeSegment == Segment.allCases.first
    }

    var isLastSegment: Bool {
        activeSegment == Segment.allCases.last
    }

    // MARK: 游标

    mutating func select(_ segment: Segment) {
        activeSegment = segment
        draft = ""
        didAutoAdvanceAfterDigit = false
    }

    mutating func movePrevious() {
        select(activeSegment.previous)
    }

    mutating func moveNext() {
        select(activeSegment.next)
    }

    /// 回到首段并清空草稿（replace/clear 共用的复位语义）。
    mutating func reset() {
        select(Segment.allCases.first!)
    }

    /// 提交后移动到下一段（inputSeparator 的尾步，不触碰草稿与标记）。
    mutating func advanceToNextSegment() {
        activeSegment = activeSegment.next
    }

    mutating func deleteBackward() {
        if draft.isEmpty {
            activeSegment = activeSegment.previous
        } else {
            draft.removeLast()
        }
        didAutoAdvanceAfterDigit = false
    }

    // MARK: 数字草稿

    /// 校验并追加单个 ASCII 数字；草稿达到段宽时先清空重开。
    mutating func appendDigit(_ character: Character) -> SegmentedFieldDigitOutcome {
        guard let digit = Self.asciiDigit(character) else { return .ignored }
        didAutoAdvanceAfterDigit = false

        if draft.count >= activeSegment.digitCount {
            draft = ""
        }

        draft.append(digit)

        return draft.count >= activeSegment.digitCount ? .filled : .pending
    }

    /// inputDigit 提交后记录“刚自动跳段”，供分隔符吞键判断使用。
    mutating func noteAutoAdvanceAfterDigit() {
        didAutoAdvanceAfterDigit = true
    }

    /// 分隔符键入的前半段：满位自动跳段后紧邻的分隔符被吞掉。
    /// 返回 false 表示该分隔符已被吞（调用方应直接返回 nil）。
    mutating func beginSeparatorInput() -> Bool {
        if didAutoAdvanceAfterDigit && draft.isEmpty {
            didAutoAdvanceAfterDigit = false
            return false
        }

        didAutoAdvanceAfterDigit = false
        return true
    }

    // MARK: 提交

    /// 提交当前段草稿：写回分量（assignDraft 钩子按段 clamp）→ 整体归一化
    /// （normalized 钩子）→ resolve 钩子把归一化分量转成日期。
    /// 无分量可编辑或草稿为空时不改分量，仅在 advance 时移动游标。
    @discardableResult
    mutating func commitActiveSegment<Components>(
        components: inout Components?,
        timeZone: TimeZone,
        advance: Bool = false,
        assignDraft: (Segment, String, inout Components) -> Void,
        normalized: (Components) -> Components,
        resolve: (Components, TimeZone) -> Date?
    ) -> Date? {
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

        assignDraft(activeSegment, draft, &nextComponents)
        nextComponents = normalized(nextComponents)
        components = nextComponents
        draft = ""
        if advance {
            activeSegment = activeSegment.next
        }
        didAutoAdvanceAfterDigit = false

        return resolve(nextComponents, timeZone)
    }

    // MARK: 显示

    /// 段的显示文本：活动段有草稿时显示草稿，否则按段宽补零。
    func digitText(for segment: Segment, value: Int) -> String {
        if segment == activeSegment && !draft.isEmpty {
            return draft
        }
        return String(format: "%0\(segment.digitCount)d", value)
    }

    /// 段在整体显示文本中的字符区间；无分量（空态）时为 nil。
    func displayRange(
        for segment: Segment,
        hasComponents: Bool,
        value: (Segment) -> Int,
        separatorLength: (Segment) -> Int
    ) -> Range<Int>? {
        guard hasComponents else { return nil }

        var cursor = 0
        for current in Segment.allCases {
            let text = digitText(for: current, value: value(current))
            let range = cursor..<(cursor + text.count)
            if current == segment {
                return range
            }
            cursor = range.upperBound
            cursor += separatorLength(current)
        }
        return nil
    }

    /// 显示偏移命中的段：偏移落在分隔符上时归给右侧段；
    /// 越界偏移归首段（空态）/ 末段。
    func segment(
        atDisplayOffset offset: Int,
        hasComponents: Bool,
        value: (Segment) -> Int,
        separatorLength: (Segment) -> Int
    ) -> Segment {
        guard hasComponents else { return Segment.allCases.first! }

        for segment in Segment.allCases {
            guard let range = displayRange(
                for: segment,
                hasComponents: hasComponents,
                value: value,
                separatorLength: separatorLength
            ) else { continue }
            if offset < range.lowerBound || offset < range.upperBound {
                return segment
            }
        }
        return Segment.allCases.last!
    }

    // MARK: 数值工具

    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func asciiDigit(_ character: Character) -> Character? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              (48...57).contains(scalar.value) else {
            return nil
        }
        return Character(scalar)
    }
}
