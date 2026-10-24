import AppKit
import SwiftUI
import XToolsDesign

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
    /// Smart Detection 建议行激活（Batch D）：壳层读剪贴板预填并打开。
    let onSelectSuggestion: (ClipboardSuggestionModel.Suggestion) -> Void
    let onRunCommand: (CommandActionID) -> Void
    let onRequestFocus: () -> Void
    let onDismiss: () -> Void
    /// ⌘K 落地页「为你建议」（Batch D）：由壳层逐次同步（updateActions
    /// 同模式），落地页顶部 Section。
    let clipboardSuggestion: ClipboardSuggestionModel.Suggestion?

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
        clipboardSuggestion: ClipboardSuggestionModel.Suggestion? = nil,
        onSelectTool: @escaping (ToolID, String?) -> Void,
        onSelectSuggestion: @escaping (ClipboardSuggestionModel.Suggestion) -> Void,
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
        self.clipboardSuggestion = clipboardSuggestion
        self.onSelectTool = onSelectTool
        self.onSelectSuggestion = onSelectSuggestion
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

    /// Absolute keyboard jumps (Home/End to the first/last row). Unlike
    /// arrow moves they bypass the visible-handoff policy — a jump always
    /// targets its endpoint, and the reveal anchor carries the direction so
    /// the native scroll settles on the matching edge.
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

    /// ⌘↑/⌘↓ 跨分组跳转（Batch D）：跳到相邻 section 的首个可选中行。
    /// 走与箭头同一 active-row API 与 reveal 链；已在边界 section 时不动。
    /// 落地页（最近/动作/分类）与过滤态（动作/工具）的分组语义由
    /// snapshot 的 section 边界推导，各自正确。
    private func jumpActiveToSection(by direction: Int) {
        guard isLiveSession() else { return }
        let snapshot = sessionModel.snapshot
        keyboardDrivenSession = presentationSession
        let previousActiveID = sessionModel.navigationState.activeRowID(in: snapshot)
        let moved = sessionModel.navigationState.jumpActiveAcrossSections(
            by: direction,
            in: snapshot
        )
        if moved, sessionModel.navigationState.activeRowID(in: snapshot) != previousActiveID {
            requestActiveReveal(for: .keyboard(delta: direction), in: snapshot)
        }
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
        if case .suggestion(let suggestion) = item {
            requestActiveReveal(for: .directActivation)
            onSelectSuggestion(suggestion)
            return
        }
        guard let toolID = sessionModel.navigationState.toolID(for: item) else { return }
        requestActiveReveal(for: .directActivation)
        // Keyword-tier matches carry the matched alias's hub segment, so a
        // search for "url" selecting 文本编码 lands directly on the URL
        // segment (same deep-link channel as the SmartPaste banner). 直达
        // 模式的 segment 行（Batch D）也经同一通道。
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
            paletteRow(
                for: item,
                title: entry.title,
                highlightRanges: highlightRanges,
                subtitle: subtitleAnnotation?.text ?? entry.categoryTitle,
                subtitleHighlightRanges: subtitleAnnotation?.highlightRanges ?? [],
                systemImage: entry.systemImage,
                activeItemID: activeItemID,
                selectableIndex: selectableIndex
            )
        case .directSegment(_, let label, _):
            // 直达模式的 segment 行（Batch D）：segment 标签为主体，工具名
            // 作副标题；无高亮范围（直达列表不参与查询匹配）。
            paletteRow(
                for: item,
                title: label,
                highlightRanges: [],
                subtitle: Self.directSegmentSubtitle(for: item),
                subtitleHighlightRanges: [],
                systemImage: Self.directSegmentSystemImage(for: item),
                activeItemID: activeItemID,
                selectableIndex: selectableIndex
            )
        case .suggestion(let suggestion):
            // Smart Detection 建议行（Batch D）：工具为主体，类型判定文案
            // 作副标题（「剪贴板中有 JSON」——不含内容本体）。
            paletteRow(
                for: item,
                title: suggestion.toolTitle,
                highlightRanges: [],
                subtitle: suggestion.message,
                subtitleHighlightRanges: [],
                systemImage: suggestion.systemImage,
                activeItemID: activeItemID,
                selectableIndex: selectableIndex
            )
        case .command(let entry):
            paletteRow(
                for: item,
                title: entry.title,
                highlightRanges: highlightRanges,
                subtitle: entry.subtitle,
                subtitleHighlightRanges: [],
                systemImage: entry.systemImage,
                activeItemID: activeItemID,
                selectableIndex: selectableIndex
            )
        case .empty:
            VStack(spacing: ToolMetrics.Spacing.compact) {
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

    /// Shared tool/command row construction: both palette entries differ only
    /// in their subtitle source, so the row, its activation, and the reveal
    /// attachment stay in one place.
    private func paletteRow(
        for item: CommandPaletteRowProjection,
        title: String,
        highlightRanges: [Range<String.Index>],
        subtitle: String?,
        subtitleHighlightRanges: [Range<String.Index>],
        systemImage: String,
        activeItemID: String?,
        selectableIndex: Int?
    ) -> some View {
        CommandPaletteRow(
            title: title,
            highlightRanges: highlightRanges,
            subtitle: subtitle,
            subtitleHighlightRanges: subtitleHighlightRanges,
            systemImage: systemImage,
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
        .padding(.horizontal, ToolMetrics.Spacing.sm)
        .padding(.vertical, ToolMetrics.Spacing.hair)
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
            .padding(.vertical, ToolMetrics.Spacing.xs)
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

    private static func directSegmentSubtitle(for item: CommandPaletteRowProjection) -> String? {
        guard case .directSegment(let tool, _, _) = item else { return nil }
        return tool.title
    }

    private static func directSegmentSystemImage(for item: CommandPaletteRowProjection) -> String {
        guard case .directSegment(let tool, _, _) = item else { return "wrench.and.screwdriver" }
        return tool.systemImage
    }

    var body: some View {
        let _ = CommandPaletteTrace.count(.paletteBody, session: presentationSession)
        let _ = contentLifecycle.updateActions(actions)
        // 「为你建议」逐次同步（Batch D）：与 updateActions 同模式——值
        // 未变时 updateSuggestions 内部直接返回，不重建快照。
        let _ = sessionModel.updateSuggestions(clipboardSuggestion)
        let snapshot = sessionModel.snapshot
        let activeItemID = sessionModel.navigationState.activeRowID(in: snapshot)
        let activeRow = sessionModel.navigationState.activeRow(in: snapshot)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CommandPaletteMetrics.searchHeaderSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(ToolTypography.icon(ToolMetrics.IconSize.medium, .medium))
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
                    onJumpToPreviousSection: {
                        guard isLiveSession() else { return }
                        jumpActiveToSection(by: -1)
                    },
                    onJumpToNextSection: {
                        guard isLiveSession() else { return }
                        jumpActiveToSection(by: 1)
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
                        // 直达模式（Batch D）：Esc 退回普通搜索（去掉触发
                        // 直达的尾随空格）；普通态 Esc 关闭面板。
                        if sessionModel.directEntry != nil {
                            updateQuery(sessionModel.query.trimmingCharacters(in: .whitespaces))
                            onRequestFocus()
                        } else {
                            onDismiss()
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: ToolMetrics.Control.small)

                ZStack {
                    if !sessionModel.query.isEmpty {
                        Button {
                            guard isLiveSession() else { return }
                            updateQuery("")
                            onRequestFocus()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(ToolTypography.icon(ToolMetrics.IconSize.medium, .regular))
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
            .frame(height: ToolMetrics.Control.swatch)

            ToolDivider()

            rowsSection(snapshot: snapshot, activeItemID: activeItemID)

            CommandPaletteHintsBar(
                returnLabel: Self.returnLabel(for: activeRow),
                directToolTitle: sessionModel.directEntry?.tool.title
            )
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
            // capture ~70ms after esc).
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
