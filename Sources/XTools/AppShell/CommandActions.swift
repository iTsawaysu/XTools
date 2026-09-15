import Foundation

/// Shell-owned commands the palette can run besides tool navigation.
///
/// The set is deliberately bounded (v3 decision: a command system, not a
/// script host). Adding an entry means teaching `RootView.runPaletteAction`
/// how to execute it; there is deliberately no closure payload so the list
/// stays hashable, testable, and free of shell references.
enum CommandActionID: String, CaseIterable, Hashable {
    case toggleAppearance
    case toggleSidebar
    case openPreferences
    case copyGeneratedUUID
}

/// One selectable command row projected into the palette. `keywords` widen
/// matching beyond the title (e.g. "uuid" matches 生成并复制 UUID).
struct CommandActionEntry: Identifiable, Hashable {
    let id: CommandActionID
    let title: String
    let subtitle: String?
    let systemImage: String
    var keywords: [String] = []

    /// Preview-style rows render live output (e.g. a freshly generated UUID)
    /// directly in the subtitle; activation copies it.
    var isPreviewStyle: Bool {
        id == .copyGeneratedUUID
    }

    func matches(query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        if title.localizedCaseInsensitiveContains(normalized) {
            return true
        }
        return keywords.contains {
            $0.localizedCaseInsensitiveContains(normalized)
        }
    }

    /// Builds the session-complete command list from stable shell actions.
    /// Preview rows are replaced rather than carried across sessions so a
    /// consumed UUID cannot remove the command from the next presentation.
    static func paletteActions(
        baseActions: [CommandActionEntry],
        previewValue: String?
    ) -> [CommandActionEntry] {
        let stableActions = baseActions.filter { $0.id != .copyGeneratedUUID }
        guard let previewValue else { return stableActions }
        return stableActions + [
            CommandActionEntry(
                id: .copyGeneratedUUID,
                title: "生成并复制 UUID",
                subtitle: previewValue,
                systemImage: "barcode",
                keywords: ["uuid", "复制", "生成"]
            )
        ]
    }
}
