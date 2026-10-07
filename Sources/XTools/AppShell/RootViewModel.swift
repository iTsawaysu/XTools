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
