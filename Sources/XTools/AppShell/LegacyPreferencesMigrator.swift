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

    private let readSourceValues: () -> [String: Any]
    let destination: UserDefaults
    let migrationFlagKey: String
    let keyPrefixes: [String]

    init(
        source: UserDefaults,
        destination: UserDefaults,
        migrationFlagKey: String = Self.migrationFlagKey,
        keyPrefixes: [String] = Self.preferredKeyPrefixes
    ) {
        readSourceValues = { source.dictionaryRepresentation() }
        self.destination = destination
        self.migrationFlagKey = migrationFlagKey
        self.keyPrefixes = keyPrefixes
    }

    private init(
        sourceValues: @escaping () -> [String: Any],
        destination: UserDefaults,
        migrationFlagKey: String = Self.migrationFlagKey,
        keyPrefixes: [String] = Self.preferredKeyPrefixes
    ) {
        readSourceValues = sourceValues
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
            from: readSourceValues(),
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
        destination: UserDefaults = .standard,
        sourceValuesReader: (() throws -> [String: Any])? = nil
    ) -> Result? {
        if destination.bool(forKey: migrationFlagKey) {
            return Result(status: .alreadyMigrated, copiedKeys: [], skippedExistingKeys: [])
        }

        do {
            let sourceValues: [String: Any]
            if let sourceValuesReader {
                sourceValues = try sourceValuesReader()
            } else {
                sourceValues = try loadLegacySourceValues()
            }
            return LegacyPreferencesMigrator(
                sourceValues: { sourceValues },
                destination: destination
            ).migrateIfNeeded()
        } catch {
            Logger(subsystem: "com.sun.xtools", category: "PreferencesMigration")
                .error("Legacy preferences migration skipped: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Reads the old preference domain. When CFPreferences does not expose any
    /// app-owned values, falls back to the on-disk plist without creating a new
    /// persistent UserDefaults bridge domain.
    static func loadLegacySourceValues(
        suiteName: String = legacyBundleIdentifier,
        fileManager: FileManager = .default,
        legacyPlistURL: URL? = nil
    ) throws -> [String: Any] {
        guard let suite = UserDefaults(suiteName: suiteName) else {
            throw MigrationError.unableToOpenSuite(suiteName)
        }

        let suiteDictionary = suite.dictionaryRepresentation()
        let suiteValues = appOwnedValues(
            from: suiteDictionary,
            keyPrefixes: preferredKeyPrefixes,
            excluding: migrationFlagKey
        )
        if !suiteValues.isEmpty {
            return suiteDictionary
        }

        if let plistValues = loadLegacyPlistValues(
            suiteName: suiteName,
            fileManager: fileManager,
            legacyPlistURL: legacyPlistURL
        ), !plistValues.isEmpty {
            return plistValues
        }

        return suiteDictionary
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
        fileManager: FileManager,
        legacyPlistURL: URL?
    ) -> [String: Any]? {
        let url = legacyPlistURL ?? fileManager.homeDirectoryForCurrentUser
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
