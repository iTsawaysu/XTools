import SwiftUI
@testable import XTools
import Testing

struct ToolMotionTests {
    @Test func motionDurationTokensStayInWorkingUiRange() {
        #expect(ToolMotion.Duration.stagger == 0.04)
        #expect(ToolMotion.Duration.micro == 0.12)
        #expect(ToolMotion.Duration.quick == 0.15)
        #expect(ToolMotion.Duration.arrival == 0.2)
        #expect(ToolMotion.Duration.fast == 0.25)
        #expect(ToolMotion.Duration.medium == 0.35)
    }

    @Test func pageArrivalStaysAHostOwnedWhitelistedPreset() {
        #expect(ToolMotion.Preset.pageArrival == ToolMotion.Curve.smoothOut(duration: ToolMotion.Duration.arrival))
    }

    @Test func motionGeometryTokensStayLightweight() {
        #expect(ToolMotion.Distance.base == 8)
        #expect(ToolMotion.Distance.large == 18)
        #expect(ToolMotion.Scale.modal == 0.98)
        #expect(ToolMotion.Scale.pressed == 0.98)
        #expect(ToolMotion.Scale.iconInserted == 0.98)
        #expect(ToolMotion.Scale.iconRemoved == 1.02)
    }

    @Test func orderedDirectionUsesSharedSmallDistance() {
        #expect(ToolMotion.OrderedDirection.backward.insertionOffsetX == -ToolMotion.Distance.small)
        #expect(ToolMotion.OrderedDirection.forward.insertionOffsetX == ToolMotion.Distance.small)
    }

    @Test func resultPresenceUsesAsymmetricProductiveTiming() {
        let exit = ToolMotion.Curve.productiveExitControlPoints

        #expect(ToolMotion.ResultPresence.appearanceDuration == ToolMotion.Duration.medium)
        #expect(ToolMotion.ResultPresence.exitDuration == ToolMotion.Duration.fast)
        #expect(exit.x1 == 0.2)
        #expect(exit.y1 == 0.0)
        #expect(exit.x2 == 1.0)
        #expect(exit.y2 == 0.9)
    }

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

    @Test func legacyToolMetricsAnimationDurationsForwardToToolMotion() {
        #expect(ToolMetrics.Animation.fast == ToolMotion.Duration.micro)
        #expect(ToolMetrics.Animation.base == ToolMotion.Duration.quick)
    }

    @Test func appKitAccordionUsesTheSharedSmoothOutToken() {
        let motion = ToolMotion.AppKitPreset.accordion
        var first = [Float](repeating: 0, count: 2)
        var second = [Float](repeating: 0, count: 2)
        motion.timingFunction.getControlPoint(at: 1, values: &first)
        motion.timingFunction.getControlPoint(at: 2, values: &second)

        #expect(motion.duration == ToolMotion.Duration.medium)
        #expect(first[0] == Float(ToolMotion.Curve.smoothOutControlPoints.x1))
        #expect(first[1] == Float(ToolMotion.Curve.smoothOutControlPoints.y1))
        #expect(second[0] == Float(ToolMotion.Curve.smoothOutControlPoints.x2))
        #expect(second[1] == Float(ToolMotion.Curve.smoothOutControlPoints.y2))
    }
}
