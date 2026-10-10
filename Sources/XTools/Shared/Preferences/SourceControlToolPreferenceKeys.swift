import Foundation

@MainActor
enum SourceControlToolPreferenceKeys {
    /// User-approved persistence (2026-09-28 task 09-28-source-control-sync-ux):
    /// the scan root survives launches. Re-picking the directory on every
    /// launch is exactly the friction this preference removes, and the value
    /// is a non-sensitive local directory path.
    static let scanDirectory = ToolPreferenceKey<String>.string(
        "tools.sourceControl.scanDirectory.v1",
        default: ""
    )
}
