import AppKit
import SwiftUI

@MainActor
enum CommandPaletteTrace {
#if DEBUG
    private static var openedAt: [Int: ContinuousClock.Instant] = [:]
    private static var emittedPhases: [Int: Set<String>] = [:]

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TOOLS_COMMAND_PALETTE_BENCHMARK"] == "1"
    }
#endif

    static func opened(session: Int) {
#if DEBUG
        guard isEnabled else { return }
        openedAt[session] = .now
        emittedPhases[session] = []
#endif
    }

    static func appeared(session: Int) {
#if DEBUG
        emit(session: session, phase: "appeared")
#endif
    }

    static func dismissed(session: Int) {
#if DEBUG
        openedAt.removeValue(forKey: session)
        emittedPhases.removeValue(forKey: session)
#endif
    }

#if DEBUG
    private static func emit(session: Int, phase: String) {
        guard isEnabled,
              let startedAt = openedAt[session],
              emittedPhases[session, default: []].insert(phase).inserted
        else {
            return
        }
        let elapsed = ContinuousClock.now - startedAt
        let components = elapsed.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        let line = String(
            format: "COMMAND_PALETTE_PRESENTATION_PHASE_RESULT session=%d phase=%@ milliseconds=%.3f\n",
            session,
            phase,
            milliseconds
        )
        FileHandle.standardError.write(Data(line.utf8))
    }
#endif
}

private enum CommandPaletteMetrics {
    static let searchHeaderSpacing: CGFloat = 9
    static let searchHeaderLeadingPadding: CGFloat = 14
    static let searchHeaderTrailingPadding: CGFloat = 14
    static let searchClearLayoutSize: CGFloat = 15
    static let searchClearButtonSize: CGFloat = 24
}

private struct CommandPaletteRevealRequest: Equatable {
    let id: String
    let anchor: CommandPaletteRevealAnchor
    let token: Int
}

/// Modal "jump to anything" palette (Command-K). Fully self-contained: it reads
/// a navigation projection plus shell-supplied command actions and reports
/// selections back through injected closures, holding no reference to the app
/// shell's own state. Row projection and active selection live in
/// `CommandPaletteNavigationState` so they can be unit-tested.
struct CommandPaletteView: View {
    let projection: ToolNavigationProjection
    let actions: [CommandActionEntry]
    @Binding var query: String
    let focusToken: Int
    let presentationSession: Int
    let canRequestSearchFocus: AppKitSearchFieldCoordinator.FocusRequestValidity
    let onSelectTool: (ToolID) -> Void
    let onRunCommand: (CommandActionID) -> Void
    let onRequestFocus: () -> Void
    let onDismiss: () -> Void

    @State private var paletteState = CommandPaletteNavigationState()
    @State private var revealRequest: CommandPaletteRevealRequest?
    @State private var revealRequestToken = 0
    @State private var revealRegistry = CommandPaletteRevealRegistry()
    @State private var pointerMovementTracker = CommandPalettePointerMovementTracker()
    /// True when the active row was last set by keyboard arrows (not pointer).
    @State private var isActiveRowKeyboardDriven = false
    private var matchingActions: [CommandActionEntry] {
        actions.filter { $0.matches(query: query) }
    }

    private var paletteSnapshot: CommandPaletteRowSnapshot {
        CommandPaletteNavigationState.snapshot(
            for: projection.commandPaletteEntries,
            actions: matchingActions
        )
    }

    private func moveActive(by delta: Int) {
        let snapshot = paletteSnapshot
        isActiveRowKeyboardDriven = true
        let previousActiveID = paletteState.activeRowID(in: snapshot)
        let visibleHandoffIndex = revealRegistry.visibleEdgeSelectableIndex(direction: delta)
        let isCurrentActiveVisible = previousActiveID.map(revealRegistry.isVisible(itemID:)) ?? false
        let hasPendingKeyboardRevealForCurrentActive = previousActiveID.map(revealRegistry.hasLatestPendingKeyboardReveal(itemID:)) ?? false
        let moveDecision = paletteState.keyboardMoveDecision(
            by: delta,
            in: snapshot,
            visibleHandoffIndex: visibleHandoffIndex,
            isCurrentActiveVisible: isCurrentActiveVisible,
            hasPendingKeyboardRevealForCurrentActive: hasPendingKeyboardRevealForCurrentActive,
            allowsVisibleHandoff: revealRegistry.hasManualScrollAfterLatestKeyboardReveal()
        )

        switch moveDecision {
        case .move(let index), .alignToVisibleSelectableIndex(let index):
            paletteState.setActiveSelectableIndex(index, in: snapshot)
        case .revealCurrent:
            requestActiveReveal(for: .keyboard(delta: delta))
        case .none:
            break
        }

        if paletteState.activeRowID(in: snapshot) != previousActiveID {
            requestActiveReveal(for: .keyboard(delta: delta), in: snapshot)
        }
    }

    private func resetActiveRowForQuery() {
        paletteState.resetActiveRow()
        requestActiveReveal(for: .queryReset, in: paletteSnapshot)
    }

    private func activateActive() {
        guard let item = paletteState.activeRow(in: paletteSnapshot) else { return }
        activate(item)
    }

    private func setActiveItem(_ item: CommandPaletteRowProjection) {
        let snapshot = paletteSnapshot
        isActiveRowKeyboardDriven = false
        guard item.id != paletteState.activeRowID(in: snapshot) else { return }
        paletteState.setActiveRow(item, in: snapshot)
        requestActiveReveal(for: .pointerMove)
    }

    private func activate(_ item: CommandPaletteRowProjection) {
        if let commandID = item.commandID {
            requestActiveReveal(for: .directActivation)
            onRunCommand(commandID)
            return
        }
        guard let toolID = paletteState.toolID(for: item) else { return }
        requestActiveReveal(for: .directActivation)
        onSelectTool(toolID)
    }

    private func requestActiveReveal(for source: CommandPaletteActiveChangeSource) {
        requestActiveReveal(for: source, in: paletteSnapshot)
    }

    private func requestActiveReveal(
        for source: CommandPaletteActiveChangeSource,
        in snapshot: CommandPaletteRowSnapshot
    ) {
        guard let anchor = source.revealAnchor,
              let activeID = paletteState.activeRowID(in: snapshot)
        else {
            return
        }

        revealRequestToken += 1
        revealRegistry.markRevealRequest(token: revealRequestToken)
        if case .keyboard = source {
            revealRegistry.markKeyboardRevealPending(itemID: activeID, token: revealRequestToken)
        }
        let request = CommandPaletteRevealRequest(
            id: activeID,
            anchor: anchor,
            token: revealRequestToken
        )
        revealRequest = request

        if case .keyboard = source {
            revealRegistry.revealImmediately(request: request)
        }
    }

    @ViewBuilder
    private func paletteItemView(
        for item: CommandPaletteRowProjection,
        activeItemID: String?,
        selectableIndex: Int?
    ) -> some View {
        switch item {
        case .sectionTitle(let text):
            CommandPaletteSectionTitle(text)
        case .tool(let entry):
            CommandPaletteRow(
                id: entry.id,
                title: entry.title,
                highlight: query,
                subtitle: entry.categoryTitle,
                systemImage: entry.systemImage,
                isActive: item.id == activeItemID,
                isKeyboardActive: item.id == activeItemID && isActiveRowKeyboardDriven,
                pointerMovementTracker: pointerMovementTracker,
                onMouseMoveActive: { setActiveItem(item) }
            ) {
                activate(item)
            }
            .background {
                CommandPaletteRevealAttachment(
                    itemID: item.id,
                    selectableIndex: selectableIndex,
                    registry: revealRegistry,
                    revealRequest: revealRequest
                )
            }
        case .command(let entry):
            CommandPaletteRow(
                id: entry.id.rawValue,
                title: entry.title,
                highlight: query,
                subtitle: entry.subtitle,
                systemImage: entry.systemImage,
                isActive: item.id == activeItemID,
                isKeyboardActive: item.id == activeItemID && isActiveRowKeyboardDriven,
                pointerMovementTracker: pointerMovementTracker,
                onMouseMoveActive: { setActiveItem(item) }
            ) {
                activate(item)
            }
            .background {
                CommandPaletteRevealAttachment(
                    itemID: item.id,
                    selectableIndex: selectableIndex,
                    registry: revealRegistry,
                    revealRequest: revealRequest
                )
            }
        case .empty:
            Text("没有匹配的工具或命令")
                .font(ToolTypography.bodyPlain)
                .foregroundStyle(ToolTheme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .center)
        }
    }

    var body: some View {
        let snapshot = paletteSnapshot
        let activeItemID = paletteState.activeRowID(in: snapshot)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CommandPaletteMetrics.searchHeaderSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: ToolMetrics.IconSize.medium, weight: .medium))
                    .foregroundStyle(ToolTheme.textSecondary)

                CommandPaletteSearchField(
                    placeholder: "搜索工具或命令…",
                    text: $query,
                    focusToken: focusToken,
                    canRequestFocus: canRequestSearchFocus,
                    onSubmit: activateActive,
                    onMoveUp: { moveActive(by: -1) },
                    onMoveDown: { moveActive(by: 1) },
                    onCancel: onDismiss
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: 24)
                .onChange(of: query) { _ in
                    // 过滤结果变化后 active row 重置到首项，避免越界 / 停在已消失的行。
                    resetActiveRowForQuery()
                }

                ZStack {
                    if !query.isEmpty {
                        Button {
                            query = ""
                            paletteState.resetActiveRow()
                            onRequestFocus()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: ToolMetrics.IconSize.medium))
                                .frame(
                                    width: CommandPaletteMetrics.searchClearButtonSize,
                                    height: CommandPaletteMetrics.searchClearButtonSize
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .toolInteractionFeedback()
                        .foregroundStyle(ToolTheme.textSecondary)
                        .accessibilityIdentifier("command-palette.search.clear")
                        .help("清除搜索")
                        .accessibilityLabel("清除搜索")
                    }
                }
                .frame(
                    width: CommandPaletteMetrics.searchClearLayoutSize,
                    height: CommandPaletteMetrics.searchClearLayoutSize
                )
                .allowsHitTesting(!query.isEmpty)
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: query.isEmpty)
            }
            .padding(.leading, CommandPaletteMetrics.searchHeaderLeadingPadding)
            .padding(.trailing, CommandPaletteMetrics.searchHeaderTrailingPadding)
            .frame(height: 48)

            ToolDivider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(snapshot.rows) { item in
                        paletteItemView(
                            for: item,
                            activeItemID: activeItemID,
                            selectableIndex: snapshot.selectableIndex(of: item)
                        )
                            .padding(.horizontal, 9)
                            .padding(.vertical, 1)
                            .id(item.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 360)

            CommandPaletteHintsBar()
        }
        .frame(width: 560)
        .toolSurface(
            .floating,
            fallback: ToolTheme.popoverBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.modal, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.modal, style: .continuous)
                .strokeBorder(ToolTheme.strongBorder, lineWidth: 0.5)
        }
        .toolShadow(ToolTheme.Shadow.modal)
        .onAppear {
            CommandPaletteTrace.appeared(session: presentationSession)
        }
    }

}

private struct CommandPaletteRevealAttachment: NSViewRepresentable {
    let itemID: String
    let selectableIndex: Int?
    let registry: CommandPaletteRevealRegistry
    let revealRequest: CommandPaletteRevealRequest?

    func makeNSView(context: Context) -> CommandPaletteRevealView {
        CommandPaletteRevealView()
    }

    func updateNSView(_ view: CommandPaletteRevealView, context: Context) {
        view.configure(
            itemID: itemID,
            selectableIndex: selectableIndex,
            registry: registry
        )

        guard let revealRequest, revealRequest.id == itemID else { return }
        view.reveal(request: revealRequest)
    }

    static func dismantleNSView(_ view: CommandPaletteRevealView, coordinator: ()) {
        view.unregister()
    }
}

@MainActor
private final class CommandPaletteRevealRegistry: NSObject {
    private final class Entry {
        weak var view: CommandPaletteRevealView?
        let selectableIndex: Int

        init(view: CommandPaletteRevealView, selectableIndex: Int) {
            self.view = view
            self.selectableIndex = selectableIndex
        }
    }

    private var entries: [String: Entry] = [:]
    private var pendingKeyboardReveal: PendingKeyboardReveal?
    private var latestRevealRequestToken = 0
    private var manualScrollGeneration = 0
    private var manualScrollGenerationAtLatestKeyboardReveal = 0
    private var observedClipViews: [ObjectIdentifier: NSClipView] = [:]

    private struct PendingKeyboardReveal {
        let itemID: String
        let token: Int
    }

    func register(itemID: String, selectableIndex: Int?, view: CommandPaletteRevealView) {
        guard let selectableIndex else {
            unregister(itemID: itemID, view: view)
            return
        }
        entries[itemID] = Entry(view: view, selectableIndex: selectableIndex)
        observeScrollView(containing: view)
    }

    func unregister(itemID: String?, view: CommandPaletteRevealView) {
        guard let itemID,
              let entry = entries[itemID],
              entry.view === view
        else {
            return
        }
        entries.removeValue(forKey: itemID)

        guard let clipView = view.enclosingScrollView?.contentView else { return }
        let clipViewID = ObjectIdentifier(clipView)
        let stillUsed = entries.values.contains { entry in
            entry.view?.enclosingScrollView?.contentView === clipView
        }
        guard !stillUsed else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
        observedClipViews.removeValue(forKey: clipViewID)
    }

    func visibleEdgeSelectableIndex(direction: Int) -> Int? {
        pruneDeadEntries()

        var edgeIndex: Int?
        for entry in entries.values where isVisible(entry) {
            guard let currentEdge = edgeIndex else {
                edgeIndex = entry.selectableIndex
                continue
            }

            if direction < 0 {
                edgeIndex = max(currentEdge, entry.selectableIndex)
            } else {
                edgeIndex = min(currentEdge, entry.selectableIndex)
            }
        }
        return edgeIndex
    }

    func isVisible(itemID: String) -> Bool {
        pruneDeadEntries()
        guard let entry = entries[itemID] else { return false }
        return isVisible(entry)
    }

    func hasLatestPendingKeyboardReveal(itemID: String) -> Bool {
        pendingKeyboardReveal?.itemID == itemID
            && pendingKeyboardReveal?.token == latestRevealRequestToken
    }

    func hasManualScrollAfterLatestKeyboardReveal() -> Bool {
        manualScrollGeneration > manualScrollGenerationAtLatestKeyboardReveal
    }

    func markKeyboardRevealPending(itemID: String, token: Int) {
        pendingKeyboardReveal = PendingKeyboardReveal(itemID: itemID, token: token)
        manualScrollGenerationAtLatestKeyboardReveal = manualScrollGeneration
    }

    func finishKeyboardReveal(request: CommandPaletteRevealRequest) {
        guard pendingKeyboardReveal?.itemID == request.id,
              pendingKeyboardReveal?.token == request.token
        else {
            return
        }
        pendingKeyboardReveal = nil
    }

    func markRevealRequest(token: Int) {
        latestRevealRequestToken = token
        if pendingKeyboardReveal?.token != token {
            pendingKeyboardReveal = nil
        }
    }

    func isLatestRevealRequest(_ request: CommandPaletteRevealRequest) -> Bool {
        request.token == latestRevealRequestToken
    }

    func revealImmediately(request: CommandPaletteRevealRequest) {
        guard isLatestRevealRequest(request),
              let entry = entries[request.id],
              let view = entry.view
        else {
            return
        }

        view.reveal(request: request)
    }

    func observeScrollView(containing view: NSView) {
        guard let clipView = view.enclosingScrollView?.contentView else { return }

        let id = ObjectIdentifier(clipView)
        guard observedClipViews[id] == nil else { return }

        clipView.postsBoundsChangedNotifications = true
        observedClipViews[id] = clipView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
    }

    @objc private func scrollViewBoundsDidChange(_ notification: Notification) {
        guard NSApp.currentEvent?.type == .scrollWheel else { return }
        manualScrollGeneration += 1
    }

    private func isVisible(_ entry: Entry) -> Bool {
        guard let view = entry.view,
              let scrollView = view.enclosingScrollView,
              let documentView = scrollView.documentView
        else {
            return false
        }

        let visibleRect = scrollView.contentView.bounds
        let rowRect = view.convert(view.bounds, to: documentView)
        return visibleRect.intersects(rowRect)
    }

    private func pruneDeadEntries() {
        entries = entries.filter { _, entry in
            entry.view != nil
        }

        let activeClipViewIDs = Set(
            entries.values.compactMap { entry -> ObjectIdentifier? in
                guard let clipView = entry.view?.enclosingScrollView?.contentView else {
                    return nil
                }
                return ObjectIdentifier(clipView)
            }
        )
        for (id, clipView) in observedClipViews where !activeClipViewIDs.contains(id) {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
            observedClipViews.removeValue(forKey: id)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

private final class CommandPaletteRevealView: NSView {
    private var lastRevealToken = 0
    private var scheduledRevealRetryToken = 0
    private weak var registry: CommandPaletteRevealRegistry?
    private var itemID: String?

    override var isFlipped: Bool {
        true
    }

    func configure(
        itemID: String,
        selectableIndex: Int?,
        registry: CommandPaletteRevealRegistry
    ) {
        if self.itemID != itemID {
            unregister()
        }

        self.itemID = itemID
        self.registry = registry
        registry.register(
            itemID: itemID,
            selectableIndex: selectableIndex,
            view: self
        )
        registry.observeScrollView(containing: self)
    }

    func unregister() {
        registry?.unregister(itemID: itemID, view: self)
    }

    func reveal(request: CommandPaletteRevealRequest) {
        guard request.token != lastRevealToken else { return }
        guard window != nil else {
            guard scheduledRevealRetryToken != request.token else { return }
            scheduledRevealRetryToken = request.token
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.reveal(request: request)
            }
            return
        }

        lastRevealToken = request.token
        guard let registry,
              registry.isLatestRevealRequest(request)
        else {
            return
        }

        switch request.anchor {
        case .keyboardEdge(let delta):
            scrollToKeyboardEdge(delta: delta)
        case .top:
            scrollToTop()
        }
        registry.finishKeyboardReveal(request: request)
    }

    private func scrollToKeyboardEdge(delta: Int) {
        guard let scrollView = enclosingScrollView,
              let documentView = scrollView.documentView
        else {
            scrollToVisible(bounds)
            return
        }

        let clipView = scrollView.contentView
        let visibleRect = clipView.bounds
        let rowRect = viewRectInDocumentView(documentView)
        let targetY: CGFloat?

        if delta > 0 {
            targetY = rowRect.maxY > visibleRect.maxY
                ? rowRect.maxY - visibleRect.height
                : nil
        } else if delta < 0 {
            targetY = rowRect.minY < visibleRect.minY
                ? rowRect.minY
                : nil
        } else {
            targetY = nil
        }

        guard let targetY else { return }

        let documentBounds = documentView.bounds
        let maxY = max(documentBounds.minY, documentBounds.maxY - visibleRect.height)
        let clampedY = min(max(targetY, documentBounds.minY), maxY)
        clipView.scroll(to: NSPoint(x: visibleRect.origin.x, y: clampedY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func viewRectInDocumentView(_ documentView: NSView) -> NSRect {
        if bounds.width > 0, bounds.height > 0 {
            return convert(bounds, to: documentView)
        }

        if let superview, superview.bounds.width > 0, superview.bounds.height > 0 {
            return superview.convert(superview.bounds, to: documentView)
        }

        return convert(bounds, to: documentView)
    }

    private func scrollToTop() {
        guard let scrollView = enclosingScrollView,
              let documentView = scrollView.documentView
        else {
            scrollToVisible(bounds)
            return
        }

        let clipView = scrollView.contentView
        let topY: CGFloat
        if documentView.isFlipped {
            topY = documentView.bounds.minY
        } else {
            topY = max(documentView.bounds.minY, documentView.bounds.maxY - clipView.bounds.height)
        }

        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: topY))
        scrollView.reflectScrolledClipView(clipView)
    }
}

private struct CommandPaletteSearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let focusToken: Int
    let canRequestFocus: AppKitSearchFieldCoordinator.FocusRequestValidity
    let onSubmit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onCancel: () -> Void

    private var configuration: AppKitSearchFieldConfiguration {
        // Arc-style large prompt input — the palette's primary affordance.
        AppKitSearchFieldConfiguration(
            placeholder: placeholder,
            font: .systemFont(ofSize: 18)
        )
    }

    private var commandHandler: AppKitSearchFieldCoordinator.CommandHandler {
        { textView, commandSelector in
            if textView.hasMarkedText(), Self.markedTextShouldHandle(commandSelector) {
                return false
            }

            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                onMoveDown()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel()
                return true
            default:
                return false
            }
        }
    }

    func makeCoordinator() -> AppKitSearchFieldCoordinator {
        AppKitSearchFieldCoordinator(
            text: $text,
            processedFocusToken: nil,
            focusRetryDelays: [0.05, 0.15]
        )
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = AppKitSearchFieldLifecycle.makeTextField(
            configuration: configuration,
            text: $text,
            focusToken: focusToken,
            coordinator: context.coordinator,
            commandHandler: commandHandler,
            canRequestFocus: canRequestFocus
        )
        textField.setAccessibilityIdentifier("command-palette.search")
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        textField.setAccessibilityIdentifier("command-palette.search")
        AppKitSearchFieldLifecycle.update(
            textField,
            configuration: configuration,
            text: $text,
            focusToken: focusToken,
            coordinator: context.coordinator,
            commandHandler: commandHandler,
            canRequestFocus: canRequestFocus
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView textField: NSTextField,
        context: Context
    ) -> CGSize? {
        guard let height = proposal.height else { return nil }
        return CGSize(width: proposal.width ?? textField.fittingSize.width, height: height)
    }

    static func dismantleNSView(
        _ textField: NSTextField,
        coordinator: AppKitSearchFieldCoordinator
    ) {
        coordinator.invalidateFocusRequests()
    }

    private static func markedTextShouldHandle(_ commandSelector: Selector) -> Bool {
        commandSelector == #selector(NSResponder.moveUp(_:))
            || commandSelector == #selector(NSResponder.moveDown(_:))
            || commandSelector == #selector(NSResponder.insertNewline(_:))
            || commandSelector == #selector(NSResponder.cancelOperation(_:))
    }
}

private struct CommandPaletteSectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(ToolTypography.groupHeader)
            .foregroundStyle(ToolTheme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Raycast-style bottom hints: the palette's keyboard grammar at a glance.
private struct CommandPaletteHintsBar: View {
    var body: some View {
        VStack(spacing: 0) {
            ToolDivider()
            HStack(spacing: 12) {
                Self.hint(key: "↑↓", label: "浏览")
                Self.hint(key: "↩", label: "执行")
                Spacer()
                Self.hint(key: "esc", label: "关闭")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
    }

    private static func hint(key: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(ToolTypography.tagMicro)
                .foregroundStyle(ToolTheme.textSecondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(ToolTheme.editorBackground, in: Capsule(style: .continuous))
            Text(label)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// v3 continuity flight: per-row launch icon anchors, keyed by row id so
/// RootView can resolve the takeoff point when a row activates.
struct PaletteRowIconAnchorsKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct CommandPaletteRow: View {
    let id: String
    let title: String
    var highlight: String = ""
    let subtitle: String?
    let systemImage: String
    var isActive: Bool = false
    var isKeyboardActive: Bool = false
    let pointerMovementTracker: CommandPalettePointerMovementTracker
    let onMouseMoveActive: () -> Void
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: ToolMetrics.IconSize.large, weight: .regular))
                    .foregroundStyle(isActive ? ToolTheme.accentHover : ToolTheme.textSecondary)
                    .frame(width: 18)
                    .anchorPreference(key: PaletteRowIconAnchorsKey.self, value: .bounds) {
                        [id: $0]
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.highlightedTitle(title, query: highlight))
                        .font(ToolTypography.bodyLarge)
                        .foregroundStyle(ToolTheme.textPrimary)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isActive {
                    Text("↩")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
            .background(
                isActive ? ToolTheme.selectionFill : Color.clear,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
            )
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                        .strokeBorder(ToolTheme.selectionStroke, lineWidth: 1)
                }
                if isKeyboardActive {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                        .strokeBorder(ToolTheme.focusRing, lineWidth: 1.5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .toolInteractionFeedback()
        .overlay {
            CommandPaletteMouseMoveActivation(
                pointerMovementTracker: pointerMovementTracker,
                onMouseMove: onMouseMoveActive
            )
        }
    }

    /// Accent-highlight the first case-insensitive query match in the title.
    private static func highlightedTitle(_ title: String, query: String) -> AttributedString {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let range = title.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive])
        else {
            return AttributedString(title)
        }
        var highlighted = AttributedString(String(title[range]))
        highlighted.foregroundColor = ToolTheme.accentHover
        return AttributedString(String(title[..<range.lowerBound]))
            + highlighted
            + AttributedString(String(title[range.upperBound...]))
    }
}

private struct CommandPaletteMouseMoveActivation: NSViewRepresentable {
    let pointerMovementTracker: CommandPalettePointerMovementTracker
    let onMouseMove: () -> Void

    func makeNSView(context: Context) -> CommandPaletteMouseMoveActivationView {
        let view = CommandPaletteMouseMoveActivationView()
        view.pointerMovementTracker = pointerMovementTracker
        view.onMouseMove = onMouseMove
        return view
    }

    func updateNSView(_ view: CommandPaletteMouseMoveActivationView, context: Context) {
        view.pointerMovementTracker = pointerMovementTracker
        view.onMouseMove = onMouseMove
    }
}

private final class CommandPaletteMouseMoveActivationView: NSView {
    var pointerMovementTracker: CommandPalettePointerMovementTracker?
    var onMouseMove: (() -> Void)?
    private var mouseTrackingArea: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let mouseTrackingArea {
            removeTrackingArea(mouseTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        mouseTrackingArea = trackingArea

        resetPointerBaselineToCurrentWindowLocation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resetPointerBaselineToCurrentWindowLocation()
    }

    override func mouseMoved(with event: NSEvent) {
        guard pointerMovementTracker?.acceptsMouseMoved(at: event.locationInWindow) == true else {
            return
        }
        onMouseMove?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func resetPointerBaselineToCurrentWindowLocation() {
        guard let window, pointerMovementTracker?.isSeeded != true else { return }
        pointerMovementTracker?.reset(to: window.mouseLocationOutsideOfEventStream)
    }
}
