import CoreGraphics
import Testing
@testable import XTools

/// Pure-value split contract for the paired paper workbench, inherited from
/// the regex page: from the configured content width the two panes share the
/// row equally through a 14pt gap and fill the residual height (280pt pane
/// minimum); below it they stack and halve the band. Floating results are
/// asserted through relationships with a tolerance, not by repeating the
/// implementation's arithmetic verbatim.
@Suite
struct IndexPairWorkbenchLayoutTests {
    private let tolerance: CGFloat = 0.000001

    @Test func belowDefaultThresholdStacksBothPanes() {
        let policy = IndexPairWorkbenchLayoutPolicy()

        #expect(policy.mode(for: 300) == .stacked)
        #expect(policy.mode(for: 719.5) == .stacked)
    }

    @Test func thresholdWidthStartsTheEqualSplit() {
        let policy = IndexPairWorkbenchLayoutPolicy()

        #expect(policy.mode(for: 720) == .horizontal)
        let paneWidth = policy.paneWidth(for: 720)

        #expect(paneWidth > 0)
        // pane + 14pt gap + pane must reassemble the full row width.
        #expect(abs(paneWidth * 2 + IndexPairWorkbenchLayoutPolicy.columnSpacing - 720) < tolerance)
    }

    @Test func wideWindowsKeepHalvesEqual() {
        let policy = IndexPairWorkbenchLayoutPolicy()
        let paneWidth = policy.paneWidth(for: 1000)

        #expect(policy.mode(for: 1000) == .horizontal)
        #expect(paneWidth > policy.paneWidth(for: 720))
        #expect(abs(paneWidth * 2 + IndexPairWorkbenchLayoutPolicy.columnSpacing - 1000) < tolerance)
    }

    @Test func customThresholdShiftsTheSplit() throws {
        let policy = IndexPairWorkbenchLayoutPolicy(threshold: 900)

        #expect(policy.mode(for: 720) == .stacked)
        #expect(policy.mode(for: 900) == .horizontal)
    }

    @Test func contractConstantsStayInheritedFromTheRegexPage() {
        #expect(IndexPairWorkbenchLayoutPolicy.defaultThreshold == 720)
        #expect(IndexPairWorkbenchLayoutPolicy.columnSpacing == 14)
        #expect(IndexPairWorkbenchLayoutPolicy.minimumPaneHeight == 280)
    }
}
