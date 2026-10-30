import SwiftUI
@testable import XTools
import Testing

struct ToolMotionTests {
    @Test func motionDurationTokensStayInWorkingUiRange() {
        #expect(ToolMotion.Duration.instant == 0)
        #expect(ToolMotion.Duration.base == 0.200)
        #expect(ToolMotion.Duration.enter == 0.260)
        #expect(ToolMotion.Duration.exit == 0.160)
        #expect(ToolMotion.Duration.loop == 1.200)
        #expect(ToolMotion.Duration.micro == 0.100)
        #expect(ToolMotion.Duration.quick == 0.140)
        #expect(ToolMotion.Duration.arrival == ToolMotion.Duration.enter)
        #expect(ToolMotion.Duration.fast == ToolMotion.Duration.base)
        #expect(ToolMotion.Duration.medium == ToolMotion.Duration.base)
        #expect(ToolMotion.Duration.pageSinkEnter == ToolMotion.Duration.enter)
        #expect(ToolMotion.Duration.pageSinkExit == ToolMotion.Duration.exit)
    }

    @Test func v9CurveAndPresetValuesStayPinned() {
        let standard = ToolMotion.Curve.standardControlPoints
        #expect(standard.x1 == 0.2)
        #expect(standard.y1 == 0.0)
        #expect(standard.x2 == 0.0)
        #expect(standard.y2 == 1.0)

        let enter = ToolMotion.Curve.enterControlPoints
        #expect(enter.x1 == 0.16)
        #expect(enter.y1 == 1.0)
        #expect(enter.x2 == 0.3)
        #expect(enter.y2 == 1.0)

        let exit = ToolMotion.Curve.exitControlPoints
        #expect(exit.x1 == 0.4)
        #expect(exit.y1 == 0.0)
        #expect(exit.x2 == 1.0)
        #expect(exit.y2 == 1.0)

        #expect(ToolMotion.Preset.pageEnter == ToolMotion.Curve.enter(duration: ToolMotion.Duration.enter))
        #expect(ToolMotion.Preset.pageExit == ToolMotion.Curve.exit(duration: ToolMotion.Duration.exit))
        #expect(ToolMotion.Distance.pageRise == 4)
        #expect(ToolMotion.Preset.toastEnter == ToolMotion.Curve.enter(duration: ToolMotion.Duration.base))
        #expect(ToolMotion.Preset.toastExit == ToolMotion.Curve.exit(duration: ToolMotion.Duration.exit))
        #expect(ToolMotion.CopyTick.out == 0.200)
        #expect(ToolMotion.CopyTick.draw == 0.200)
        #expect(ToolMotion.CopyTick.back == 0.140)
        #expect(ToolMotion.Preset.delight == ToolMotion.Curve.delight())
        #expect(ToolMotion.Preset.reducedMotionFade == ToolMotion.Curve.standard(duration: ToolMotion.Duration.micro))
    }

    @Test func pageArrivalStaysAHostOwnedWhitelistedPreset() {
        #expect(ToolMotion.Preset.pageArrival == ToolMotion.Curve.enter(duration: ToolMotion.Duration.pageSinkEnter))
        #expect(ToolMotion.Preset.pageDeparture == ToolMotion.Curve.exit(duration: ToolMotion.Duration.pageSinkExit))
        #expect(ToolMotion.Scale.pageArrivalSink == 0.995)
        #expect(ToolMotion.Scale.pageDepartureSink == 0.992)
        #expect(ToolMotion.Distance.pageSinkRise == 10)
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
        let exit = ToolMotion.Curve.exitControlPoints

        #expect(ToolMotion.ResultPresence.appearanceDuration == ToolMotion.Duration.base)
        #expect(ToolMotion.ResultPresence.exitDuration == ToolMotion.Duration.exit)
        #expect(exit.x1 == 0.4)
        #expect(exit.y1 == 0.0)
        #expect(exit.x2 == 1.0)
        #expect(exit.y2 == 1.0)
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

    @Test func emptyStateArrivalIsOneTimeline() {
        #expect(ToolMotion.EmptyArrival.riseDistance == 4)
        #expect(ToolMotion.EmptyArrival.elementArrival == ToolMotion.EmptyArrival.arrive)
        #expect(ToolMotion.EmptyArrival.arrive == ToolMotion.Curve.enter(duration: ToolMotion.Duration.enter))
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

        #expect(motion.duration == ToolMotion.Duration.base)
        #expect(first[0] == Float(ToolMotion.Curve.standardControlPoints.x1))
        #expect(first[1] == Float(ToolMotion.Curve.standardControlPoints.y1))
        #expect(second[0] == Float(ToolMotion.Curve.standardControlPoints.x2))
        #expect(second[1] == Float(ToolMotion.Curve.standardControlPoints.y2))
    }
}
