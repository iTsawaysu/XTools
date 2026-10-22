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
}
