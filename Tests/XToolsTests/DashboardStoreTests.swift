import Foundation
import XCTest
@testable import XTools

@MainActor
final class DashboardStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "DashboardStoreTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testActivityTrimsAndOrdersRecentsAtNinetyDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let store = DashboardStore(defaults: makeDefaults(), calendar: calendar, now: { base })
        store.recordLaunch(toolID: "json", at: base)
        store.recordLaunch(toolID: "json", at: calendar.date(byAdding: .hour, value: 1, to: base)!)
        store.recordLaunch(toolID: "jwt", at: calendar.date(byAdding: .day, value: -89, to: base)!)
        store.recordLaunch(toolID: "old", at: calendar.date(byAdding: .day, value: -90, to: base)!)
        XCTAssertEqual(store.recentTools.map(\.toolID), ["json", "jwt"])
        XCTAssertEqual(store.recentTools.count, 2)
    }

    func testUnknownToolsCanBeFilteredFromRecents() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let store = DashboardStore(defaults: makeDefaults(), calendar: calendar, now: { base })
        store.recordLaunch(toolID: "json", at: base)
        store.recordLaunch(toolID: "gone", at: base.addingTimeInterval(1))
        store.recordLaunch(toolID: "json", at: base.addingTimeInterval(2))

        XCTAssertEqual(store.recentTools(knownToolIDs: ["json"]).map(\.toolID), ["json"])
    }

    func testRepeatedSelectionCanBeIgnoredAtStoreBoundary() {
        let store = DashboardStore(defaults: makeDefaults())
        let date = Date()
        store.recordLaunchIfChanged(toolID: "json", previousToolID: nil, at: date)
        store.recordLaunchIfChanged(toolID: "json", previousToolID: "json", at: date.addingTimeInterval(1))
        XCTAssertEqual(store.recentTools.count, 1)
        XCTAssertEqual(store.recentTools.first?.lastOpenedAt, date)
    }

}
