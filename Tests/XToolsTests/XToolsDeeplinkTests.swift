@testable import XTools
import Foundation
import Testing

/// 阶段③ Batch D 深链与多窗口共享单例的行为测试：
/// - `XToolsDeeplink.parse`：合法 URL、容错（scheme/host/id/segment/input）；
/// - `XToolsDeeplinkConsumer`：同帧同 URL 单消费、间隔窗口外的重复生效；
/// - `ShellSharedStores.claimWindowLaunch` + `ShellNavigationModel(
///   resumesSelection:)`：首窗恢复语义、后续窗口默认仪表盘；
/// - 直达载荷投递：选择变化作废（一次性）。
@MainActor
struct XToolsDeeplinkTests {
    // MARK: - 解析

    @Test func parsesToolSegmentAndInput() throws {
        let url = URL(string: "xtools://tool/text-encoding?segment=base64&input=hello%20world")!
        let deeplink = try #require(XToolsDeeplink.parse(url))
        #expect(deeplink.toolID == "text-encoding")
        #expect(deeplink.segment == "base64")
        #expect(deeplink.input == "hello world")
    }

    @Test func parsesToolWithoutQuery() throws {
        let deeplink = try #require(XToolsDeeplink.parse(URL(string: "xtools://tool/formatter")!))
        #expect(deeplink.toolID == "formatter")
        #expect(deeplink.segment == nil)
        #expect(deeplink.input == nil)
    }

    @Test func emptySegmentAndInputCollapseToNil() throws {
        let deeplink = try #require(
            XToolsDeeplink.parse(URL(string: "xtools://tool/formatter?segment=&input=")!)
        )
        #expect(deeplink.segment == nil)
        #expect(deeplink.input == nil)
    }

    @Test func rejectsWrongSchemeHostOrMissingToolID() {
        #expect(XToolsDeeplink.parse(URL(string: "https://tool/formatter")!) == nil)
        #expect(XToolsDeeplink.parse(URL(string: "xtools://other/formatter")!) == nil)
        #expect(XToolsDeeplink.parse(URL(string: "xtools://tool")!) == nil)
        #expect(XToolsDeeplink.parse(URL(string: "xtools://tool/")!) == nil)
        #expect(XToolsDeeplink.parse(URL(string: "xtools://formatter")!) == nil)
    }

    @Test func unknownToolIDStillParsesForConsumerSideFallback() throws {
        // 非法 id 不在解析层拒绝：消费端 openSuggestionTarget 以注册表兜底忽略。
        let deeplink = try #require(
            XToolsDeeplink.parse(URL(string: "xtools://tool/not-a-tool?input=x")!)
        )
        #expect(deeplink.toolID.rawValue == "not-a-tool")
    }

    // MARK: - 消费去重

    @Test func sameURLWithinWindowIsClaimedOnce() {
        let consumer = XToolsDeeplinkConsumer()
        let url = URL(string: "xtools://tool/formatter")!
        let now = Date().timeIntervalSince1970

        #expect(consumer.claim(url, now: now))
        #expect(!consumer.claim(url, now: now + 0.01))
        #expect(!consumer.claim(url, now: now + 0.04))

        // 超过窗口的同一 URL（用户再次触发）照常生效。
        #expect(consumer.claim(url, now: now + XToolsDeeplinkConsumer.deduplicationWindow + 0.01))

        // 不同 URL 不受去重影响。
        let other = URL(string: "xtools://tool/diff")!
        #expect(consumer.claim(other, now: now))
    }

    // MARK: - 多窗口共享单例（D4）

    @Test func sharedStoresClaimYieldsRecoveryOnlyForFirstWindow() throws {
        let defaults = UserDefaults(suiteName: "XToolsDeeplinkTests.\(UUID().uuidString)")!
        let stores = ShellSharedStores(defaults: defaults)

        #expect(stores.claimWindowLaunch(), "首个窗口保留恢复语义")
        #expect(!stores.claimWindowLaunch(), "后续窗口默认仪表盘")
        #expect(!stores.claimWindowLaunch())
    }

    @Test func resumesSelectionFalseLeavesSelectionOnDashboard() {
        let defaults = UserDefaults(suiteName: "XToolsDeeplinkTests.\(UUID().uuidString)")!
        defaults.set("formatter", forKey: "tools.shell.selectedToolID.v1")

        let resumes = ShellNavigationModel(preferences: ToolPreferenceStore(defaults: defaults))
        #expect(resumes.selectedToolID == "formatter")

        let dashboard = ShellNavigationModel(
            preferences: ToolPreferenceStore(defaults: defaults),
            resumesSelection: false
        )
        #expect(dashboard.selectedToolID == nil, "新窗口不恢复上次工具（默认仪表盘）")
    }

    @Test func entryPayloadInvalidatesOnSelectionChange() throws {
        let defaults = UserDefaults(suiteName: "XToolsDeeplinkTests.\(UUID().uuidString)")!
        let model = ShellNavigationModel(preferences: ToolPreferenceStore(defaults: defaults))

        model.deliverEntryFocus(toolID: "formatter", text: "{\"a\":1}")
        let payload = try #require(model.workbenchEntryPayload)
        #expect(payload.toolID == "formatter")
        #expect(payload.text == "{\"a\":1}")

        // 选择变化 → 载荷作废（一次性投递,防停靠回访重写旧文本）。
        model.selectedToolID = "diff"
        #expect(model.workbenchEntryPayload == nil)

        // 同工具直达（仅聚焦）：新投递覆盖,text 为 nil。
        model.deliverEntryFocus(toolID: "diff", text: nil)
        model.deliverEntryFocus(toolID: "diff", text: nil)
        let focusOnly = try #require(model.workbenchEntryPayload)
        #expect(focusOnly.text == nil)
        #expect(focusOnly.id != payload.id, "重复投递必须携带新的请求序号")
    }
}
