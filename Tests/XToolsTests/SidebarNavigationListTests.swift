import AppKit
@testable import XTools
import SwiftUI
import Testing

struct SidebarNavigationListTests {
    @Test @MainActor func coordinatorOwnsOneFlippedDocumentAndReusesToolTrackAcrossFavoriteMigration() throws {
        let coordinator = SidebarNavigationListCoordinator()
        let scrollView = coordinator.makeScrollView()
        let beforeEntries = Self.entries(
            groups: [Self.group(section: .category(.development), items: [Self.alpha, Self.beta])]
        )
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: beforeEntries, favoriteOrder: [])
        )

        #expect(scrollView.documentView === coordinator.documentView)
        #expect(coordinator.documentView.isFlipped)
        let before = try #require(coordinator.cachedTrackObjectIdentifier(for: "tool.list-alpha"))

        let afterEntries = Self.entries(groups: [
            Self.group(section: .favorites, items: [Self.favoriteAlpha]),
            Self.group(section: .category(.development), items: [Self.beta]),
        ])
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: afterEntries, favoriteOrder: [.alpha])
        )

        let after = try #require(coordinator.cachedTrackObjectIdentifier(for: "tool.list-alpha"))
        #expect(after == before)
        #expect(coordinator.activeTrackIDs.filter { $0 == "tool.list-alpha" }.count == 1)
        #expect(
            coordinator.documentView.subviews.compactMap {
                ($0 as? SidebarNavigationTrackView)?.trackID
            } == afterEntries.map(\.id)
        )
    }

    @Test @MainActor func favoriteMigrationReconcilesHoverToCurrentToolGeometry() throws {
        let pointer = SidebarPointerLocationBox()
        let coordinator = SidebarNavigationListCoordinator(
            pointerLocationProvider: { _ in pointer.point }
        )
        let scrollView = coordinator.makeScrollView()
        let beforeEntries = Self.entries(
            groups: [Self.group(section: .category(.development), items: [Self.alpha, Self.beta])]
        )
        pointer.point = Self.center(of: "tool.list-alpha", in: beforeEntries)

        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: beforeEntries, favoriteOrder: [])
        )

        let beforeTrack = try #require(
            coordinator.cachedTrackObjectIdentifier(for: "tool.list-alpha")
        )
        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == true)
        #expect(coordinator.debugTrackState(for: "tool.list-beta")?.isHovered == false)

        let afterEntries = Self.entries(groups: [
            Self.group(section: .favorites, items: [Self.favoriteAlpha]),
            Self.group(section: .category(.development), items: [Self.beta]),
        ])
        pointer.point = Self.center(of: "tool.list-alpha", in: afterEntries)
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: afterEntries, favoriteOrder: [.alpha])
        )

        #expect(
            coordinator.cachedTrackObjectIdentifier(for: "tool.list-alpha") == beforeTrack
        )
        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == true)
        #expect(coordinator.debugTrackState(for: "tool.list-beta")?.isHovered == false)

        pointer.point = Self.center(of: "tool.list-beta", in: afterEntries)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == false)
        #expect(coordinator.debugTrackState(for: "tool.list-beta")?.isHovered == true)

        pointer.point = Self.center(of: "tool.list-alpha", in: afterEntries)
        scrollView.setFrameSize(CGSize(width: 260, height: 600))
        scrollView.layoutSubtreeIfNeeded()
        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == true)
        #expect(coordinator.debugTrackState(for: "tool.list-beta")?.isHovered == false)

        coordinator.updatePointerLocation(nil)
        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == false)
        #expect(coordinator.debugTrackState(for: "tool.list-beta")?.isHovered == false)
    }

    @Test @MainActor func favoriteMigrationReconcilesWhenFavoritesAlreadyContainAnotherTool() throws {
        let pointer = SidebarPointerLocationBox()
        let coordinator = SidebarNavigationListCoordinator(
            pointerLocationProvider: { _ in pointer.point }
        )
        let scrollView = coordinator.makeScrollView()
        let beforeEntries = Self.entries(groups: [
            Self.group(section: .favorites, items: [Self.favoriteBeta]),
            Self.group(section: .category(.development), items: [Self.alpha]),
        ])
        pointer.point = Self.center(of: "tool.list-alpha", in: beforeEntries)
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: beforeEntries, favoriteOrder: [.beta])
        )
        let beforeTrack = try #require(
            coordinator.cachedTrackObjectIdentifier(for: "tool.list-alpha")
        )
        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == true)

        let afterEntries = Self.entries(groups: [
            Self.group(
                section: .favorites,
                items: [Self.favoriteBeta, Self.favoriteAlpha]
            ),
        ])
        pointer.point = Self.center(of: "tool.list-alpha", in: afterEntries)
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(
                entries: afterEntries,
                favoriteOrder: [.beta, .alpha]
            )
        )

        #expect(
            coordinator.cachedTrackObjectIdentifier(for: "tool.list-alpha") == beforeTrack
        )
        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == true)
        #expect(coordinator.debugTrackState(for: "tool.list-beta")?.isHovered == false)
    }

    @Test @MainActor func favoriteAnimationCompletionReconcilesStationaryPointerAtFinalFrame() async throws {
        let pointer = SidebarPointerLocationBox()
        let coordinator = SidebarNavigationListCoordinator(
            pointerLocationProvider: { _ in pointer.point }
        )
        let scrollView = coordinator.makeScrollView()
        let beforeEntries = Self.entries(
            groups: [Self.group(section: .category(.development), items: [Self.alpha, Self.beta])]
        )
        pointer.point = Self.center(of: "tool.list-alpha", in: beforeEntries)
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: beforeEntries, favoriteOrder: [])
        )
        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == true)

        let afterEntries = Self.entries(groups: [
            Self.group(section: .favorites, items: [Self.favoriteAlpha]),
            Self.group(section: .category(.development), items: [Self.beta]),
        ])
        let finalPoint = Self.center(of: "tool.list-alpha", in: afterEntries)
        pointer.point = nil
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(
                entries: afterEntries,
                favoriteOrder: [.alpha],
                reduceMotion: false
            )
        )
        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == false)

        pointer.point = finalPoint
        try await Self.waitUntil {
            coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == true
        }
        #expect(coordinator.debugTrackState(for: "tool.list-beta")?.isHovered == false)
    }

    @Test @MainActor func collapsedOrInactiveTracksCannotRetainHover() throws {
        let pointer = SidebarPointerLocationBox()
        let coordinator = SidebarNavigationListCoordinator(
            pointerLocationProvider: { _ in pointer.point }
        )
        let scrollView = coordinator.makeScrollView()
        let group = Self.group(section: .category(.development), items: [Self.alpha])
        let expanded = Self.entries(groups: [group])
        pointer.point = Self.center(of: "tool.list-alpha", in: expanded)
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: expanded, reduceMotion: true)
        )
        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == true)

        let collapsed = SidebarNavigationEntryProjection.entries(
            groups: [group],
            isSearchActive: false,
            isSectionExpanded: { _ in false }
        )
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: collapsed, reduceMotion: true)
        )

        let state = try #require(coordinator.debugTrackState(for: "tool.list-alpha"))
        #expect(state.isHidden)
        #expect(!state.isInteractionEnabled)
        #expect(!state.isHovered)
    }

    @Test @MainActor func collapsedToolTrackKeepsNaturalContentGeometry() throws {
        let coordinator = SidebarNavigationListCoordinator()
        let scrollView = coordinator.makeScrollView()
        let collapsed = SidebarNavigationEntryProjection.entries(
            groups: [Self.group(section: .category(.development), items: [Self.alpha])],
            isSearchActive: false,
            isSectionExpanded: { _ in false }
        )

        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: collapsed, reduceMotion: true)
        )

        let state = try #require(coordinator.debugTrackState(for: "tool.list-alpha"))
        #expect(state.frameHeight == 0)
        #expect(state.contentHeight == SidebarMetrics.expandedRowHeight)
        #expect(state.isHidden)
        #expect(!state.isInteractionEnabled)
        #expect(state.isAccessibilityHidden)
    }

    @Test @MainActor func documentReplacesItsVisiblePointerTrackingArea() {
        let documentView = SidebarNavigationDocumentView()
        documentView.frame = CGRect(x: 0, y: 0, width: 220, height: 400)

        documentView.updateTrackingAreas()
        documentView.updateTrackingAreas()

        let pointerAreas = documentView.trackingAreas.filter { area in
            area.options.contains(.mouseEnteredAndExited)
                && area.options.contains(.mouseMoved)
                && area.options.contains(.activeInKeyWindow)
                && area.options.contains(.inVisibleRect)
        }
        #expect(pointerAreas.count == 1)
        #expect(pointerAreas.first?.owner === documentView)
    }

    @Test @MainActor func unchangedPresentationShortCircuitsWhileSelectionStillRewrites() throws {
        let coordinator = SidebarNavigationListCoordinator()
        let scrollView = coordinator.makeScrollView()
        let entries = Self.entries(
            groups: [Self.group(section: .category(.development), items: [Self.alpha, Self.beta])]
        )

        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(
                entries: entries,
                selectedToolID: .alpha,
                reduceMotion: true
            )
        )
        let before = try #require(coordinator.cachedTrackObjectIdentifier(for: "tool.list-alpha"))
        let beforeIDs = coordinator.activeTrackIDs
        let beforeAlpha = try #require(coordinator.debugTrackState(for: "tool.list-alpha"))

        // Identical presentation-driving inputs must skip full reconcile/host rewrite.
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(
                entries: entries,
                selectedToolID: .alpha,
                reduceMotion: true
            )
        )
        #expect(coordinator.cachedTrackObjectIdentifier(for: "tool.list-alpha") == before)
        #expect(coordinator.activeTrackIDs == beforeIDs)
        let unchangedAlpha = try #require(coordinator.debugTrackState(for: "tool.list-alpha"))
        #expect(unchangedAlpha.frameHeight == beforeAlpha.frameHeight)
        #expect(unchangedAlpha.isInteractionEnabled == beforeAlpha.isInteractionEnabled)

        // Selection still has to rewrite hosted content without destroying track identity.
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(
                entries: entries,
                selectedToolID: .beta,
                reduceMotion: true
            )
        )
        #expect(coordinator.cachedTrackObjectIdentifier(for: "tool.list-alpha") == before)
        #expect(coordinator.activeTrackIDs == beforeIDs)
        let afterSelection = try #require(coordinator.debugTrackState(for: "tool.list-alpha"))
        #expect(afterSelection.frameHeight == beforeAlpha.frameHeight)
        #expect(afterSelection.isInteractionEnabled)
    }

    @Test @MainActor func collapsePreparationDisablesHostedControlsAndAccessibilityImmediately() {
        let button = NSButton(title: "Alpha", target: nil, action: nil)
        let track = SidebarNavigationTrackView(
            trackID: "tool.list-alpha",
            groupID: "category.development",
            kind: .tool(.alpha),
            naturalContentHeight: SidebarMetrics.expandedRowHeight,
            hostedContentView: button
        )
        track.frame = CGRect(x: 0, y: 0, width: 200, height: 0)
        track.layoutSubtreeIfNeeded()

        track.applyInteraction(.preparing(targetExpanded: false))

        #expect(!track.isHidden)
        #expect(!button.isEnabled)
        #expect(button.isAccessibilityHidden())
        #expect(track.hitTest(NSPoint(x: 2, y: 2)) == nil)
        #expect(track.debugState.contentHeight == SidebarMetrics.expandedRowHeight)
    }

    @Test @MainActor func expansionPreparationKeepsHostedControlsEnabledWhileStandardHitTestingWaits() {
        let button = NSButton(title: "Alpha", target: nil, action: nil)
        let track = SidebarNavigationTrackView(
            trackID: "tool.list-alpha",
            groupID: "category.development",
            kind: .tool(.alpha),
            naturalContentHeight: SidebarMetrics.expandedRowHeight,
            hostedContentView: button
        )
        track.frame = CGRect(
            x: 0,
            y: 0,
            width: 200,
            height: SidebarMetrics.expandedRowHeight
        )
        track.layoutSubtreeIfNeeded()

        track.applyInteraction(.preparing(targetExpanded: true))

        #expect(!track.isHidden)
        #expect(button.isEnabled)
        #expect(button.isAccessibilityHidden())
        #expect(track.hitTest(NSPoint(x: 2, y: 2)) == nil)
        #expect(track.debugState.acceptsPresentationSelection)
    }

    @Test @MainActor func presentationSelectionLandsLatestExpansionAndSelectsExactlyOnce() throws {
        let coordinator = SidebarNavigationListCoordinator()
        let scrollView = coordinator.makeScrollView()
        let group = Self.group(section: .category(.development), items: [Self.alpha])
        let collapsed = SidebarNavigationEntryProjection.entries(
            groups: [group],
            isSearchActive: false,
            isSectionExpanded: { _ in false }
        )
        let expanded = Self.entries(groups: [group])
        var selections: [ToolID] = []

        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: collapsed, reduceMotion: true)
        )
        #expect(!coordinator.activatePresentationTool(.alpha))

        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(
                entries: expanded,
                reduceMotion: false,
                onSelectTool: { selections.append($0) }
            )
        )

        let preparing = try #require(
            coordinator.debugTrackState(for: "tool.list-alpha")
        )
        #expect(!preparing.isInteractionEnabled)
        #expect(preparing.areHostedControlsEnabled)
        #expect(preparing.acceptsPresentationSelection)

        #expect(coordinator.activatePresentationTool(.alpha))
        #expect(selections == [.alpha])

        let landed = try #require(
            coordinator.debugTrackState(for: "tool.list-alpha")
        )
        #expect(landed.frameHeight == SidebarMetrics.expandedRowHeight)
        #expect(landed.isInteractionEnabled)
        #expect(landed.areHostedControlsEnabled)
        #expect(!landed.isAccessibilityHidden)
        #expect(!landed.acceptsPresentationSelection)
        #expect(!coordinator.activatePresentationTool(.alpha))
        #expect(selections == [.alpha])
    }

    @Test @MainActor func keyboardSelectionLandsActiveExpansionBeforeMoving() throws {
        let coordinator = SidebarNavigationListCoordinator()
        let scrollView = coordinator.makeScrollView()
        let group = Self.group(
            section: .category(.development),
            items: [Self.alpha, Self.beta]
        )
        let collapsed = SidebarNavigationEntryProjection.entries(
            groups: [group],
            isSearchActive: false,
            isSectionExpanded: { _ in false }
        )
        let expanded = Self.entries(groups: [group])
        var selections: [ToolID] = []

        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: collapsed, reduceMotion: true)
        )
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(
                entries: expanded,
                reduceMotion: false,
                onSelectTool: { selections.append($0) }
            )
        )

        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 125
        ))
        coordinator.documentView.keyDown(with: event)

        #expect(selections == [.alpha])
        let landed = try #require(
            coordinator.debugTrackState(for: "tool.list-alpha")
        )
        #expect(landed.isInteractionEnabled)
        #expect(!landed.isAccessibilityHidden)
        #expect(!landed.acceptsPresentationSelection)
    }

    @Test @MainActor func tripleToggleFinishesAtLatestTargetAndReduceMotionLandsImmediately() async throws {
        let coordinator = SidebarNavigationListCoordinator()
        let scrollView = coordinator.makeScrollView()
        let expanded = Self.entries(
            groups: [Self.group(section: .category(.development), items: [Self.alpha])]
        )
        let collapsed = SidebarNavigationEntryProjection.entries(
            groups: [Self.group(section: .category(.development), items: [Self.alpha])],
            isSearchActive: false,
            isSectionExpanded: { _ in false }
        )

        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: expanded, reduceMotion: true)
        )
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: collapsed, reduceMotion: false)
        )
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: expanded, reduceMotion: false)
        )
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: collapsed, reduceMotion: false)
        )

        try await Self.waitUntil {
            coordinator.debugTrackState(for: "tool.list-alpha")?.isHidden == true
        }
        let finalCollapsed = try #require(
            coordinator.debugTrackState(for: "tool.list-alpha")
        )
        #expect(finalCollapsed.frameHeight == 0)
        #expect(finalCollapsed.isHidden)
        #expect(!finalCollapsed.isInteractionEnabled)

        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: expanded, reduceMotion: false)
        )
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: expanded, reduceMotion: true)
        )

        let reducedMotionLanding = try #require(
            coordinator.debugTrackState(for: "tool.list-alpha")
        )
        #expect(reducedMotionLanding.frameHeight == SidebarMetrics.expandedRowHeight)
        #expect(!reducedMotionLanding.isHidden)
        #expect(reducedMotionLanding.isInteractionEnabled)
        #expect(!reducedMotionLanding.isAccessibilityHidden)
    }

    @Test @MainActor func searchForcesImmediateExpansionThenRestoresPersistedCollapse() throws {
        let coordinator = SidebarNavigationListCoordinator()
        let scrollView = coordinator.makeScrollView()
        let group = Self.group(section: .category(.development), items: [Self.alpha])
        let collapsed = SidebarNavigationEntryProjection.entries(
            groups: [group],
            isSearchActive: false,
            isSectionExpanded: { _ in false }
        )
        let searching = SidebarNavigationEntryProjection.entries(
            groups: [group],
            isSearchActive: true,
            isSectionExpanded: { _ in false }
        )

        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: collapsed, reduceMotion: false)
        )
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(
                entries: searching,
                isSearchActive: true,
                reduceMotion: false
            )
        )
        let searchingState = try #require(
            coordinator.debugTrackState(for: "tool.list-alpha")
        )
        #expect(searchingState.frameHeight == SidebarMetrics.expandedRowHeight)
        #expect(searchingState.isInteractionEnabled)

        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: collapsed, reduceMotion: false)
        )
        let restored = try #require(
            coordinator.debugTrackState(for: "tool.list-alpha")
        )
        #expect(restored.frameHeight == 0)
        #expect(restored.isHidden)
        #expect(!restored.isInteractionEnabled)
    }

    private static func configuration(
        entries: [SidebarNavigationEntry],
        favoriteOrder: [ToolID] = [],
        selectedToolID: ToolID? = nil,
        isSearchActive: Bool = false,
        reduceMotion: Bool = true,
        onSelectTool: @escaping (ToolID) -> Void = { _ in }
    ) -> SidebarNavigationListConfiguration {
        SidebarNavigationListConfiguration(
            entries: entries,
            selectedToolID: selectedToolID,
            selectedSection: nil,
            favoriteOrder: favoriteOrder,
            isSearchActive: isSearchActive,
            reduceMotion: reduceMotion,
            colorScheme: .dark,
            onSelectTool: onSelectTool,
            onToggleFavorite: { _ in },
            onToggleSection: { _ in }
        )
    }

    @MainActor
    private static func center(
        of trackID: String,
        in entries: [SidebarNavigationEntry]
    ) -> CGPoint {
        let frame = frame(of: trackID, in: entries)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    @MainActor
    private static func frame(
        of trackID: String,
        in entries: [SidebarNavigationEntry]
    ) -> CGRect {
        let plan = SidebarNavigationLayout.plan(
            entries: entries,
            width: SidebarView.idealWidth
        )
        return plan.targets.first(where: { $0.id == trackID })?.frame ?? .null
    }

    private static func entries(groups: [ToolNavigationGroup]) -> [SidebarNavigationEntry] {
        SidebarNavigationEntryProjection.entries(
            groups: groups,
            isSearchActive: false,
            isSectionExpanded: { _ in true }
        )
    }

    @MainActor
    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private static var alpha: ToolNavigationItem {
        item(.alpha, isFavorite: false, section: .category(.development))
    }

    private static var favoriteAlpha: ToolNavigationItem {
        item(.alpha, isFavorite: true, section: .favorites)
    }

    private static var beta: ToolNavigationItem {
        item(.beta, isFavorite: false, section: .category(.development))
    }

    private static var favoriteBeta: ToolNavigationItem {
        item(.beta, isFavorite: true, section: .favorites)
    }

    private static func group(
        section: ToolNavigationSection,
        items: [ToolNavigationItem]
    ) -> ToolNavigationGroup {
        ToolNavigationGroup(
            title: section == .favorites ? "收藏" : "Development",
            systemImage: section == .favorites ? "star.fill" : "hammer",
            section: section,
            items: items
        )
    }

    private static func item(
        _ id: ToolID,
        isFavorite: Bool,
        section: ToolNavigationSection
    ) -> ToolNavigationItem {
        ToolNavigationItem(
            id: id,
            title: id.rawValue,
            categoryID: .development,
            systemImage: "gear",
            isFavorite: isFavorite,
            section: section
        )
    }
}

@MainActor
private final class SidebarPointerLocationBox {
    var point: CGPoint?
}

private extension ToolID {
    static let alpha = ToolID(rawValue: "list-alpha")
    static let beta = ToolID(rawValue: "list-beta")
}
