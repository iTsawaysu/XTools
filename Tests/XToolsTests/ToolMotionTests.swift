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

    @Test func pageTransitionPresetsRespectReduceMotion() {
        for preset in [
            ToolMotion.Preset.pageArrival,
            ToolMotion.Preset.pageDeparture,
            ToolMotion.Preset.pageSharedAxisArrival,
            ToolMotion.Preset.pageSharedAxisDeparture,
            ToolMotion.Preset.pageBloomArrival,
            ToolMotion.Preset.pageBloomDeparture
        ] {
            #expect(ToolMotion.animation(preset, reduceMotion: true) == nil)
            #expect(ToolMotion.animation(preset, reduceMotion: false) != nil)
        }
    }

    @Test func pageTransitionDurationsStayOrdered() {
        #expect(ToolMotion.Duration.pageSinkExit < ToolMotion.Duration.pageSinkEnter)
        #expect(ToolMotion.Duration.pageSharedAxisExit < ToolMotion.Duration.pageSharedAxisEnter)
        #expect(ToolMotion.Duration.pageBloomExit < ToolMotion.Duration.pageBloomEnter)
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
