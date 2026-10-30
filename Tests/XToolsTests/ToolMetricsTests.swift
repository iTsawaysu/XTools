import Testing
@testable import XTools

struct ToolMetricsTests {
    @Test func controlHeightLadderStaysOrderedAndUnique() {
        // v9 moved 32pt out of the general ladder and into the primary-CTA
        // exception. The old names remain as compatibility aliases for P2b
        // migration; their values are asserted below.
        let ladder = [
            ToolMetrics.ControlHeight.icon24,
            ToolMetrics.ControlHeight.compact28,
            ToolMetrics.ControlHeight.field38,
            ToolMetrics.ControlHeight.bar44,
        ]

        #expect(ladder == [24, 28, 38, 44])
        #expect(Set(ladder).count == ladder.count)
        #expect(ladder == ladder.sorted())
        #expect(ToolMetrics.ControlHeight.cta32 == 32)

        #expect(ToolMetrics.ControlHeight.compact == ToolMetrics.ControlHeight.icon24)
        #expect(ToolMetrics.ControlHeight.small == ToolMetrics.ControlHeight.compact28)
        #expect(ToolMetrics.ControlHeight.action == ToolMetrics.ControlHeight.cta32)
        #expect(ToolMetrics.ControlHeight.field == ToolMetrics.ControlHeight.field38)
        #expect(ToolMetrics.ControlHeight.row == ToolMetrics.ControlHeight.bar44)
    }

    @Test func spacingTokensStayOnThe4ptGrid() {
        let values = [
            ToolMetrics.Spacing.xs,
            ToolMetrics.Spacing.sm,
            ToolMetrics.Spacing.md,
            ToolMetrics.Spacing.base,
            ToolMetrics.Spacing.lg,
            ToolMetrics.Spacing.xl,
            ToolMetrics.Spacing.xxl,
            ToolMetrics.Spacing.page,
            ToolMetrics.Spacing.panelInset,
            ToolMetrics.Spacing.panelSection,
        ]

        #expect(values == [4, 8, 12, 16, 16, 24, 32, 32, 16, 12])
        #expect(values.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
    }

    @Test func borderWidthsStayTwoTierPlusSelection() {
        #expect(ToolMetrics.BorderWidth.hairline == 0.5)
        #expect(ToolMetrics.BorderWidth.selection == 1)
        #expect(ToolMetrics.BorderWidth.focus == 1.5)
    }
}
