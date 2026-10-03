import AppKit
import SwiftUI

private enum CommandPaletteMetrics {
    static let searchHeaderSpacing: CGFloat = 9
    static let searchHeaderLeadingPadding: CGFloat = 14
    static let searchHeaderTrailingPadding: CGFloat = 14
    static let searchClearLayoutSize: CGFloat = 15
    static let searchClearButtonSize: CGFloat = 24
    /// PageUp/PageDown step when no row has registered with the reveal
    /// registry yet (rows register on mount, so this only covers the very
    /// first press racing the list).
    static let pageStepFallback = 8
    /// 列表视口固定高度：面板整体尺寸恒定，任何查询切换都只有行内容变化。
    static let listHeight: CGFloat = 420
}

@MainActor
final class CommandPaletteContentLifecycle: ObservableObject, CommandPalettePresentationLifecycle {
    let revealRegistry = CommandPaletteRevealRegistry()
    let pointerMovementTracker = CommandPalettePointerMovementTracker()
    private(set) var sessionRevealRequest: CommandPaletteRevealRequest?

    private var liveSession: Int?
    private weak var sessionModel: CommandPaletteSessionModel?
    private var baseActions: [CommandActionEntry]
    private var revealRequestToken = 0
    private weak var searchField: NSTextField?
    private weak var searchCoordinator: AppKitSearchFieldCoordinator?

    init(
        session: Int,
        actions: [CommandActionEntry]
    ) {
        self.baseActions = actions
        resume(session: session)
    }

    func attachSessionModel(_ sessionModel: CommandPaletteSessionModel) {
        self.sessionModel = sessionModel
    }

    func updateActions(_ actions: [CommandActionEntry]) {
        baseActions = actions
    }

    func commandPaletteDidOpen(session: Int) {
        withTransaction(ToolMotion.disabledTransaction) {
            sessionModel?.beginSession(session, actions: baseActions)
            resume(session: session)
            // The persistent native field resets with the session while the
            // panel is still invisible: the text is cleared here (beginSession
            // already reset the model query) and focus scheduling is re-armed
            // after the previous session's close invalidation.
            searchField?.stringValue = ""
            searchCoordinator?.rearmFocusRequests()
            // Enable the persistent field ahead of the SwiftUI update pass and
            // attempt focus on this runloop turn — waiting for the scheduled
            // retry chain used to leave the first ~50ms of the open arc
            // without a cursor. A failed attempt (the first open has no
            // window yet) falls through to the [0.05, 0.15] retry chain; a
            // succeeded one makes those retries no-ops (already first
            // responder with the field editor owned).
            if let field = searchField {
                field.isEnabled = true
                field.window?.makeFirstResponder(field)
            }
            sessionRevealRequest = makeRevealRequest(
                source: .openReset,
                snapshot: sessionModel?.snapshot,
                session: session
            )
        }
    }

    func prepareSessionIfNeeded(session: Int) {
        guard sessionModel?.session != session else { return }
        commandPaletteDidOpen(session: session)
    }

    func makeRevealRequest(
        source: CommandPaletteActiveChangeSource,
        snapshot: CommandPaletteRowSnapshot?,
        session: Int
    ) -> CommandPaletteRevealRequest? {
        guard liveSession == session,
              let snapshot,
              let anchor = source.revealAnchor,
              let activeID = sessionModel?.navigationState.activeRowID(in: snapshot)
        else {
            return nil
        }

        revealRequestToken &+= 1
        revealRegistry.markRevealRequest(
            token: revealRequestToken,
            session: session
        )
        if case .keyboard = source {
            revealRegistry.markKeyboardRevealPending(
                itemID: activeID,
                token: revealRequestToken,
                session: session
            )
        }
        return CommandPaletteRevealRequest(
            id: activeID,
            anchor: anchor,
            token: revealRequestToken,
            session: session
        )
    }

    func resume(session: Int) {
        liveSession = session
        pointerMovementTracker.clear()
        revealRegistry.resume(session: session)
    }

    func attachSearchField(
        _ field: NSTextField,
        coordinator: AppKitSearchFieldCoordinator
    ) {
        searchField = field
        searchCoordinator = coordinator
    }

    func detachSearchField(_ field: NSTextField) {
        guard searchField === field else { return }
        searchField = nil
        searchCoordinator = nil
    }

    func commandPaletteDidClose(session: Int) {
        guard liveSession == session else { return }
        liveSession = nil
        revealRegistry.suspend(session: session)
        pointerMovementTracker.clear()

        // The persistent field stays in the retained tree after close, so the
        // close path owns dropping its field editor and disabling input —
        // exactly the editor teardown the per-session rebuild used to do.
        searchCoordinator?.invalidateFocusRequests()
        searchField?.isEnabled = false
        if let field = searchField,
           let window = field.window,
           let editor = field.currentEditor(),
           window.firstResponder === editor {
            window.makeFirstResponder(nil)
        }
    }

    func tearDown() {
        if let liveSession {
            commandPaletteDidClose(session: liveSession)
        }
    }
}


/// Modal "jump to anything" palette (Command-K). Fully self-contained: it owns
/// the presentation-local query, narrow tool projection, and active selection,
/// while reporting selections through injected closures. It holds no reference
/// to the app shell's own state.
@MainActor
struct CommandPaletteView: View {
    let presentation: CommandPalettePresentationModel
    let actions: [CommandActionEntry]
    let isPresented: Bool
    let reduceMotion: Bool
    let focusToken: Int
    let presentationSession: Int
    let canRequestSearchFocus: AppKitSearchFieldCoordinator.FocusRequestValidity
    let onSelectTool: (ToolID, String?) -> Void
    let onRunCommand: (CommandActionID) -> Void
    let onRequestFocus: () -> Void
    let onDismiss: () -> Void

    @StateObject private var sessionModel: CommandPaletteSessionModel
    @State private var revealRequest: CommandPaletteRevealRequest?
    @StateObject private var contentLifecycle: CommandPaletteContentLifecycle
    /// True when the active row was last set by keyboard arrows (not pointer).
    @State private var keyboardDrivenSession: Int?
    /// Row selection frames published by the list and resolved behind the
    /// rows by the floating highlight layer.
    @State private var rowAnchors: [String: Anchor<CGRect>] = [:]
    let usage: any PaletteUsageScoring

    init(
        presentation: CommandPalettePresentationModel,
        registry: ToolRegistry,
        actions: [CommandActionEntry],
        isPresented: Bool,
        reduceMotion: Bool,
        focusToken: Int,
        presentationSession: Int,
        canRequestSearchFocus: @escaping AppKitSearchFieldCoordinator.FocusRequestValidity,
        usage: any PaletteUsageScoring = NoPaletteUsage(),
        onSelectTool: @escaping (ToolID, String?) -> Void,
        onRunCommand: @escaping (CommandActionID) -> Void,
        onRequestFocus: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.actions = actions
        self.isPresented = isPresented
        self.reduceMotion = reduceMotion
        self.focusToken = focusToken
        self.presentationSession = presentationSession
        self.canRequestSearchFocus = canRequestSearchFocus
        self.usage = usage
        self.onSelectTool = onSelectTool
        self.onRunCommand = onRunCommand
        self.onRequestFocus = onRequestFocus
        self.onDismiss = onDismiss
        _sessionModel = StateObject(
            wrappedValue: CommandPaletteSessionModel(
                registry: registry,
                actions: actions,
                session: presentationSession,
                usage: usage
            )
        )
        _contentLifecycle = StateObject(
            wrappedValue: CommandPaletteContentLifecycle(
                session: presentationSession,
                actions: actions
            )
        )
    }

    private var isPresentationReady: Bool {
        isPresented && sessionModel.session == presentationSession
    }

    private func isLiveSession() -> Bool {
        isPresentationReady && canRequestSearchFocus()
    }

    /// Field callbacks guard on live presentation state instead of a
    /// body-time captured session: the native field persists across
    /// sessions, so only the live readiness checks can reject a replaced
    /// or closed presentation.
    private var queryBinding: Binding<String> {
        Binding(
            get: { sessionModel.query },
            set: { query in
                guard isLiveSession() else { return }
                updateQuery(query)
            }
        )
    }

    private func updateQuery(_ query: String) {
        guard isLiveSession(), sessionModel.setQuery(query) else { return }
        pruneRowAnchors(to: sessionModel.snapshot)
        requestActiveReveal(for: .queryReset, in: sessionModel.snapshot)
    }

    /// 查询变更只裁剪已消失行的锚点，而不是整表清空：行集身份不变的键入
    /// （如 "base6" → "base64"，同样的两行）不会让 ForEach 重算
    /// anchorPreference，整表清空后 onPreferenceChange 不再触发，浮动
    /// 高亮从此解析不到活动行（上下键只剩行内键盘焦点环）。仍挂载行的
    /// Anchor 在 resolve 时读取当前几何，位置随新布局自动更新，不会在
    /// 旧位置残影；被移除的行不可能成为活动行，死键没有解析机会。
    private func pruneRowAnchors(to snapshot: CommandPaletteRowSnapshot) {
        guard !rowAnchors.isEmpty else { return }
        let liveIDs = Set(snapshot.rows.filter(\.isSelectable).map(\.id))
        rowAnchors = rowAnchors.filter { liveIDs.contains($0.key) }
    }

    private func moveActive(by delta: Int) {
        guard isLiveSession() else { return }
        let snapshot = sessionModel.snapshot
        keyboardDrivenSession = presentationSession
        let previousActiveID = sessionModel.navigationState.activeRowID(in: snapshot)
        let visibleHandoffIndex = contentLifecycle.revealRegistry.visibleEdgeSelectableIndex(direction: delta)
        let isCurrentActiveVisible = previousActiveID.map(
            contentLifecycle.revealRegistry.isVisible(itemID:)
        ) ?? false
        let hasPendingKeyboardRevealForCurrentActive = previousActiveID.map(
            contentLifecycle.revealRegistry.hasLatestPendingKeyboardReveal(itemID:)
        ) ?? false
        let moveDecision = sessionModel.navigationState.keyboardMoveDecision(
            by: delta,
            in: snapshot,
            visibleHandoffIndex: visibleHandoffIndex,
            isCurrentActiveVisible: isCurrentActiveVisible,
            hasPendingKeyboardRevealForCurrentActive: hasPendingKeyboardRevealForCurrentActive,
            allowsVisibleHandoff: contentLifecycle.revealRegistry.hasManualScrollAfterLatestKeyboardReveal()
        )

        switch moveDecision {
        case .move(let index), .alignToVisibleSelectableIndex(let index):
            sessionModel.navigationState.setActiveSelectableIndex(index, in: snapshot)
        case .revealCurrent:
            requestActiveReveal(for: .keyboard(delta: delta))
        case .none:
            break
        }

        if sessionModel.navigationState.activeRowID(in: snapshot) != previousActiveID {
            requestActiveReveal(for: .keyboard(delta: delta), in: snapshot)
        }
    }

    /// Absolute keyboard jumps (Home/⌘↑ to the first row, End/⌘↓ to the
    /// last). Unlike arrow moves they bypass the visible-handoff policy — a
    /// jump always targets its endpoint, and the reveal anchor carries the
    /// direction so the native scroll settles on the matching edge.
    private func moveActiveToBoundary(delta: Int, targetIndex: Int) {
        guard isLiveSession() else { return }
        let snapshot = sessionModel.snapshot
        guard let target = CommandPaletteSearch.activationIndex(
            highlight: targetIndex,
            count: snapshot.selectableCount
        ) else {
            return
        }

        keyboardDrivenSession = presentationSession
        if sessionModel.navigationState.activeSelectableIndex(in: snapshot) != target {
            sessionModel.navigationState.setActiveSelectableIndex(target, in: snapshot)
        }
        requestActiveReveal(for: .keyboard(delta: delta), in: snapshot)
    }

    /// PageUp/PageDown move by the real visible row count, following the
    /// same reveal arc as arrow keys.
    private func moveActiveByPage(delta: Int) {
        guard isLiveSession() else { return }
        let snapshot = sessionModel.snapshot
        guard let current = sessionModel.navigationState.activeSelectableIndex(in: snapshot) else {
            return
        }
        let step = max(
            1,
            contentLifecycle.revealRegistry.visibleSelectableCount()
                ?? CommandPaletteMetrics.pageStepFallback
        )
        moveActiveToBoundary(delta: delta, targetIndex: current + delta * step)
    }

    private func activateActive() {
        guard isLiveSession(),
              let item = sessionModel.navigationState.activeRow(in: sessionModel.snapshot)
        else {
            return
        }
        activate(item)
    }

    private func setActiveItem(_ item: CommandPaletteRowProjection) {
        guard isLiveSession() else { return }
        let snapshot = sessionModel.snapshot
        keyboardDrivenSession = nil
        guard item.id != sessionModel.navigationState.activeRowID(in: snapshot) else { return }
        sessionModel.navigationState.setActiveRow(item, in: snapshot)
        requestActiveReveal(for: .pointerMove)
    }

    private func activate(_ item: CommandPaletteRowProjection) {
        guard isLiveSession() else { return }
        if let commandID = item.commandID {
            requestActiveReveal(for: .directActivation)
            onRunCommand(commandID)
            return
        }
        guard let toolID = sessionModel.navigationState.toolID(for: item) else { return }
        requestActiveReveal(for: .directActivation)
        // Keyword-tier matches carry the matched alias's hub segment, so a
        // search for "url" selecting 文本编码 lands directly on the URL
        // segment (same deep-link channel as the SmartPaste banner).
        onSelectTool(toolID, sessionModel.snapshot.deepLinkSegment(for: item))
    }

    private func requestActiveReveal(for source: CommandPaletteActiveChangeSource) {
        requestActiveReveal(for: source, in: sessionModel.snapshot)
    }

    private func requestActiveReveal(
        for source: CommandPaletteActiveChangeSource,
        in snapshot: CommandPaletteRowSnapshot
    ) {
        guard let request = contentLifecycle.makeRevealRequest(
            source: source,
            snapshot: snapshot,
            session: presentationSession
        ) else { return }
        revealRequest = request

        if case .keyboard = source {
            contentLifecycle.revealRegistry.revealImmediately(request: request)
        }
    }

    /// Warms the retained palette tree for the live presentation session.
    /// Reads the presentation model (a reference) instead of this struct's
    /// `isPresented`/`presentationSession` because onChange action closures
    /// execute on the previous body's view copy, where those stored
    /// properties still hold pre-transition values.
    private func preparePresentationIfNeeded() {
        guard presentation.shows else { return }
        contentLifecycle.prepareSessionIfNeeded(session: presentation.session)
    }

    /// Live-source presentation readiness for transition-boundary callbacks
    /// (see `preparePresentationIfNeeded`). Body-time reads should keep
    /// using `isPresentationReady`.
    private var isPresentationReadyLive: Bool {
        presentation.shows && sessionModel.session == presentation.session
    }

    private var currentRevealRequest: CommandPaletteRevealRequest? {
        if revealRequest?.session == presentationSession {
            return revealRequest
        }
        guard contentLifecycle.sessionRevealRequest?.session == presentationSession else {
            return nil
        }
        return contentLifecycle.sessionRevealRequest
    }

    @ViewBuilder
    private func paletteItemView(
        for item: CommandPaletteRowProjection,
        activeItemID: String?,
        selectableIndex: Int?,
        sectionCount: Int?,
        highlightRanges: [Range<String.Index>],
        subtitleAnnotation: CommandPaletteSubtitleAnnotation?
    ) -> some View {
        switch item {
        case .sectionTitle(let text):
            CommandPaletteSectionTitle(text, count: sectionCount)
        case .tool(let entry):
            CommandPaletteRow(
                title: entry.title,
                highlightRanges: highlightRanges,
                subtitle: subtitleAnnotation?.text ?? entry.categoryTitle,
                subtitleHighlightRanges: subtitleAnnotation?.highlightRanges ?? [],
                systemImage: entry.systemImage,
                isActive: item.id == activeItemID,
                isKeyboardActive: item.id == activeItemID
                    && keyboardDrivenSession == sessionModel.session
            ) {
                activate(item)
            }
            .background {
                CommandPaletteRowAttachment(
                    itemID: item.id,
                    selectableIndex: selectableIndex,
                    registry: contentLifecycle.revealRegistry,
                    session: presentationSession,
                    interactionEnabled: isPresentationReady,
                    revealRequest: currentRevealRequest?.id == item.id
                        ? currentRevealRequest : nil,
                    pointerMovementTracker: contentLifecycle.pointerMovementTracker,
                    onMouseMove: { setActiveItem(item) }
                )
            }
        case .command(let entry):
            CommandPaletteRow(
                title: entry.title,
                highlightRanges: highlightRanges,
                subtitle: entry.subtitle,
                systemImage: entry.systemImage,
                isActive: item.id == activeItemID,
                isKeyboardActive: item.id == activeItemID
                    && keyboardDrivenSession == sessionModel.session
            ) {
                activate(item)
            }
            .background {
                CommandPaletteRowAttachment(
                    itemID: item.id,
                    selectableIndex: selectableIndex,
                    registry: contentLifecycle.revealRegistry,
                    session: presentationSession,
                    interactionEnabled: isPresentationReady,
                    revealRequest: currentRevealRequest?.id == item.id
                        ? currentRevealRequest : nil,
                    pointerMovementTracker: contentLifecycle.pointerMovementTracker,
                    onMouseMove: { setActiveItem(item) }
                )
            }
        case .empty:
            VStack(spacing: 10) {
                Text("没有匹配的工具或命令")
                    .font(ToolTypography.bodyPlain)
                    .foregroundStyle(ToolTheme.textSecondary)
                // No-results states keep a recovery path (clear-and-retry)
                // instead of a dead end.
                Button {
                    guard isLiveSession() else { return }
                    updateQuery("")
                    onRequestFocus()
                } label: {
                    Text("清除搜索")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.accentHover)
                }
                .buttonStyle(.plain)
                .toolInteractionFeedback()
                .accessibilityIdentifier("command-palette.empty.clear")
            }
            .frame(maxWidth: .infinity)
            .frame(height: CommandPaletteMetrics.listHeight)
        }
    }

    /// One list row: content plus list padding and its selection-frame
    /// anchor. Rows mount fully visible — the panel's own open arc carries
    /// the entrance, so rapid ⌘K toggling never shows a blank list window.
    private func arrivedRow(
        for item: CommandPaletteRowProjection,
        activeItemID: String?,
        selectableIndex: Int?,
        sectionCount: Int?,
        highlightRanges: [Range<String.Index>],
        subtitleAnnotation: CommandPaletteSubtitleAnnotation?
    ) -> some View {
        paletteItemView(
            for: item,
            activeItemID: activeItemID,
            selectableIndex: selectableIndex,
            sectionCount: sectionCount,
            highlightRanges: highlightRanges,
            subtitleAnnotation: subtitleAnnotation
        )
        .padding(.horizontal, 9)
        .padding(.vertical, 1)
        .anchorPreference(key: CommandPaletteRowAnchorsKey.self, value: .bounds) { bounds in
            Self.rowAnchors(
                itemID: item.id,
                isSelectable: selectableIndex != nil,
                bounds: bounds
            )
        }
        .id(item.id)
    }

    private static func rowAnchors(
        itemID: String,
        isSelectable: Bool,
        bounds: Anchor<CGRect>
    ) -> [String: Anchor<CGRect>] {
        isSelectable ? [itemID: bounds] : [:]
    }

    /// The scrollable row list: rows with the floating
    /// selection highlight behind them.
    private func rowsSection(
        snapshot: CommandPaletteRowSnapshot,
        activeItemID: String?
    ) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(snapshot.rows) { item in
                    arrivedRow(
                        for: item,
                        activeItemID: activeItemID,
                        selectableIndex: snapshot.selectableIndex(of: item),
                        sectionCount: Self.sectionCount(for: item, in: snapshot),
                        highlightRanges: snapshot.titleHighlightRanges(for: item),
                        subtitleAnnotation: snapshot.subtitleAnnotation(for: item)
                    )
                }
            }
            .padding(.vertical, 4)
            // Floating selection highlight: resolves the active row's frame
            // in list space and springs between rows on keyboard moves
            // (geometry lives in `CommandPaletteSelectionHighlightHost`).
            .background {
                CommandPaletteSelectionHighlightHost(
                    activeItemID: activeItemID,
                    anchors: rowAnchors
                )
            }
            .onPreferenceChange(CommandPaletteRowAnchorsKey.self) { rowAnchors = $0 }
        }
        // 固定列表高度：查询切换（含清除搜索回落地页）不再让面板瞬时
        // 长高/缩矮——新露出区域行内容晚一帧布局的空白就是白闪的来源。
        .frame(height: CommandPaletteMetrics.listHeight)
    }

    /// ↩ 对当前选中行的语义：命令＝执行，工具（与兜底）＝跳转。
    private static func returnLabel(for row: CommandPaletteRowProjection?) -> String {
        row?.commandID != nil ? "执行" : "跳转"
    }

    private static func sectionCount(
        for item: CommandPaletteRowProjection,
        in snapshot: CommandPaletteRowSnapshot
    ) -> Int? {
        guard case .sectionTitle(let title) = item else { return nil }
        return snapshot.sectionCountsByTitle[title]
    }

    var body: some View {
        let _ = CommandPaletteTrace.count(.paletteBody, session: presentationSession)
        let _ = contentLifecycle.updateActions(actions)
        let snapshot = sessionModel.snapshot
        let activeItemID = sessionModel.navigationState.activeRowID(in: snapshot)
        let activeRow = sessionModel.navigationState.activeRow(in: snapshot)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CommandPaletteMetrics.searchHeaderSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: ToolMetrics.IconSize.medium, weight: .medium))
                    .foregroundStyle(ToolTheme.textSecondary)

                CommandPaletteSearchField(
                    placeholder: "搜索工具或命令…",
                    text: queryBinding,
                    focusToken: focusToken,
                    isSessionActive: isPresentationReady,
                    presentationSession: presentationSession,
                    canRequestFocus: {
                        isLiveSession()
                    },
                    contentLifecycle: contentLifecycle,
                    onSubmit: {
                        guard isLiveSession() else { return }
                        activateActive()
                    },
                    onMoveUp: {
                        guard isLiveSession() else { return }
                        moveActive(by: -1)
                    },
                    onMoveDown: {
                        guard isLiveSession() else { return }
                        moveActive(by: 1)
                    },
                    onMoveToFirst: {
                        guard isLiveSession() else { return }
                        moveActiveToBoundary(delta: -1, targetIndex: 0)
                    },
                    onMoveToLast: {
                        guard isLiveSession() else { return }
                        moveActiveToBoundary(delta: 1, targetIndex: .max)
                    },
                    onPageUp: {
                        guard isLiveSession() else { return }
                        moveActiveByPage(delta: -1)
                    },
                    onPageDown: {
                        guard isLiveSession() else { return }
                        moveActiveByPage(delta: 1)
                    },
                    onCancel: {
                        guard isLiveSession() else { return }
                        onDismiss()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: 24)

                ZStack {
                    if !sessionModel.query.isEmpty {
                        Button {
                            guard isLiveSession() else { return }
                            updateQuery("")
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
                .allowsHitTesting(!sessionModel.query.isEmpty)
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: sessionModel.query.isEmpty)
            }
            .padding(.leading, CommandPaletteMetrics.searchHeaderLeadingPadding)
            .padding(.trailing, CommandPaletteMetrics.searchHeaderTrailingPadding)
            .frame(height: 48)

            ToolDivider()

            rowsSection(snapshot: snapshot, activeItemID: activeItemID)

            CommandPaletteHintsBar(returnLabel: Self.returnLabel(for: activeRow))
        }
        .frame(width: 560)
        // Opaque surface, deliberately NOT the system material: a transient
        // `.regular` material re-composites under the open/close opacity arc
        // and flashes a bright placeholder frame (the “white block” on rapid
        // ⌘K). The palette is also the densest reading
        // surface, which the surface policy keeps opaque for readability.
        .indexSurface(
            .modal,
            fill: ToolTheme.popoverBackground,
            border: ToolTheme.strongBorder,
            borderWidth: 0.5
        )
        // The retained row/search subtree ignores the surrounding modal
        // transaction so a session reset cannot animate row insertion or text
        // replacement. Explicit control animations deeper in the subtree can
        // still opt in because this does not set `disablesAnimations`.
        .transaction { transaction in
            CommandPaletteTrace.presentationTransaction(
                session: isPresented ? presentationSession : sessionModel.session,
                isPresented: isPresented,
                isVisible: isPresentationReady,
                hasAnimation: transaction.animation != nil,
                disablesAnimations: transaction.disablesAnimations
            )
            transaction.animation = nil
        }
        .allowsHitTesting(isPresentationReady)
        .accessibilityHidden(!isPresentationReady)
        .onAppear {
            contentLifecycle.attachSessionModel(sessionModel)
            presentation.installLifecycle(contentLifecycle)
            CommandPaletteTrace.appeared(session: presentationSession)
            preparePresentationIfNeeded()
        }
        .onDisappear {
            presentation.removeLifecycle(contentLifecycle)
            contentLifecycle.tearDown()
        }
        .onChange(of: presentationSession) { _ in
            preparePresentationIfNeeded()
            // A rapid reopen must not paint the floating highlight at the
            // previous session's row frames before the list republishes
            // anchors. Only the open side clears the anchors: close also
            // bumps the session, and wiping anchors on the close path blanks
            // the selection highlight for one frame mid-fade — the selected
            // row then shows the bare near-white panel, a row-shaped bright
            // step (the residual ⌘K white flash; captured by the 60fps
            // autopilot ~70ms after esc, see CommandPaletteAutopilot).
            // During close the highlight rides the shared fade unchanged.
            if presentation.shows {
                rowAnchors = [:]
            }
        }
        .onChange(of: isPresented) { _ in
            preparePresentationIfNeeded()
        }
        .onChange(of: actions) { newActions in
            guard isPresentationReadyLive else { return }
            sessionModel.replaceActions(newActions)
        }
    }

}

struct CommandPaletteVisibilityGeometry: Equatable {
    let opacity: Double
    let offsetY: CGFloat

    /// Presentation mapping (MOTION cmdkIn/cmdkOut): the panel rises from
    /// `riseDistance` below while fading in; close reverses the same
    /// continuous function on the exit arc. One shared mapping keeps rapid
    /// open/close reversals continuous — the presentation never hard-switches
    /// geometry mid-flight. Deliberately opacity+translation only: a scale
    /// channel would resample the retained native-view subtree (~45 NSViews)
    /// on every interpolated frame and quantize the open arc into brightness
    /// steps.
    static func resolve(
        progress: CGFloat,
        reduceMotion: Bool
    ) -> Self {
        let progress = min(max(progress, 0), 1)
        return Self(
            opacity: Double(progress),
            offsetY: reduceMotion
                ? 0
                : ToolMotion.PaletteMotion.riseDistance * (1 - progress)
        )
    }
}
