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
    /// When true (default) side-by-side panes share the taller pane's height,
    /// keeping the pair bottom-aligned. Pages whose right column is a settings
    /// rail pass false: stretching the rail to a tall preview would push its
    /// primary action below the fold.
    var equalizesHeight = true
    /// Lower bound for a side-by-side pane. Callers whose panes stay usable
    /// below the 280pt default (e.g. image comparison cards with capped
    /// preview heights) pass a smaller value together with a matching
    /// collapse width.
    var minimumPaneWidth: CGFloat = 280
    /// Fixed trailing-pane width for settings rails. When set, the leading
    /// pane takes the remaining width instead of splitting the pair evenly;
    /// the rail is capped at 45% of the pair so the leading pane never
    /// collapses into a sliver.
    var trailingWidth: CGFloat? = nil
    private let leading: Leading
    private let trailing: Trailing

    init(
        collapseWidth: CGFloat = 900,
        fillsHeight: Bool = false,
        equalizesHeight: Bool = true,
        minimumPaneWidth: CGFloat = 280,
        trailingWidth: CGFloat? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.collapseWidth = collapseWidth
        self.fillsHeight = fillsHeight
        self.equalizesHeight = equalizesHeight
        self.minimumPaneWidth = minimumPaneWidth
        self.trailingWidth = trailingWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        IndexResponsivePairLayout(
            collapseWidth: collapseWidth,
            spacing: Self.spacing,
            fillsHeight: fillsHeight,
            equalizesHeight: equalizesHeight,
            minimumPaneWidth: minimumPaneWidth,
            trailingWidth: trailingWidth
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
    let equalizesHeight: Bool
    let minimumPaneWidth: CGFloat
    let trailingWidth: CGFloat?

    private var paneMinWidth: CGFloat {
        max(minimumPaneWidth, (resolvedCollapseWidth - spacing) / 2)
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
            let widths = horizontalPaneWidths(for: width)
            let paneHeight = fillsHeight ? proposal.height : nil
            let leadingSize = subviews[0].sizeThatFits(ProposedViewSize(width: widths.leading, height: paneHeight))
            let trailingSize = subviews[1].sizeThatFits(ProposedViewSize(width: widths.trailing, height: paneHeight))
            let naturalHeight = max(leadingSize.height, trailingSize.height)

            return CGSize(
                width: width,
                height: fillsHeight ? max(naturalHeight, proposal.height ?? naturalHeight) : naturalHeight
            )
        }

        let width = resolvedWidth(proposal.width)
        if fillsHeight, let proposedHeight = proposal.height, proposedHeight.isFinite {
            let leadingNatural = subviews[0]
                .sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            let heights = verticalPaneHeights(available: proposedHeight, leadingNatural: leadingNatural)
            return CGSize(width: width, height: max(proposedHeight, heights.leading + spacing + heights.trailing))
        }

        let paneProposal = ProposedViewSize(width: width, height: nil)
        let leadingSize = subviews[0].sizeThatFits(paneProposal)
        let trailingSize = subviews[1].sizeThatFits(paneProposal)
        return CGSize(width: width, height: leadingSize.height + spacing + trailingSize.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard subviews.count >= 2 else { return }

        if usesHorizontalLayout(width: bounds.width) {
            let widths = horizontalPaneWidths(for: bounds.width)
            // Both panes share one height so the pair stays equal-height and
            // bottom-aligned on wide windows. When `fillsHeight` the pair fills
            // the height the parent offers; otherwise both panes grow to the
            // taller one's natural height — without this, content-sized panes
            // render at their own heights and produce a ragged grid. (Panes opt
            // into filling via `.verticallyFilling()`.)
            let h0 = subviews[0].sizeThatFits(ProposedViewSize(width: widths.leading, height: nil)).height
            let h1 = subviews[1].sizeThatFits(ProposedViewSize(width: widths.trailing, height: nil)).height

            let paneHeight: CGFloat
            if fillsHeight {
                paneHeight = bounds.height
            } else {
                paneHeight = equalizesHeight ? max(h0, h1) : 0
            }

            if equalizesHeight || fillsHeight {
                subviews[0].place(
                    at: CGPoint(x: bounds.minX, y: bounds.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: widths.leading, height: paneHeight)
                )
                subviews[1].place(
                    at: CGPoint(x: bounds.minX + widths.leading + spacing, y: bounds.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: widths.trailing, height: paneHeight)
                )
            } else {
                // 各自保持自然高度、顶部对齐：设置栏不被预览卡拉长。
                subviews[0].place(
                    at: CGPoint(x: bounds.minX, y: bounds.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: widths.leading, height: h0)
                )
                subviews[1].place(
                    at: CGPoint(x: bounds.minX + widths.leading + spacing, y: bounds.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: widths.trailing, height: h1)
                )
            }
            return
        }

        if fillsHeight, bounds.height.isFinite {
            // Stacked narrow window: the leading pane keeps its compact
            // natural height (regex controls), the trailing pane takes the
            // rest so the test text stays the largest surface. Splitting the
            // height in half instead leaves the controls padded with empty
            // space and shrinks the editor.
            let leadingNatural = subviews[0]
                .sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            let heights = verticalPaneHeights(available: bounds.height, leadingNatural: leadingNatural)
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: heights.leading)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + heights.leading + spacing),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: heights.trailing)
            )
            return
        }

        let paneProposal = ProposedViewSize(width: bounds.width, height: nil)
        let leadingHeight = subviews[0].sizeThatFits(paneProposal).height
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: paneProposal
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + leadingHeight + spacing),
            anchor: .topLeading,
            proposal: paneProposal
        )
    }

    private func usesHorizontalLayout(width: CGFloat?) -> Bool {
        guard let width, width.isFinite else { return true }
        return width >= resolvedCollapseWidth
    }

    private func horizontalPaneWidths(for width: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let evenPane = max(paneMinWidth, (width - spacing) / 2)
        guard let trailingWidth else {
            return (evenPane, evenPane)
        }
        let trailing = min(max(trailingWidth, 220), width * 0.45)
        return (max(width - spacing - trailing, paneMinWidth), trailing)
    }

    private func resolvedWidth(_ proposedWidth: CGFloat?) -> CGFloat {
        guard let proposedWidth, proposedWidth.isFinite else { return resolvedCollapseWidth }
        return proposedWidth
    }

    private func verticalPaneHeights(available: CGFloat, leadingNatural: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        let minLeading: CGFloat = 132
        let minTrailing: CGFloat = 148
        let maxLeading = max(minLeading, available * 0.55)

        var leading = min(max(leadingNatural, minLeading), maxLeading)
        var trailing = available - leading - spacing
        if trailing < minTrailing {
            trailing = minTrailing
            leading = max(minLeading, available - trailing - spacing)
        }
        return (leading, trailing)
    }
}
