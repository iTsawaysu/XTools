import SwiftUI

// MARK: - IndexPairLayout

/// Lays out an input/output (or source/result, editor/preview) pair so the two
/// panels stay equal width, equal height, and bottom-aligned on wide windows,
/// and stack vertically on narrow windows without distortion. Part of the
/// Index* design system used by the live tool pages.
struct IndexPairLayout<Leading: View, Trailing: View>: View {
    /// Spacing between the two panes, matching the page-level section spacing.
    static var spacing: CGFloat { 14 }

    var collapseWidth: CGFloat = 900
    /// When true the side-by-side panes stretch to fill the height the parent
    /// offers (so input/output panels grow with the window). Default false
    /// keeps every existing caller's natural, content-sized height.
    var fillsHeight = false
    private let leading: Leading
    private let trailing: Trailing

    init(
        collapseWidth: CGFloat = 900,
        fillsHeight: Bool = false,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.collapseWidth = collapseWidth
        self.fillsHeight = fillsHeight
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        IndexResponsivePairLayout(
            collapseWidth: collapseWidth,
            spacing: Self.spacing,
            fillsHeight: fillsHeight
        ) {
            leading
                .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            trailing
                .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct IndexResponsivePairLayout: Layout {
    let collapseWidth: CGFloat
    let spacing: CGFloat
    let fillsHeight: Bool

    private var paneMinWidth: CGFloat {
        max(280, (resolvedCollapseWidth - spacing) / 2)
    }

    /// A zero width was historically used by a few pages to mean “always
    /// side-by-side”. Treat it as the adaptive formatter breakpoint instead:
    /// when the sidebar leaves a narrow content rail, the pair stacks before
    /// either editor becomes unusably small. Callers that need a bespoke
    /// breakpoint still pass an explicit positive value.
    private var resolvedCollapseWidth: CGFloat {
        collapseWidth > 0 ? collapseWidth : ToolMetrics.Breakpoint.pairCollapseFormatter
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard subviews.count >= 2 else { return .zero }

        if usesHorizontalLayout(width: proposal.width) {
            let width = resolvedWidth(proposal.width)
            let paneWidth = horizontalPaneWidth(for: width)
            let paneHeight = fillsHeight ? proposal.height : nil
            let paneProposal = ProposedViewSize(width: paneWidth, height: paneHeight)
            let leadingSize = subviews[0].sizeThatFits(paneProposal)
            let trailingSize = subviews[1].sizeThatFits(paneProposal)
            let naturalHeight = max(leadingSize.height, trailingSize.height)

            return CGSize(
                width: width,
                height: fillsHeight ? max(naturalHeight, proposal.height ?? naturalHeight) : naturalHeight
            )
        }

        let width = resolvedWidth(proposal.width)
        let paneHeight = fillsHeight ? verticalPaneHeight(for: proposal.height) : nil
        let paneProposal = ProposedViewSize(width: width, height: paneHeight)
        let leadingSize = subviews[0].sizeThatFits(paneProposal)
        let trailingSize = subviews[1].sizeThatFits(paneProposal)
        let naturalHeight = leadingSize.height + spacing + trailingSize.height

        if fillsHeight, let proposedHeight = proposal.height, proposedHeight.isFinite {
            return CGSize(width: width, height: max(proposedHeight, naturalHeight))
        }

        return CGSize(width: width, height: naturalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard subviews.count >= 2 else { return }

        if usesHorizontalLayout(width: bounds.width) {
            let paneWidth = horizontalPaneWidth(for: bounds.width)
            // Both panes share one height so the pair stays equal-height and
            // bottom-aligned on wide windows. When `fillsHeight` the pair fills
            // the height the parent offers; otherwise both panes grow to the
            // taller one's natural height — without this, content-sized panes
            // render at their own heights and produce a ragged grid. (Panes opt
            // into filling via `.verticallyFilling()`.)
            let paneHeight: CGFloat
            if fillsHeight {
                paneHeight = bounds.height
            } else {
                let measuringProposal = ProposedViewSize(width: paneWidth, height: nil)
                let h0 = subviews[0].sizeThatFits(measuringProposal).height
                let h1 = subviews[1].sizeThatFits(measuringProposal).height
                paneHeight = max(h0, h1)
            }
            let paneProposal = ProposedViewSize(width: paneWidth, height: paneHeight)
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: paneProposal
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX + paneWidth + spacing, y: bounds.minY),
                anchor: .topLeading,
                proposal: paneProposal
            )
            return
        }

        let paneHeight = fillsHeight ? verticalPaneHeight(for: bounds.height) : nil
        let paneProposal = ProposedViewSize(width: bounds.width, height: paneHeight)
        let leadingHeight = subviews[0].sizeThatFits(paneProposal).height
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: paneProposal
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + (paneHeight ?? leadingHeight) + spacing),
            anchor: .topLeading,
            proposal: paneProposal
        )
    }

    private func usesHorizontalLayout(width: CGFloat?) -> Bool {
        guard let width, width.isFinite else { return true }
        return width >= resolvedCollapseWidth
    }

    private func horizontalPaneWidth(for width: CGFloat) -> CGFloat {
        max(paneMinWidth, (width - spacing) / 2)
    }

    private func resolvedWidth(_ proposedWidth: CGFloat?) -> CGFloat {
        guard let proposedWidth, proposedWidth.isFinite else { return resolvedCollapseWidth }
        return proposedWidth
    }

    private func verticalPaneHeight(for height: CGFloat?) -> CGFloat? {
        guard let height, height.isFinite else { return nil }
        return max(0, (height - spacing) / 2)
    }
}
