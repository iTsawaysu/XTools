import Foundation
import AppKit
import Combine
import XCTest
@testable import XTools

/// 仪表盘门面行为（阶段③ frecency 单源后）：数据与持久化都在
/// `ToolUsageFrequencyStore`，这里锁定观察语义、通道与写线程纪律。
@MainActor
final class DashboardStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "DashboardStoreTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func makeStore(_ defaults: UserDefaults) -> DashboardStore {
        DashboardStore(usage: ToolUsageFrequencyStore(defaults: defaults))
    }

    func testUnknownToolsCanBeFilteredFromRecents() {
        let store = makeStore(makeDefaults())
        let base = Date()
        store.recordLaunch(toolID: "json", at: base)
        store.recordLaunch(toolID: "gone", at: base.addingTimeInterval(1))
        store.recordLaunch(toolID: "json", at: base.addingTimeInterval(2))

        XCTAssertEqual(store.recentTools(knownToolIDs: ["json"]).map(\.toolID), ["json"])
    }

    func testRepeatedSelectionCanBeIgnoredAtStoreBoundary() throws {
        let store = makeStore(makeDefaults())
        let date = Date()
        store.recordLaunchIfChanged(toolID: "json", previousToolID: nil, at: date)
        store.recordLaunchIfChanged(toolID: "json", previousToolID: "json", at: date.addingTimeInterval(1))
        XCTAssertEqual(store.recentTools.count, 1)
        // 合并事件环以 epochSeconds(Double) 承载时间戳（旧 palette 环格式），
        // Date 往返在亚微秒级有舍入；语义等价比较放宽到毫秒。
        let storedTimestamp = try XCTUnwrap(store.recentTools.first?.lastOpenedAt)
        XCTAssertEqual(storedTimestamp.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }

    func testLaunchesPublishExactlyOncePerAcceptedLaunch() {
        let store = makeStore(makeDefaults())
        var publications = 0
        let observer = store.objectWillChange.sink { publications += 1 }
        for index in 0..<25 {
            store.recordLaunch(toolID: ToolID(rawValue: "tool-\(index)"))
        }
        XCTAssertEqual(publications, 25)
        XCTAssertEqual(store.launchToken, 25)
        withExtendedLifetime(observer) {}
    }

    /// 单源持久化契约：navigation 历史全部落 `tools.palette.recents.v1`
    /// （合并事件环），写入必须离开主线程，释放 owner 前排空最新快照。
    func testBackgroundWritesPreserveEveryAcceptedLaunchOnRelease() throws {
        let defaults = DashboardRecordingDefaults(
            suiteName: "DashboardStoreTests.\(UUID())",
            recentsKey: AppShellPreferenceKeys.paletteRecents.rawKey
        )!
        var store: DashboardStore? = DashboardStore(usage: ToolUsageFrequencyStore(defaults: defaults))
        for index in 0..<200 {
            store?.recordLaunch(toolID: ToolID(rawValue: "tool-\(index)"))
        }
        // Releasing the owner drains the latest coalesced snapshot before returning.
        store = nil
        let stored = try XCTUnwrap(defaults.string(forKey: AppShellPreferenceKeys.paletteRecents.rawKey))
        let saved = try JSONDecoder().decode(
            [ToolUsageFrequencyStore.UsageEvent].self,
            from: Data(stored.utf8)
        )
        XCTAssertEqual(saved.map(\.toolID), (0..<200).map { "tool-\($0)" })
        XCTAssertTrue(saved.allSatisfy { $0.resolvedChannel == .navigation })
        let historyWrites = defaults.recentsWrites
        XCTAssertFalse(historyWrites.isEmpty)
        XCTAssertTrue(historyWrites.allSatisfy { !$0 }, "History writes must leave the main thread")
    }

    func testApplicationTerminationFlushesLatestHistoryAndLaunchPublishesOnce() throws {
        let defaults = makeDefaults()
        let store = makeStore(defaults)
        var publications = 0
        let observer = store.objectWillChange.sink { publications += 1 }
        for index in 0..<25 {
            store.recordLaunch(toolID: ToolID(rawValue: "tool-\(index)"))
        }
        XCTAssertEqual(publications, 25)
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        let stored = try XCTUnwrap(defaults.string(forKey: AppShellPreferenceKeys.paletteRecents.rawKey))
        let saved = try JSONDecoder().decode(
            [ToolUsageFrequencyStore.UsageEvent].self,
            from: Data(stored.utf8)
        )
        XCTAssertEqual(saved.map(\.toolID), (0..<25).map { "tool-\($0)" })
        withExtendedLifetime(observer) {}
    }
}

private final class DashboardRecordingDefaults: UserDefaults {
    private let lock = NSLock()
    private var storedWrites: [(key: String, isMainThread: Bool)] = []
    private let recentsKey: String

    init?(suiteName suiteNameParam: String, recentsKey: String) {
        self.recentsKey = recentsKey
        super.init(suiteName: suiteNameParam)
    }

    /// 只统计使用日志键的写入（迁移位图键在 init 的主线程落位，不属于
    /// 「历史写入离开主线程」的契约范围）。
    var recentsWrites: [Bool] {
        lock.withLock {
            storedWrites
                .filter { $0.key == recentsKey }
                .map(\.isMainThread)
        }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { storedWrites.append((defaultName, Thread.isMainThread)) }
        super.set(value, forKey: defaultName)
    }
}
