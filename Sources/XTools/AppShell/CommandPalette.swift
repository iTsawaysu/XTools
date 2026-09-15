import AppKit
import SwiftUI

private enum CommandPaletteMetrics {
    static let searchHeaderSpacing: CGFloat = 9
    static let searchHeaderLeadingPadding: CGFloat = 14
    static let searchHeaderTrailingPadding: CGFloat = 14
    static let searchClearLayoutSize: CGFloat = 15
    static let searchClearButtonSize: CGFloat = 24
}

@MainActor
private final class CommandPaletteContentLifecycle: ObservableObject, CommandPalettePresentationLifecycle {
    let revealRegistry = CommandPaletteRevealRegistry()
    let pointerMovementTracker = CommandPalettePointerMovementTracker()
    private(set) var sessionRevealRequest: CommandPaletteRevealRequest?

    private var liveSession: Int?
    private weak var sessionModel: CommandPaletteSessionModel?
    private var baseActions: [CommandActionEntry]
    private var revealRequestToken = 0
    private weak var searchField: NSTextField?
    private weak var searchCoordinator: AppKitSearchFieldCoordinator?
    private var searchSession: Int?

    init(
        session: Int,
        actions: [CommandActionEntry]
    ) {
        self.baseActions = actions.filter { $0.id != .copyGeneratedUUID }
        resume(session: session)
    }

    func attachSessionModel(_ sessionModel: CommandPaletteSessionModel) {
        self.sessionModel = sessionModel
    }

    func updateActions(_ actions: [CommandActionEntry]) {
        baseActions = actions.filter { $0.id != .copyGeneratedUUID }
    }

    func commandPaletteDidOpen(session: Int, previewValue: String?) {
        let actions = CommandActionEntry.paletteActions(
            baseActions: baseActions,
            previewValue: previewValue
        )
        withTransaction(ToolMotion.disabledTransaction) {
            sessionModel?.beginSession(session, actions: actions)
            resume(session: session)
            sessionRevealRequest = makeRevealRequest(
                source: .openReset,
                snapshot: sessionModel?.snapshot,
                session: session
            )
        }
    }

    func prepareSessionIfNeeded(
        session: Int,
        previewValue: String?
    ) {
        guard sessionModel?.session != session else { return }
        commandPaletteDidOpen(session: session, previewValue: previewValue)
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
        coordinator: AppKitSearchFieldCoordinator,
        session: Int
    ) {
        searchField = field
        searchCoordinator = coordinator
        searchSession = session
        field.isEnabled = liveSession == session
    }

    func detachSearchField(_ field: NSTextField) {
        guard searchField === field else { return }
        searchField = nil
        searchCoordinator = nil
        searchSession = nil
    }

    func commandPaletteDidClose(session: Int) {
        guard liveSession == session else { return }
        liveSession = nil
        revealRegistry.suspend(session: session)
        pointerMovementTracker.clear()

        guard searchSession == session else { return }
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
    let onSelectTool: (ToolID) -> Void
    let onRunCommand: (CommandActionID) -> Void
    let onRequestFocus: () -> Void
    let onDismiss: () -> Void

    @StateObject private var sessionModel: CommandPaletteSessionModel
    @State private var revealRequest: CommandPaletteRevealRequest?
    @StateObject private var contentLifecycle: CommandPaletteContentLifecycle
    /// True when the active row was last set by keyboard arrows (not pointer).
    @State private var keyboardDrivenSession: Int?
    init(
        presentation: CommandPalettePresentationModel,
        registry: ToolRegistry,
        actions: [CommandActionEntry],
        isPresented: Bool,
        reduceMotion: Bool,
        focusToken: Int,
        presentationSession: Int,
        canRequestSearchFocus: @escaping AppKitSearchFieldCoordinator.FocusRequestValidity,
        onSelectTool: @escaping (ToolID) -> Void,
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
        self.onSelectTool = onSelectTool
        self.onRunCommand = onRunCommand
        self.onRequestFocus = onRequestFocus
        self.onDismiss = onDismiss
        _sessionModel = StateObject(
            wrappedValue: CommandPaletteSessionModel(
                registry: registry,
                actions: actions,
                session: presentationSession
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

    private func isInputSessionLive(_ inputSession: Int) -> Bool {
        inputSession == presentationSession
            && inputSession == sessionModel.session
            && isLiveSession()
    }

    private func queryBinding(inputSession: Int) -> Binding<String> {
        Binding(
            get: { sessionModel.query },
            set: { query in
                guard isInputSessionLive(inputSession) else { return }
                updateQuery(query)
            }
        )
    }

    private func updateQuery(_ query: String) {
        guard isLiveSession(), sessionModel.setQuery(query) else { return }
        requestActiveReveal(for: .queryReset, in: sessionModel.snapshot)
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
        onSelectTool(toolID)
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

    private func preparePresentationIfNeeded() {
        guard isPresented else { return }
        contentLifecycle.prepareSessionIfNeeded(
            session: presentationSession,
            previewValue: presentation.previewValue
        )
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
        selectableIndex: Int?
    ) -> some View {
        switch item {
        case .sectionTitle(let text):
            CommandPaletteSectionTitle(text)
        case .tool(let entry):
            CommandPaletteRow(
                id: entry.id,
                title: entry.title,
                highlight: sessionModel.query,
                subtitle: entry.categoryTitle,
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
                    revealRequest: currentRevealRequest,
                    pointerMovementTracker: contentLifecycle.pointerMovementTracker,
                    onMouseMove: { setActiveItem(item) }
                )
            }
        case .command(let entry):
            CommandPaletteRow(
                id: entry.id.rawValue,
                title: entry.title,
                highlight: sessionModel.query,
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
                    revealRequest: currentRevealRequest,
                    pointerMovementTracker: contentLifecycle.pointerMovementTracker,
                    onMouseMove: { setActiveItem(item) }
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
        let _ = CommandPaletteTrace.count(.paletteBody, session: presentationSession)
        let _ = contentLifecycle.updateActions(actions)
        let snapshot = sessionModel.snapshot
        let activeItemID = sessionModel.navigationState.activeRowID(in: snapshot)
        let inputSession = sessionModel.session
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CommandPaletteMetrics.searchHeaderSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: ToolMetrics.IconSize.medium, weight: .medium))
                    .foregroundStyle(ToolTheme.textSecondary)

                CommandPaletteSearchField(
                    placeholder: "搜索工具或命令…",
                    text: queryBinding(inputSession: inputSession),
                    focusToken: focusToken,
                    presentationSession: inputSession,
                    canRequestFocus: {
                        isInputSessionLive(inputSession)
                    },
                    contentLifecycle: contentLifecycle,
                    onSubmit: {
                        guard isInputSessionLive(inputSession) else { return }
                        activateActive()
                    },
                    onMoveUp: {
                        guard isInputSessionLive(inputSession) else { return }
                        moveActive(by: -1)
                    },
                    onMoveDown: {
                        guard isInputSessionLive(inputSession) else { return }
                        moveActive(by: 1)
                    },
                    onCancel: {
                        guard isInputSessionLive(inputSession) else { return }
                        onDismiss()
                    }
                )
                .id(inputSession)
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
        .modifier(
            CommandPaletteVisibilityModifier(
                progress: isPresentationReady ? 1 : 0,
                isPresented: isPresented,
                reduceMotion: reduceMotion,
                traceSession: isPresented ? presentationSession : sessionModel.session
            )
        )
        .animation(
            ToolMotion.animation(ToolMotion.Preset.modal, reduceMotion: reduceMotion),
            value: isPresentationReady
        )
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
        }
        .onChange(of: isPresented) { _ in
            preparePresentationIfNeeded()
        }
        .onChange(of: actions) { newActions in
            guard isPresentationReady else { return }
            sessionModel.replaceActions(newActions)
        }
    }

}

/// Retained content cannot use an insertion transition after its first mount.
/// Drive the same modal geometry from one presentation-owned progress value:
/// opening settles upward by six points, while closing keeps the original
/// opacity-and-scale-only removal.
private struct CommandPaletteVisibilityModifier: @MainActor AnimatableModifier {
    var progress: CGFloat
    let isPresented: Bool
    let reduceMotion: Bool
    let traceSession: Int

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let _ = CommandPaletteTrace.presentationProgress(
            session: traceSession,
            isPresented: isPresented,
            progress: progress
        )
        content
            .opacity(progress)
            .scaleEffect(reduceMotion ? 1 : ToolMotion.Scale.modal + (1 - ToolMotion.Scale.modal) * progress)
            .offset(
                y: reduceMotion || !isPresented
                    ? 0
                    : -ToolMotion.Distance.small * (1 - progress)
            )
    }
}

private struct CommandPaletteSearchField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let focusToken: Int
    let presentationSession: Int
    let canRequestFocus: AppKitSearchFieldCoordinator.FocusRequestValidity
    let contentLifecycle: CommandPaletteContentLifecycle
    let onSubmit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onCancel: () -> Void

    @MainActor
    final class Coordinator {
        let search: AppKitSearchFieldCoordinator
        weak var contentLifecycle: CommandPaletteContentLifecycle?

        init(
            search: AppKitSearchFieldCoordinator,
            contentLifecycle: CommandPaletteContentLifecycle
        ) {
            self.search = search
            self.contentLifecycle = contentLifecycle
        }
    }

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

    func makeCoordinator() -> Coordinator {
        let presentationSession = presentationSession
        return Coordinator(
            search: AppKitSearchFieldCoordinator(
                text: $text,
                processedFocusToken: nil,
                focusRetryDelays: [0.05, 0.15],
                requestFocus: { textField, delayedRetries, isValid in
                    AppKitSearchFieldLifecycle.requestFocus(
                        textField,
                        delayedRetries: delayedRetries,
                        isValid: isValid,
                        observer: CommandPaletteTrace.focusAttemptObserver(
                            session: presentationSession
                        )
                    )
                }
            ),
            contentLifecycle: contentLifecycle
        )
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = AppKitSearchFieldLifecycle.makeTextField(
            configuration: configuration,
            text: $text,
            focusToken: focusToken,
            coordinator: context.coordinator.search,
            commandHandler: commandHandler,
            canRequestFocus: canRequestFocus
        )
        textField.setAccessibilityIdentifier("command-palette.search")
        contentLifecycle.attachSearchField(
            textField,
            coordinator: context.coordinator.search,
            session: presentationSession
        )
        CommandPaletteTrace.observeNativeReady(
            textField,
            session: presentationSession,
            isValid: canRequestFocus
        )
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        textField.setAccessibilityIdentifier("command-palette.search")
        AppKitSearchFieldLifecycle.update(
            textField,
            configuration: configuration,
            text: $text,
            focusToken: focusToken,
            coordinator: context.coordinator.search,
            commandHandler: commandHandler,
            canRequestFocus: canRequestFocus
        )
        contentLifecycle.attachSearchField(
            textField,
            coordinator: context.coordinator.search,
            session: presentationSession
        )
        CommandPaletteTrace.observeNativeReady(
            textField,
            session: presentationSession,
            isValid: canRequestFocus
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
        coordinator: Coordinator
    ) {
        coordinator.contentLifecycle?.detachSearchField(textField)
        coordinator.search.invalidateFocusRequests()
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
