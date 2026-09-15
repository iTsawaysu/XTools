import SwiftUI

/// One mounted palette session owns query, active-row state, and the current
/// row snapshot. Native editing updates this reference synchronously, so Return
/// immediately after an edit cannot activate a snapshot for the previous query.
@MainActor
final class CommandPaletteSessionModel: ObservableObject {
    private struct State {
        var session: Int
        var query: String
        var navigationState: CommandPaletteNavigationState
        var snapshot: CommandPaletteRowSnapshot
        var actions: [CommandActionEntry]
    }

    @Published private var state: State

    private let registry: ToolRegistry

    var session: Int { state.session }
    var query: String { state.query }
    var snapshot: CommandPaletteRowSnapshot { state.snapshot }
    var navigationState: CommandPaletteNavigationState {
        get { state.navigationState }
        set {
            var next = state
            next.navigationState = newValue
            state = next
        }
    }

    init(registry: ToolRegistry, actions: [CommandActionEntry], session: Int = 0) {
        self.registry = registry
        let snapshot = Self.makeSnapshot(
            registry: registry,
            actions: actions,
            query: ""
        )
        self.state = State(
            session: session,
            query: "",
            navigationState: CommandPaletteNavigationState(),
            snapshot: snapshot,
            actions: actions
        )
        CommandPaletteTrace.count(.commandProjection)
    }

    func beginSession(_ session: Int, actions: [CommandActionEntry]) {
        guard state.session != session else {
            replaceActions(actions)
            return
        }
        let snapshot = Self.makeSnapshot(
            registry: registry,
            actions: actions,
            query: ""
        )
        CommandPaletteTrace.count(.commandProjection, session: session)
        state = State(
            session: session,
            query: "",
            navigationState: CommandPaletteNavigationState(),
            snapshot: snapshot,
            actions: actions
        )
    }

    @discardableResult
    func setQuery(_ newQuery: String) -> Bool {
        guard query != newQuery else { return false }
        let snapshot = Self.makeSnapshot(
            registry: registry,
            actions: state.actions,
            query: newQuery
        )
        CommandPaletteTrace.count(.commandProjection)
        var next = state
        next.snapshot = snapshot
        next.navigationState.resetActiveRow()
        next.query = newQuery
        state = next
        return true
    }

    func replaceActions(_ newActions: [CommandActionEntry]) {
        guard state.actions != newActions else { return }
        let snapshot = Self.makeSnapshot(
            registry: registry,
            actions: newActions,
            query: state.query
        )
        CommandPaletteTrace.count(.commandProjection)
        var next = state
        next.actions = newActions
        next.snapshot = snapshot
        next.navigationState.resetActiveRow()
        state = next
    }

    private static func makeSnapshot(
        registry: ToolRegistry,
        actions: [CommandActionEntry],
        query: String
    ) -> CommandPaletteRowSnapshot {
        CommandPaletteTrace.count(.rowSnapshot)
        let projection = ToolNavigationCommandProjection(
            registry: registry,
            query: query
        )
        return CommandPaletteNavigationState.snapshot(
            for: projection.entries,
            actions: actions.filter { $0.matches(query: query) }
        )
    }
}
