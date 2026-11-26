import AppKit
import SwiftUI

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
    /// `RootView.onAppear` can fire again when a window is re-shown. Once the
    /// initial resume choice has been applied for this view model, repeated
    /// appearances must not emit duplicate recent-launch events.
    var hasHandledInitialToolSelection = false
    let commandPalettePresentation = CommandPalettePresentationModel()

    var showsCommandPalette: Bool { commandPalettePresentation.shows }
    var commandPaletteFocusToken: Int { commandPalettePresentation.focusToken }
    var commandPalettePresentationSession: Int { commandPalettePresentation.session }

    private let preferences: ToolPreferenceStore?

    init(preferences: ToolPreferenceStore? = nil) {
        self.preferences = preferences
        let startup = Self.startupSelection(preferences: preferences)
        self.selectedToolID = startup.toolID
        self.autoResumeLastTool = startup.autoResume
        let sidebarPreference = preferences?.value(for: AppShellPreferenceKeys.sidebarVisibility) ?? "visible"
        self.sidebarVisibility = SidebarVisibility(preferenceValue: sidebarPreference)
    }

    static func startupSelection(preferences: ToolPreferenceStore?) -> (autoResume: Bool, toolID: ToolID?) {
        guard let preferences, preferences.value(for: AppShellPreferenceKeys.autoResumeLastTool) else {
            return (false, nil)
        }
        let rawID = preferences.value(for: AppShellPreferenceKeys.selectedToolID)
        return (true, rawID.isEmpty ? nil : ToolID(rawValue: rawID))
    }

    func focusSearch() {
        closeCommandPalette()
        if sidebarVisibility == .hidden { sidebarVisibility = .visible }
        // Arm on the key event's turn. The representable sees the new focus
        // token on a later update and would otherwise miss the first key.
        AppKitSearchFieldCoordinator.armSidebarSearchKeystrokeHandoff()
        searchFocusToken += 1
    }

    func focusCommandPalette() {
        commandPalettePresentation.focus()
    }

    func openCommandPalette() {
        AppKitSearchFieldCoordinator.invalidateSidebarSearchFocus()
        commandPalettePresentation.open()
    }

    /// Toggles the command palette for the Command-K and toolbar triggers.
    /// Keeping this separate from `openCommandPalette()` preserves idempotent
    /// opening for navigation flows that need to reveal the palette.
    func toggleCommandPalette() {
        if showsCommandPalette {
            closeCommandPalette()
        } else {
            openCommandPalette()
        }
    }

    func closeCommandPalette() {
        commandPalettePresentation.close()
    }

    var sidebarTogglePresentation: SidebarTogglePresentation {
        sidebarVisibility == .visible ? .hide : .show
    }

    func toggleSidebar(reduceMotion: Bool) {
        let nextVisibility: SidebarVisibility = sidebarVisibility == .visible ? .hidden : .visible
        if nextVisibility == .hidden {
            AppKitSearchFieldCoordinator.invalidateSidebarSearchFocus()
        }
        withToolAnimation(ToolMotion.Preset.shellResize, reduceMotion: reduceMotion) {
            sidebarVisibility = nextVisibility
        }
    }
}
