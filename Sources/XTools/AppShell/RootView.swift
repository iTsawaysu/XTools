import AppKit
import SwiftUI
import XToolsDesign

struct RootView: View {
    // 导航 5 状态 + 侧栏搜索聚焦 token 下沉 ShellNavigationModel（C1 分家）；
    // 面板/Toast 已是独立模型（rootBody=0 隔离契约），此处只组合。
    @StateObject private var navigation: ShellNavigationModel
    @StateObject private var toastCenter = ToolToastCenter()
    @StateObject private var fileInputPanelCoordinator = FileInputPanelCoordinator()
    @StateObject private var fileOutputPanelCoordinator = FileOutputPanelCoordinator()
    // 收藏 / 折叠 / 使用频率是侧栏与页面局部观察状态（阶段③ B4 契约）：
    // RootView 刻意不订阅——收藏切换只触发侧栏/页面局部重估，Section 折叠
    // 只触发列表区重估，rootBody 保持 0。所有权沿用 paletteRecents 先例：
    // init 构造、无观察引用下发；Batch D 多窗口时升级为环境注入共享单例。
    private let favorites: FavoritesStore
    private let sidebarSections: SidebarSectionExpansionStore
    @StateObject private var workspaceRepository: ToolWorkspaceRepository
    @StateObject private var dashboardStore: DashboardStore
    @StateObject private var smartPaste = SmartPasteMonitor()
    @StateObject private var hubSegmentEntryHint = HubSegmentEntryHint()
    @StateObject private var systemAppearanceSource: SystemAppearanceSource
    @State private var showsPreferences = false
    // 投影记忆化：RootView 会在无关 shell 抖动（toast、建议横幅）时整体重估
    // body；查询、选择未变时重建整个导航树是纯浪费。投影自阶段③ B 起不含
    // 收藏（收藏观察已下沉侧栏），缓存键收敛为（查询、选择）二元组。
    @State private var sidebarProjectionCache = SidebarProjectionCache()
    // detail 列的动作路由盒：见 DetailActionRouting 协议注释。
    @State private var detailRouting = DetailActionRoutingBox()
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
        navigation: ShellNavigationModel? = nil,
        defaults: UserDefaults = .standard,
        workspaceRepository: ToolWorkspaceRepository? = nil,
        systemAppearanceSource: SystemAppearanceSource? = nil
    ) {
        _themeName = AppStorage(
            wrappedValue: defaults.string(forKey: "dt.theme") ?? AppThemePreference.system.preferenceValue,
            "dt.theme",
            store: defaults
        )
        let preferences = ToolPreferenceStore(defaults: defaults)
        _navigation = StateObject(wrappedValue: navigation ?? ShellNavigationModel(preferences: preferences))
        // frecency 单源（阶段③）：仪表盘与 ⌘K 面板共用同一事件环与衰减
        // 公式，两消费方各持通道门面委托读写（导航 = .navigation，⌘K = .palette）。
        let usageFrequency = ToolUsageFrequencyStore(defaults: defaults)
        self.paletteRecents = PaletteRecentsStore(usage: usageFrequency)
        let validToolIDs = Set(
            ToolRegistry.default.categoryGroups().flatMap { $0.tools.map(\.id) }
        )
        self.favorites = FavoritesStore(defaults: defaults, validToolIDs: validToolIDs)
        self.sidebarSections = SidebarSectionExpansionStore(defaults: defaults)
        _workspaceRepository = StateObject(
            wrappedValue: workspaceRepository ?? ToolWorkspaceRepository(preferences: preferences)
        )
        _dashboardStore = StateObject(wrappedValue: DashboardStore(usage: usageFrequency))
        _systemAppearanceSource = StateObject(
            wrappedValue: systemAppearanceSource ?? SystemAppearanceSource()
        )
    }

    private var themePreference: AppThemePreference {
        AppThemePreference(preferenceValue: themeName)
    }

    /// 侧栏 + detail 双列（C1 分家：body 拆子表达式，控制类型检查复杂度；
    /// 布局与观察面不变）。
    private var shellColumns: some View {
        HStack(spacing: 0) {
            SidebarView(
                projection: sidebarProjection,
                registry: registry,
                favorites: favorites,
                sidebarSections: sidebarSections,
                recentToolIDs: sidebarRecentToolIDs,
                selectedToolID: navigation.selectedToolID,
                searchText: $navigation.searchText,
                searchFocusToken: navigation.searchFocusToken,
                onSelectTool: { _ = navigationActions.selectTool($0) },
                onOpenDashboard: { navigationActions.openDashboard() },
                onToggleFavorite: { toggleFavorite($0, showsToast: false) },
                onMoveFavorites: { navigationActions.moveFavorites($0, toOffset: $1) },
                onToggleSection: { navigationActions.toggleSection($0, exclusive: $1) },
                onToggleTheme: toggleTheme,
                onPreferences: showPreferences,
                themeTitle: themePreference.title,
                themeIcon: themePreference.icon
            )
            .frame(width: navigation.sidebarVisibility == .visible ? SidebarView.idealWidth : 0)
            .clipped()
            .allowsHitTesting(navigation.sidebarVisibility == .visible)
            .accessibilityHidden(navigation.sidebarVisibility == .hidden)

            detailColumn
        }
    }

    /// 浮层组：命令面板 / 隐藏快捷键 / Toast+HUD 双通道（C4）。
    private var shellOverlayLayer: some View {
        ZStack {
            CommandPaletteOverlayHost(
                presentation: navigation.commandPalettePresentation,
                registry: registry,
                baseActions: commandBaseActions,
                reduceMotion: reduceMotion,
                usage: paletteRecents,
                onSelectTool: launchFromPalette,
                onRunCommand: runPaletteCommand,
                onRequestFocus: navigation.focusCommandPalette,
                onDismiss: closeCommandPaletteAnimated
            )
            .zIndex(2)

            keyboardShortcuts

            // Toast/HUD 双通道（C4）：前台 key 窗口走 Toast 队列；窗口非 key
            // 或应用未激活时同 payload 降级右下 HUD（呈现判定在 center.show）。
            ToolToastHost(center: toastCenter)
            ToolHUDHost(center: toastCenter)
                .zIndex(3)
        }
    }

    var body: some View {
        let _ = CommandPaletteTrace.count(.rootBody)
        shellRoot
            .focusedSceneObject(navigation)
            .toolbar { windowToolbar }
            .sheet(isPresented: $showsPreferences) {
                RootPreferencesSheet(
                    themeName: $themeName,
                    autoResumeLastTool: $navigation.autoResumeLastTool,
                    systemAppearanceSource: systemAppearanceSource
                )
            }
            .onAppear {
                smartPaste.noteSelectedTool(navigation.selectedToolID)
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
            .onChange(of: navigation.selectedToolID) { newToolID in
                smartPaste.noteSelectedTool(newToolID)
            }
    }

    /// 壳层根视图（C1 分家：body 拆子表达式控制类型检查复杂度；挂点顺序
    /// 与拆分前逐字一致）。
    private var shellRoot: some View {
        ZStack {
            shellColumns
            shellOverlayLayer
        }
        // min 尺寸单源：与 XToolsApp Scene 层共用 ToolMetrics.Window 常量。
        .frame(minWidth: ToolMetrics.Window.minimumWidth, minHeight: ToolMetrics.Window.minimumHeight)
        .background(ToolTheme.windowBackground)
        // 外观链单挂点（C2 收敛）：AppThemeEnvironment 唯一解析并内聚
        // WindowAppearanceOwner 单应用器，RootView 不再单独挂窗口应用器。
        .background(WindowChromeConfigurator())
        .background(FileInputPanelWindowBinder(coordinator: fileInputPanelCoordinator))
        .background(FileOutputPanelWindowBinder(coordinator: fileOutputPanelCoordinator))
        // Toast/HUD 双通道（C4）：呈现判定所需的宿主窗口经 binder 注入 center。
        .background(ToolToastWindowBinder(center: toastCenter))
        .tint(ToolTheme.accent)
        .environment(\.toolToastCenter, toastCenter)
        .environment(\.fileInputPanelClient, fileInputPanelCoordinator.client)
        .environment(\.fileOutputPanelClient, fileOutputPanelCoordinator.client)
        .environmentObject(workspaceRepository)
        .environmentObject(hubSegmentEntryHint)
        .appThemeEnvironment(preference: themePreference, source: systemAppearanceSource)
    }

    private var windowToolbar: some ToolbarContent {
        WindowToolbarContent(
            selectedTool: selectedTool,
            isSidebarVisible: navigation.sidebarVisibility == .visible,
            // 传收藏 store 引用（不读 isFavorite）：收藏星观察下沉到
            // FavoriteToolbarLabel 自身，收藏切换不重估 Root（B4 契约）。
            favorites: favorites,
            // 传模型引用（let 常量，不读计算属性）：读取 showsCommandPalette
            // 会在 body 里依赖面板状态，而面板开关不触发 body 重估——压暗
            // 观察在 CommandTriggerLabel 内完成。
            presentation: navigation.commandPalettePresentation,
            onToggleSidebar: toggleSidebar,
            onToggleFavorite: toggleFavorite,
            onCommandPalette: { toggleCommandPaletteAnimated() },
            // 外观链收敛（C2）：RootView 不再自行解析 colorScheme，工具栏
            // 拿解析输入在本体消费同一解析函数（原生 chrome 在 SwiftUI 环境
            // 之外，环境注入到不了工具栏条目）。
            themePreference: themePreference,
            systemAppearanceSource: systemAppearanceSource
        )
    }

    private var detailColumn: some View {
        detailRouting.update(actions: navigationActions)
        return VStack(spacing: 0) {
            ToolDetailHostView(
                registry: registry,
                selectedToolID: navigation.selectedToolID,
                transitionIntent: navigation.pageTransitionIntent,
                dashboardStore: dashboardStore,
                favorites: favorites,
                routing: detailRouting
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ToolTheme.workspaceBackground)
        // v3: one reliable transaction for the tool-switch arrival — the host
        // owns the id-driven transition; this root-level animation keyed on
        // the selection guarantees the crossfade plays even when the switch
        // originates outside the host (palette, sidebar, shortcuts).
        // 阶段③ 决策 9：兜底与 ToolPageStage 的泊车到达对齐同一 0.18s
        // crossfade（原 pageArrival 景深编排已退役）。
        .toolAnimation(ToolMotion.Preset.contentCrossfade, value: navigation.selectedToolID)
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
            navigation: navigation,
            favorites: favorites,
            sidebarSections: sidebarSections,
            dashboardStore: dashboardStore
        )
    }

    private var sidebarProjection: ToolNavigationProjection {
        CommandPaletteTrace.count(.sidebarProjection)
        return sidebarProjectionCache.projection(
            registry: registry,
            selectedToolID: navigation.selectedToolID,
            query: navigation.searchText
        )
    }

    /// 侧栏「最近使用」top5（navigation 通道，最新优先）。读经 dashboardStore
    /// 门面（launchToken 发布语义）；导航发生时 RootView 本就随选择重估，
    /// 使用频率记录路径不额外触发壳层失效。
    private var sidebarRecentToolIDs: [ToolID] {
        let knownToolIDs = Set(registry.categoryGroups().flatMap { $0.tools.map(\.id) })
        return Array(
            dashboardStore
                .recentTools(knownToolIDs: knownToolIDs)
                .prefix(5)
                .map(\.toolID)
        )
    }

    private var selectedTool: RegisteredTool? {
        navigation.selectedToolID.flatMap(registry.tool(for:))
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
        _ = navigationActions.selectTool(toolID, intent: .originBloom)
        closeCommandPaletteAnimated()
    }

    // MARK: - Animated palette presentation (v3)

    /// Palette open/close uses one explicit transaction shared by the stable
    /// presentation shell; AppKit field/session replacement stays inside it.
    private func toggleCommandPaletteAnimated() {
        withToolAnimation(ToolMotion.Preset.modal, reduceMotion: reduceMotion) {
            navigationActions.toggleCommandPalette()
        }
    }

    private func openCommandPaletteAnimated() {
        withToolAnimation(ToolMotion.Preset.modal, reduceMotion: reduceMotion) {
            navigationActions.openCommandPalette()
        }
    }

    private func closeCommandPaletteAnimated() {
        withToolAnimation(ToolMotion.Preset.modal, reduceMotion: reduceMotion) {
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
                title: navigation.sidebarTogglePresentation.title,
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
            guard IndexPasteboard.copyString(UUID().uuidString.lowercased()) else {
                toastCenter.show(ToolFeedbackCopy.clipboardWriteFailure, tone: .error)
                return
            }
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
        navigation.toggleSidebar(reduceMotion: reduceMotion)
    }

    private func cancelCurrentMode() {
        if navigation.showsCommandPalette {
            closeCommandPaletteAnimated()
            return
        }

        if !navigation.searchText.isEmpty {
            navigation.searchText = ""
        }
    }
}

/// 单条目投影缓存：输入二元组（查询、选择）未变时直接复用上一次的投影
/// 结果；任一真实变化仍会全量重建。只为砍掉无关 shell 抖动引发的重复
/// 构建，不改变任何投影语义。（收藏自阶段③ B 起不进投影——收藏切换由
/// 侧栏局部观察承接，缓存键随之收敛。）
@MainActor
private final class SidebarProjectionCache {
    private var query: String?
    private var selectedToolID: ToolID?
    private var projection: ToolNavigationProjection?

    func projection(
        registry: ToolRegistry,
        selectedToolID: ToolID?,
        query: String
    ) -> ToolNavigationProjection {
        if let projection,
           self.query == query,
           self.selectedToolID == selectedToolID {
            return projection
        }

        let rebuilt = ToolNavigationProjection(
            registry: registry,
            selectedToolID: selectedToolID,
            query: query
        )
        self.query = query
        self.selectedToolID = selectedToolID
        self.projection = rebuilt
        return rebuilt
    }
}

/// DetailActionRouting 的 RootView 侧实现：持有的动作集在每次 body 重估时
/// 刷新，但盒本体是与视图同生命周期的稳定引用，子视图的输入比较不再被
/// 逐次重建的闭包身份击穿。
@MainActor
private final class DetailActionRoutingBox: DetailActionRouting {
    private var actions: ToolNavigationActions?

    func update(actions: ToolNavigationActions) {
        self.actions = actions
    }

    func selectTool(_ toolID: ToolID) {
        _ = actions?.selectTool(toolID)
    }

    func openCommandPalette() {
        actions?.openCommandPalette()
    }

    func toggleFavorite(_ toolID: ToolID) -> Bool? {
        actions?.toggleFavorite(toolID)
    }
}
