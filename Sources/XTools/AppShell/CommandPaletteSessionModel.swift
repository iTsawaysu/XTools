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
///
/// The landing sections are cached under `(actions, recentToolIDs)` so a
/// warm ⌘K reopen reuses them without a registry traversal (see
/// `makeLandingSnapshot`).
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

    /// Landing-page cache. The cache KEY is `(actions, recentToolIDs)` and
    /// the cached CONTENT is the composed `[CommandPaletteSection]`
    /// (最近使用 + 动作 + categories).
    ///
    /// A cache hit therefore requires only that the action list and the
    /// frecency recents are unchanged; the final snapshot is assembled from
    /// value-type sections — cheap, with no registry traversal. A real
    /// rebuild inside the visible open arc quantizes the palette's fade-in
    /// into a brightness step, which is what this cache removes.
    private struct LandingCacheKey: Equatable {
        let actions: [CommandActionEntry]
        let recentToolIDs: [ToolID]
    }

    private struct LandingCacheEntry {
        let key: LandingCacheKey
        let sections: [CommandPaletteSection]
    }

    private var landingCache: LandingCacheEntry?

    #if DEBUG
    /// Blank-query snapshot requests served from the landing cache without
    /// recomposing sections (test hook).
    private(set) var landingCacheHitCount = 0
    #endif

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
        // One `now` for the whole cold composition: the sections and their
        // cache key must read the same recents snapshot, or a snapshot taken
        // across an instant boundary could cache sections that disagree with
        // their own key.
        let now = Date()
        let actionRecords = CommandActionEntry.searchRecords(for: actions)
        // Cold landing composition: no cache exists before phase-one init
        // completes, so the sections are built here and seed the cache.
        let sections = Self.landingSections(
            registry: registry,
            actions: actions,
            usage: usage,
            now: now
        )
        self.landingCache = LandingCacheEntry(
            key: LandingCacheKey(
                actions: actions,
                recentToolIDs: usage.recentToolIDs(
                    limit: LandingMetrics.recentsLimit,
                    now: now
                )
            ),
            sections: sections
        )
        CommandPaletteTrace.count(.rowSnapshot)
        let snapshot = CommandPaletteNavigationState.snapshot(sections: sections)
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
        let snapshot = makeSnapshot(
            query: "",
            actions: actions,
            actionRecords: actionRecords
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
        let snapshot = makeSnapshot(
            query: newQuery,
            actions: state.actions,
            actionRecords: state.actionRecords
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
        let snapshot = makeSnapshot(
            query: state.query,
            actions: newActions,
            actionRecords: actionRecords
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

    /// The landing sections: usage-ranked recents first, then the shell
    /// commands, then every category with its tools in registry order.
    private static func landingSections(
        registry: ToolRegistry,
        actions: [CommandActionEntry],
        usage: any PaletteUsageScoring,
        now: Date
    ) -> [CommandPaletteSection] {
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
        // anchor hover/reveal at the wrong instance. Empty
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

        return sections
    }

    /// Builds the row snapshot for `query`. A blank query composes the
    /// landing page through the `(actions, recentToolIDs)` cache: a hit
    /// reuses the cached sections; an actions or recents change recomposes
    /// and refreshes the cache.
    private func makeSnapshot(
        query: String,
        actions: [CommandActionEntry],
        actionRecords: [ToolSearchRecord]
    ) -> CommandPaletteRowSnapshot {
        // A blank query composes the landing page instead of a flat list.
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return makeLandingSnapshot(actions: actions)
        }

        CommandPaletteTrace.count(.rowSnapshot)
        let projection = Self.applyFrecencyBoost(
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

        var subtitleAnnotationsByID: [String: CommandPaletteSubtitleAnnotation] = [:]
        var deepLinkSegmentsByID: [String: String] = [:]
        subtitleAnnotationsByID.reserveCapacity(projection.entries.count)
        for (entry, match) in zip(projection.entries, projection.matches) {
            guard let match else { continue }
            if !match.aliasMatches.isEmpty {
                subtitleAnnotationsByID[entry.id] = Self.composedSubtitle(
                    categoryTitle: entry.categoryTitle,
                    aliasMatches: match.aliasMatches
                )
            }
            if let segment = match.deepLinkSegment {
                deepLinkSegmentsByID[entry.id] = segment
            }
        }

        return CommandPaletteNavigationState.snapshot(
            for: projection.entries,
            actions: matchedActions.map(\.0),
            titleHighlightRangesByID: titleHighlightRangesByID,
            subtitleAnnotationsByID: subtitleAnnotationsByID,
            deepLinkSegmentsByID: deepLinkSegmentsByID
        )
    }

    /// Composes a keyword-tier match-reason subtitle: the category title
    /// plus each matched alias label, with label-local highlight ranges
    /// offset into the composed string so rendering paints the matched
    /// fragments in the shared accent.
    private static func composedSubtitle(
        categoryTitle: String?,
        aliasMatches: [ToolSearchEngine.AliasMatch]
    ) -> CommandPaletteSubtitleAnnotation {
        // Segments assembled left to right; ranges recorded as character
        // offsets so each label's ranges survive the offset shift.
        var text = ""
        var ranges: [Range<Int>] = []

        func appendLabel(_ aliasMatch: ToolSearchEngine.AliasMatch) {
            let base = text.count
            text += aliasMatch.label
            for range in aliasMatch.labelRanges {
                let lower = base + aliasMatch.label.distance(
                    from: aliasMatch.label.startIndex,
                    to: range.lowerBound
                )
                let upper = base + aliasMatch.label.distance(
                    from: aliasMatch.label.startIndex,
                    to: range.upperBound
                )
                ranges.append(lower..<upper)
            }
        }

        if let categoryTitle, !categoryTitle.isEmpty {
            text += categoryTitle + " · "
        }
        appendLabel(aliasMatches[0])
        for aliasMatch in aliasMatches.dropFirst() {
            text += " · "
            appendLabel(aliasMatch)
        }

        let sortedRanges = ranges.sorted { $0.lowerBound < $1.lowerBound }
        return CommandPaletteSubtitleAnnotation(
            text: text,
            highlightRanges: sortedRanges.map { range in
                text.index(text.startIndex, offsetBy: range.lowerBound)
                    ..< text.index(text.startIndex, offsetBy: range.upperBound)
            }
        )
    }

    /// The blank-query landing snapshot for `actions`: sections come from the
    /// `(actions, recentToolIDs)` cache and are assembled into the final
    /// snapshot directly.
    private func makeLandingSnapshot(actions: [CommandActionEntry]) -> CommandPaletteRowSnapshot {
        let key = LandingCacheKey(
            actions: actions,
            recentToolIDs: usage.recentToolIDs(
                limit: LandingMetrics.recentsLimit,
                now: Date()
            )
        )
        let sections: [CommandPaletteSection]
        if let landingCache, landingCache.key == key {
            #if DEBUG
            landingCacheHitCount += 1
            #endif
            sections = landingCache.sections
        } else {
            CommandPaletteTrace.count(.rowSnapshot)
            sections = Self.landingSections(
                registry: registry,
                actions: actions,
                usage: usage,
                now: Date()
            )
            landingCache = LandingCacheEntry(key: key, sections: sections)
        }
        return CommandPaletteNavigationState.snapshot(sections: sections)
    }
}
