import Testing
@testable import XTools

struct ToolMetricsTests {
    @Test func controlHeightLadderStaysOrderedAndUnique() {
        let ladder = [
            ToolMetrics.ControlHeight.compact,
            ToolMetrics.ControlHeight.small,
            ToolMetrics.ControlHeight.action,
            ToolMetrics.ControlHeight.field,
            ToolMetrics.ControlHeight.row,
        ]

        #expect(ladder == [24, 28, 32, 38, 44])
        #expect(Set(ladder).count == ladder.count)
        #expect(ladder == ladder.sorted())
    }
}
