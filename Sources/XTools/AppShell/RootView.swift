import AppKit
import SwiftUI

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
    @StateObject private var hubSegmentEntryHint = HubSegmentEntryHint()
    @StateObject private var systemAppearanceSource: SystemAppearanceSource
    @State private var previousSelectedToolID: ToolID?
    @State private var showsPreferences = false
    // ⌘K frecency: palette launches feed the recents landing section and
    // within-tier ranking refinement. Deliberately NOT observed: recording
    // a launch must not invalidate the app shell (the palette reads it
    // synchronously when composing snapshots).
    private let paletteRecents: PaletteRecentsStore
    @AppStorage("dt.theme") private var themeName = AppThemePreference.system.preferenceValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let registry = ToolRegistry.default

    init(
        viewModel: RootViewModel? = nil,
        defaults: UserDefaults = .standard,
        systemAppearanceSource: SystemAppearanceSource? = nil
    ) {
        _themeName = AppStorage(
            wrappedValue: defaults.string(forKey: "dt.theme") ?? AppThemePreference.system.preferenceValue,
            "dt.theme",
            store: defaults
        )
        let preferences = ToolPreferenceStore(defaults: defaults)
        _viewModel = StateObject(wrappedValue: viewModel ?? RootViewModel(preferences: preferences))
        self.paletteRecents = PaletteRecentsStore(preferences: preferences)
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
                usage: paletteRecents,
                onSelectTool: launchFromPalette,
                onRunCommand: runPaletteCommand,
                onRequestFocus: viewModel.focusCommandPalette,
                onDismiss: closeCommandPaletteAnimated
            )
            .zIndex(2)

            keyboardShortcuts

            ToolToastHost(center: toastCenter)
                .zIndex(3)
        }
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
        .environmentObject(hubSegmentEntryHint)
        .appThemeEnvironment(preference: themePreference, source: systemAppearanceSource)
        .toolbar {
            WindowToolbarContent(
                selectedTool: selectedTool,
                isSidebarVisible: viewModel.sidebarVisibility == .visible,
                isFavorite: selectedTool.map { favorites.isFavorite($0.id) } ?? false,
                // 传模型引用（let 常量，不读计算属性）：读取 showsCommandPalette
                // 会在 body 里依赖面板状态，而面板开关不触发 body 重估——压暗
                // 观察在 CommandTriggerLabel 内完成。
                presentation: viewModel.commandPalettePresentation,
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
        // control positions untouched while the hint is visible. The entrance/
        // exit transaction comes from the monitor's applyToolMotion writes; the
        // container-level animation below is the same belt-and-braces the toast
        // host carries. `.id(suggestion)` forces a remove+insert when a new
        // clipboard replaces the visible banner (same-tick nil→new writes would
        // otherwise merge into an unanimated content swap).
        .overlay(alignment: .top) {
            if let suggestion = smartPaste.suggestion {
                SmartPasteSuggestionBanner(
                    suggestion: suggestion,
                    onOpen: {
                        // 深链目标带分段时先写提示（带 toolID，由目标 Hub 校验
                        // 消费），再切换工具；Hub 出现时一次性消费（覆盖记忆
                        // 的分段）。
                        hubSegmentEntryHint.request = suggestion.hubSegment.map {
                            HubSegmentEntryHint.Request(toolID: suggestion.toolID, segment: $0)
                        }
                        _ = navigationActions.selectTool(suggestion.toolID)
                    },
                    onDismiss: smartPaste.dismiss
                )
                .id(suggestion)
                .padding(.top, ToolMetrics.Spacing.md)
                .padding(.horizontal, ToolMetrics.Spacing.lg)
                .toolTransition(ToolMotion.Transition.toastPanel, reduceMotion: reduceMotion)
            }
        }
        .animation(
            ToolMotion.animation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion),
            value: smartPaste.suggestion
        )
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

    // MARK: - Palette launches

    /// Launch a tool from the command palette. A keyword-tier match carries
    /// the matched alias's hub segment: write the one-shot segment hint
    /// BEFORE switching (same channel as the SmartPaste banner) so the
    /// arriving hub consumes it and overrides its remembered segment.
    private func launchFromPalette(_ toolID: ToolID, segment: String?) {
        if let segment {
            hubSegmentEntryHint.request = HubSegmentEntryHint.Request(
                toolID: toolID,
                segment: segment
            )
        }
        paletteRecents.recordLaunch(toolID)
        _ = navigationActions.selectTool(toolID)
        closeCommandPaletteAnimated()
    }

    // MARK: - Animated palette presentation (v3)

    /// Palette open/close uses one explicit transaction shared by the stable
    /// presentation shell; AppKit field/session replacement stays inside it.
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
            CommandActionEntry(
                id: .copyGeneratedUUID,
                title: "生成并复制 UUID",
                subtitle: "随机唯一标识符",
                systemImage: "barcode",
                keywords: ["uuid", "复制", "生成"]
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
            // The value is generated at activation: every run copies a fresh
            // UUID with the shared copy toast feedback.
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(UUID().uuidString.lowercased(), forType: .string)
            toastCenter.show(ToolFeedbackCopy.copied, tone: .success)
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
            // ⌘F lives in the Edit menu (FindMenuCommands): it opens the
            // focused text surface's native find bar and falls back to the
            // sidebar tool search when no editor holds focus.
            Button("Workbench", action: { navigationActions.openDashboard() })
                .keyboardShortcut("0", modifiers: .command)

            Button("Preferences", action: showPreferences)
                .keyboardShortcut(",", modifiers: .command)

            ForEach(Array(registry.categoryGroups().enumerated()), id: \.offset) { index, group in
                // 只给前 9 个分类赋 ⌘1-⌘9：第 10 个分类的 Character("10")
                // 会在 body 求值期触发 precondition 崩溃。
                if index < 9 {
                    Button("Category \(group.category.title)") {
                        _ = navigationActions.selectCategory(at: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }

            Button("Cancel", action: cancelCurrentMode)
                .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func showPreferences() {
        closeCommandPaletteAnimated()
        showsPreferences = true
    }

    private func toggleTheme() {
        let next = themePreference.next
        // Wave 2 theme crossfade: the colorScheme flip dissolves through one
        // shared envelope instead of hard-cutting (AppKit sidebar chrome still
        // flips natively via WindowAppearanceOwner).
        withToolAnimation(ToolMotion.Preset.themeCrossfade, reduceMotion: reduceMotion) {
            themeName = next.preferenceValue
        }
        toastCenter.show(next.toastMessage, tone: .success)
    }

    private func toggleSidebar() {
        viewModel.toggleSidebar(reduceMotion: reduceMotion)
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
