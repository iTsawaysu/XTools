import AppKit
import SwiftUI

/// User-selected appearance preference. `system` defers to macOS appearance
/// (the default); `light`/`dark` are explicit overrides.
enum AppThemePreference: String, CaseIterable {
    case system
    case light
    case dark

    init(preferenceValue: String) {
        self = AppThemePreference(rawValue: preferenceValue) ?? .system
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var next: AppThemePreference {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }

    var title: String {
        switch self {
        case .system: return "主题:跟随系统"
        case .light: return "主题:浅色"
        case .dark: return "主题:深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var toastMessage: String {
        switch self {
        case .system: return "已切换为跟随系统外观"
        case .light: return "已切换到浅色"
        case .dark: return "已切换到深色"
        }
    }
}

enum SidebarVisibility: Equatable {
    case visible
    case hidden

    fileprivate init(preferenceValue: String) {
        self = preferenceValue == "hidden" ? .hidden : .visible
    }

    fileprivate var preferenceValue: String {
        self == .hidden ? "hidden" : "visible"
    }
}

@MainActor
protocol CommandPalettePresentationLifecycle: AnyObject {
    func commandPaletteDidOpen(session: Int, previewValue: String?)
    func commandPaletteDidClose(session: Int)
}

/// Lightweight presentation state observed only by the palette overlay host.
/// RootViewModel deliberately does not forward this object's notifications, so
/// opening or focusing the palette does not invalidate the full app shell.
@MainActor
final class CommandPalettePresentationModel: ObservableObject {
    private struct State {
        var shows = false
        var focusToken = 0
        var session = 0
        var previewValue: String?
        var hasPresented = false
    }

    @Published private var state = State()
    private weak var lifecycle: (any CommandPalettePresentationLifecycle)?

    var shows: Bool { state.shows }
    var focusToken: Int { state.focusToken }
    var session: Int { state.session }
    var previewValue: String? { state.previewValue }
    var hasPresented: Bool { state.hasPresented }

    func installLifecycle(_ lifecycle: any CommandPalettePresentationLifecycle) {
        self.lifecycle = lifecycle
    }

    func removeLifecycle(_ lifecycle: any CommandPalettePresentationLifecycle) {
        guard self.lifecycle === lifecycle else { return }
        self.lifecycle = nil
    }

    func consumePreviewValue() {
        guard state.previewValue != nil else { return }
        var next = state
        next.previewValue = nil
        state = next
    }

    func focus() {
        var next = state
        next.focusToken += 1
        state = next
    }

    func open() {
        if state.shows {
            focus()
            return
        }

        let nextSession = state.session + 1
        CommandPaletteTrace.requestStarted(session: nextSession)
        var next = state
        next.shows = true
        next.focusToken += 1
        next.session = nextSession
        next.previewValue = UUID().uuidString.lowercased()
        next.hasPresented = true
        CommandPaletteTrace.opened(session: nextSession)
        lifecycle?.commandPaletteDidOpen(
            session: nextSession,
            previewValue: next.previewValue
        )
        state = next
    }

    func toggle() {
        if state.shows {
            close()
        } else {
            open()
        }
    }

    func close() {
        guard state.shows else { return }
        let closingSession = state.session
        CommandPaletteTrace.dismissed(session: closingSession)
        var next = state
        next.shows = false
        next.session += 1
        state = next
        // MainActor serialization makes the new invalid session visible before
        // native callbacks are synchronously suspended.
        lifecycle?.commandPaletteDidClose(session: closingSession)
    }
}

@MainActor
final class RootViewModel: ObservableObject {
    @Published var selectedToolID: ToolID? {
        didSet {
            guard oldValue != selectedToolID else { return }
            // Keep the last valid tool available for the optional resume
            // preference while allowing the dashboard to use a nil selection.
            if let selectedToolID {
                preferences?.set(selectedToolID.rawValue, for: AppShellPreferenceKeys.selectedToolID)
            }
        }
    }
    @Published var searchText = ""
    @Published var autoResumeLastTool: Bool {
        didSet { preferences?.set(autoResumeLastTool, for: AppShellPreferenceKeys.autoResumeLastTool) }
    }
    @Published var sidebarVisibility: SidebarVisibility {
        didSet {
            guard oldValue != sidebarVisibility else { return }
            preferences?.set(sidebarVisibility.preferenceValue, for: AppShellPreferenceKeys.sidebarVisibility)
        }
    }
    @Published private(set) var searchFocusToken = 0
    let commandPalettePresentation = CommandPalettePresentationModel()

    var showsCommandPalette: Bool { commandPalettePresentation.shows }
    var commandPaletteFocusToken: Int { commandPalettePresentation.focusToken }
    var commandPalettePresentationSession: Int { commandPalettePresentation.session }
    var commandPalettePreviewValue: String? { commandPalettePresentation.previewValue }

    private let preferences: ToolPreferenceStore?

    init(preferences: ToolPreferenceStore? = nil) {
        self.preferences = preferences
        let selectedToolRawValue = preferences?.value(for: AppShellPreferenceKeys.selectedToolID) ?? ""
        self.selectedToolID = selectedToolRawValue.isEmpty
            ? nil
            : ToolID(rawValue: selectedToolRawValue)
        self.autoResumeLastTool = preferences?.value(for: AppShellPreferenceKeys.autoResumeLastTool) ?? false
        let sidebarPreference = preferences?.value(for: AppShellPreferenceKeys.sidebarVisibility) ?? "visible"
        self.sidebarVisibility = SidebarVisibility(preferenceValue: sidebarPreference)
    }

    func focusSearch() {
        searchFocusToken += 1
    }

    /// Expires the palette's one-shot preview payload after it is consumed.
    func consumeCommandPalettePreviewValue() {
        commandPalettePresentation.consumePreviewValue()
    }

    func focusCommandPalette() {
        commandPalettePresentation.focus()
    }

    func openCommandPalette() {
        commandPalettePresentation.open()
    }

    /// Toggles the command palette for the Command-K and toolbar triggers.
    /// Keeping this separate from `openCommandPalette()` preserves idempotent
    /// opening for navigation flows that need to reveal the palette.
    func toggleCommandPalette() {
        commandPalettePresentation.toggle()
    }

    func closeCommandPalette() {
        commandPalettePresentation.close()
    }

    var sidebarTogglePresentation: SidebarTogglePresentation {
        sidebarVisibility == .visible ? .hide : .show
    }

    func toggleSidebar(reduceMotion: Bool) {
        withToolAnimation(ToolMotion.Preset.shellResize, reduceMotion: reduceMotion) {
            sidebarVisibility = sidebarVisibility == .hidden ? .visible : .hidden
        }
    }
}

struct RootView: View {
    @StateObject private var viewModel: RootViewModel
    @StateObject private var toastCenter = ToolToastCenter()
    @StateObject private var fileInputPanelCoordinator = FileInputPanelCoordinator()
    @StateObject private var fileOutputPanelCoordinator = FileOutputPanelCoordinator()
    @StateObject private var favorites = FavoritesStore()
    @StateObject private var sidebarSections = SidebarSectionExpansionStore()
    @StateObject private var workspaceRepository: ToolWorkspaceRepository
    @StateObject private var dashboardStore: DashboardStore
    @StateObject private var smartPaste = SmartPasteMonitor()
    @StateObject private var systemAppearanceSource: SystemAppearanceSource
    @State private var previousSelectedToolID: ToolID?
    @State private var showsPreferences = false
    // v3 continuity flight: palette-row icon → page title rail.
    @StateObject private var iconFlight = PaletteIconFlightCoordinator()
    @AppStorage("dt.theme") private var themeName = AppThemePreference.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let registry = ToolRegistry.default

    init(
        viewModel: RootViewModel? = nil,
        defaults: UserDefaults = .standard,
        systemAppearanceSource: SystemAppearanceSource? = nil
    ) {
        _themeName = AppStorage(
            wrappedValue: defaults.string(forKey: "dt.theme") ?? AppThemePreference.system.rawValue,
            "dt.theme",
            store: defaults
        )
        let preferences = ToolPreferenceStore(defaults: defaults)
        _viewModel = StateObject(wrappedValue: viewModel ?? RootViewModel(preferences: preferences))
        let validToolIDs = Set(
            ToolRegistry.default.categoryGroups().flatMap { $0.tools.map(\.id) }
        )
        _favorites = StateObject(
            wrappedValue: FavoritesStore(defaults: defaults, validToolIDs: validToolIDs)
        )
        _workspaceRepository = StateObject(
            wrappedValue: ToolWorkspaceRepository(preferences: preferences)
        )
        _dashboardStore = StateObject(wrappedValue: DashboardStore(defaults: defaults))
        _systemAppearanceSource = StateObject(
            wrappedValue: systemAppearanceSource ?? SystemAppearanceSource()
        )
    }

    private var themePreference: AppThemePreference {
        AppThemePreference(preferenceValue: themeName)
    }

    private var resolvedColorScheme: ColorScheme {
        SystemAppearanceSource.resolvedColorScheme(
            preference: themePreference,
            systemColorScheme: systemAppearanceSource.colorScheme
        )
    }

    var body: some View {
        let _ = CommandPaletteTrace.count(.rootBody)
        ZStack {
            HStack(spacing: 0) {
                SidebarView(
                    projection: sidebarProjection,
                    selectedToolID: viewModel.selectedToolID,
                    favoriteOrder: favorites.favoriteIDs,
                    searchText: $viewModel.searchText,
                    searchFocusToken: viewModel.searchFocusToken,
                    onSelectTool: { _ = navigationActions.selectTool($0) },
                    onOpenDashboard: { navigationActions.openDashboard() },
                    onToggleFavorite: { toggleFavorite($0, showsToast: false) },
                    isSectionExpanded: { navigationActions.isSectionExpanded($0) },
                    onToggleSection: { navigationActions.toggleSection($0) },
                    onToggleSectionExclusive: { navigationActions.toggleSection($0, exclusive: true) },
                    onToggleTheme: toggleTheme,
                    onPreferences: showPreferences,
                    themeTitle: themePreference.title,
                    themeIcon: themePreference.icon
                )
                .frame(width: viewModel.sidebarVisibility == .visible ? SidebarView.idealWidth : 0)
                .clipped()
                .allowsHitTesting(viewModel.sidebarVisibility == .visible)
                .accessibilityHidden(viewModel.sidebarVisibility == .hidden)

                detailColumn
            }


            CommandPaletteOverlayHost(
                presentation: viewModel.commandPalettePresentation,
                registry: registry,
                baseActions: commandBaseActions,
                reduceMotion: reduceMotion,
                onSelectTool: launchFromPalette,
                onRunCommand: runPaletteCommand,
                onRequestFocus: viewModel.focusCommandPalette,
                onDismiss: closeCommandPaletteAnimated
            )
            .zIndex(2)

            if let flight = iconFlight.flight {
                PaletteIconGhostView(flight: flight) {
                    iconFlight.clearFlight()
                }
                .zIndex(4)
            }

            keyboardShortcuts

            ToolToastHost(center: toastCenter)
                .zIndex(3)
        }
        .modifier(FlightGeometryResolver(coordinator: iconFlight))
        .focusedSceneObject(viewModel)
        .frame(minWidth: 960, minHeight: 640)
        .background(ToolTheme.windowBackground)
        .background(WindowAppearanceOwner(preference: themePreference))
        .background(WindowChromeConfigurator())
        .background(FileInputPanelWindowBinder(coordinator: fileInputPanelCoordinator))
        .background(FileOutputPanelWindowBinder(coordinator: fileOutputPanelCoordinator))
        .tint(ToolTheme.accent)
        .environment(\.toolToastCenter, toastCenter)
        .environment(\.fileInputPanelClient, fileInputPanelCoordinator.client)
        .environment(\.fileOutputPanelClient, fileOutputPanelCoordinator.client)
        .environmentObject(workspaceRepository)
        .appThemeEnvironment(preference: themePreference, source: systemAppearanceSource)
        .toolbar {
            WindowToolbarContent(
                selectedTool: selectedTool,
                isSidebarVisible: viewModel.sidebarVisibility == .visible,
                isFavorite: selectedTool.map { favorites.isFavorite($0.id) } ?? false,
                onToggleSidebar: toggleSidebar,
                onToggleFavorite: toggleFavorite,
                onCommandPalette: { toggleCommandPaletteAnimated() },
                colorScheme: resolvedColorScheme
            )
        }
        .sheet(isPresented: $showsPreferences) {
            RootPreferencesSheet(
                themeName: $themeName,
                autoResumeLastTool: $viewModel.autoResumeLastTool,
                systemAppearanceSource: systemAppearanceSource
            )
        }
        .onAppear {
            previousSelectedToolID = viewModel.selectedToolID
            smartPaste.noteSelectedTool(viewModel.selectedToolID)
            navigationActions.selectDefaultToolIfNeeded(sidebarProjection.defaultToolID)
            ToolPageEntryBenchmark.runIfRequested(
                registry: registry,
                navigationActions: navigationActions
            )
        }
        .onChange(of: scenePhase) { phase in
            // Sample the clipboard only when the app comes forward — never in
            // the background.
            guard phase == .active else { return }
            smartPaste.refresh(registry: registry)
        }
        .onChange(of: viewModel.selectedToolID) { newToolID in
            if let previous = previousSelectedToolID, previous != newToolID {
                workspaceRepository.evictHeavyPayloads(for: previous)
            }
            previousSelectedToolID = newToolID
            smartPaste.noteSelectedTool(newToolID)
        }
    }

    private var detailColumn: some View {
        VStack(spacing: 0) {
            ToolDetailHostView(
                registry: registry,
                selectedToolID: viewModel.selectedToolID,
                dashboardStore: dashboardStore,
                favoriteIDs: favorites.favoriteIDs,
                onSelectTool: { _ = navigationActions.selectTool($0) },
                onOpenCommandPalette: { openCommandPaletteAnimated() },
                autoResumeLastTool: viewModel.autoResumeLastTool,
                onSetAutoResumeLastTool: { viewModel.autoResumeLastTool = $0 }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ToolTheme.workspaceBackground)
        // v3: one reliable transaction for the tool-switch arrival — the host
        // owns the id-driven transition; this root-level animation keyed on
        // the selection guarantees the crossfade plays even when the switch
        // originates outside the host (palette, sidebar, shortcuts).
        .toolAnimation(ToolMotion.Preset.pageArrival, value: viewModel.selectedToolID)
        // Floating suggestion: overlay keeps page layout, scroll ownership, and
        // control positions untouched while the hint is visible.
        .overlay(alignment: .top) {
            if let suggestion = smartPaste.suggestion {
                SmartPasteSuggestionBanner(
                    suggestion: suggestion,
                    onOpen: { _ = navigationActions.selectTool(suggestion.toolID) },
                    onDismiss: smartPaste.dismiss
                )
                .padding(.top, ToolMetrics.Spacing.md)
                .padding(.horizontal, ToolMetrics.Spacing.lg)
                .toolTransition(ToolMotion.Transition.topRowInsertion, reduceMotion: reduceMotion)
                .toolAnimation(ToolMotion.Preset.panelReveal, value: suggestion.toolID)
            }
        }
    }

    private var navigationActions: ToolNavigationActions {
        ToolNavigationActions(
            registry: registry,
            viewModel: viewModel,
            favorites: favorites,
            sidebarSections: sidebarSections,
            dashboardStore: dashboardStore
        )
    }

    private var sidebarProjection: ToolNavigationProjection {
        CommandPaletteTrace.count(.sidebarProjection)
        return ToolNavigationProjection(
            registry: registry,
            favoriteIDs: favorites.favoriteIDs,
            selectedToolID: viewModel.selectedToolID,
            query: viewModel.searchText
        )
    }

    private var selectedTool: RegisteredTool? {
        viewModel.selectedToolID.flatMap(registry.tool(for:))
    }

    // MARK: - Palette icon flight (v3 continuity)

    /// Launch a tool from the command palette, capturing the row icon's
    /// takeoff point so the icon can fly to the arriving page's title rail.
    /// Sidebar and keyboard launches skip the flight — the palette is the one
    /// surface whose geometry this owns.
    private func launchFromPalette(_ toolID: ToolID) {
        iconFlight.cancelPendingLaunch()
        if viewModel.selectedToolID != toolID,
           !reduceMotion,
           let tool = registry.tool(for: toolID),
           let fromRect = iconFlight.paletteIconRects["tool.\(toolID.rawValue)"] {
            iconFlight.beginLaunch(
                PendingPaletteFlight(
                    toolID: toolID,
                    systemImage: tool.systemImage,
                    from: CGPoint(x: fromRect.midX, y: fromRect.midY)
                )
            )
        }
        _ = navigationActions.selectTool(toolID)
        closeCommandPaletteAnimated()
    }

    // MARK: - Animated palette presentation (v3)

    /// Palette open/close must run inside one explicit animation transaction:
    /// an `.animation(value:)` wrapper alone is unreliable across the if-branch
    /// plus AppKit search field insertion, which read as a hard pop.
    private func toggleCommandPaletteAnimated() {
        withToolAnimation(ToolMotion.Preset.modal) {
            navigationActions.toggleCommandPalette()
        }
    }

    private func openCommandPaletteAnimated() {
        withToolAnimation(ToolMotion.Preset.modal) {
            navigationActions.openCommandPalette()
        }
    }

    private func closeCommandPaletteAnimated() {
        withToolAnimation(ToolMotion.Preset.modal) {
            navigationActions.closeCommandPalette()
        }
    }

    // MARK: - Command system

    /// Shell commands shown beside tool navigation in the palette. The list is
    /// bounded by `CommandActionID`; execution lives in `runPaletteCommand`.
    private var commandBaseActions: [CommandActionEntry] {
        [
            CommandActionEntry(
                id: .toggleAppearance,
                title: "切换主题",
                subtitle: themePreference.title,
                systemImage: themePreference.icon,
                keywords: ["外观", "深色", "浅色", "跟随系统", "theme"]
            ),
            CommandActionEntry(
                id: .toggleSidebar,
                title: viewModel.sidebarTogglePresentation.title,
                subtitle: "侧边栏",
                systemImage: "sidebar.left",
                keywords: ["侧栏", "sidebar"]
            ),
            CommandActionEntry(
                id: .openPreferences,
                title: "打开设置",
                subtitle: "外观与启动行为",
                systemImage: "gearshape",
                keywords: ["偏好", "设置", "preferences"]
            ),
        ]
    }

    private func runPaletteCommand(_ action: CommandActionID) {
        closeCommandPaletteAnimated()
        switch action {
        case .toggleAppearance:
            toggleTheme()
        case .toggleSidebar:
            toggleSidebar()
        case .openPreferences:
            showPreferences()
        case .copyGeneratedUUID:
            guard let value = viewModel.commandPalettePreviewValue else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            toastCenter.show(ToolFeedbackCopy.copied, tone: .success)
            // One-shot preview: consuming the row expires the payload so a
            // stale value is never copied twice from an old session.
            viewModel.consumeCommandPalettePreviewValue()
        }
    }

    private func toggleFavorite() {
        guard let tool = selectedTool else { return }
        toggleFavorite(tool.id, showsToast: true)
    }

    private func toggleFavorite(_ toolID: ToolID, showsToast: Bool) {
        guard let nowFavorite = navigationActions.toggleFavorite(toolID) else { return }
        guard showsToast else { return }
        toastCenter.show(nowFavorite ? "已加入收藏" : "已取消收藏", tone: .success)
    }

    private var keyboardShortcuts: some View {
        Group {
            Button("Focus Search", action: focusSidebarSearch)
                .keyboardShortcut("f", modifiers: .command)

            Button("Command Palette", action: { toggleCommandPaletteAnimated() })
                .keyboardShortcut("k", modifiers: .command)

            Button("Workbench", action: { navigationActions.openDashboard() })
                .keyboardShortcut("0", modifiers: .command)

            Button("Preferences", action: showPreferences)
                .keyboardShortcut(",", modifiers: .command)

            ForEach(Array(registry.categoryGroups().enumerated()), id: \.offset) { index, group in
                Button("Category \(group.category.title)") {
                    _ = navigationActions.selectCategory(at: index)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }

            Button("Cancel", action: cancelCurrentMode)
                .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func focusSidebarSearch() {
        if viewModel.sidebarVisibility == .hidden {
            setSidebarVisibility(.visible)
        }

        viewModel.focusSearch()
    }

    private func showPreferences() {
        closeCommandPaletteAnimated()
        showsPreferences = true
    }

    private func toggleTheme() {
        let next = themePreference.next
        themeName = next.rawValue
        toastCenter.show(next.toastMessage, tone: .success)
    }

    private func toggleSidebar() {
        viewModel.toggleSidebar(reduceMotion: reduceMotion)
    }

    private func setSidebarVisibility(_ visibility: SidebarVisibility) {
        withToolAnimation(ToolMotion.Preset.shellResize, reduceMotion: reduceMotion) {
            viewModel.sidebarVisibility = visibility
        }
    }

    private func cancelCurrentMode() {
        if viewModel.showsCommandPalette {
            closeCommandPaletteAnimated()
            return
        }

        if !viewModel.searchText.isEmpty {
            viewModel.searchText = ""
        }
    }
}

private struct RootPreferencesSheet: View {
    @Binding var themeName: String
    @Binding var autoResumeLastTool: Bool
    @ObservedObject var systemAppearanceSource: SystemAppearanceSource
    @Environment(\.dismiss) private var dismiss

    private var themePreference: AppThemePreference {
        AppThemePreference(preferenceValue: themeName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(ToolTypography.sectionHeader)
                        .foregroundStyle(ToolTheme.textPrimary)
                    Text("调整 XTools 的外观和启动行为。")
                        .font(ToolTypography.bodyPlain)
                        .foregroundStyle(ToolTheme.textSecondary)
                }
                Spacer(minLength: 12)
                Button("完成") { dismiss() }
                    .buttonStyle(IndexButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
            }

            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: 0.5)
                .padding(.vertical, 20)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("外观")
                        .font(ToolTypography.label)
                        .foregroundStyle(ToolTheme.textSecondary)
                    Picker("主题", selection: $themeName) {
                        Text("跟随系统").tag(AppThemePreference.system.rawValue)
                        Text("浅色").tag(AppThemePreference.light.rawValue)
                        Text("深色").tag(AppThemePreference.dark.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("主题")
                }

                Toggle(isOn: $autoResumeLastTool) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("启动时继续上次工具")
                            .font(ToolTypography.bodyMedium)
                            .foregroundStyle(ToolTheme.textPrimary)
                        Text("关闭时，XTools 会直接打开个人工作台。")
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textSecondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("所有设置只保存在本机。")
            }
            .font(ToolTypography.caption)
            .foregroundStyle(ToolTheme.textTertiary)
        }
        .padding(24)
        .frame(width: 440, height: 300)
        .background(ToolTheme.panelBackground)
        .background(WindowAppearanceOwner(preference: themePreference))
        .appThemeEnvironment(preference: themePreference, source: systemAppearanceSource)
    }
}

/// Stable lightweight observer for presentation-only state. The first open
/// creates one retained palette tree; later sessions reset its local model while
/// its native row identities remain stable.
private struct CommandPaletteOverlayHost: View {
    @ObservedObject var presentation: CommandPalettePresentationModel
    let registry: ToolRegistry
    let baseActions: [CommandActionEntry]
    let reduceMotion: Bool
    let onSelectTool: (ToolID) -> Void
    let onRunCommand: (CommandActionID) -> Void
    let onRequestFocus: () -> Void
    let onDismiss: () -> Void

    private var actions: [CommandActionEntry] {
        CommandActionEntry.paletteActions(
            baseActions: baseActions,
            previewValue: presentation.previewValue
        )
    }

    var body: some View {
        ZStack {
            if presentation.hasPresented {
                CommandPaletteScrim(onDismiss: onDismiss)
                    .opacity(presentation.shows ? 1 : 0)
                    .allowsHitTesting(presentation.shows)
                    .accessibilityHidden(!presentation.shows)
                    .animation(
                        ToolMotion.animation(ToolMotion.Preset.modal, reduceMotion: reduceMotion),
                        value: presentation.shows
                    )
                    .toolTransition(ToolMotion.Transition.scrim, reduceMotion: reduceMotion)
                    .zIndex(1)

                let presentationSession = presentation.session
                CommandPaletteView(
                    presentation: presentation,
                    registry: registry,
                    actions: actions,
                    isPresented: presentation.shows,
                    reduceMotion: reduceMotion,
                    focusToken: presentation.focusToken,
                    presentationSession: presentationSession,
                    canRequestSearchFocus: {
                        presentation.shows && presentation.session == presentationSession
                    },
                    onSelectTool: onSelectTool,
                    onRunCommand: onRunCommand,
                    onRequestFocus: onRequestFocus,
                    onDismiss: onDismiss
                )
                .toolTransition(
                    ToolMotion.Transition.commandPalette,
                    reduceMotion: reduceMotion
                )
                .zIndex(2)
            }
        }
    }
}

private struct CommandPaletteScrim: View {
    let onDismiss: () -> Void

    var body: some View {
        Color.black.opacity(0.30)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
    }
}

/// Owns the palette→title continuity flight: anchor collection, coordinate
/// resolution, and the pending→active handoff when the new page's title rail
/// publishes its geometry.
@MainActor
private final class PaletteIconFlightCoordinator: ObservableObject {
    private(set) var paletteIconRects: [String: CGRect] = [:]
    @Published private(set) var flight: PaletteIconFlight?
    private var pending: PendingPaletteFlight?

    func beginLaunch(_ pending: PendingPaletteFlight) {
        self.pending = pending
    }

    func cancelPendingLaunch() {
        pending = nil
    }

    func clearFlight() {
        flight = nil
        pending = nil
    }

    func resolve(proxy: GeometryProxy, iconAnchors: [String: Anchor<CGRect>], railAnchor: Anchor<CGRect>?) {
        CommandPaletteTrace.count(.iconAnchorResolution)
        paletteIconRects = iconAnchors.mapValues { proxy[$0] }
        guard let pending, let railRect = railAnchor.map({ proxy[$0] }) else { return }
        flight = PaletteIconFlight(
            systemImage: pending.systemImage,
            from: pending.from,
            to: CGPoint(x: railRect.minX, y: railRect.minY),
            id: pending.toolID.rawValue
        )
        self.pending = nil
    }
}

/// Resolves the continuity-flight anchors into the root ZStack coordinate
/// space and keeps them current.
private struct FlightGeometryResolver: ViewModifier {
    let coordinator: PaletteIconFlightCoordinator
    @State private var iconAnchors: [String: Anchor<CGRect>] = [:]
    @State private var railAnchor: Anchor<CGRect>?

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: iconAnchors) { anchors in
                            coordinator.resolve(proxy: proxy, iconAnchors: anchors, railAnchor: railAnchor)
                        }
                        .onChange(of: railAnchor) { newRailAnchor in
                            coordinator.resolve(proxy: proxy, iconAnchors: iconAnchors, railAnchor: newRailAnchor)
                        }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onPreferenceChange(PaletteRowIconAnchorsKey.self) { iconAnchors = $0 }
            .onPreferenceChange(PageTitleRailAnchorKey.self) { railAnchor = $0 }
    }
}

/// Pending takeoff captured at palette-row activation, waiting for the new
/// page's title rail geometry to arrive.
private struct PendingPaletteFlight: Equatable {
    let toolID: ToolID
    let systemImage: String
    let from: CGPoint
}

private struct PaletteIconFlight: Equatable {
    let systemImage: String
    let from: CGPoint
    let to: CGPoint
    let id: String
}

/// Transient accent ghost that carries the launched tool's icon from its
/// palette row to the arriving page's title rail. Decorative only: no hit
/// testing, no accessibility presence, removed right after landing.
private struct PaletteIconGhostView: View {
    let flight: PaletteIconFlight
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        Image(systemName: flight.systemImage)
            .font(.system(size: ToolMetrics.IconSize.large, weight: .medium))
            .foregroundStyle(ToolTheme.accent)
            .scaleEffect(arrived ? 0.7 : 1)
            .opacity(arrived ? 0 : 0.95)
            .position(arrived ? flight.to : flight.from)
            .animation(ToolMotion.animation(ToolMotion.Preset.settle, reduceMotion: reduceMotion), value: arrived)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                if !reduceMotion {
                    try? await Task.sleep(for: .milliseconds(16))
                    withToolAnimation(ToolMotion.Preset.settle) {
                        arrived = true
                    }
                    try? await Task.sleep(for: .milliseconds(380))
                }
                onFinished()
            }
    }
}
