import CoreGraphics
import Testing
@testable import XTools

/// Pure-value split contract inherited from the Base64 file page (now owned by
/// the shared file workbench shell): below 900pt the two panes stack with a
/// 280pt floor each; from 900pt they share the row through a 14pt gap in a
/// `1 : 1.05` ratio and the horizontal row keeps a 398pt minimum height.
/// Floating results are asserted through relationships with a tolerance, not
/// by repeating the implementation's arithmetic verbatim.
@Suite
struct IndexFileWorkbenchLayoutTests {
    private let tolerance: CGFloat = 0.000001

    @Test func belowThresholdStacksBothPanes() {
        let policy = IndexFileWorkbenchLayoutPolicy()

        #expect(policy.mode(for: 680) == .stacked)
        #expect(policy.columnWidths(for: 680) == nil)
        #expect(policy.mode(for: 899.5) == .stacked)
        #expect(policy.columnWidths(for: 899.5) == nil)
    }

    @Test func thresholdWidthStartsTheHorizontalSplit() throws {
        let policy = IndexFileWorkbenchLayoutPolicy()
        let widths = try #require(policy.columnWidths(for: 900))

        #expect(policy.mode(for: 900) == .horizontal)
        #expect(widths.leading > 0)
        // leading + 14pt gap + trailing must reassemble the full row width.
        #expect(abs(widths.leading + IndexFileWorkbenchLayoutPolicy.columnSpacing + widths.trailing - 900) < tolerance)
    }

    @Test func widerWindowsKeepGrowingBothColumns() throws {
        let policy = IndexFileWorkbenchLayoutPolicy()
        let thresholdWidths = try #require(policy.columnWidths(for: 900))
        let widths = try #require(policy.columnWidths(for: 920))

        #expect(policy.mode(for: 920) == .horizontal)
        #expect(widths.leading > thresholdWidths.leading)
        #expect(widths.trailing > thresholdWidths.trailing)
        #expect(abs(widths.leading + IndexFileWorkbenchLayoutPolicy.columnSpacing + widths.trailing - 920) < tolerance)
    }

    @Test func trailingColumnTakesThe105PercentShare() throws {
        let policy = IndexFileWorkbenchLayoutPolicy()
        let widths = try #require(policy.columnWidths(for: 1200))

        #expect(abs(widths.trailing - widths.leading * 1.05) < tolerance)
        #expect(abs(widths.leading + widths.trailing + IndexFileWorkbenchLayoutPolicy.columnSpacing - 1200) < tolerance)
    }

    @Test func contractConstantsStayInheritedFromTheBase64FilePage() {
        #expect(IndexFileWorkbenchLayoutPolicy.minimumHorizontalWidth == 900)
        #expect(IndexFileWorkbenchLayoutPolicy.columnSpacing == 14)
        #expect(IndexFileWorkbenchLayoutPolicy.leadingWeight == 1)
        #expect(IndexFileWorkbenchLayoutPolicy.trailingWeight == 1.05)
        #expect(IndexFileWorkbenchLayoutPolicy.minimumHorizontalHeight == 398)
        #expect(IndexFileWorkbenchLayoutPolicy.minimumStackedPaneHeight == 280)
    }
}
