import Combine
import Foundation

enum DashboardCardKind: String, Codable, CaseIterable, Identifiable {
    case continueWork
    case activityOverview
    case sevenDayTrend
    case favorites
    case recent
    case quickActions
    case categoryHighlights

    var id: String { rawValue }
    var isActivity: Bool { self == .activityOverview || self == .sevenDayTrend || self == .categoryHighlights }
}

enum DashboardCardSpan: String, Codable, CaseIterable {
    case small, medium, large
}

struct DashboardCardLayout: Codable, Equatable, Identifiable {
    let id: String
    var kind: DashboardCardKind
    var isVisible: Bool
    var span: DashboardCardSpan
    var sortOrder: Int

    init(kind: DashboardCardKind, isVisible: Bool = true, span: DashboardCardSpan, sortOrder: Int) {
        self.id = kind.rawValue
        self.kind = kind
        self.isVisible = isVisible
        self.span = span
        self.sortOrder = sortOrder
    }
}

struct DashboardActivityEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let toolID: ToolID
    let timestamp: Date
    var count: Int

    init(id: UUID = UUID(), toolID: ToolID, timestamp: Date, count: Int = 1) {
        self.id = id
        self.toolID = toolID
        self.timestamp = timestamp
        self.count = max(1, count)
    }
}

struct DashboardActivityDay: Codable, Equatable, Identifiable {
    let date: Date
    let launchCount: Int
    let activeToolCount: Int
    var id: Date { date }
}

struct DashboardRecentTool: Codable, Equatable, Identifiable {
    let toolID: ToolID
    let lastOpenedAt: Date
    let launchCount: Int
    var id: ToolID { toolID }
}

struct DashboardCategorySummary: Equatable, Identifiable {
    let categoryID: ToolCategoryID
    let launchCount: Int
    let activeToolCount: Int
    var id: ToolCategoryID { categoryID }
}

struct DashboardPreferences: Codable, Equatable {
    static let currentVersion = 1
    var version: Int = currentVersion
    var cards: [DashboardCardLayout] = DashboardPreferences.defaultCards
    var activity: [DashboardActivityEvent] = []

    static let defaultCards: [DashboardCardLayout] = [
        .init(kind: .continueWork, span: .large, sortOrder: 0),
        .init(kind: .activityOverview, span: .medium, sortOrder: 1),
        .init(kind: .sevenDayTrend, span: .medium, sortOrder: 2),
        .init(kind: .favorites, span: .medium, sortOrder: 3),
        .init(kind: .recent, span: .medium, sortOrder: 4),
        .init(kind: .quickActions, span: .medium, sortOrder: 5),
        .init(kind: .categoryHighlights, span: .large, sortOrder: 6)
    ]

    private enum CodingKeys: String, CodingKey { case version, cards, activity }
    private struct RawCard: Codable {
        var id: String?
        var kind: String
        var isVisible: Bool
        var span: DashboardCardSpan
        var sortOrder: Int
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        guard version == Self.currentVersion else { throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "Unsupported dashboard preferences version") }
        let rawCards = try container.decodeIfPresent([RawCard].self, forKey: .cards) ?? []
        cards = rawCards.compactMap { raw in
            guard let kind = DashboardCardKind(rawValue: raw.kind) else { return nil }
            return DashboardCardLayout(kind: kind, isVisible: raw.isVisible, span: raw.span, sortOrder: raw.sortOrder)
        }
        let decodedActivity = try container.decodeIfPresent([DashboardActivityEvent].self, forKey: .activity) ?? []
        activity = decodedActivity
    }
}

@MainActor
final class DashboardStore: ObservableObject {
    static let persistenceKey = "tools.dashboard.preferences.v1"
    static let retentionDays = 90

    @Published private(set) var preferences: DashboardPreferences
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        let loaded = Self.load(from: defaults) ?? DashboardPreferences()
        self.preferences = loaded
        self.preferences.cards = normalizeCards(loaded.cards)
        trimActivity(reference: now())
    }

    var cards: [DashboardCardLayout] {
        preferences.cards.filter(\.isVisible).sorted { $0.sortOrder < $1.sortOrder }
    }

    var recentTools: [DashboardRecentTool] {
        Dictionary(grouping: preferences.activity, by: \.toolID).compactMap { toolID, events in
            guard let latest = events.max(by: { $0.timestamp < $1.timestamp }) else { return nil }
            return DashboardRecentTool(toolID: toolID, lastOpenedAt: latest.timestamp, launchCount: events.reduce(0) { $0 + $1.count })
        }.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    /// Recent tools whose IDs are present in the current registry. Persisted
    /// history may outlive a removed tool; callers can pass the registry IDs
    /// before presenting rows so stale entries never reach the UI.
    func recentTools(knownToolIDs: Set<ToolID>) -> [DashboardRecentTool] {
        recentTools.filter { knownToolIDs.contains($0.toolID) }
    }

    func recentToolAggregates(knownToolIDs: Set<ToolID>? = nil) -> [DashboardRecentTool] {
        guard let knownToolIDs else { return recentTools }
        return recentTools(knownToolIDs: knownToolIDs)
    }

    var totalLaunches: Int { preferences.activity.reduce(0) { $0 + $1.count } }
    var activeDays: Int { activityHistoryDays.count }
    var lastActivityAt: Date? { preferences.activity.map(\.timestamp).max() }

    /// Activity grouped by local calendar day for the retained history.
    var activityHistoryDays: [DashboardActivityDay] {
        let grouped = Dictionary(grouping: preferences.activity) { calendar.startOfDay(for: $0.timestamp) }
        return grouped.map { date, events in
            DashboardActivityDay(date: date, launchCount: events.reduce(0) { $0 + $1.count }, activeToolCount: Set(events.map(\.toolID)).count)
        }.sorted { $0.date < $1.date }
    }

    /// A continuous seven-day local-calendar projection, including zero days.
    /// The final element is today according to the store's injected clock.
    var activityDays: [DashboardActivityDay] {
        let today = calendar.startOfDay(for: now())
        let grouped = Dictionary(uniqueKeysWithValues: activityHistoryDays.map { ($0.date, $0) })
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return grouped[date] ?? DashboardActivityDay(date: date, launchCount: 0, activeToolCount: 0)
        }
    }

    var sevenDayTrend: [DashboardActivityDay] { activityDays }

    func categorySummaries(categoryFor: (ToolID) -> ToolCategoryID?) -> [DashboardCategorySummary] {
        var counts: [ToolCategoryID: (launches: Int, tools: Set<ToolID>)] = [:]
        for event in preferences.activity {
            guard let category = categoryFor(event.toolID) else { continue }
            var value = counts[category] ?? (0, [])
            value.launches += event.count
            value.tools.insert(event.toolID)
            counts[category] = value
        }
        return counts.map { DashboardCategorySummary(categoryID: $0.key, launchCount: $0.value.launches, activeToolCount: $0.value.tools.count) }
            .sorted { $0.launchCount == $1.launchCount ? $0.categoryID.rawValue < $1.categoryID.rawValue : $0.launchCount > $1.launchCount }
    }

    func categoryStats(categoryFor: (ToolID) -> ToolCategoryID?) -> [DashboardCategorySummary] {
        categorySummaries(categoryFor: categoryFor)
    }

    func recordLaunch(toolID: ToolID, at date: Date? = nil) {
        let timestamp = date ?? now()
        // Retention is anchored to the current local day; an imported or
        // test event timestamp must not move the retention window backwards.
        preferences.activity.append(DashboardActivityEvent(toolID: toolID, timestamp: timestamp))
        trimActivity(reference: now())
        persist()
    }

    func recordLaunchIfChanged(toolID: ToolID, previousToolID: ToolID?, at date: Date? = nil) {
        guard previousToolID != toolID else { return }
        recordLaunch(toolID: toolID, at: date)
    }

    func setCards(_ cards: [DashboardCardLayout]) {
        let ordered = cards.enumerated().map { index, card in
            var copy = card
            copy.sortOrder = index
            return copy
        }
        preferences.cards = normalizeCards(ordered)
        persist()
    }

    func updateCard(kind: DashboardCardKind, isVisible: Bool? = nil, span: DashboardCardSpan? = nil) {
        guard let index = preferences.cards.firstIndex(where: { $0.kind == kind }) else { return }
        if let isVisible { preferences.cards[index].isVisible = isVisible }
        if let span { preferences.cards[index].span = span }
        persist()
    }

    func resetLayout() {
        preferences.cards = DashboardPreferences.defaultCards
        persist()
    }

    func resetActivity() {
        preferences.activity = []
        persist()
    }

    func resetAll() {
        preferences = DashboardPreferences()
        persist()
    }

    private func trimActivity(reference: Date) {
        guard let cutoff = calendar.date(byAdding: .day, value: -(Self.retentionDays - 1), to: calendar.startOfDay(for: reference)) else { return }
        let trimmed = preferences.activity.filter { $0.timestamp >= cutoff }
        if trimmed.count != preferences.activity.count { preferences.activity = trimmed; persist() }
    }

    private func normalizeCards(_ cards: [DashboardCardLayout]) -> [DashboardCardLayout] {
        var ordered: [DashboardCardLayout] = []
        var seen: Set<DashboardCardKind> = []
        for card in cards where seen.insert(card.kind).inserted { ordered.append(card) }
        for defaultCard in DashboardPreferences.defaultCards where seen.insert(defaultCard.kind).inserted { ordered.append(defaultCard) }
        return ordered.enumerated().map { offset, card in
            var copy = card; copy.sortOrder = offset; return copy
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.persistenceKey)
        objectWillChange.send()
    }

    private static func load(from defaults: UserDefaults) -> DashboardPreferences? {
        guard let data = defaults.data(forKey: persistenceKey), let decoded = try? JSONDecoder().decode(DashboardPreferences.self, from: data), decoded.version == DashboardPreferences.currentVersion else { return nil }
        return decoded
    }
}
