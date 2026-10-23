import CoreGraphics
import Testing
@testable import XTools

/// 弹性参数区换行规划纯数学契约（design.md §2 / §9）：给定可用宽度与各
/// 控件理想宽度 → 行分组。规则与承载渲染的 `IndexFlowLayout` 一致——
/// 放不下就换行、行内间距计入、恰好占满不换行、超宽控件独占一行不丢弃；
/// 结果按输入顺序连续覆盖所有下标（硬规则：永不横向滚动，
/// PRD AC「RegexTester 全部预设无横向滚动、无折叠后门」的数学基础）。
/// 纯数值断言，风格对齐布局策略测试。
@Suite
struct WorkbenchParameterFlowPlanningTests {
    @Test func emptyInputProducesNoRows() {
        #expect(WorkbenchParameterFlowPlanning.rows(
            idealWidths: [],
            availableWidth: 400,
            spacing: 12
        ).isEmpty)
    }

    @Test func singleFittingItemTakesOneRow() {
        let rows = WorkbenchParameterFlowPlanning.rows(
            idealWidths: [120],
            availableWidth: 400,
            spacing: 12
        )
        #expect(rows == [0..<1])
    }

    @Test func itemsWrapOntoNewLinesInsteadOfOverflowing() {
        // 100 + 12 + 100 = 212 ≤ 250；212 + 12 + 100 = 324 > 250 → 换行。
        let rows = WorkbenchParameterFlowPlanning.rows(
            idealWidths: [100, 100, 100],
            availableWidth: 250,
            spacing: 12
        )
        #expect(rows == [0..<2, 2..<3])
    }

    @Test func rowsCoverEveryIndexExactlyOnceInOrder() {
        let idealWidths: [CGFloat] = [80, 300, 90, 40, 260, 120]
        let rows = WorkbenchParameterFlowPlanning.rows(
            idealWidths: idealWidths,
            availableWidth: 360,
            spacing: 12
        )

        var seen: [Int] = []
        for row in rows {
            #expect(!row.isEmpty)
            seen.append(contentsOf: row)
        }
        #expect(seen == Array(idealWidths.indices))
    }

    @Test func exactFitStaysOnTheSameLine() {
        // 50 + 10 + 40 = 100，恰好占满：规则用严格大于判定溢出，不换行。
        let rows = WorkbenchParameterFlowPlanning.rows(
            idealWidths: [50, 40],
            availableWidth: 100,
            spacing: 10
        )
        #expect(rows == [0..<2])
    }

    @Test func spacingCountsTowardTheLineBudget() {
        // 50 + 10 + 50 = 110 > 100 → 分两行；预算放宽到 110 又回到一行。
        #expect(WorkbenchParameterFlowPlanning.rows(
            idealWidths: [50, 50],
            availableWidth: 100,
            spacing: 10
        ) == [0..<1, 1..<2])
        #expect(WorkbenchParameterFlowPlanning.rows(
            idealWidths: [50, 50],
            availableWidth: 110,
            spacing: 10
        ) == [0..<2])
    }

    @Test func oversizedItemKeepsItsOwnRowAndIsNeverDropped() {
        // 单个控件宽于可用宽度：独占一行（不丢弃、不横向滚动），其后项换行继续。
        let rows = WorkbenchParameterFlowPlanning.rows(
            idealWidths: [40, 500, 40],
            availableWidth: 300,
            spacing: 12
        )
        #expect(rows == [0..<1, 1..<2, 2..<3])
    }
}
