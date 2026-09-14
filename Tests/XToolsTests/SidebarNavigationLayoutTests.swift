@testable import XTools
import CoreGraphics
import Testing

struct SidebarNavigationLayoutTests {
    @Test func layoutUsesUniqueFlatTargetsAndExactDocumentHeight() {
        let entries = Self.entries(isExpanded: true)
        let plan = SidebarNavigationLayout.plan(entries: entries, width: 220)

        #expect(plan.targets.map(\.id) == entries.map(\.id))
        #expect(Set(plan.targets.map(\.id)).count == plan.targets.count)
        #expect(plan.targets.first?.frame.minX == SidebarNavigationLayout.horizontalPadding)
        #expect(plan.targets.allSatisfy {
            $0.frame.width == 220 - SidebarNavigationLayout.horizontalPadding * 2
        })
        #expect(plan.documentHeight == plan.targets.last!.frame.maxY + SidebarNavigationLayout.verticalPadding)
    }

    @Test func collapsedAndExpandedPlansShareIdentityAndStayStacked() {
        let collapsed = SidebarNavigationLayout.plan(
            entries: Self.entries(isExpanded: false),
            width: 220
        )
        let expanded = SidebarNavigationLayout.plan(
            entries: Self.entries(isExpanded: true),
            width: 220
        )

        #expect(collapsed.targets.map(\.id) == expanded.targets.map(\.id))
        #expect(collapsed.documentHeight < expanded.documentHeight)

        for plan in [collapsed, expanded] {
            for pair in zip(plan.targets, plan.targets.dropFirst()) {
                #expect(pair.0.frame.maxY <= pair.1.frame.minY + 0.001)
            }
        }

        // Disclosure content collapses by zeroing height while keeping track identity.
        let collapsedHeights = Dictionary(
            uniqueKeysWithValues: collapsed.targets.map { ($0.id, $0.frame.height) }
        )
        let expandedHeights = Dictionary(
            uniqueKeysWithValues: expanded.targets.map { ($0.id, $0.frame.height) }
        )
        #expect(collapsedHeights["tool.layout-alpha"] == 0)
        #expect(expandedHeights["tool.layout-alpha"] == SidebarMetrics.expandedRowHeight)
        #expect(collapsedHeights["header.category.development"] == expandedHeights["header.category.development"])
    }

    @Test func staleAnimationCompletionCannotFinalizeNewerTarget() {
        var gate = SidebarNavigationAnimationGate()
        let collapse = gate.request(target: .init(
            targets: Self.entries(isExpanded: false).map {
                .init(id: $0.id, minY: 0, height: $0.presentedHeight)
            },
            documentHeight: 54
        ))
        let expandTarget = SidebarNavigationAnimationTarget(
            targets: Self.entries(isExpanded: true).map {
                .init(id: $0.id, minY: 0, height: $0.presentedHeight)
            },
            documentHeight: 126
        )
        let expand = gate.request(target: expandTarget)

        #expect(!gate.accepts(collapse))
        #expect(gate.accepts(expand))

        gate.synchronize(target: expandTarget)
        #expect(!gate.accepts(expand))
    }

    @Test func interactionFinalizationMatchesLatestPresentationTarget() {
        let collapsing = SidebarNavigationTrackInteraction.preparing(targetExpanded: false)
        #expect(!collapsing.isHidden)
        #expect(!collapsing.isInteractionEnabled)
        #expect(!collapsing.areControlsEnabled)
        #expect(!collapsing.acceptsPresentationSelection)
        #expect(collapsing.isAccessibilityHidden)

        let collapsed = SidebarNavigationTrackInteraction.finalized(targetExpanded: false)
        #expect(collapsed.isHidden)
        #expect(!collapsed.isInteractionEnabled)
        #expect(!collapsed.areControlsEnabled)
        #expect(!collapsed.acceptsPresentationSelection)
        #expect(collapsed.isAccessibilityHidden)

        let expanding = SidebarNavigationTrackInteraction.preparing(targetExpanded: true)
        #expect(!expanding.isHidden)
        #expect(!expanding.isInteractionEnabled)
        #expect(expanding.areControlsEnabled)
        #expect(expanding.acceptsPresentationSelection)
        #expect(expanding.isAccessibilityHidden)

        let expanded = SidebarNavigationTrackInteraction.finalized(targetExpanded: true)
        #expect(!expanded.isHidden)
        #expect(expanded.isInteractionEnabled)
        #expect(expanded.areControlsEnabled)
        #expect(!expanded.acceptsPresentationSelection)
        #expect(!expanded.isAccessibilityHidden)
    }

    @Test func presentationHitTestingUsesOnlyVisibleFramesAndPrefersTopmostTarget() {
        let alpha = ToolID(rawValue: "presentation-alpha")
        let beta = ToolID(rawValue: "presentation-beta")
        let targets = [
            SidebarNavigationPresentationHitTarget(
                toolID: alpha,
                frame: CGRect(x: 10, y: 20, width: 180, height: 24)
            ),
            SidebarNavigationPresentationHitTarget(
                toolID: beta,
                frame: CGRect(x: 10, y: 30, width: 180, height: 24)
            ),
        ]

        #expect(
            SidebarNavigationPresentationHitTesting.toolID(
                at: CGPoint(x: 24, y: 25),
                targets: targets
            ) == alpha
        )
        #expect(
            SidebarNavigationPresentationHitTesting.toolID(
                at: CGPoint(x: 24, y: 35),
                targets: targets
            ) == beta
        )
        #expect(
            SidebarNavigationPresentationHitTesting.toolID(
                at: CGPoint(x: 24, y: 60),
                targets: targets
            ) == nil
        )
        #expect(
            SidebarNavigationPresentationHitTesting.toolID(
                at: CGPoint(x: 24, y: 20),
                targets: [
                    SidebarNavigationPresentationHitTarget(
                        toolID: alpha,
                        frame: .zero
                    ),
                ]
            ) == nil
        )
    }

    @Test func scrollAnchorPreservesAbsoluteOriginSmartRevealsAndClampsShrink() {
        let fitting = SidebarNavigationScrollAnchor.capture(
            originY: 0,
            documentHeight: 400,
            viewportHeight: 400
        )
        #expect(fitting.resolvedOriginY(documentHeight: 900, viewportHeight: 400) == 0)

        let undersized = SidebarNavigationScrollAnchor.capture(
            originY: 0,
            documentHeight: 320,
            viewportHeight: 400
        )
        #expect(undersized.resolvedOriginY(documentHeight: 900, viewportHeight: 400) == 0)

        // Middle section expanded while list was scrolled to bottom:
        // MUST keep stationary origin (0px shift) so clicked header does not fly up offscreen!
        let middleSectionExpandedWhileScrolled = SidebarNavigationScrollAnchor.capture(
            originY: 300,
            documentHeight: 700,
            viewportHeight: 400,
            expandedSectionBounds: SidebarNavigationSectionBounds(headerMinY: 320, sectionMaxY: 550)
        )
        #expect(middleSectionExpandedWhileScrolled.resolvedOriginY(documentHeight: 900, viewportHeight: 400) == 300)

        // Ordinary section without bounds keeps origin clamped to max
        let ordinary = SidebarNavigationScrollAnchor.capture(
            originY: 120,
            documentHeight: 700,
            viewportHeight: 400
        )
        #expect(ordinary.resolvedOriginY(documentHeight: 900, viewportHeight: 400) == 120)

        // Bottom section expanded and its children extend beyond viewport:
        // Smart Reveal gently scrolls down to reveal children (up to 550 - 400 = 150)
        let bottomSectionSmartReveal = SidebarNavigationScrollAnchor.capture(
            originY: 50,
            documentHeight: 600,
            viewportHeight: 400,
            expandedSectionBounds: SidebarNavigationSectionBounds(headerMinY: 300, sectionMaxY: 550)
        )
        #expect(bottomSectionSmartReveal.resolvedOriginY(documentHeight: 800, viewportHeight: 400) == 150)

        // Giant section expanded at bottom:
        // Must NEVER scroll section header past top of viewport (guarded by headerMinY - 6pt breathing room = 194)
        let giantSectionHeaderPinnedGuard = SidebarNavigationScrollAnchor.capture(
            originY: 50,
            documentHeight: 600,
            viewportHeight: 400,
            expandedSectionBounds: SidebarNavigationSectionBounds(headerMinY: 200, sectionMaxY: 850)
        )
        #expect(giantSectionHeaderPinnedGuard.resolvedOriginY(documentHeight: 1000, viewportHeight: 400) == 194)

        // Shrinking / collapse smoothly clamps to maximumOriginY without whitespace
        let shrinking = SidebarNavigationScrollAnchor.capture(
            originY: 220,
            documentHeight: 800,
            viewportHeight: 400
        )
        #expect(shrinking.resolvedOriginY(documentHeight: 500, viewportHeight: 400) == 100)
    }

    private static func entries(isExpanded: Bool) -> [SidebarNavigationEntry] {
        SidebarNavigationEntryProjection.entries(
            groups: [ToolNavigationGroup(
                title: "Development",
                systemImage: "hammer",
                section: .category(.development),
                items: [
                    item(.alpha),
                    item(.beta),
                ]
            )],
            isSearchActive: false,
            isSectionExpanded: { _ in isExpanded }
        )
    }

    private static func item(_ id: ToolID) -> ToolNavigationItem {
        ToolNavigationItem(
            id: id,
            title: id.rawValue,
            categoryID: .development,
            systemImage: "gear",
            isFavorite: false,
            section: .category(.development)
        )
    }
}

private extension ToolID {
    static let alpha = ToolID(rawValue: "layout-alpha")
    static let beta = ToolID(rawValue: "layout-beta")
}
