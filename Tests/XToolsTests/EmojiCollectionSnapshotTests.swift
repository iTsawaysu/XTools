@testable import XTools
import XToolsCore
import Testing

struct EmojiCollectionSnapshotTests {
    @Test func flatSnapshotAppliesToneAndUsesExactRenderedHelpText() throws {
        let wave = try #require(EmojiCatalog.allEntries.first { $0.base == "👋" })
        let rocket = try #require(EmojiCatalog.allEntries.first { $0.base == "🚀" })
        let tone = EmojiCatalog.skinTones[3].scalar

        let snapshot = IndexEmojiCollectionSnapshot.flat(entries: [wave, rocket], tone: tone)

        #expect(!snapshot.isSectioned)
        #expect(snapshot.sections.count == 1)
        #expect(snapshot.sections[0].items.map(\.glyph) == ["👋🏽", "🚀"])
        #expect(snapshot.sections[0].items[0].helpText.contains("U+1F3FD"))
    }

    @Test func sectionedSnapshotPreservesCatalogHierarchyOrderAndDuplicates() throws {
        let group = try #require(
            EmojiCatalog.groups.first { $0.name == EmojiCatalog.specialSymbolGroupName }
        )
        let snapshot = IndexEmojiCollectionSnapshot.sectioned(
            sections: group.sections,
            tone: EmojiCatalog.skinTones[1].scalar
        )

        #expect(snapshot.isSectioned)
        #expect(snapshot.sections.count == group.sections.flatMap(\.subsections).count)
        #expect(snapshot.sections.first?.groupTitle == group.sections.first?.name)
        #expect(snapshot.sections.first?.subsectionTitle == group.sections.first?.subsections.first?.name)
        #expect(snapshot.sections.filter(\.startsGroup).count == group.sections.count)
        #expect(snapshot.sections.flatMap(\.items).filter { $0.glyph == "▶" }.count == 2)
        #expect(Set(snapshot.sections.flatMap(\.items).map(\.id)).count == snapshot.sections.flatMap(\.items).count)
        #expect(snapshot.sections.flatMap(\.items).allSatisfy { !$0.helpText.isEmpty })
    }
}
