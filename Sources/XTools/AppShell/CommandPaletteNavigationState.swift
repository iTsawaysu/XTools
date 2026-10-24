import CoreGraphics
import Foundation

enum CommandPaletteRowProjection: Identifiable, Hashable {
    case sectionTitle(String)
    case tool(ToolNavigationCommandEntry)
    case command(CommandActionEntry)
    /// 直达模式的 segment 行（Batch D）：某工具在「别名+空格」直达列表里
    /// 的一个分段目标，回车经既有 deepLinkSegment 通道打开对应分段。
    case directSegment(tool: ToolNavigationCommandEntry, label: String, segment: String)
    /// Smart Detection 建议行（Batch D）：剪贴板内容类型判定命中的工具，
    /// 回车/点击由壳层读剪贴板预填（建议状态只存类型判定，不含内容）。
    case suggestion(ClipboardSuggestionModel.Suggestion)
    case empty

    var id: String {
        switch self {
        case .sectionTitle(let text):
            return "title.\(text)"
        case .tool(let entry):
            return entry.id
        case .command(let entry):
            return "command.\(entry.id.rawValue)"
        case .directSegment(let tool, _, let segment):
            return "direct.\(tool.toolID.rawValue).\(segment)"
        case .suggestion(let suggestion):
            return "suggestion.\(suggestion.kind.rawValue)"
        case .empty:
            return "empty"
        }
    }

    var toolID: ToolID? {
        switch self {
        case .tool(let entry):
            return entry.toolID
        case .directSegment(let tool, _, _):
            return tool.toolID
        case .suggestion(let suggestion):
            return suggestion.toolID
        case .sectionTitle, .command, .empty:
            return nil
        }
    }

    var commandID: CommandActionID? {
        switch self {
        case .command(let entry):
            return entry.id
        case .sectionTitle, .tool, .directSegment, .suggestion, .empty:
            return nil
        }
    }

    var isSelectable: Bool {
        toolID != nil || commandID != nil
    }
}

/// One titled group of palette rows; the sectioned builder renders each
/// group under a header carrying the group's row count.
struct CommandPaletteSection: Equatable {
    let title: String
    let rows: [CommandPaletteRowProjection]
}

/// One tool row's composed match-reason subtitle: the category title plus
/// the matched alias labels, with highlight ranges into `text` covering the
/// matched label fragments (painted in the same accent as title ranges).
struct CommandPaletteSubtitleAnnotation: Equatable {
    let text: String
    let highlightRanges: [Range<String.Index>]
}

/// The palette's one cached row list. Selectable navigation is precomputed,
/// and `titleHighlightRangesByID` carries the engine's title-match ranges
/// (keyed by row id) so row rendering never re-runs matching. Rows own no
/// other derived per-row state — keyword-tier alias hits likewise arrive
/// pre-composed as subtitle annotations (`subtitleAnnotationsByID`), and
/// their deep-link segments (`deepLinkSegmentsByID`).
struct CommandPaletteRowSnapshot: Equatable {
    let rows: [CommandPaletteRowProjection]
    private let selectableRows: [CommandPaletteRowProjection]
    private let selectableIndicesByID: [String: Int]
    let titleHighlightRangesByID: [String: [Range<String.Index>]]
    let subtitleAnnotationsByID: [String: CommandPaletteSubtitleAnnotation]
    let deepLinkSegmentsByID: [String: String]
    let sectionCountsByTitle: [String: Int]

    init(
        rows: [CommandPaletteRowProjection],
        titleHighlightRangesByID: [String: [Range<String.Index>]] = [:],
        subtitleAnnotationsByID: [String: CommandPaletteSubtitleAnnotation] = [:],
        deepLinkSegmentsByID: [String: String] = [:],
        sectionCountsByTitle: [String: Int] = [:]
    ) {
        self.rows = rows
        self.titleHighlightRangesByID = titleHighlightRangesByID
        self.subtitleAnnotationsByID = subtitleAnnotationsByID
        self.deepLinkSegmentsByID = deepLinkSegmentsByID
        self.sectionCountsByTitle = sectionCountsByTitle

        var selectableRows: [CommandPaletteRowProjection] = []
        var selectableIndicesByID: [String: Int] = [:]
        selectableRows.reserveCapacity(rows.count)
        selectableIndicesByID.reserveCapacity(rows.count)
        for row in rows where row.isSelectable {
            let index = selectableRows.count
            selectableRows.append(row)
            if selectableIndicesByID[row.id] == nil {
                selectableIndicesByID[row.id] = index
            }
        }
        self.selectableRows = selectableRows
        self.selectableIndicesByID = selectableIndicesByID
    }

    var selectableCount: Int {
        selectableRows.count
    }

    func selectableRow(at index: Int) -> CommandPaletteRowProjection? {
        guard selectableRows.indices.contains(index) else { return nil }
        return selectableRows[index]
    }

    func selectableIndex(of row: CommandPaletteRowProjection) -> Int? {
        guard row.isSelectable else { return nil }
        return selectableIndicesByID[row.id]
    }

    /// ⌘↑/⌘↓ 跨分组的跳转目标：`from`（可选中下标）所在 section 的相邻
    /// section 首个可选中行下标。direction 1 = 下一 section，−1 = 上一；
    /// 越界（已在首/末 section）或单 section 返回 nil（原地不动）。
    func sectionJumpTarget(from currentIndex: Int, direction: Int) -> Int? {
        guard direction != 0 else { return nil }
        let bounds = selectableSectionBounds()
        guard let home = bounds.firstIndex(where: { $0.contains(currentIndex) }) else {
            return nil
        }
        let neighbor = home + direction
        guard bounds.indices.contains(neighbor) else {
            return nil
        }
        return bounds[neighbor].lowerBound
    }

    /// 每个 section 在「可选中行下标空间」里的连续区间（按 rows 顺序）。
    /// ⌘↑/⌘↓ 跨分组跳转（阶段③ Batch D）按此推导相邻 section：落地页
    /// （最近/动作/分类）与过滤态（动作/工具）从同一 rows 流推导，各自
    /// 语义天然正确。`.sectionTitle` 行开新组；title 前出现的可选中行
    /// （防御性兜底，正常组装不产生）归入无标题首组。
    func selectableSectionBounds() -> [Range<Int>] {
        var bounds: [Range<Int>] = []
        var current: Range<Int>?
        var selectableIndex = 0
        for row in rows {
            if case .sectionTitle = row {
                if let open = current {
                    bounds.append(open)
                    current = nil
                }
                continue
            }
            guard row.isSelectable else { continue }
            current = (current?.lowerBound ?? selectableIndex)..<(selectableIndex + 1)
            selectableIndex += 1
        }
        if let open = current {
            bounds.append(open)
        }
        return bounds
    }

    func titleHighlightRanges(for row: CommandPaletteRowProjection) -> [Range<String.Index>] {
        titleHighlightRangesByID[row.id] ?? []
    }

    func subtitleAnnotation(for row: CommandPaletteRowProjection) -> CommandPaletteSubtitleAnnotation? {
        subtitleAnnotationsByID[row.id]
    }

    func deepLinkSegment(for row: CommandPaletteRowProjection) -> String? {
        deepLinkSegmentsByID[row.id]
    }
}

enum CommandPaletteRevealAnchor: Equatable {
    case keyboardEdge(delta: Int)
    case top
}

enum CommandPaletteActiveChangeSource: Equatable {
    case keyboard(delta: Int)
    case queryReset
    case openReset
    case pointerMove
    case directActivation

    var revealAnchor: CommandPaletteRevealAnchor? {
        switch self {
        case .keyboard(let delta):
            return .keyboardEdge(delta: delta)
        case .queryReset, .openReset:
            return .top
        case .pointerMove, .directActivation:
            return nil
        }
    }
}

enum CommandPaletteKeyboardMoveDecision: Equatable {
    case move(toSelectableIndex: Int)
    case alignToVisibleSelectableIndex(Int)
    case revealCurrent
    case none
}

struct CommandPaletteKeyboardMovePolicy: Equatable {
    let currentSelectableIndex: Int?
    let selectableCount: Int
    let delta: Int
    let visibleHandoffIndex: Int?
    let isCurrentActiveVisible: Bool
    let hasPendingKeyboardRevealForCurrentActive: Bool
    let allowsVisibleHandoff: Bool

    var decision: CommandPaletteKeyboardMoveDecision {
        guard delta != 0,
              let currentIndex = currentSelectableIndex,
              let normalizedCurrentIndex = CommandPaletteSearch.activationIndex(
                highlight: currentIndex,
                count: selectableCount
              )
        else {
            return .none
        }

        let nextIndex = CommandPaletteSearch.clampedHighlight(
            normalizedCurrentIndex,
            movingBy: delta,
            count: selectableCount
        )
        guard nextIndex != normalizedCurrentIndex else {
            return isCurrentActiveVisible ? .none : .revealCurrent
        }

        if isCurrentActiveVisible || hasPendingKeyboardRevealForCurrentActive {
            return .move(toSelectableIndex: nextIndex)
        }

        if allowsVisibleHandoff,
           let visibleHandoffIndex,
           let handoffIndex = CommandPaletteSearch.activationIndex(
            highlight: visibleHandoffIndex,
            count: selectableCount
           ) {
            return .alignToVisibleSelectableIndex(handoffIndex)
        }

        return .move(toSelectableIndex: nextIndex)
    }
}

struct CommandPaletteNavigationState: Equatable {
    private(set) var activeIndex = 0

    /// The primary builder: composes titled sections into one flat row list
    /// with precomputed selection indices and per-section counts. Empty
    /// sections are skipped; a fully empty composition still yields the
    /// no-results row.
    static func snapshot(
        sections: [CommandPaletteSection],
        titleHighlightRangesByID: [String: [Range<String.Index>]] = [:],
        subtitleAnnotationsByID: [String: CommandPaletteSubtitleAnnotation] = [:],
        deepLinkSegmentsByID: [String: String] = [:]
    ) -> CommandPaletteRowSnapshot {
        var rows: [CommandPaletteRowProjection] = []
        var sectionCountsByTitle: [String: Int] = [:]
        rows.reserveCapacity(sections.reduce(0) { $0 + $1.rows.count + 1 })

        for section in sections where !section.rows.isEmpty {
            rows.append(.sectionTitle(section.title))
            rows.append(contentsOf: section.rows)
            if sectionCountsByTitle[section.title] == nil {
                sectionCountsByTitle[section.title] = section.rows.count
            }
        }

        return CommandPaletteRowSnapshot(
            rows: rows.isEmpty ? [.empty] : rows,
            titleHighlightRangesByID: titleHighlightRangesByID,
            subtitleAnnotationsByID: subtitleAnnotationsByID,
            deepLinkSegmentsByID: deepLinkSegmentsByID,
            sectionCountsByTitle: sectionCountsByTitle
        )
    }

    /// Ranked-results convenience: commands under one shared 动作 section,
    /// tools under one shared 工具 section.
    static func snapshot(
        for entries: [ToolNavigationCommandEntry],
        actions: [CommandActionEntry] = [],
        titleHighlightRangesByID: [String: [Range<String.Index>]] = [:],
        subtitleAnnotationsByID: [String: CommandPaletteSubtitleAnnotation] = [:],
        deepLinkSegmentsByID: [String: String] = [:]
    ) -> CommandPaletteRowSnapshot {
        snapshot(
            sections: [
                CommandPaletteSection(
                    title: "动作",
                    rows: actions.map(CommandPaletteRowProjection.command)
                ),
                CommandPaletteSection(
                    title: "工具",
                    rows: entries.map(CommandPaletteRowProjection.tool)
                ),
            ],
            titleHighlightRangesByID: titleHighlightRangesByID,
            subtitleAnnotationsByID: subtitleAnnotationsByID,
            deepLinkSegmentsByID: deepLinkSegmentsByID
        )
    }

    func activeRowID(in snapshot: CommandPaletteRowSnapshot) -> String? {
        activeRow(in: snapshot)?.id
    }

    func activeSelectableIndex(in snapshot: CommandPaletteRowSnapshot) -> Int? {
        CommandPaletteSearch.activationIndex(
            highlight: activeIndex,
            count: snapshot.selectableCount
        )
    }

    func activeRow(in snapshot: CommandPaletteRowSnapshot) -> CommandPaletteRowProjection? {
        guard let index = activeSelectableIndex(in: snapshot) else {
            return nil
        }
        return snapshot.selectableRow(at: index)
    }

    func activeToolID(in snapshot: CommandPaletteRowSnapshot) -> ToolID? {
        activeRow(in: snapshot).flatMap(toolID(for:))
    }

    func toolID(for row: CommandPaletteRowProjection) -> ToolID? {
        row.toolID
    }

    func canMoveActive(by delta: Int, in snapshot: CommandPaletteRowSnapshot) -> Bool {
        guard let currentIndex = activeSelectableIndex(in: snapshot) else {
            return false
        }

        return CommandPaletteSearch.clampedHighlight(
            currentIndex,
            movingBy: delta,
            count: snapshot.selectableCount
        ) != currentIndex
    }

    func keyboardMoveDecision(
        by delta: Int,
        in snapshot: CommandPaletteRowSnapshot,
        visibleHandoffIndex: Int?,
        isCurrentActiveVisible: Bool,
        hasPendingKeyboardRevealForCurrentActive: Bool,
        allowsVisibleHandoff: Bool
    ) -> CommandPaletteKeyboardMoveDecision {
        CommandPaletteKeyboardMovePolicy(
            currentSelectableIndex: activeSelectableIndex(in: snapshot),
            selectableCount: snapshot.selectableCount,
            delta: delta,
            visibleHandoffIndex: visibleHandoffIndex,
            isCurrentActiveVisible: isCurrentActiveVisible,
            hasPendingKeyboardRevealForCurrentActive: hasPendingKeyboardRevealForCurrentActive,
            allowsVisibleHandoff: allowsVisibleHandoff
        ).decision
    }

    mutating func moveActive(by delta: Int, in snapshot: CommandPaletteRowSnapshot) {
        activeIndex = CommandPaletteSearch.clampedHighlight(
            activeIndex,
            movingBy: delta,
            count: snapshot.selectableCount
        )
    }

    /// ⌘↑/⌘↓ 跨分组跳转（阶段③ Batch D）：跳到相邻 section 的首个可选
    /// 中行。direction 1 = 下一 section，−1 = 上一 section；已在边界
    /// section、无活跃行或只有一个 section 时不动（返回 false）。跳转走
    /// 与箭头同一 active-row API，不旁路任何选择状态。
    @discardableResult
    mutating func jumpActiveAcrossSections(
        by direction: Int,
        in snapshot: CommandPaletteRowSnapshot
    ) -> Bool {
        guard direction != 0,
              let currentIndex = activeSelectableIndex(in: snapshot),
              let targetIndex = snapshot.sectionJumpTarget(from: currentIndex, direction: direction)
        else {
            return false
        }
        guard targetIndex != currentIndex else { return false }
        setActiveSelectableIndex(targetIndex, in: snapshot)
        return true
    }

    mutating func resetActiveRow() {
        activeIndex = 0
    }

    mutating func setActiveSelectableIndex(_ index: Int, in snapshot: CommandPaletteRowSnapshot) {
        guard let clampedIndex = CommandPaletteSearch.activationIndex(
            highlight: index,
            count: snapshot.selectableCount
        ) else {
            return
        }
        activeIndex = clampedIndex
    }

    mutating func setActiveRow(_ row: CommandPaletteRowProjection, in snapshot: CommandPaletteRowSnapshot) {
        guard let index = snapshot.selectableIndex(of: row) else { return }
        activeIndex = index
    }

    func selectableIndex(of row: CommandPaletteRowProjection, in snapshot: CommandPaletteRowSnapshot) -> Int? {
        snapshot.selectableIndex(of: row)
    }
}

struct CommandPalettePointerMovementState: Equatable {
    private(set) var lastLocationInWindow: CGPoint?

    mutating func reset(to location: CGPoint?) {
        lastLocationInWindow = location
    }

    mutating func acceptsMouseMoved(at location: CGPoint) -> Bool {
        defer {
            lastLocationInWindow = location
        }

        guard let lastLocationInWindow else {
            return false
        }
        return lastLocationInWindow != location
    }
}

@MainActor
final class CommandPalettePointerMovementTracker {
    private var movement = CommandPalettePointerMovementState()

    var isSeeded: Bool {
        movement.lastLocationInWindow != nil
    }

    func reset(to location: CGPoint?) {
        movement.reset(to: location)
    }

    func clear() {
        movement.reset(to: nil)
    }

    func acceptsMouseMoved(at location: CGPoint) -> Bool {
        movement.acceptsMouseMoved(at: location)
    }
}

enum CommandPaletteSearch {
    static func clampedHighlight(_ index: Int, movingBy delta: Int, count: Int) -> Int {
        guard count > 0 else { return index }
        return clamped(index + delta, within: count)
    }

    static func activationIndex(highlight index: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return clamped(index, within: count)
    }

    private static func clamped(_ value: Int, within count: Int) -> Int {
        min(max(value, 0), count - 1)
    }
}
