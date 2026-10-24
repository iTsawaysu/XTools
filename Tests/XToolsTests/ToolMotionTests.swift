import SwiftUI
@testable import XTools
import Testing
import XToolsDesign

struct ToolMotionTests {
    @Test func reduceMotionGateRemovesSwiftUIAnimations() {
        switch ToolMotion.animation(.easeInOut(duration: 1), reduceMotion: true) {
        case nil:
            break
        case .some:
            Issue.record("Reduce Motion must disable SwiftUI animations")
        }

        switch ToolMotion.animation(.easeInOut(duration: 1), reduceMotion: false) {
        case nil:
            Issue.record("Animations should remain available when Reduce Motion is off")
        case .some:
            break
        }
    }

    /// 阶段③ 决策 9：页面切换只剩 crossfade（普通）与 originBloom（⌘K）
    /// 两个 preset 家族；depth/sharedAxis 的位移缩放编排已随 token 退役。
    @Test func pageTransitionPresetsRespectReduceMotion() {
        for preset in [
            ToolMotion.Preset.contentCrossfade,
            ToolMotion.Preset.pageBloomArrival,
            ToolMotion.Preset.pageBloomDeparture
        ] {
            #expect(ToolMotion.animation(preset, reduceMotion: true) == nil)
            #expect(ToolMotion.animation(preset, reduceMotion: false) != nil)
        }
    }

    @Test func pageBloomDurationsStayOrdered() {
        // 出场不拖累新页到达：bloom 离开弧必须短于到达弧。
        #expect(ToolMotion.Duration.pageBloomExit < ToolMotion.Duration.pageBloomEnter)
    }

    /// 阶段③ 决策 9：普通页面切换的唯一包络 = 0.18s easeInOut crossfade
    /// （纯 opacity、无位移；RM 折叠为直切）。锁定时长与曲线来源，防止
    /// 调用侧再冒出第二套切页时长。
    @Test func contentCrossfadeIsTheSinglePageSwitchEnvelope() {
        #expect(ToolMotion.Duration.contentCrossfade == 0.18)
        #expect(ToolMotion.Preset.contentCrossfade == ToolMotion.Curve.inOut(duration: ToolMotion.Duration.contentCrossfade))
        #expect(ToolMotion.animation(ToolMotion.Preset.contentCrossfade, reduceMotion: true) == nil)
        #expect(ToolMotion.animation(ToolMotion.Preset.contentCrossfade, reduceMotion: false) != nil)
    }

    /// v6: page-level effects resolve to four semantics only. Legacy preset
    /// names must alias one of them so no fifth timing family can reappear.
    @Test func inPagePresetsCollapseToFourSemantics() {
        #expect(ToolMotion.Preset.textSwap == ToolMotion.Preset.controlFeedback)
        #expect(ToolMotion.Preset.iconSwap == ToolMotion.Preset.controlFeedback)
        #expect(ToolMotion.Preset.orderedContent == ToolMotion.Preset.contentReveal)
        #expect(ToolMotion.Preset.tabs == ToolMotion.Preset.contentReveal)
        #expect(ToolMotion.Preset.accordion == ToolMotion.Preset.contentReveal)
        #expect(ToolMotion.Preset.panelReveal == ToolMotion.Preset.contentReveal)
        #expect(ToolMotion.Preset.modal == ToolMotion.Preset.settle)
        #expect(ToolMotion.animation(ToolMotion.Preset.contentReveal, reduceMotion: true) == nil)
        #expect(ToolMotion.animation(ToolMotion.Preset.controlFeedback, reduceMotion: true) == nil)
        #expect(ToolMotion.animation(ToolMotion.Preset.diagnostic, reduceMotion: true) == nil)
        #expect(ToolMotion.animation(ToolMotion.Preset.settle, reduceMotion: true) == nil)
    }
}
