import AppKit
import Testing
@testable import XTools

/// 阶段③ Batch C Toast/HUD 双通道（design.md §5 / PRD 决策 10）。
///
/// 呈现判定发生在 `show` 时刻：key 窗口 + 应用激活 → 现状 Toast 队列；
/// 窗口非 key / 应用未激活 → 同 payload 降级 HUD（单条、固定 2s 自动隐藏、
/// 无动作钮）。判定经 init 注入（真窗口绑定路径由 ToolToastWindowBinder
/// 承接，见 ShellGovernanceContractTests 锚点）；两条通道同 payload 同
/// 无障碍播报，不新建文案。
@MainActor
final class MutablePresentationProbe {
    var isHUD = false
}

struct ToolToastCenterDualChannelTests {
    @MainActor
    private final class RecordingAnnouncer: ToolAccessibilityAnnouncing {
        var announcements: [String] = []
        func announceStatus(_ text: String) {
            announcements.append(text)
        }
    }

    @MainActor
    @Test func inactivePresentationRoutesToHudChannelWithoutToastMessages() {
        let announcer = RecordingAnnouncer()
        let center = ToolToastCenter(announcer: announcer, isHUDPresentation: { true })

        center.show("已加入收藏", tone: .success)

        #expect(center.messages.isEmpty, "HUD 降级不得污染 Toast 队列")
        #expect(center.hudMessage?.text == "已加入收藏")
        #expect(center.hudMessage?.tone == .success)
        #expect(announcer.announcements.count == 1, "两条通道同 payload 同播报")
    }

    @MainActor
    @Test func hudReplacementKeepsASingleSlotAndResetsTheHideWindow() {
        let center = ToolToastCenter(announcer: RecordingAnnouncer(), isHUDPresentation: { true })

        center.show("第一条")
        center.show("第二条", tone: .error)

        #expect(center.hudMessage?.text == "第二条", "单条槽位，新 payload 顶替旧条")
        #expect(center.hudMessage?.tone == .error)
    }

    @MainActor
    @Test func hudAutoHidesAfterTheFixedTwoSecondWindow() async {
        let center = ToolToastCenter(announcer: RecordingAnnouncer(), isHUDPresentation: { true })
        #expect(ToolToastCenter.hudAutoHideDuration == .seconds(2))

        center.show("已复制")
        #expect(center.hudMessage != nil)

        try? await Task.sleep(for: .milliseconds(2_250))
        #expect(center.hudMessage == nil, "HUD 必须在固定 2s 后自动隐藏")
    }

    @MainActor
    @Test func activePresentationKeepsTheToastQueueUntouched() {
        let center = ToolToastCenter(announcer: RecordingAnnouncer(), isHUDPresentation: { false })

        center.show("已复制", tone: .error)

        #expect(center.messages.count == 1)
        #expect(center.messages.first?.tone == .error)
        #expect(center.hudMessage == nil)
    }

    @MainActor
    @Test func channelDecisionIsPerShowAndDoesNotMigrateMessages() {
        // 判定只在入队时刻发生：HUD 已在场的 payload 不随窗口状态迁移回
        // Toast，新判定只影响后续 show。
        let probe = MutablePresentationProbe()
        probe.isHUD = true
        let center = ToolToastCenter(announcer: RecordingAnnouncer(), isHUDPresentation: { probe.isHUD })

        center.show("降级期间")
        #expect(center.hudMessage?.text == "降级期间")
        #expect(center.messages.isEmpty)

        probe.isHUD = false
        center.show("前台期间")
        #expect(center.messages.map(\.text) == ["前台期间"], "恢复前台后新消息走 Toast")
        #expect(center.hudMessage?.text == "降级期间", "已入 HUD 的 payload 不迁移")
    }
}
