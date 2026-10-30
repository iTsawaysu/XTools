import Foundation
import SwiftUI
@testable import XTools
import Testing

/// 2026-10 审计：真实窗口插值采样段（首挂载全弧、20/50/100ms 三档反转循环、
/// 进度 ≥0.999/≤0.001 边界轮询、定时 toggle 爆发）已整体移出留档至
/// /Users/sun/Downloads/tmp/xtools-tests-archive-2026-10-09/CommandPaletteMotionSamplingTests.swift。
/// 本文件只保留调用产品几何与动效token的断言，不证明真实窗口插值或响应期限。
@Suite(.serialized)
struct CommandPaletteMotionTests {
    @Test
    func visibilityGeometryIsAContinuousFunctionOfProgress() {
        // Check the product geometry across the full progress range.
        // The current palette fades without moving or scaling its native views.
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

    /// v9 fade timing: quick opening, exit closing, no positional travel.
    @Test
    func paletteMotionTokensMatchWave2Prototype() {
        #expect(ToolMotion.PaletteMotion.riseDistance == 0)
        #expect(ToolMotion.PaletteMotion.open == ToolMotion.Curve.standard(duration: ToolMotion.Duration.quick))
        #expect(ToolMotion.PaletteMotion.close == ToolMotion.Curve.standard(duration: ToolMotion.Duration.exit))
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

}
