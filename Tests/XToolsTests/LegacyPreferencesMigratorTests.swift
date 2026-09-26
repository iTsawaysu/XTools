@testable import XTools
import Foundation
import Testing

struct LegacyPreferencesMigratorTests {
    @Test func firstMigrationCopiesAppOwnedKeysIntoEmptyDestination() {
        let source = Self.defaults(prefix: "source")
        let destination = Self.defaults(prefix: "destination")

        source.defaults.set(["json-formatter", "uuid-generator"], forKey: "tools.favorites.v1")
        source.defaults.set(["category.web"], forKey: "tools.sidebar.collapsedSections.v1")
        source.defaults.set("hidden", forKey: "tools.shell.sidebarVisibility.v1")
        source.defaults.set("dark", forKey: "dt.theme")
        source.defaults.set("noise", forKey: "AppleLanguages")
        source.defaults.set("ignore-me", forKey: "unrelated.global.setting")

        let result = LegacyPreferencesMigrator(
            source: source.defaults,
            destination: destination.defaults
        ).migrateIfNeeded()

        #expect(result.status == .migrated)
        #expect(Set(result.copiedKeys) == [
            "tools.favorites.v1",
            "tools.sidebar.collapsedSections.v1",
            "tools.shell.sidebarVisibility.v1",
            "dt.theme"
        ])
        #expect(result.skippedExistingKeys.isEmpty)
        #expect(destination.defaults.array(forKey: "tools.favorites.v1") as? [String] == [
            "json-formatter",
            "uuid-generator"
        ])
        #expect(destination.defaults.array(forKey: "tools.sidebar.collapsedSections.v1") as? [String] == [
            "category.web"
        ])
        #expect(destination.defaults.string(forKey: "tools.shell.sidebarVisibility.v1") == "hidden")
        #expect(destination.defaults.string(forKey: "dt.theme") == "dark")

        let persisted = destination.defaults.persistentDomain(forName: destination.suiteName) ?? [:]
        #expect(persisted["AppleLanguages"] == nil)
        #expect(persisted["unrelated.global.setting"] == nil)
        #expect(destination.defaults.bool(forKey: LegacyPreferencesMigrator.migrationFlagKey))
    }

    @Test func alreadyMigratedDoesNotCopyOrOverwriteAgain() {
        let source = Self.defaults(prefix: "source")
        let destination = Self.defaults(prefix: "destination")

        destination.defaults.set(true, forKey: LegacyPreferencesMigrator.migrationFlagKey)
        destination.defaults.set(["kept-new"], forKey: "tools.favorites.v1")
        source.defaults.set(["legacy-only"], forKey: "tools.favorites.v1")
        source.defaults.set("hidden", forKey: "tools.shell.sidebarVisibility.v1")

        let first = LegacyPreferencesMigrator(
            source: source.defaults,
            destination: destination.defaults
        ).migrateIfNeeded()
        let second = LegacyPreferencesMigrator(
            source: source.defaults,
            destination: destination.defaults
        ).migrateIfNeeded()

        #expect(first.status == .alreadyMigrated)
        #expect(second.status == .alreadyMigrated)
        #expect(first.copiedKeys.isEmpty)
        #expect(second.copiedKeys.isEmpty)
        #expect(destination.defaults.array(forKey: "tools.favorites.v1") as? [String] == ["kept-new"])
        #expect(destination.defaults.object(forKey: "tools.shell.sidebarVisibility.v1") == nil)
    }

    @Test func existingDestinationValuesAreNotClobberedByLegacyValues() {
        let source = Self.defaults(prefix: "source")
        let destination = Self.defaults(prefix: "destination")

        destination.defaults.set(["new-app-favorites"], forKey: "tools.favorites.v1")
        destination.defaults.set("visible", forKey: "tools.shell.sidebarVisibility.v1")
        source.defaults.set(["legacy-favorites"], forKey: "tools.favorites.v1")
        source.defaults.set("hidden", forKey: "tools.shell.sidebarVisibility.v1")
        source.defaults.set(["category.crypto"], forKey: "tools.sidebar.collapsedSections.v1")
        source.defaults.set(4, forKey: "tools.tokenGenerator.length.v1")

        let result = LegacyPreferencesMigrator(
            source: source.defaults,
            destination: destination.defaults
        ).migrateIfNeeded()

        #expect(result.status == .migrated)
        #expect(Set(result.copiedKeys) == [
            "tools.sidebar.collapsedSections.v1",
            "tools.tokenGenerator.length.v1"
        ])
        #expect(Set(result.skippedExistingKeys) == [
            "tools.favorites.v1",
            "tools.shell.sidebarVisibility.v1"
        ])
        #expect(destination.defaults.array(forKey: "tools.favorites.v1") as? [String] == ["new-app-favorites"])
        #expect(destination.defaults.string(forKey: "tools.shell.sidebarVisibility.v1") == "visible")
        #expect(destination.defaults.array(forKey: "tools.sidebar.collapsedSections.v1") as? [String] == [
            "category.crypto"
        ])
        #expect(destination.defaults.integer(forKey: "tools.tokenGenerator.length.v1") == 4)
        #expect(destination.defaults.bool(forKey: LegacyPreferencesMigrator.migrationFlagKey))
    }

    @Test func emptySourceStillRecordsCompletionFlagForIdempotency() {
        let source = Self.defaults(prefix: "source")
        let destination = Self.defaults(prefix: "destination")

        let result = LegacyPreferencesMigrator(
            source: source.defaults,
            destination: destination.defaults
        ).migrateIfNeeded()

        #expect(result.status == .migrated)
        #expect(result.copiedKeys.isEmpty)
        #expect(destination.defaults.bool(forKey: LegacyPreferencesMigrator.migrationFlagKey))

        source.defaults.set(["late-legacy"], forKey: "tools.favorites.v1")
        let second = LegacyPreferencesMigrator(
            source: source.defaults,
            destination: destination.defaults
        ).migrateIfNeeded()

        #expect(second.status == .alreadyMigrated)
        #expect(destination.defaults.object(forKey: "tools.favorites.v1") == nil)
    }

    @Test func customPrefixAndFlagKeepTheirExistingMigrationContract() {
        let source = Self.defaults(prefix: "source")
        let destination = Self.defaults(prefix: "destination")
        let customFlag = "LegacyPreferencesMigratorTests.didMigrate"

        source.defaults.set("copied", forKey: "custom.preference")
        source.defaults.set("ignored", forKey: "tools.favorites.v1")
        let result = LegacyPreferencesMigrator(
            source: source.defaults,
            destination: destination.defaults,
            migrationFlagKey: customFlag,
            keyPrefixes: ["custom."]
        ).migrateIfNeeded()

        #expect(result.status == .migrated)
        #expect(result.copiedKeys == ["custom.preference"])
        #expect(destination.defaults.string(forKey: "custom.preference") == "copied")
        #expect(destination.defaults.object(forKey: "tools.favorites.v1") == nil)
        #expect(destination.defaults.bool(forKey: customFlag))
        let persisted = destination.defaults.persistentDomain(forName: destination.suiteName) ?? [:]
        #expect(persisted[LegacyPreferencesMigrator.migrationFlagKey] == nil)
    }

    @Test func productionFallbackReadsIsolatedPlistWithoutCreatingASourceDomain() throws {
        let destination = Self.defaults(prefix: "destination")
        destination.defaults.set(["new-app"], forKey: "tools.favorites.v1")

        let legacySuiteName = "LegacyPreferencesMigratorTests.legacy.\(UUID().uuidString)"
        let plistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(legacySuiteName).plist")
        let fixture: [String: Any] = [
            "tools.favorites.v1": ["legacy"],
            "tools.sidebar.collapsedSections.v1": ["category.web"],
            "dt.theme": "dark",
            "AppleLanguages": ["en"],
            "unrelated.setting": "ignored",
        ]
        let fixtureData = try PropertyListSerialization.data(
            fromPropertyList: fixture,
            format: .xml,
            options: 0
        )
        try fixtureData.write(to: plistURL, options: .atomic)

        let result = LegacyPreferencesMigrator.migrateFromLegacyDomainIfNeeded(
            destination: destination.defaults,
            sourceValuesReader: {
                try LegacyPreferencesMigrator.loadLegacySourceValues(
                    suiteName: legacySuiteName,
                    fileManager: .default,
                    legacyPlistURL: plistURL
                )
            }
        )

        #expect(result?.status == .migrated)
        #expect(Set(result?.copiedKeys ?? []) == [
            "tools.sidebar.collapsedSections.v1",
            "dt.theme",
        ])
        #expect(result?.skippedExistingKeys == ["tools.favorites.v1"])
        #expect(destination.defaults.array(forKey: "tools.favorites.v1") as? [String] == ["new-app"])
        #expect(destination.defaults.array(forKey: "tools.sidebar.collapsedSections.v1") as? [String] == [
            "category.web"
        ])
        #expect(destination.defaults.string(forKey: "dt.theme") == "dark")
        #expect(destination.defaults.bool(forKey: LegacyPreferencesMigrator.migrationFlagKey))
        let persisted = destination.defaults.persistentDomain(forName: destination.suiteName) ?? [:]
        #expect(persisted["AppleLanguages"] == nil)
        #expect(persisted["unrelated.setting"] == nil)

        let isolatedSource = try #require(UserDefaults(suiteName: legacySuiteName))
        #expect((isolatedSource.persistentDomain(forName: legacySuiteName) ?? [:]).isEmpty)
    }

    @Test func productionConstantsStayPinnedToLegacyDomainAndStableFlag() {
        #expect(LegacyPreferencesMigrator.legacyBundleIdentifier == "com.sun.tools")
        #expect(
            LegacyPreferencesMigrator.migrationFlagKey
                == "xtools.didMigratePreferencesFrom.com.sun.tools"
        )
        #expect(LegacyPreferencesMigrator.preferredKeyPrefixes == ["tools.", "dt."])
    }

    @Test func productionEntryReturnsAlreadyMigratedWithoutTouchingSourceDomain() {
        let destination = Self.defaults(prefix: "destination")
        destination.defaults.set(true, forKey: LegacyPreferencesMigrator.migrationFlagKey)
        destination.defaults.set(["kept-new"], forKey: "tools.favorites.v1")
        var sourceReadCount = 0

        let result = LegacyPreferencesMigrator.migrateFromLegacyDomainIfNeeded(
            destination: destination.defaults,
            sourceValuesReader: {
                sourceReadCount += 1
                return ["tools.favorites.v1": ["must-not-read"]]
            }
        )

        #expect(result?.status == .alreadyMigrated)
        #expect(result?.copiedKeys.isEmpty == true)
        #expect(sourceReadCount == 0)
        #expect(destination.defaults.array(forKey: "tools.favorites.v1") as? [String] == ["kept-new"])
        #expect(destination.defaults.bool(forKey: LegacyPreferencesMigrator.migrationFlagKey))
    }

    private struct SuiteDefaults {
        let defaults: UserDefaults
        let suiteName: String
    }

    private static func defaults(prefix: String) -> SuiteDefaults {
        let suiteName = "LegacyPreferencesMigratorTests.\(prefix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SuiteDefaults(defaults: defaults, suiteName: suiteName)
    }
}
