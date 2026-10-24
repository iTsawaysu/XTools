import AppKit
import SwiftUI
import XToolsDesign

/// 壳层导航模型（阶段③ C1 分家，design.md §3）：RootView 的 5 个导航状态
/// （selectedToolID / searchText / pageTransitionIntent / sidebarVisibility /
/// autoResume）与侧栏搜索聚焦 token 全部下沉于此，RootView 只组合。
/// 持久化 didSet 语义自 RootViewModel 原样平移（tools.shell.*.v1 键全部不变）。
///
/// `commandPalettePresentation` 刻意以不转发的 let 引用住在这里（与分家前
/// RootViewModel 同一隔离契约）：面板开关只发布 presentation 自身，
/// ShellNavigationModel.objectWillChange 不受牵连，Root body 不因 ⌘K 重估
/// （rootBody=0 契约）。Batch D 多窗口时本模型保持每窗口独立。
@MainActor
final class ShellNavigationModel: ObservableObject {
    @Published var selectedToolID: ToolID? {
        didSet {
            guard oldValue != selectedToolID else { return }
            // 直达/预填载荷是一次性投递（Batch D）：投递总发生在选择落定
            // 之后，选择再变化即作废旧载荷——防止停靠回访/整页重建时把
            // 旧文本重新写进首位输入。
            if workbenchEntryPayload != nil {
                workbenchEntryPayload = nil
            }
            // Keep the last valid tool available for the optional resume
            // preference while allowing the dashboard to use a nil selection.
            if let selectedToolID {
                preferences?.set(selectedToolID.rawValue, for: AppShellPreferenceKeys.selectedToolID)
            }
        }
    }
    @Published var searchText = ""
    /// Set by navigation actions right before the selection changes; the page
    /// stage reads it once per arrival.
    @Published var pageTransitionIntent: ToolPageTransitionIntent = .depth
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
    /// 壳层直达载荷（Batch D）：⌘K 直达回车（仅聚焦）/ SmartPaste 建议、
    /// deeplink input（聚焦 + 预填）。每窗口独立；经
    /// `deliverEntryFocus(toolID:text:)` 投递，WorkbenchSurface 校验归属后
    /// 消费。内容只驻留内存、随选择变化作废，不落盘。
    @Published private(set) var workbenchEntryPayload: WorkbenchEntryPayload?
    let commandPalettePresentation = CommandPalettePresentationModel()

    var showsCommandPalette: Bool { commandPalettePresentation.shows }
    var commandPaletteFocusToken: Int { commandPalettePresentation.focusToken }
    var commandPalettePresentationSession: Int { commandPalettePresentation.session }

    private let preferences: ToolPreferenceStore?
    private var workbenchEntrySequence = 0

    init(preferences: ToolPreferenceStore? = nil, resumesSelection: Bool = true) {
        self.preferences = preferences
        let selectedToolRawValue = preferences?.value(for: AppShellPreferenceKeys.selectedToolID) ?? ""
        self.selectedToolID = resumesSelection && !selectedToolRawValue.isEmpty
            ? ToolID(rawValue: selectedToolRawValue)
            : nil
        self.autoResumeLastTool = preferences?.value(for: AppShellPreferenceKeys.autoResumeLastTool) ?? false
        let sidebarPreference = preferences?.value(for: AppShellPreferenceKeys.sidebarVisibility) ?? "visible"
        self.sidebarVisibility = SidebarVisibility(preferenceValue: sidebarPreference)
    }

    func focusSearch() {
        searchFocusToken += 1
    }

    /// 投递壳层直达载荷（Batch D）。调用方必须先让目标工具的选择落定
    /// （`selectTool` 先行），本方法在之后写入——既保证新到达页面的代际
    /// 请求与载荷同帧合成，也不被 selectedToolID didSet 的作废逻辑清掉。
    /// text = nil 表示仅聚焦（⌘K「别名+空格」直达回车）。
    func deliverEntryFocus(toolID: ToolID, text: String?) {
        workbenchEntrySequence += 1
        workbenchEntryPayload = WorkbenchEntryPayload(
            id: workbenchEntrySequence,
            toolID: toolID,
            text: text
        )
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
