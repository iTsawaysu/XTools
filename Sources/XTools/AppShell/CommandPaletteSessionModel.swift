import SwiftUI

/// One mounted palette session owns query, active-row state, and the current
/// row snapshot. Native editing updates this reference synchronously, so Return
/// immediately after an edit cannot activate a snapshot for the previous query.
///
/// Command engine records (`actionRecords`) are rebuilt only when the action
/// list changes, not per keystroke — tool records live prebuilt inside the
/// registry, so every query replacement runs comparisons only.
///
/// The blank-query landing page composes sections instead of one flat tool
/// list: 最近使用 (frecency, capped) → 动作 → one section per tool category,
/// mirroring the sidebar's mental model. A typed query keeps the ranked
/// 动作 + 工具 structure with frecency refinement inside tiers.
@MainActor
final class CommandPaletteSessionModel: ObservableObject {
    private enum LandingMetrics {
        static let recentsLimit = 5
    }

    private enum FrecencyBoost {
        /// One launch today adds one rank point; the cap keeps heavy usage
        /// worth roughly two matched characters, so frecency refines
        /// within-tier order instead of overriding relevance.
        static let perScorePoint = 1.0
        static let cap = 40
    }

    private struct State {
        var session: Int
        var query: String
        var navigationState: CommandPaletteNavigationState
        var snapshot: CommandPaletteRowSnapshot
        var actions: [CommandActionEntry]
        var actionRecords: [ToolSearchRecord]
    }

    @Published private var state: State

    private let registry: ToolRegistry
    private let usage: any PaletteUsageScoring

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

    init(
        registry: ToolRegistry,
        actions: [CommandActionEntry],
        session: Int = 0,
        usage: any PaletteUsageScoring = NoPaletteUsage()
    ) {
        self.registry = registry
        self.usage = usage
        let actionRecords = CommandActionEntry.searchRecords(for: actions)
        let snapshot = Self.makeSnapshot(
            registry: registry,
            actions: actions,
            actionRecords: actionRecords,
            usage: usage,
            query: ""
        )
        self.state = State(
            session: session,
            query: "",
            navigationState: CommandPaletteNavigationState(),
            snapshot: snapshot,
            actions: actions,
            actionRecords: actionRecords
        )
        CommandPaletteTrace.count(.commandProjection)
    }

    func beginSession(_ session: Int, actions: [CommandActionEntry]) {
        guard state.session != session else {
            replaceActions(actions)
            return
        }
        let actionRecords = CommandActionEntry.searchRecords(for: actions)
        let snapshot = Self.makeSnapshot(
            registry: registry,
            actions: actions,
            actionRecords: actionRecords,
            usage: usage,
            query: ""
        )
        CommandPaletteTrace.count(.commandProjection, session: session)
        state = State(
            session: session,
            query: "",
            navigationState: CommandPaletteNavigationState(),
            snapshot: snapshot,
            actions: actions,
            actionRecords: actionRecords
        )
    }

    @discardableResult
    func setQuery(_ newQuery: String) -> Bool {
        guard query != newQuery else { return false }
        let snapshot = Self.makeSnapshot(
            registry: registry,
            actions: state.actions,
            actionRecords: state.actionRecords,
            usage: usage,
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
        let actionRecords = CommandActionEntry.searchRecords(for: newActions)
        let snapshot = Self.makeSnapshot(
            registry: registry,
            actions: newActions,
            actionRecords: actionRecords,
            usage: usage,
            query: state.query
        )
        CommandPaletteTrace.count(.commandProjection)
        var next = state
        next.actions = newActions
        next.actionRecords = actionRecords
        next.snapshot = snapshot
        next.navigationState.resetActiveRow()
        state = next
    }

    // MARK: - Snapshot composition

    /// Frecency refinement inside an engine tier (never across tiers): with
    /// no usage data this returns the projection's order unchanged.
    private static func applyFrecencyBoost(
        _ projection: ToolNavigationCommandProjection,
        usage: any PaletteUsageScoring,
        now: Date
    ) -> ToolNavigationCommandProjection {
        struct Boosted {
            let entry: ToolNavigationCommandEntry
            let match: ToolSearchEngine.Match?
            let tier: ToolSearchEngine.Tier
            let boostedScore: Int
            let position: Int
        }

        let boosted = zip(projection.entries, projection.matches).enumerated()
            .map { position, pair -> Boosted in
                let (entry, match) = pair
                guard let match else {
                    return Boosted(
                        entry: entry,
                        match: nil,
                        tier: .titlePrefix,
                        boostedScore: 0,
                        position: position
                    )
                }
                let boost = min(
                    Int(usage.frecencyScore(for: entry.toolID, now: now) * FrecencyBoost.perScorePoint),
                    FrecencyBoost.cap
                )
                return Boosted(
                    entry: entry,
                    match: match,
                    tier: match.tier,
                    boostedScore: match.score + boost,
                    position: position
                )
            }
            .sorted { left, right in
                if left.tier != right.tier {
                    return left.tier < right.tier
                }
                if left.boostedScore != right.boostedScore {
                    return left.boostedScore > right.boostedScore
                }
                return left.position < right.position
            }

        return ToolNavigationCommandProjection(
            entries: boosted.map(\.entry),
            matches: boosted.map(\.match)
        )
    }

    /// The blank-query landing page: usage-ranked recents first, then shell
    /// commands, then every category with its tools in registry order.
    private static func landingSnapshot(
        registry: ToolRegistry,
        actions: [CommandActionEntry],
        usage: any PaletteUsageScoring,
        now: Date
    ) -> CommandPaletteRowSnapshot {
        var sections: [CommandPaletteSection] = []

        let recentTools = usage.recentToolIDs(limit: LandingMetrics.recentsLimit, now: now)
            .compactMap { registry.tool(for: $0) }
        if !recentTools.isEmpty {
            sections.append(CommandPaletteSection(
                title: "最近使用",
                rows: recentTools.map { tool in
                    CommandPaletteRowProjection.tool(
                        ToolNavigationCommandEntry(
                            tool: tool,
                            categoryTitle: registry.categoryTitle(for: tool.categoryID)
                        )
                    )
                }
            ))
        }

        if !actions.isEmpty {
            sections.append(CommandPaletteSection(
                title: "动作",
                rows: actions.map(CommandPaletteRowProjection.command)
            ))
        }

        // Tools surfaced by the recents section must not repeat in their
        // category section: duplicate row ids would break ForEach identity and
        // anchor hover/reveal/icon-flight at the wrong instance. Empty
        // categories are dropped by the snapshot builder.
        let recentToolIDs = Set(recentTools.map(\.id))
        for group in registry.categoryGroups() {
            sections.append(CommandPaletteSection(
                title: group.category.title,
                rows: group.tools
                    .filter { !recentToolIDs.contains($0.id) }
                    .map { tool in
                        CommandPaletteRowProjection.tool(
                            ToolNavigationCommandEntry(
                                tool: tool,
                                categoryTitle: group.category.title
                            )
                        )
                    }
            ))
        }

        return CommandPaletteNavigationState.snapshot(sections: sections)
    }

    private static func makeSnapshot(
        registry: ToolRegistry,
        actions: [CommandActionEntry],
        actionRecords: [ToolSearchRecord],
        usage: any PaletteUsageScoring,
        query: String
    ) -> CommandPaletteRowSnapshot {
        CommandPaletteTrace.count(.rowSnapshot)

        // A blank query composes the landing page instead of a flat list.
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return landingSnapshot(
                registry: registry,
                actions: actions,
                usage: usage,
                now: Date()
            )
        }

        let projection = applyFrecencyBoost(
            ToolNavigationCommandProjection(registry: registry, query: query),
            usage: usage,
            now: Date()
        )

        let matchedActions = zip(actions, actionRecords).compactMap { action, record in
            ToolSearchEngine.match(record: record, query: query)
                .map { (action, $0) }
        }

        var titleHighlightRangesByID: [String: [Range<String.Index>]] = [:]
        titleHighlightRangesByID.reserveCapacity(
            projection.entries.count + matchedActions.count
        )
        for (entry, match) in zip(projection.entries, projection.matches) {
            guard let match, !match.titleRanges.isEmpty else { continue }
            titleHighlightRangesByID[entry.id] = match.titleRanges
        }
        for (action, match) in matchedActions where !match.titleRanges.isEmpty {
            titleHighlightRangesByID["command.\(action.id.rawValue)"] = match.titleRanges
        }

        return CommandPaletteNavigationState.snapshot(
            for: projection.entries,
            actions: matchedActions.map(\.0),
            titleHighlightRangesByID: titleHighlightRangesByID
        )
    }
}
