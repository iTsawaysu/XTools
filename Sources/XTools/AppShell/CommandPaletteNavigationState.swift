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

struct CommandPaletteRowSnapshot: Equatable {
    let rows: [CommandPaletteRowProjection]
    private let selectableRows: [CommandPaletteRowProjection]
    private let selectableIndicesByID: [String: Int]

    init(rows: [CommandPaletteRowProjection]) {
        self.rows = rows

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

    static func rows(
        for entries: [ToolNavigationCommandEntry],
        actions: [CommandActionEntry] = []
    ) -> [CommandPaletteRowProjection] {
        snapshot(for: entries, actions: actions).rows
    }

    static func snapshot(
        for entries: [ToolNavigationCommandEntry],
        actions: [CommandActionEntry] = []
    ) -> CommandPaletteRowSnapshot {
        var rows: [CommandPaletteRowProjection] = []
        if !actions.isEmpty {
            rows.append(.sectionTitle("动作"))
            rows.append(contentsOf: actions.map(CommandPaletteRowProjection.command))
        }
        if !entries.isEmpty {
            rows.append(.sectionTitle("工具"))
            rows.append(contentsOf: entries.map(CommandPaletteRowProjection.tool))
        }
        return CommandPaletteRowSnapshot(rows: rows.isEmpty ? [.empty] : rows)
    }

    func activeRowID(in rows: [CommandPaletteRowProjection]) -> String? {
        activeRowID(in: CommandPaletteRowSnapshot(rows: rows))
    }

    func activeRowID(in snapshot: CommandPaletteRowSnapshot) -> String? {
        activeRow(in: snapshot)?.id
    }

    func activeSelectableIndex(in rows: [CommandPaletteRowProjection]) -> Int? {
        activeSelectableIndex(in: CommandPaletteRowSnapshot(rows: rows))
    }

    func activeSelectableIndex(in snapshot: CommandPaletteRowSnapshot) -> Int? {
        CommandPaletteSearch.activationIndex(
            highlight: activeIndex,
            count: snapshot.selectableCount
        )
    }

    func activeRow(in rows: [CommandPaletteRowProjection]) -> CommandPaletteRowProjection? {
        activeRow(in: CommandPaletteRowSnapshot(rows: rows))
    }

    func activeRow(in snapshot: CommandPaletteRowSnapshot) -> CommandPaletteRowProjection? {
        guard let index = activeSelectableIndex(in: snapshot) else {
            return nil
        }
        return snapshot.selectableRow(at: index)
    }

    func activeToolID(in rows: [CommandPaletteRowProjection]) -> ToolID? {
        activeRow(in: rows).flatMap(toolID(for:))
    }

    func toolID(for row: CommandPaletteRowProjection) -> ToolID? {
        row.toolID
    }

    mutating func moveActive(by delta: Int, in rows: [CommandPaletteRowProjection]) {
        let snapshot = CommandPaletteRowSnapshot(rows: rows)
        activeIndex = CommandPaletteSearch.clampedHighlight(
            activeIndex,
            movingBy: delta,
            count: snapshot.selectableCount
        )
    }

    func canMoveActive(by delta: Int, in rows: [CommandPaletteRowProjection]) -> Bool {
        let snapshot = CommandPaletteRowSnapshot(rows: rows)
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
        in rows: [CommandPaletteRowProjection],
        visibleHandoffIndex: Int?,
        isCurrentActiveVisible: Bool,
        hasPendingKeyboardRevealForCurrentActive: Bool,
        allowsVisibleHandoff: Bool
    ) -> CommandPaletteKeyboardMoveDecision {
        keyboardMoveDecision(
            by: delta,
            in: CommandPaletteRowSnapshot(rows: rows),
            visibleHandoffIndex: visibleHandoffIndex,
            isCurrentActiveVisible: isCurrentActiveVisible,
            hasPendingKeyboardRevealForCurrentActive: hasPendingKeyboardRevealForCurrentActive,
            allowsVisibleHandoff: allowsVisibleHandoff
        )
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

    mutating func resetActiveRow() {
        activeIndex = 0
    }

    mutating func setActiveSelectableIndex(_ index: Int, in rows: [CommandPaletteRowProjection]) {
        setActiveSelectableIndex(index, in: CommandPaletteRowSnapshot(rows: rows))
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

    mutating func setActiveRow(_ row: CommandPaletteRowProjection, in rows: [CommandPaletteRowProjection]) {
        setActiveRow(row, in: CommandPaletteRowSnapshot(rows: rows))
    }

    mutating func setActiveRow(_ row: CommandPaletteRowProjection, in snapshot: CommandPaletteRowSnapshot) {
        guard let index = snapshot.selectableIndex(of: row) else { return }
        activeIndex = index
    }

    func selectableIndex(of row: CommandPaletteRowProjection, in rows: [CommandPaletteRowProjection]) -> Int? {
        CommandPaletteRowSnapshot(rows: rows).selectableIndex(of: row)
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
