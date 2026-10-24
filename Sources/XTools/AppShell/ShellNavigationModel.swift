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
    let commandPalettePresentation = CommandPalettePresentationModel()

    var showsCommandPalette: Bool { commandPalettePresentation.shows }
    var commandPaletteFocusToken: Int { commandPalettePresentation.focusToken }
    var commandPalettePresentationSession: Int { commandPalettePresentation.session }

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
