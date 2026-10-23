import CoreGraphics
import Testing
@testable import XTools

/// 对等双栏分栏策略的阈值参数契约（design.md §3 / §9）：新壳
/// `WorkbenchIOPairSplitPolicy` 的两种策略由共享 internal 纯数值类型
/// （`IndexPairWorkbenchLayoutPolicy` / `IndexFileWorkbenchLayoutPolicy`）
/// 承载，默认值必须与旧壳常量完全一致——旧壳继续用旧策略不受影响。
/// 风格对齐 `IndexFileWorkbenchLayoutTests` / `IndexPairWorkbenchLayoutTests`
/// （关系断言 + 容差，不复述实现的算术）。
@Suite
struct WorkbenchIOPairSplitPolicyTests {
    private let tolerance: CGFloat = 0.000001

    // MARK: - 默认值等价旧策略

    @Test func defaultPolicyIsTheEqualPairContract() throws {
        #expect(WorkbenchIOPairSplitPolicy.default == .pairEqual(threshold: 720))
        #expect(WorkbenchIOPairSplitPolicy.default == WorkbenchIOPairSplitPolicy.pairEqual(
            threshold: IndexPairWorkbenchLayoutPolicy.defaultThreshold
        ))

        let pairPolicy = try #require(WorkbenchIOPairSplitPolicy.default.pairPolicy)
        #expect(pairPolicy.threshold == IndexPairWorkbenchLayoutPolicy.defaultThreshold)
        #expect(WorkbenchIOPairSplitPolicy.default.filePolicy == nil)
    }

    @Test func filePolicyKeepsTheInheritedBase64FileContract() throws {
        let policy = WorkbenchIOPairSplitPolicy.fileAsymmetric

        #expect(policy.pairPolicy == nil)
        let filePolicy = try #require(policy.filePolicy)
        // 与旧壳同一类型、同一常量（两侧引用同一定义）。
        #expect(filePolicy == IndexFileWorkbenchLayoutPolicy())
        #expect(IndexFileWorkbenchLayoutPolicy.minimumHorizontalWidth == 900)
        #expect(IndexFileWorkbenchLayoutPolicy.leadingWeight == 1)
        #expect(IndexFileWorkbenchLayoutPolicy.trailingWeight == 1.05)
        #expect(IndexFileWorkbenchLayoutPolicy.minimumHorizontalHeight == 398)
        #expect(IndexFileWorkbenchLayoutPolicy.minimumStackedPaneHeight == 280)
    }

    // MARK: - 等宽契约阈值参数化

    @Test func pairEqualFollowsTheSharedPairMath() throws {
        let policy = WorkbenchIOPairSplitPolicy.default
        let pairPolicy = try #require(policy.pairPolicy)

        // 阈值下堆叠、阈值起等宽分栏（旧 pair 契约数学原样生效）。
        #expect(pairPolicy.mode(for: 719.5) == .stacked)
        #expect(pairPolicy.mode(for: 720) == .horizontal)

        let paneWidth = pairPolicy.paneWidth(for: 720)
        #expect(paneWidth > 0)
        #expect(abs(paneWidth * 2 + IndexPairWorkbenchLayoutPolicy.columnSpacing - 720) < tolerance)
    }

    @Test func customThresholdShiftsTheEqualSplit() throws {
        let policy = WorkbenchIOPairSplitPolicy.pairEqual(threshold: 900)
        let pairPolicy = try #require(policy.pairPolicy)

        #expect(pairPolicy.mode(for: 720) == .stacked)
        #expect(pairPolicy.mode(for: 900) == .horizontal)
    }

    // MARK: - 文件契约阈值行为（新旧同一定义的直接证据）

    @Test func filePolicyReassemblesTheRowBelowAndAboveTheSplit() throws {
        let filePolicy = try #require(WorkbenchIOPairSplitPolicy.fileAsymmetric.filePolicy)

        #expect(filePolicy.mode(for: 899.5) == .stacked)
        #expect(filePolicy.columnWidths(for: 899.5) == nil)

        let widths = try #require(filePolicy.columnWidths(for: 1200))
        #expect(abs(widths.trailing - widths.leading * 1.05) < tolerance)
        #expect(
            abs(widths.leading + widths.trailing + IndexFileWorkbenchLayoutPolicy.columnSpacing - 1200)
                < tolerance
        )
    }
}
