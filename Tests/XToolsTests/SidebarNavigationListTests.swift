import AppKit
import Foundation
@testable import XTools
import SwiftUI
import Testing

struct SidebarNavigationListTests {
    @Test @MainActor func sidebarCoordinatorPerformanceBenchmark() {
        guard ProcessInfo.processInfo.environment["TOOLS_SIDEBAR_BENCHMARK"] == "1" else {
            return
        }

        SidebarNavigationCoordinatorPerformanceBenchmark.run()
    }

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

    @Test @MainActor func hoverSkipsTrailingSpacingAndCollapsedTracks() throws {
        let pointer = SidebarPointerLocationBox()
        let coordinator = SidebarNavigationListCoordinator(
            pointerLocationProvider: { _ in pointer.point }
        )
        let scrollView = coordinator.makeScrollView()
        let expandedGroup = Self.group(
            section: .category(.development),
            items: [Self.alpha]
        )
        let collapsedGroup = Self.group(
            section: .category(.utility),
            items: [Self.beta]
        )
        let entries = SidebarNavigationEntryProjection.entries(
            groups: [expandedGroup, collapsedGroup],
            isSearchActive: false,
            isSectionExpanded: { section in section == .category(.development) }
        )
        pointer.point = Self.center(of: "tool.list-alpha", in: entries)

        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: entries, reduceMotion: true)
        )

        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == true)
        #expect(coordinator.debugTrackState(for: "tool.list-beta")?.isHovered == false)
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

    @Test @MainActor func scrollViewAndDocumentViewConfigureFullLayerBackingAndPredominantScrolling() {
        let coordinator = SidebarNavigationListCoordinator()
        let scrollView = coordinator.makeScrollView()

        #expect(scrollView.wantsLayer)
        #expect(scrollView.contentView.wantsLayer)
        #expect(coordinator.documentView.wantsLayer)
        #expect(coordinator.documentView.layerContentsRedrawPolicy == .onSetNeedsDisplay)
        #expect(scrollView.usesPredominantAxisScrolling)
        #expect(scrollView.scrollerStyle == .overlay)
    }

    @Test @MainActor func liveScrollingSuspendsHoverReconciliationUntilScrollEnds() throws {
        let pointer = SidebarPointerLocationBox()
        let coordinator = SidebarNavigationListCoordinator(
            pointerLocationProvider: { _ in pointer.point }
        )
        let scrollView = coordinator.makeScrollView()
        let entries = Self.entries(
            groups: [Self.group(section: .category(.development), items: [Self.alpha, Self.beta])]
        )
        pointer.point = Self.center(of: "tool.list-alpha", in: entries)
        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: entries, favoriteOrder: [])
        )
        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == true)
        #expect(coordinator.debugTrackState(for: "tool.list-beta")?.isHovered == false)

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        guard let customScrollView = scrollView as? SidebarNavigationScrollView else {
            Issue.record("scrollView must be SidebarNavigationScrollView")
            return
        }
        #expect(customScrollView.isLiveScrolling)

        pointer.point = Self.center(of: "tool.list-beta", in: entries)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == true)
        #expect(coordinator.debugTrackState(for: "tool.list-beta")?.isHovered == false)

        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )
        #expect(!customScrollView.isLiveScrolling)
        #expect(coordinator.debugTrackState(for: "tool.list-alpha")?.isHovered == false)
        #expect(coordinator.debugTrackState(for: "tool.list-beta")?.isHovered == true)
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

    @Test @MainActor func resizePreservesHostedContentGeometryAfterFinalLayoutFlush() throws {
        let coordinator = SidebarNavigationListCoordinator()
        let scrollView = coordinator.makeScrollView()
        let container = NSView(frame: CGRect(x: 0, y: 0, width: SidebarView.idealWidth, height: 600))
        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        container.addSubview(scrollView)
        container.layoutSubtreeIfNeeded()
        let entries = Self.entries(
            groups: [Self.group(section: .category(.development), items: [Self.alpha])]
        )

        coordinator.update(
            scrollView: scrollView,
            configuration: Self.configuration(entries: entries)
        )
        let track = try #require(
            coordinator.documentView.subviews.first { ($0 as? SidebarNavigationTrackView)?.trackID == "tool.list-alpha" }
                as? SidebarNavigationTrackView
        )
        let initialViewportWidth = scrollView.contentSize.width
        #expect(track.frame.width == initialViewportWidth - SidebarNavigationLayout.horizontalPadding * 2)

        container.setFrameSize(CGSize(width: 260, height: 600))
        // NSViewRepresentable's parent assigns the native scroll view's frame
        // during layout; make that production placement explicit in this
        // isolated AppKit fixture before flushing its subtree.
        scrollView.frame = container.bounds
        container.layoutSubtreeIfNeeded()

        let viewportWidth = scrollView.contentSize.width
        #expect(viewportWidth == 260)
        #expect(track.frame.width == viewportWidth - SidebarNavigationLayout.horizontalPadding * 2)
        #expect(coordinator.documentView.frame.width == max(viewportWidth, SidebarView.idealWidth))
        #expect(track.hostedContentView.frame.width == track.frame.width)
        #expect(track.hostedContentView.frame.height == SidebarMetrics.expandedRowHeight)
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
private enum SidebarNavigationCoordinatorPerformanceBenchmark {
    private static let warmupIterations = 1
    private static let sampleIterations = 3
    private static let hoverIterations = 400
    private static let updateIterations = 12
    private static let resizeIterations = 80

    static func run() {
        let registry = ToolRegistry.default
        let allGroups = ToolNavigationProjection(
            registry: registry,
            favoriteIDs: [],
            selectedToolID: nil,
            query: ""
        ).sidebarGroups
        let searchGroups = ToolNavigationProjection(
            registry: registry,
            favoriteIDs: [],
            selectedToolID: nil,
            query: "json"
        ).sidebarGroups
        let allEntries = SidebarNavigationEntryProjection.entries(
            groups: allGroups,
            isSearchActive: false,
            isSectionExpanded: { _ in true }
        )
        let searchEntries = SidebarNavigationEntryProjection.entries(
            groups: searchGroups,
            isSearchActive: true,
            isSectionExpanded: { _ in true }
        )
        let hoverPoints = SidebarNavigationLayout.plan(
            entries: allEntries,
            width: SidebarView.idealWidth
        ).targets.compactMap { target -> CGPoint? in
            guard case .tool = target.kind, !target.frame.isEmpty else { return nil }
            return CGPoint(x: target.frame.midX, y: target.frame.midY)
        }
        guard !hoverPoints.isEmpty else {
            FileHandle.standardError.write(Data("SIDEBAR_COORDINATOR_BENCHMARK_ERROR no-hover-targets\n".utf8))
            return
        }

        let pointer = SidebarPointerLocationBox()
        let coordinator = SidebarNavigationListCoordinator(
            pointerLocationProvider: { _ in pointer.point }
        )
        let scrollView = coordinator.makeScrollView()
        scrollView.setFrameSize(CGSize(width: SidebarView.idealWidth, height: 600))
        coordinator.update(
            scrollView: scrollView,
            configuration: configuration(entries: allEntries, isSearchActive: false)
        )

        measure(label: "scroll-hover", iterations: hoverIterations) {
            for index in 0..<hoverIterations {
                pointer.point = hoverPoints[index % hoverPoints.count]
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
        measure(label: "search-update", iterations: updateIterations) {
            for _ in 0..<updateIterations {
                coordinator.update(
                    scrollView: scrollView,
                    configuration: configuration(entries: searchEntries, isSearchActive: true)
                )
                coordinator.update(
                    scrollView: scrollView,
                    configuration: configuration(entries: allEntries, isSearchActive: false)
                )
            }
        }
        measure(label: "resize", iterations: resizeIterations) {
            for index in 0..<resizeIterations {
                let width: CGFloat = index.isMultiple(of: 2) ? 260 : 300
                scrollView.setFrameSize(CGSize(width: width, height: 600))
                scrollView.layoutSubtreeIfNeeded()
            }
        }
    }

    private static func configuration(
        entries: [SidebarNavigationEntry],
        isSearchActive: Bool
    ) -> SidebarNavigationListConfiguration {
        SidebarNavigationListConfiguration(
            entries: entries,
            selectedToolID: nil,
            selectedSection: nil,
            favoriteOrder: [],
            isSearchActive: isSearchActive,
            reduceMotion: true,
            colorScheme: .dark,
            onSelectTool: { _ in },
            onToggleFavorite: { _ in },
            onToggleSection: { _ in }
        )
    }

    private static func measure(
        label: String,
        iterations: Int,
        operation: () -> Void
    ) {
        for _ in 0..<warmupIterations {
            operation()
        }
        for _ in 0..<sampleIterations {
            let startedAt = ContinuousClock.now
            operation()
            let duration = startedAt.duration(to: .now).components
            let milliseconds = Double(duration.seconds) * 1_000
                + Double(duration.attoseconds) / 1_000_000_000_000_000
            FileHandle.standardError.write(Data(String(
                format: "SIDEBAR_COORDINATOR_BENCHMARK operation=%@ iterations=%d milliseconds=%.3f\n",
                label,
                iterations,
                milliseconds
            ).utf8))
        }
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
