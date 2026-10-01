import CoreGraphics
import Foundation

enum CommandPaletteRowProjection: Identifiable, Hashable {
    case sectionTitle(String)
    case tool(ToolNavigationCommandEntry)
    case command(CommandActionEntry)
    case empty

    var id: String {
        switch self {
        case .sectionTitle(let text):
            return "title.\(text)"
        case .tool(let entry):
            return entry.id
        case .command(let entry):
            return "command.\(entry.id.rawValue)"
        case .empty:
            return "empty"
        }
    }

    var toolID: ToolID? {
        switch self {
        case .tool(let entry):
            return entry.toolID
        case .sectionTitle, .command, .empty:
            return nil
        }
    }

    var commandID: CommandActionID? {
        switch self {
        case .command(let entry):
            return entry.id
        case .sectionTitle, .tool, .empty:
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

/// The palette's one cached row list. Selectable navigation is precomputed,
/// and `titleHighlightRangesByID` carries the engine's title-match ranges
/// (keyed by row id) so row rendering never re-runs matching. Rows own no
/// other derived per-row state.
struct CommandPaletteRowSnapshot: Equatable {
    let rows: [CommandPaletteRowProjection]
    private let selectableRows: [CommandPaletteRowProjection]
    private let selectableIndicesByID: [String: Int]
    let titleHighlightRangesByID: [String: [Range<String.Index>]]
    let sectionCountsByTitle: [String: Int]

    init(
        rows: [CommandPaletteRowProjection],
        titleHighlightRangesByID: [String: [Range<String.Index>]] = [:],
        sectionCountsByTitle: [String: Int] = [:]
    ) {
        self.rows = rows
        self.titleHighlightRangesByID = titleHighlightRangesByID
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

    func titleHighlightRanges(for row: CommandPaletteRowProjection) -> [Range<String.Index>] {
        titleHighlightRangesByID[row.id] ?? []
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
        titleHighlightRangesByID: [String: [Range<String.Index>]] = [:]
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
            sectionCountsByTitle: sectionCountsByTitle
        )
    }

    /// Ranked-results convenience: commands under one shared 动作 section,
    /// tools under one shared 工具 section.
    static func snapshot(
        for entries: [ToolNavigationCommandEntry],
        actions: [CommandActionEntry] = [],
        titleHighlightRangesByID: [String: [Range<String.Index>]] = [:]
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
            titleHighlightRangesByID: titleHighlightRangesByID
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
