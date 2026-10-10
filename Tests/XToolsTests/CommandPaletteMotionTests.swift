import AppKit
import Foundation
import QuartzCore
import SwiftUI
@testable import XTools
import Testing

/// 2026-10 审计：真实窗口插值采样段（首挂载全弧、20/50/100ms 三档反转循环、
/// 进度 ≥0.999/≤0.001 边界轮询、定时 toggle 爆发）已整体移出留档至
/// /Users/sun/Downloads/tmp/xtools-tests-archive-2026-10-09/CommandPaletteMotionSamplingTests.swift。
/// 本文件保留非采样的结构/数学/token 断言与合成的 deadline 纯逻辑测试。
@Suite(.serialized)
struct CommandPaletteMotionTests {
    @Test
    func visibilityGeometryIsAContinuousFunctionOfProgress() {
        // Wave 2: the palette rises/sinks `PaletteMotion.riseDistance` (8pt)
        // across the full progress sweep (prototype cmdkRise). Opacity and
        // translation are the only channels — no scale that would resample
        // the retained native-view subtree.
        var previous = CommandPaletteVisibilityGeometry.resolve(
            progress: 0,
            reduceMotion: false
        )
        for progress in stride(from: CGFloat(0.05), through: 1, by: 0.05) {
            let current = CommandPaletteVisibilityGeometry.resolve(
                progress: progress,
                reduceMotion: false
            )

            #expect(abs(current.opacity - Double(progress)) < 0.000_001)
            #expect(abs(current.offsetY - previous.offsetY) <= ToolMotion.PaletteMotion.riseDistance * 0.05 + 0.000_001)
            previous = current
        }

        #expect(previous.offsetY == 0)
    }

    @Test
    func reduceMotionKeepsOffsetFixedAndOpacityLinearAcrossAllProgress() {
        for progress in stride(from: CGFloat(0), through: 1, by: 0.05) {
            let geometry = CommandPaletteVisibilityGeometry.resolve(
                progress: progress,
                reduceMotion: true
            )

            #expect(geometry.offsetY == 0)
            #expect(geometry.opacity == Double(progress))
        }
    }

    // MARK: - Wave 2 palette choreography (prototype MOTION cmdk*)

    /// Terminal values lock: open rise 8pt spring, ~140ms close settle,
    /// launcher-fast arcs (open 150ms, close 140ms), no per-row arrival gate
    /// (content mounts visible), highlight spring. No scale/scrim tokens:
    /// the panel must not scale the native-view subtree and the scrim rides
    /// the single progress interpolation.
    @Test
    func paletteMotionTokensMatchWave2Prototype() {
        #expect(ToolMotion.PaletteMotion.riseDistance == 0)
        // Springs keep the presentation retargetable (timing-curve variants
        // stalled real-window reversals); launcher-fast cadence.
        #expect(ToolMotion.PaletteMotion.open == Animation.easeOut(duration: 0.13))
        #expect(ToolMotion.PaletteMotion.close == Animation.easeOut(duration: 0.12))
        // Keyboard selection highlight is instant (no interpolation token).
    }

    /// Fade-only presentation: opacity spans 0→1 across the progress range
    /// with no positional travel, one continuous mapping for both directions.
    @Test
    func visibilityGeometryMatchesWave2Endpoints() {
        let start = CommandPaletteVisibilityGeometry.resolve(
            progress: 0,
            reduceMotion: false
        )
        let settled = CommandPaletteVisibilityGeometry.resolve(
            progress: 1,
            reduceMotion: false
        )

        #expect(start.offsetY == ToolMotion.PaletteMotion.riseDistance)
        #expect(start.opacity == 0)
        #expect(settled.offsetY == 0)
        #expect(settled.opacity == 1)

        for progress in stride(from: CGFloat(0.05), to: 1, by: 0.05) {
            let geometry = CommandPaletteVisibilityGeometry.resolve(
                progress: progress,
                reduceMotion: false
            )
            // Fade-only: no positional travel at any intermediate progress.
            #expect(geometry.offsetY == 0)
            #expect(geometry.opacity > 0 && geometry.opacity < 1)
        }
    }

#if DEBUG
    @Test
    func reversalDeadlineRequiresProgressInsteadOfARepeatedSetter() throws {
        let requestedAt = ContinuousClock.now
        for presented in [false, true] {
            let repeated = Self.sample(progress: 0.5, presented: presented, at: requestedAt + .milliseconds(5))
            let wrongDirection = Self.sample(
                progress: presented ? 0.4 : 0.6, presented: presented,
                at: requestedAt + .milliseconds(10)
            )
            let stalled = [repeated, wrongDirection]
            #expect(Self.firstAdvancingSample(in: stalled[...], from: 0.5, towardPresented: presented) == nil)
            // A prompt retarget setter cannot conceal movement that starts at
            // or after the original 100ms deadline.
            for delay in [99, 100, 101] {
                let moving = Self.sample(
                    progress: presented ? 0.6 : 0.4, presented: presented,
                    at: requestedAt + .milliseconds(delay)
                )
                let samples = stalled + [moving]
                let advancing = try #require(Self.firstAdvancingSample(
                    in: samples[...], from: 0.5, towardPresented: presented
                ))
                #expect(advancing.timestamp == moving.timestamp)
                #expect(Self.isWithinResponseBudget(advancing, requestedAt: requestedAt) == (delay < 100))
            }
        }
    }

    @Test
    func reversalDeadlineStartsAtRequestAndRejectsPreRequestSamples() {
        let requestedAt = ContinuousClock.now
        let previous = Self.sample(progress: 0.5, presented: false, at: requestedAt - .milliseconds(200))
        let response = Self.sample(progress: 0.6, presented: true, at: requestedAt + .milliseconds(20))
        #expect(!Self.isWithinResponseBudget(previous, requestedAt: requestedAt))
        #expect(Self.isWithinResponseBudget(response, requestedAt: requestedAt))
        #expect(Self.milliseconds(from: previous.timestamp, to: response.timestamp) == 220)
    }

    private static func firstAdvancingSample(
        in samples: ArraySlice<TimedProgressSample>,
        from progress: CGFloat,
        towardPresented: Bool
    ) -> TimedProgressSample? {
        samples.first { sample in
            guard sample.observedShows == towardPresented else { return false }
            let distance = sample.sample.progress - progress
            return towardPresented ? distance > 0.000_001 : distance < -0.000_001
        }
    }

    private static func isWithinResponseBudget(
        _ sample: TimedProgressSample,
        requestedAt: ContinuousClock.Instant
    ) -> Bool {
        sample.timestamp >= requestedAt && sample.timestamp - requestedAt < .milliseconds(100)
    }

    private static func sample(
        progress: CGFloat,
        presented: Bool,
        at timestamp: ContinuousClock.Instant
    ) -> TimedProgressSample {
        TimedProgressSample(
            timestamp: timestamp,
            sample: CommandPaletteTrace.PresentationProgressSample(
                session: 1, isPresented: presented, progress: progress, reduceMotion: false,
                geometry: CommandPaletteVisibilityGeometry.resolve(progress: progress, reduceMotion: false)
            ),
            observedShows: presented,
            observedSession: 1
        )
    }

    private static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Double {
        let value = (end - start).components
        return Double(value.seconds) * 1_000
            + Double(value.attoseconds) / 1_000_000_000_000_000
    }
#endif
}

#if DEBUG
private struct TimedProgressSample {
    let timestamp: ContinuousClock.Instant
    let sample: CommandPaletteTrace.PresentationProgressSample
    let observedShows: Bool?
    let observedSession: Int?
}
#endif
