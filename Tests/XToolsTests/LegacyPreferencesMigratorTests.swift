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

        let result = LegacyPreferencesMigrator.migrateFromLegacyDomainIfNeeded(
            destination: destination.defaults
        )

        #expect(result?.status == .alreadyMigrated)
        #expect(result?.copiedKeys.isEmpty == true)
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
