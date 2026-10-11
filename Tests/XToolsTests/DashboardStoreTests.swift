import Foundation
import AppKit
import Combine
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

    func testBackgroundWritesPreserveEveryAcceptedLaunchOnRelease() throws {
        let defaults = DashboardRecordingDefaults(suiteName: "DashboardStoreTests.\(UUID())")!
        var store: DashboardStore? = DashboardStore(defaults: defaults)
        for index in 0..<200 {
            store?.recordLaunch(toolID: ToolID(rawValue: "tool-\(index)"))
        }
        // Releasing the owner drains the latest coalesced snapshot before returning.
        store = nil
        let data = try XCTUnwrap(defaults.data(forKey: DashboardStore.persistenceKey))
        let saved = try JSONDecoder().decode(DashboardPreferences.self, from: data)
        XCTAssertEqual(saved.activity.map(\.toolID.rawValue), (0..<200).map { "tool-\($0)" })
        XCTAssertFalse(defaults.writeThreads.isEmpty)
        XCTAssertTrue(defaults.writeThreads.allSatisfy { !$0 }, "History writes must leave the main thread")
    }

    func testApplicationTerminationFlushesLatestHistoryAndLaunchPublishesOnce() throws {
        let defaults = makeDefaults()
        let store = DashboardStore(defaults: defaults)
        var publications = 0
        let observer = store.objectWillChange.sink { publications += 1 }
        for index in 0..<25 {
            store.recordLaunch(toolID: ToolID(rawValue: "tool-\(index)"))
        }
        XCTAssertEqual(publications, 25)
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        let data = try XCTUnwrap(defaults.data(forKey: DashboardStore.persistenceKey))
        let saved = try JSONDecoder().decode(DashboardPreferences.self, from: data)
        XCTAssertEqual(saved.activity.map(\.toolID.rawValue), (0..<25).map { "tool-\($0)" })
        withExtendedLifetime(observer) {}
    }

}

private final class DashboardRecordingDefaults: UserDefaults {
    private let lock = NSLock()
    private var storedWriteThreads: [Bool] = []
    var writeThreads: [Bool] { lock.withLock { storedWriteThreads } }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { storedWriteThreads.append(Thread.isMainThread) }
        super.set(value, forKey: defaultName)
    }
}
