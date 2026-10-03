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

    func matches(query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }
        return ToolSearchEngine.match(record: searchRecord, query: normalized) != nil
    }

    var searchRecord: ToolSearchRecord {
        ToolSearchRecord(title: title, keywords: keywords)
    }

    /// Prebuilt engine records aligned with `actions`; build once per action
    /// list change and zip with the actions when filtering.
    static func searchRecords(for actions: [CommandActionEntry]) -> [ToolSearchRecord] {
        actions.map(\.searchRecord)
    }
}
