import Foundation
import XCTest
@testable import XTools

@MainActor
final class DashboardStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "DashboardStoreTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testDefaultsExposeProductOrder() {
        let store = DashboardStore(defaults: makeDefaults())
        XCTAssertEqual(store.cards.map(\.kind), [.continueWork, .activityOverview, .sevenDayTrend, .favorites, .recent, .quickActions, .categoryHighlights])
        XCTAssertEqual(store.cards.first?.span, .large)
    }

    func testActivityAggregatesAndTrimsAtNinetyDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let store = DashboardStore(defaults: makeDefaults(), calendar: calendar, now: { base })
        store.recordLaunch(toolID: "json", at: base)
        store.recordLaunch(toolID: "json", at: calendar.date(byAdding: .hour, value: 1, to: base)!)
        store.recordLaunch(toolID: "jwt", at: calendar.date(byAdding: .day, value: -89, to: base)!)
        store.recordLaunch(toolID: "old", at: calendar.date(byAdding: .day, value: -90, to: base)!)
        XCTAssertEqual(store.totalLaunches, 3)
        XCTAssertEqual(store.activeDays, 2)
        XCTAssertEqual(store.recentTools.first?.toolID, "json")
    }

    func testActivityDaysAreContinuousSevenDayProjectionWithZeroFill() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let store = DashboardStore(defaults: makeDefaults(), calendar: calendar, now: { base })
        store.recordLaunch(toolID: "json", at: calendar.date(byAdding: .day, value: -2, to: base)!)

        XCTAssertEqual(store.activityDays.count, 7)
        XCTAssertEqual(store.activityDays.map(\.launchCount), [0, 0, 0, 0, 1, 0, 0])
        XCTAssertEqual(store.activityDays.map(\.date), (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: base))
        })
    }

    func testSetCardsUsesCallerOrderForSortOrder() {
        let store = DashboardStore(defaults: makeDefaults())
        let cards = [
            DashboardCardLayout(kind: .recent, span: .small, sortOrder: 99),
            DashboardCardLayout(kind: .continueWork, span: .large, sortOrder: -4)
        ]
        store.setCards(cards)
        XCTAssertEqual(store.preferences.cards.first?.kind, .recent)
        XCTAssertEqual(store.preferences.cards.first?.sortOrder, 0)
        XCTAssertEqual(store.preferences.cards.first(where: { $0.kind == .continueWork })?.sortOrder, 1)
    }

    func testUnknownToolsCanBeFilteredAndCategoryAggregatesIgnoreUnknown() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let store = DashboardStore(defaults: makeDefaults(), calendar: calendar, now: { base })
        store.recordLaunch(toolID: "json", at: base)
        store.recordLaunch(toolID: "gone", at: base.addingTimeInterval(1))
        store.recordLaunch(toolID: "json", at: base.addingTimeInterval(2))

        XCTAssertEqual(store.recentTools(knownToolIDs: ["json"]).map(\.toolID), ["json"])
        let summaries = store.categorySummaries { $0 == "json" ? .development : nil }
        XCTAssertEqual(summaries, [DashboardCategorySummary(categoryID: .development, launchCount: 2, activeToolCount: 1)])
    }

    func testRepeatedSelectionCanBeIgnoredAtStoreBoundary() {
        let store = DashboardStore(defaults: makeDefaults())
        let date = Date()
        store.recordLaunchIfChanged(toolID: "json", previousToolID: nil, at: date)
        store.recordLaunchIfChanged(toolID: "json", previousToolID: "json", at: date.addingTimeInterval(1))
        XCTAssertEqual(store.totalLaunches, 1)
    }

    func testResetLayoutAndActivityAreIndependent() {
        let store = DashboardStore(defaults: makeDefaults())
        store.updateCard(kind: .recent, isVisible: false, span: .small)
        store.recordLaunch(toolID: "json")
        store.resetActivity()
        XCTAssertEqual(store.activeDays, 0)
        XCTAssertFalse(store.cards.contains { $0.kind == .recent })
        store.resetLayout()
        XCTAssertTrue(store.cards.contains { $0.kind == .recent })
    }

    func testWaterfallPlannerBalancesColumnsAndSpansLargeCards() {
        let placements = DashboardWaterfallPlanner.placements(
            for: [.medium, .medium, .medium, .medium, .large],
            compact: false
        )

        XCTAssertEqual(placements.map(\.column), [0, 1, 0, 1, 0])
        XCTAssertEqual(placements.map(\.row), [0, 0, 1, 1, 2])
        XCTAssertEqual(placements.last?.columnSpan, 2)
    }

    func testWaterfallPlannerUsesOneOrderedColumnWhenCompact() {
        let placements = DashboardWaterfallPlanner.placements(
            for: [.large, .small, .medium],
            compact: true
        )

        XCTAssertEqual(placements.map(\.column), [0, 0, 0])
        XCTAssertEqual(placements.map(\.row), [0, 1, 2])
        XCTAssertTrue(placements.allSatisfy { $0.columnSpan == 1 })
    }

    func testDashboardChromeUsesSharedTitleRailRhythm() {
        let chrome = IndexPageChrome.dashboard

        XCTAssertEqual(chrome.horizontalPadding, 30)
        XCTAssertEqual(chrome.topPadding, 2)
        XCTAssertEqual(chrome.headerLeadingPadding, ToolMetrics.Spacing.sm)
        XCTAssertEqual(chrome.headerRailWidth, ToolMetrics.Spacing.xs / 2)
        XCTAssertGreaterThan(chrome.bottomPadding, chrome.topPadding)
    }
}
