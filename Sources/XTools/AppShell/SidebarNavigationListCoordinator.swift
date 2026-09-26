import AppKit
import SwiftUI

typealias SidebarNavigationPointerLocationProvider = @MainActor (SidebarNavigationDocumentView) -> CGPoint?

@MainActor
final class SidebarNavigationListCoordinator {
    let documentView = SidebarNavigationDocumentView()

    private enum UpdateMode {
        case immediate
        case animated
        case contentOnly
    }

    private struct HostedContentKey: Equatable {
        let entry: SidebarNavigationEntry
        /// Row-derived selection state instead of the raw selection: a tool
        /// switch flips these on only the outgoing/incoming rows (and the rows
        /// of the newly active section), so every other track keeps its cached
        /// SwiftUI content instead of re-rendering on every click.
        let isRowSelected: Bool
        let isRowInActiveSection: Bool
        let isSectionActive: Bool
        let isSearchActive: Bool
        let interaction: SidebarNavigationTrackInteraction
        let colorScheme: ColorScheme
        let reduceMotion: Bool
    }

    private var tracksByID: [String: SidebarNavigationTrackView] = [:]
    private var hostedContentKeysByTrackID: [String: HostedContentKey] = [:]
    private var currentConfiguration: SidebarNavigationListConfiguration?
    private var currentPlan: SidebarNavigationLayoutPlan?
    private var animationGate = SidebarNavigationAnimationGate()
    private var activeAnimationToken: SidebarNavigationAnimationToken?
    private var scrollAnchor: SidebarNavigationScrollAnchor?
    private let pointerLocationProvider: SidebarNavigationPointerLocationProvider
    private var hoveredTrackID: String?
    private weak var scrollView: NSScrollView?
    /// Sliding selection chrome below every track (v3). Owns the selection
    /// pill + rail so tool switches can spring it between rows; the hosted
    /// rows keep only their text/icon color states.
    private let selectionIndicator = SidebarSelectionIndicatorView()

    var activeTrackIDs: [String] {
        currentPlan?.targets.map(\.id) ?? []
    }

    init(
        pointerLocationProvider: @escaping SidebarNavigationPointerLocationProvider = {
            $0.currentPointerLocation
        }
    ) {
        self.pointerLocationProvider = pointerLocationProvider
        documentView.onFrameSizeChange = { [weak self] in
            guard self?.activeAnimationToken == nil else { return }
            self?.applyScrollAnchor()
            self?.reconcilePointerLocation()
        }
        documentView.onMoveSelection = { [weak self] offset in
            self?.moveKeyboardSelection(offset: offset)
        }
        documentView.onActivateSelection = { [weak self] in
            self?.activateKeyboardSelection()
        }
        documentView.onActivatePresentationSelection = { [weak self] point in
            self?.activatePresentationTool(at: point) ?? false
        }
        documentView.onPointerLocationChange = { [weak self] point in
            self?.updatePointerLocation(point)
        }
    }

    func makeScrollView() -> NSScrollView {
        let scrollView = SidebarNavigationScrollView(
            frame: CGRect(x: 0, y: 0, width: SidebarView.idealWidth, height: 600)
        )
        scrollView.wantsLayer = true
        scrollView.drawsBackground = false
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        // Overlay scroller that fades in while scrolling (autohides) so long
        // tool lists read as scrollable without a permanent scroller lane.
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .automatic
        scrollView.usesPredominantAxisScrolling = true
        scrollView.setAccessibilityIdentifier("sidebar.navigation")
        scrollView.documentView = documentView
        documentView.wantsLayer = true
        documentView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        documentView.frame = CGRect(x: 0, y: 0, width: SidebarView.idealWidth, height: 0)
        // Below every track: reordering cycles only touch tracks, so the
        // indicator keeps its backmost slot through the list's lifetime.
        documentView.addSubview(selectionIndicator, positioned: .below, relativeTo: nil)
        scrollView.onViewportSizeChange = { [weak self] size in
            self?.resizeViewport(to: size)
        }
        scrollView.onViewportBoundsChange = { [weak self] in
            self?.reconcilePointerLocation()
        }
        self.scrollView = scrollView
        return scrollView
    }

    func update(
        scrollView: NSScrollView,
        configuration: SidebarNavigationListConfiguration
    ) {
        self.scrollView = scrollView
        let width = resolvedDocumentWidth(for: scrollView)
        let plan = SidebarNavigationLayout.plan(entries: configuration.entries, width: width)

        // Skip full hosted-content rewrite and track reconcile when plan geometry and
        // presentation-driving configuration are unchanged (ADR-0015-local hygiene).
        if shouldSkipPresentationUpdate(configuration: configuration, plan: plan) {
            return
        }

        let mode = updateMode(configuration: configuration, plan: plan)
        let previousActiveIDs = Set(currentPlan?.targets.map(\.id) ?? [])
        let previousSelectedToolID = currentConfiguration?.selectedToolID

        if mode != .contentOnly {
            beginScrollAnchorIfNeeded(configuration: configuration, plan: plan)
        }

        reconcileTracks(
            configuration: configuration,
            plan: plan,
            mode: mode,
            previousActiveIDs: previousActiveIDs
        )
        currentConfiguration = configuration

        switch mode {
        case .immediate:
            applyImmediate(plan: plan, configuration: configuration)
        case .animated:
            applyAnimated(plan: plan, configuration: configuration)
        case .contentOnly:
            applyWidth(plan: plan)
            currentPlan = plan
            // Pure tool switch on an unchanged plan: the only path that
            // springs the selection chrome between rows.
            positionSelectionIndicator(
                configuration: configuration,
                plan: plan,
                slide: previousSelectedToolID != configuration.selectedToolID
            )
            reconcilePointerLocation()
        }
    }

    /// Resolves the frame the sliding selection chrome should occupy, or nil
    /// when the selected tool is absent from the plan (search filtering,
    /// workspace focus) or its section is not the active one — the exact
    /// `shouldHighlight` parity the row-level fill used to own.
    private func selectionIndicatorFrame(
        configuration: SidebarNavigationListConfiguration,
        plan: SidebarNavigationLayoutPlan
    ) -> CGRect? {
        guard let selectedToolID = configuration.selectedToolID else { return nil }
        guard let target = plan.targets.first(where: { target in
            if case .tool(selectedToolID) = target.kind { return true }
            return false
        }), let entry = configuration.entries.first(where: { $0.id == target.id }),
            case .item(_, let section) = entry.content,
            section == configuration.selectedSection,
            target.frame.height > 0.5
        else { return nil }
        return target.frame
    }

    /// Lays the sliding selection chrome. `slide` is reserved for pure tool
    /// switches; every structural path (immediate relayout, disclosure
    /// accordion, resize) lands or rides without its own spring.
    private func positionSelectionIndicator(
        configuration: SidebarNavigationListConfiguration,
        plan: SidebarNavigationLayoutPlan,
        slide: Bool
    ) {
        selectionIndicator.updateColors()
        guard let frame = selectionIndicatorFrame(configuration: configuration, plan: plan) else {
            selectionIndicator.setHidden(true)
            return
        }
        selectionIndicator.setSelectionFrame(
            frame,
            slide: slide,
            reduceMotion: configuration.reduceMotion
        )
    }

    private func shouldSkipPresentationUpdate(
        configuration: SidebarNavigationListConfiguration,
        plan: SidebarNavigationLayoutPlan
    ) -> Bool {
        guard let currentConfiguration, let currentPlan else {
            return false
        }
        guard activeAnimationToken == nil else {
            return false
        }
        return currentPlan == plan
            && currentConfiguration.entries == configuration.entries
            && currentConfiguration.selectedToolID == configuration.selectedToolID
            && currentConfiguration.selectedSection == configuration.selectedSection
            && currentConfiguration.favoriteOrder == configuration.favoriteOrder
            && currentConfiguration.isSearchActive == configuration.isSearchActive
            && currentConfiguration.reduceMotion == configuration.reduceMotion
            && currentConfiguration.colorScheme == configuration.colorScheme
    }

    func cachedTrackObjectIdentifier(for trackID: String) -> ObjectIdentifier? {
        tracksByID[trackID].map(ObjectIdentifier.init)
    }

    func debugTrackState(for trackID: String) -> SidebarNavigationTrackDebugState? {
        tracksByID[trackID]?.debugState
    }

    /// Test-support: resolved sliding-selection chrome state, mirroring
    /// `debugTrackState` for the indicator lane.
    var debugSelectionIndicatorState: (frame: CGRect, isVisible: Bool) {
        (
            selectionIndicator.frame,
            selectionIndicator.alphaValue > 0.5
        )
    }

    @discardableResult
    func activatePresentationTool(_ toolID: ToolID) -> Bool {
        guard activeAnimationToken != nil,
              let configuration = currentConfiguration,
              let target = currentPlan?.targets.first(where: { target in
                  target.kind == .tool(toolID)
              }),
              tracksByID[target.id]?.interaction.acceptsPresentationSelection == true,
              finishActiveAnimationIfNeeded()
        else {
            return false
        }

        configuration.onSelectTool(toolID)
        return true
    }

    private func updateMode(
        configuration: SidebarNavigationListConfiguration,
        plan: SidebarNavigationLayoutPlan
    ) -> UpdateMode {
        guard let currentConfiguration, let currentPlan else {
            return .immediate
        }

        let target = SidebarNavigationAnimationTarget(plan: plan)
        let currentTarget = SidebarNavigationAnimationTarget(plan: currentPlan)
        let reduceMotionInterrupted = configuration.reduceMotion && activeAnimationToken != nil
        let searchChanged = configuration.isSearchActive != currentConfiguration.isSearchActive

        if reduceMotionInterrupted || configuration.isSearchActive || searchChanged {
            return .immediate
        }
        guard target != currentTarget else {
            return .contentOnly
        }
        if configuration.reduceMotion {
            return .immediate
        }

        let expansionChanged = expansionState(in: configuration.entries)
            != expansionState(in: currentConfiguration.entries)
        let favoriteOrderChanged = configuration.favoriteOrder != currentConfiguration.favoriteOrder
        let identityOrderChanged = plan.targets.map(\.id) != currentPlan.targets.map(\.id)
        return expansionChanged || favoriteOrderChanged || identityOrderChanged
            ? .animated
            : .immediate
    }

    private func reconcileTracks(
        configuration: SidebarNavigationListConfiguration,
        plan: SidebarNavigationLayoutPlan,
        mode: UpdateMode,
        previousActiveIDs: Set<String>
    ) {
        let entriesByID = Dictionary(
            uniqueKeysWithValues: configuration.entries.map { ($0.id, $0) }
        )
        let activeIDs = Set(plan.targets.map(\.id))

        for target in plan.targets {
            guard let entry = entriesByID[target.id] else { continue }
            let wasActive = previousActiveIDs.contains(target.id)
            let requiresNewTrack = tracksByID[target.id] == nil
            let track = tracksByID[target.id] ?? makeTrack(
                entry: entry,
                target: target,
                configuration: configuration
            )
            var requiresLayout = requiresNewTrack
            tracksByID[target.id] = track
            requiresLayout = track.update(
                groupID: target.groupID,
                naturalContentHeight: target.naturalHeight
            ) || requiresLayout

            if track.superview !== documentView {
                track.frame = CGRect(
                    x: target.frame.minX,
                    y: target.frame.minY,
                    width: target.frame.width,
                    height: mode == .immediate ? target.frame.height : 0
                )
                track.alphaValue = mode == .immediate
                    ? (target.kind == .header || target.frame.height > 0 ? 1.0 : 0.0)
                    : (target.kind == .header ? 1.0 : 0.0)
                documentView.addSubview(track)
                requiresLayout = true
            }

            let interaction = interaction(
                for: target,
                configuration: configuration,
                mode: mode,
                wasActive: wasActive,
                track: track
            )
            track.applyInteraction(interaction)
            requiresLayout = updateHostedContent(
                track: track,
                entry: entry,
                configuration: configuration
            ) || requiresLayout
            // Immediate mode lands every frame and hosted root in applyImmediate.
            // Avoid walking the same SwiftUI subtree once here and again there.
            if mode != .immediate, requiresLayout {
                track.layoutSubtreeIfNeeded()
            }
            track.applyInteraction(interaction)
        }

        orderActiveTracks(plan: plan)

        for track in tracksByID.values where !activeIDs.contains(track.trackID) {
            guard track.superview === documentView else { continue }
            track.applyInteraction(.preparing(targetExpanded: false))
        }
    }

    private func orderActiveTracks(plan: SidebarNavigationLayoutPlan) {
        let targetIDs = plan.targets.map(\.id)
        let activeIDSet = Set(targetIDs)
        let currentIDs = documentView.subviews.compactMap {
            ($0 as? SidebarNavigationTrackView)?.trackID
        }.filter(activeIDSet.contains)
        guard currentIDs != targetIDs else { return }

        let orderedTracks = targetIDs.compactMap { tracksByID[$0] }
        for track in orderedTracks {
            track.removeFromSuperview()
        }
        for track in orderedTracks {
            documentView.addSubview(track)
        }
    }

    private func makeTrack(
        entry: SidebarNavigationEntry,
        target: SidebarNavigationTrackTarget,
        configuration: SidebarNavigationListConfiguration
    ) -> SidebarNavigationTrackView {
        let interaction = initialInteraction(
            for: target,
            configuration: configuration
        )
        let hoverState = SidebarNavigationTrackHoverState()
        let hostingView = NSHostingView(rootView: trackRoot(
            entry: entry,
            configuration: configuration,
            interaction: interaction,
            hoverState: hoverState
        ))
        hostingView.sizingOptions = []
        let track = SidebarNavigationTrackView(
            trackID: target.id,
            groupID: target.groupID,
            kind: target.kind,
            naturalContentHeight: target.naturalHeight,
            hostedContentView: hostingView,
            hoverState: hoverState
        )
        // v3 full-row hit target: the AppKit track owns row activation so the
        // whole row — not just the label — jumps to the tool (or toggles the
        // section), matching native sidebar rows. The favorite slot stays a
        // pass-through (see SidebarNavigationTrackView.mouseDown).
        switch target.kind {
        case .tool(let toolID):
            track.onActivateRow = { [weak self] in
                self?.currentConfiguration?.onSelectTool(toolID)
            }
        case .header:
            if case .header(let group, _) = entry.content {
                let section = group.section
                track.onActivateRow = { [weak self] in
                    self?.currentConfiguration?.onToggleSection(section)
                }
                track.onActivateHeader = { [weak self] event in
                    guard let self, let configuration = self.currentConfiguration else { return }
                    if event.modifierFlags.contains(.option) {
                        if let exclusive = configuration.onToggleSectionExclusive {
                            exclusive(section)
                        } else {
                            configuration.onToggleSection(section)
                        }
                    } else {
                        configuration.onToggleSection(section)
                    }
                }
            }
        case .spacing:
            break
        }
        return track
    }

    @discardableResult
    private func updateHostedContent(
        track: SidebarNavigationTrackView,
        entry: SidebarNavigationEntry,
        configuration: SidebarNavigationListConfiguration
    ) -> Bool {
        guard let hostingView = track.hostedContentView
            as? NSHostingView<SidebarNavigationTrackRoot>
        else {
            return false
        }

        let key = HostedContentKey(
            entry: entry,
            isRowSelected: Self.isRowSelected(entry: entry, selectedToolID: configuration.selectedToolID),
            isRowInActiveSection: Self.isRowInActiveSection(
                entry: entry,
                selectedSection: configuration.selectedSection
            ),
            isSectionActive: Self.isSectionActive(
                entry: entry,
                selectedSection: configuration.selectedSection
            ),
            isSearchActive: configuration.isSearchActive,
            interaction: track.interaction,
            colorScheme: configuration.colorScheme,
            reduceMotion: configuration.reduceMotion
        )
        if hostedContentKeysByTrackID[track.trackID] == key {
            return false
        }

        hostingView.rootView = trackRoot(
            entry: entry,
            configuration: configuration,
            interaction: track.interaction,
            hoverState: track.hoverState
        )
        hostedContentKeysByTrackID[track.trackID] = key
        return true
    }

    private func trackRoot(
        entry: SidebarNavigationEntry,
        configuration: SidebarNavigationListConfiguration,
        interaction: SidebarNavigationTrackInteraction,
        hoverState: SidebarNavigationTrackHoverState
    ) -> SidebarNavigationTrackRoot {
        SidebarNavigationTrackRoot(
            entry: entry,
            selectedToolID: configuration.selectedToolID,
            selectedSection: configuration.selectedSection,
            isSearchActive: configuration.isSearchActive,
            interaction: interaction,
            hoverState: hoverState,
            colorScheme: configuration.colorScheme,
            reduceMotion: configuration.reduceMotion,
            onSelectTool: configuration.onSelectTool,
            onToggleFavorite: configuration.onToggleFavorite,
            onToggleSection: configuration.onToggleSection
        )
    }

    private static func isRowSelected(
        entry: SidebarNavigationEntry,
        selectedToolID: ToolID?
    ) -> Bool {
        guard case .item(let item, _) = entry.content else { return false }
        return item.id == selectedToolID
    }

    private static func isRowInActiveSection(
        entry: SidebarNavigationEntry,
        selectedSection: ToolNavigationSection?
    ) -> Bool {
        switch entry.content {
        case .item(_, let section):
            return section == selectedSection
        case .header, .spacing:
            return false
        }
    }

    private static func isSectionActive(
        entry: SidebarNavigationEntry,
        selectedSection: ToolNavigationSection?
    ) -> Bool {
        switch entry.content {
        case .header(let group, _):
            return group.section == selectedSection
        case .item, .spacing:
            return false
        }
    }

    private func initialInteraction(
        for target: SidebarNavigationTrackTarget,
        configuration: SidebarNavigationListConfiguration
    ) -> SidebarNavigationTrackInteraction {
        switch target.kind {
        case .header:
            return headerInteraction(isSearchActive: configuration.isSearchActive)
        case .tool:
            return .finalized(targetExpanded: target.frame.height > 0)
        case .spacing:
            return spacingInteraction
        }
    }

    private func interaction(
        for target: SidebarNavigationTrackTarget,
        configuration: SidebarNavigationListConfiguration,
        mode: UpdateMode,
        wasActive: Bool,
        track: SidebarNavigationTrackView
    ) -> SidebarNavigationTrackInteraction {
        switch target.kind {
        case .header:
            return headerInteraction(isSearchActive: configuration.isSearchActive)
        case .spacing:
            return spacingInteraction
        case .tool:
            let targetExpanded = target.frame.height > 0
            switch mode {
            case .immediate:
                return .finalized(targetExpanded: targetExpanded)
            case .animated:
                if !targetExpanded || !wasActive || !track.interaction.isInteractionEnabled {
                    return .preparing(targetExpanded: targetExpanded)
                }
                return track.interaction
            case .contentOnly:
                return track.interaction
            }
        }
    }

    private var spacingInteraction: SidebarNavigationTrackInteraction {
        SidebarNavigationTrackInteraction(
            isHidden: false,
            isInteractionEnabled: false,
            areControlsEnabled: false,
            acceptsPresentationSelection: false,
            isAccessibilityHidden: true
        )
    }

    private func headerInteraction(isSearchActive: Bool) -> SidebarNavigationTrackInteraction {
        SidebarNavigationTrackInteraction(
            isHidden: false,
            isInteractionEnabled: !isSearchActive,
            areControlsEnabled: !isSearchActive,
            acceptsPresentationSelection: false,
            isAccessibilityHidden: false
        )
    }

    private func applyImmediate(
        plan: SidebarNavigationLayoutPlan,
        configuration: SidebarNavigationListConfiguration
    ) {
        let target = SidebarNavigationAnimationTarget(plan: plan)
        animationGate.synchronize(target: target)
        activeAnimationToken = nil
        let activeIDs = Set(plan.targets.map(\.id))
        let entriesByID = Dictionary(uniqueKeysWithValues: configuration.entries.map { ($0.id, $0) })

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            for target in plan.targets {
                guard let track = tracksByID[target.id] else { continue }
                if track.frame != target.frame {
                    track.frame = target.frame
                }
                let alpha: CGFloat = target.kind == .header || target.frame.height > 0 ? 1.0 : 0.0
                if track.alphaValue != alpha {
                    track.alphaValue = alpha
                }
            }
            documentView.frame = documentFrame(
                width: resolvedDocumentWidth(for: scrollView),
                height: plan.documentHeight
            )
        }

        for target in plan.targets {
            guard let track = tracksByID[target.id] else { continue }
            let interaction = initialInteraction(
                for: target,
                configuration: configuration
            )
            track.applyInteraction(interaction)
            let contentChanged: Bool
            if let entry = entriesByID[target.id] {
                contentChanged = updateHostedContent(
                    track: track,
                    entry: entry,
                    configuration: configuration
                )
            } else {
                contentChanged = false
            }
            // The frame setter and root assignment both mark layout dirty. A
            // clean existing track needs no recursive AppKit/SwiftUI walk.
            if contentChanged || track.needsLayout || track.hostedContentView.needsLayout {
                track.layoutSubtreeIfNeeded()
            }
            track.applyInteraction(interaction)
        }

        hideInactiveTracks(activeIDs: activeIDs)
        currentPlan = plan
        positionSelectionIndicator(configuration: configuration, plan: plan, slide: false)
        finishScrollAnchor()
        reconcilePointerLocation()
    }

    private func applyAnimated(
        plan: SidebarNavigationLayoutPlan,
        configuration: SidebarNavigationListConfiguration
    ) {
        let token = animationGate.request(
            target: SidebarNavigationAnimationTarget(plan: plan)
        )
        activeAnimationToken = token
        let activeIDs = Set(plan.targets.map(\.id))
        let retiringTracks = tracksByID.values.filter {
            $0.superview === documentView && !activeIDs.contains($0.trackID)
        }
        let motion = ToolMotion.AppKitPreset.accordion

        let targetOriginY: CGFloat? = {
            guard let scrollView, let scrollAnchor else { return nil }
            return scrollAnchor.resolvedOriginY(
                documentHeight: plan.documentHeight,
                viewportHeight: scrollView.contentView.bounds.height
            )
        }()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = motion.duration
            context.timingFunction = motion.timingFunction
            for target in plan.targets {
                guard let track = tracksByID[target.id] else { continue }
                track.animator().frame = target.frame
                if target.kind != .header {
                    track.animator().alphaValue = target.frame.height > 0 ? 1.0 : 0.0
                }
            }
            for track in retiringTracks {
                var frame = track.frame
                frame.size.height = 0
                track.animator().frame = frame
                track.animator().alphaValue = 0.0
            }
            // Selection chrome rides the same disclosure motion as the rows —
            // never its own spring during structural changes.
            selectionIndicator.updateColors()
            selectionIndicator.prepareForStructuralMotion()
            if let frame = selectionIndicatorFrame(configuration: configuration, plan: plan) {
                if selectionIndicator.alphaValue < 0.01 {
                    selectionIndicator.frame = frame
                    selectionIndicator.layoutSubtreeIfNeeded()
                    selectionIndicator.alphaValue = 1
                } else {
                    selectionIndicator.animator().frame = frame
                }
            } else {
                selectionIndicator.animator().alphaValue = 0
            }
            documentView.animator().frame = documentFrame(
                width: resolvedDocumentWidth(for: scrollView),
                height: plan.documentHeight
            )
            if let targetOriginY, let scrollView {
                let clipView = scrollView.contentView
                if abs(clipView.bounds.origin.y - targetOriginY) > 0.25 {
                    clipView.animator().bounds = NSRect(
                        origin: NSPoint(x: clipView.bounds.origin.x, y: targetOriginY),
                        size: clipView.bounds.size
                    )
                }
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.completeAnimation(token: token, activeIDs: activeIDs)
            }
        }
        currentPlan = plan
        reconcilePointerLocation()
    }

    private func completeAnimation(
        token: SidebarNavigationAnimationToken,
        activeIDs: Set<String>
    ) {
        guard animationGate.accepts(token), activeAnimationToken == token else {
            return
        }

        guard let configuration = currentConfiguration else { return }
        let entriesByID = Dictionary(uniqueKeysWithValues: configuration.entries.map { ($0.id, $0) })

        for target in currentPlan?.targets ?? [] {
            guard let track = tracksByID[target.id] else { continue }
            switch target.kind {
            case .tool:
                track.applyInteraction(
                    .finalized(targetExpanded: target.frame.height > 0)
                )
            case .header:
                track.applyInteraction(
                    headerInteraction(
                        isSearchActive: currentConfiguration?.isSearchActive ?? false
                    )
                )
            case .spacing:
                track.applyInteraction(spacingInteraction)
            }
            track.alphaValue = target.kind == .header || target.frame.height > 0 ? 1.0 : 0.0

            if let configuration = currentConfiguration,
               let entry = entriesByID[target.id] {
                updateHostedContent(
                    track: track,
                    entry: entry,
                    configuration: configuration
                )
                track.layoutSubtreeIfNeeded()
                track.applyInteraction(track.interaction)
            }
        }

        hideInactiveTracks(activeIDs: activeIDs)
        activeAnimationToken = nil
        finishScrollAnchor()
        reconcilePointerLocation()
    }

    private func hideInactiveTracks(activeIDs: Set<String>) {
        for track in tracksByID.values where !activeIDs.contains(track.trackID) {
            if hoveredTrackID == track.trackID {
                setHoveredTrackID(nil)
            }
            hostedContentKeysByTrackID.removeValue(forKey: track.trackID)
            track.applyInteraction(.finalized(targetExpanded: false))
            track.removeFromSuperview()
        }
    }

    private func applyWidth(plan: SidebarNavigationLayoutPlan) {
        for target in plan.targets {
            guard let track = tracksByID[target.id] else { continue }
            var frame = track.frame
            frame.origin.x = target.frame.minX
            frame.size.width = target.frame.width
            guard track.frame != frame else { continue }
            track.frame = frame
        }
        var frame = documentView.frame
        frame.size.width = resolvedDocumentWidth(for: scrollView)
        if documentView.frame != frame {
            documentView.frame = frame
        }
    }

    private func resizeViewport(to size: CGSize) {
        guard size.width > 0,
              let configuration = currentConfiguration
        else {
            return
        }
        let plan = SidebarNavigationLayout.plan(
            entries: configuration.entries,
            width: size.width
        )
        guard plan != currentPlan else { return }
        applyWidth(plan: plan)
        currentPlan = plan
        // Width-only relayout: keep the chrome glued to the (resized) row.
        positionSelectionIndicator(configuration: configuration, plan: plan, slide: false)
        reconcilePointerLocation()
    }

    private func beginScrollAnchorIfNeeded(
        configuration: SidebarNavigationListConfiguration,
        plan: SidebarNavigationLayoutPlan
    ) {
        guard currentPlan != nil,
              let scrollView
        else {
            return
        }
        let clipView = scrollView.contentView
        let expandedSectionBounds = newlyExpandedSectionBounds(
            configuration: configuration,
            plan: plan
        )
        scrollAnchor = SidebarNavigationScrollAnchor.capture(
            originY: clipView.bounds.origin.y,
            documentHeight: documentView.frame.height,
            viewportHeight: clipView.bounds.height,
            expandedSectionBounds: expandedSectionBounds
        )
    }

    private func newlyExpandedSectionBounds(
        configuration: SidebarNavigationListConfiguration,
        plan: SidebarNavigationLayoutPlan
    ) -> SidebarNavigationSectionBounds? {
        guard let currentConfiguration else { return nil }
        let previousExpandedState = expansionState(in: currentConfiguration.entries)
        let newExpandedState = expansionState(in: configuration.entries)

        guard let newlyExpandedGroupID = newExpandedState.first(where: { groupID, isExpanded in
            isExpanded && !(previousExpandedState[groupID] ?? false)
        })?.key else {
            return nil
        }

        let sectionTargets = plan.targets.filter { $0.groupID == newlyExpandedGroupID }
        guard let headerTarget = sectionTargets.first(where: { $0.kind == .header }),
              let maxY = sectionTargets.map(\.frame.maxY).max()
        else {
            return nil
        }

        return SidebarNavigationSectionBounds(
            headerMinY: headerTarget.frame.minY,
            sectionMaxY: maxY
        )
    }

    private func applyScrollAnchor() {
        guard let scrollAnchor, let scrollView else { return }
        let clipView = scrollView.contentView
        let originY = scrollAnchor.resolvedOriginY(
            documentHeight: documentView.frame.height,
            viewportHeight: clipView.bounds.height
        )
        guard abs(clipView.bounds.origin.y - originY) > 0.25 else { return }
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: originY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func finishScrollAnchor() {
        applyScrollAnchor()
        scrollAnchor = nil
    }

    private func resolvedDocumentWidth(for scrollView: NSScrollView?) -> CGFloat {
        guard let scrollView else { return SidebarView.idealWidth }
        return max(scrollView.contentSize.width, SidebarView.idealWidth)
    }

    private func documentFrame(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: width, height: height)
    }

    private func expansionState(
        in entries: [SidebarNavigationEntry]
    ) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            guard case .header(let group, let isExpanded) = entry.content else {
                return nil
            }
            return (group.id, isExpanded)
        })
    }

    func updatePointerLocation(_ point: CGPoint?) {
        setHoveredTrackID(point.flatMap(resolveHoveredTrackID(at:)))
    }

    private func reconcilePointerLocation() {
        updatePointerLocation(pointerLocationProvider(documentView))
    }

    private func resolveHoveredTrackID(at point: CGPoint) -> String? {
        // Static tracks do not overlap, but preserve the presentation helper's
        // reverse-order semantics for the animated case. This path runs for
        // every mouse move and scroll-bound change, so do not allocate a target
        // array and a ToolID lookup dictionary before testing one point.
        guard let currentPlan else { return nil }
        for target in currentPlan.targets.reversed() {
            guard case .tool = target.kind else { continue }
            guard let track = tracksByID[target.id],
                  track.superview === documentView,
                  track.interaction.isInteractionEnabled,
                  !track.isHidden
            else {
                continue
            }

            let frame = activeAnimationToken == nil
                ? track.frame
                : track.presentationFrame ?? track.frame
            if !frame.isEmpty && frame.contains(point) {
                return target.id
            }
        }
        return nil
    }

    private func setHoveredTrackID(_ proposedTrackID: String?) {
        let nextTrackID = proposedTrackID.flatMap { trackID -> String? in
            guard let track = tracksByID[trackID],
                  case .tool = track.kind,
                  track.superview === documentView,
                  track.interaction.isInteractionEnabled,
                  !track.isHidden
            else {
                return nil
            }
            return trackID
        }
        guard hoveredTrackID != nextTrackID else { return }

        if let hoveredTrackID {
            tracksByID[hoveredTrackID]?.hoverState.setHovered(false)
        }
        hoveredTrackID = nextTrackID
        if let nextTrackID {
            tracksByID[nextTrackID]?.hoverState.setHovered(true)
        }
    }

    private var operableToolIDs: [ToolID] {
        guard let configuration = currentConfiguration else { return [] }
        return configuration.entries.compactMap { entry in
            guard case .item(let item, _) = entry.content,
                  tracksByID[entry.id]?.interaction.isInteractionEnabled == true
            else {
                return nil
            }
            return item.id
        }
    }

    private func activatePresentationTool(at point: NSPoint) -> Bool {
        let targets = currentPlan?.targets.compactMap { target -> SidebarNavigationPresentationHitTarget? in
            guard case .tool(let toolID) = target.kind,
                  let track = tracksByID[target.id],
                  track.interaction.acceptsPresentationSelection,
                  let frame = track.presentationFrame
            else {
                return nil
            }
            return SidebarNavigationPresentationHitTarget(toolID: toolID, frame: frame)
        } ?? []

        guard let toolID = SidebarNavigationPresentationHitTesting.toolID(
            at: point,
            targets: targets
        ) else {
            return false
        }
        return activatePresentationTool(toolID)
    }

    @discardableResult
    private func finishActiveAnimationIfNeeded() -> Bool {
        guard activeAnimationToken != nil,
              let currentPlan,
              let currentConfiguration
        else {
            return false
        }
        applyImmediate(plan: currentPlan, configuration: currentConfiguration)
        return true
    }

    private func moveKeyboardSelection(offset: Int) {
        _ = finishActiveAnimationIfNeeded()
        guard let configuration = currentConfiguration else { return }
        let toolIDs = operableToolIDs
        guard !toolIDs.isEmpty else { return }
        let currentIndex = configuration.selectedToolID.flatMap(toolIDs.firstIndex(of:))
        let nextIndex: Int
        if let currentIndex {
            nextIndex = min(max(currentIndex + offset, 0), toolIDs.count - 1)
        } else {
            nextIndex = offset >= 0 ? 0 : toolIDs.count - 1
        }
        configuration.onSelectTool(toolIDs[nextIndex])
    }

    private func activateKeyboardSelection() {
        _ = finishActiveAnimationIfNeeded()
        guard let configuration = currentConfiguration,
              let selectedToolID = configuration.selectedToolID,
              operableToolIDs.contains(selectedToolID)
        else {
            return
        }
        configuration.onSelectTool(selectedToolID)
    }
}
