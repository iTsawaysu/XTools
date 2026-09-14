import Foundation
import os

/// One-shot copy of preferences from the pre-rename app domain (`com.sun.tools`)
/// into the current app's standard UserDefaults (`com.sun.xtools`).
///
/// Key names are preserved (`tools.*`, `dt.*`); only the preference domain changes.
/// Existing destination values are never overwritten. Failures are best-effort and
/// must not block app launch.
struct LegacyPreferencesMigrator {
    /// Preference domain used by the previous Tools.app bundle id.
    static let legacyBundleIdentifier = "com.sun.tools"

    /// Stable completion flag written to the destination domain after a migration attempt.
    static let migrationFlagKey = "xtools.didMigratePreferencesFrom.com.sun.tools"

    /// App-owned key prefixes. Filters out Apple/global suite noise from
    /// `dictionaryRepresentation()`.
    static let preferredKeyPrefixes = ["tools.", "dt."]

    struct Result: Equatable, Sendable {
        enum Status: Equatable, Sendable {
            case alreadyMigrated
            case migrated
        }

        var status: Status
        var copiedKeys: [String]
        var skippedExistingKeys: [String]

        var didPerformMigration: Bool {
            status == .migrated
        }
    }

    let source: UserDefaults
    let destination: UserDefaults
    let migrationFlagKey: String
    let keyPrefixes: [String]

    init(
        source: UserDefaults,
        destination: UserDefaults,
        migrationFlagKey: String = Self.migrationFlagKey,
        keyPrefixes: [String] = Self.preferredKeyPrefixes
    ) {
        self.source = source
        self.destination = destination
        self.migrationFlagKey = migrationFlagKey
        self.keyPrefixes = keyPrefixes
    }

    /// Copies eligible source keys into the destination when the destination key
    /// is absent, then records the completion flag. Idempotent.
    @discardableResult
    func migrateIfNeeded() -> Result {
        if destination.bool(forKey: migrationFlagKey) {
            return Result(status: .alreadyMigrated, copiedKeys: [], skippedExistingKeys: [])
        }

        var copiedKeys: [String] = []
        var skippedExistingKeys: [String] = []

        let sourceValues = Self.appOwnedValues(
            from: source.dictionaryRepresentation(),
            keyPrefixes: keyPrefixes,
            excluding: migrationFlagKey
        )

        for key in sourceValues.keys.sorted() {
            guard let value = sourceValues[key] else { continue }
            if destination.object(forKey: key) != nil {
                skippedExistingKeys.append(key)
                continue
            }
            destination.set(value, forKey: key)
            copiedKeys.append(key)
        }

        destination.set(true, forKey: migrationFlagKey)
        return Result(
            status: .migrated,
            copiedKeys: copiedKeys,
            skippedExistingKeys: skippedExistingKeys
        )
    }

    /// Production entry point: open the legacy domain and migrate into `.standard`.
    /// Never throws; logs and returns on failure so launch is never blocked.
    ///
    /// Checks the completion flag before opening the legacy suite so subsequent
    /// launches skip suite/plist I/O and never create a temporary bridge suite.
    @discardableResult
    static func migrateFromLegacyDomainIfNeeded(
        destination: UserDefaults = .standard
    ) -> Result? {
        if destination.bool(forKey: migrationFlagKey) {
            return Result(status: .alreadyMigrated, copiedKeys: [], skippedExistingKeys: [])
        }

        do {
            let source = try openLegacySourceDefaults()
            return LegacyPreferencesMigrator(
                source: source,
                destination: destination
            ).migrateIfNeeded()
        } catch {
            Logger(subsystem: "com.sun.xtools", category: "PreferencesMigration")
                .error("Legacy preferences migration skipped: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Opens `UserDefaults(suiteName:)` for the old bundle id. When the suite has
    /// no app-owned keys, falls back to loading `~/Library/Preferences/com.sun.tools.plist`
    /// into a temporary suite so domain data remains readable after the rename.
    static func openLegacySourceDefaults(
        suiteName: String = legacyBundleIdentifier,
        fileManager: FileManager = .default
    ) throws -> UserDefaults {
        guard let suite = UserDefaults(suiteName: suiteName) else {
            throw MigrationError.unableToOpenSuite(suiteName)
        }

        let suiteValues = appOwnedValues(
            from: suite.dictionaryRepresentation(),
            keyPrefixes: preferredKeyPrefixes,
            excluding: migrationFlagKey
        )
        if !suiteValues.isEmpty {
            return suite
        }

        if let plistValues = loadLegacyPlistValues(
            suiteName: suiteName,
            fileManager: fileManager
        ), !plistValues.isEmpty {
            let bridgeSuiteName = "xtools.legacy-preferences-bridge.\(UUID().uuidString)"
            guard let bridge = UserDefaults(suiteName: bridgeSuiteName) else {
                throw MigrationError.unableToOpenSuite(bridgeSuiteName)
            }
            bridge.removePersistentDomain(forName: bridgeSuiteName)
            for (key, value) in plistValues {
                bridge.set(value, forKey: key)
            }
            return bridge
        }

        return suite
    }

    private static func appOwnedValues(
        from dictionary: [String: Any],
        keyPrefixes: [String],
        excluding excludedKey: String
    ) -> [String: Any] {
        dictionary.filter { key, _ in
            key != excludedKey
                && keyPrefixes.contains { key.hasPrefix($0) }
        }
    }

    private static func loadLegacyPlistValues(
        suiteName: String,
        fileManager: FileManager
    ) -> [String: Any]? {
        let url = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suiteName).plist")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return NSDictionary(contentsOf: url) as? [String: Any]
    }

    enum MigrationError: Error, LocalizedError {
        case unableToOpenSuite(String)

        var errorDescription: String? {
            switch self {
            case .unableToOpenSuite(let name):
                return "Unable to open UserDefaults suite '\(name)'."
            }
        }
    }
}
