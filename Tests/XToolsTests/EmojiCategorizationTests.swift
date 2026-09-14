import Foundation
import XToolsCore
import Testing

struct EmojiCategorizationTests {
    @Test func bundledPrecompiledCatalogMatchesSourceOfTruth() throws {
        let data = try #require(EmojiCatalog.bundledPrecompiledCatalogData())
        let decoded = try #require(EmojiCatalog.decodePrecompiledCatalog(data))

        #expect(decoded == EmojiCatalog.buildSourceCatalog())
        #expect(decoded == EmojiCatalog.groups)
    }

    @Test func invalidPrecompiledCatalogsAreRejectedForSourceFallback() throws {
        #expect(EmojiCatalog.decodePrecompiledCatalog(Data("not a plist".utf8)) == nil)

        let data = try #require(EmojiCatalog.bundledPrecompiledCatalogData())
        var propertyList = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        propertyList["schemaVersion"] = -1
        let mismatched = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .binary,
            options: 0
        )

        #expect(EmojiCatalog.decodePrecompiledCatalog(mismatched) == nil)
    }

    @Test func catalogBuildsExpectedGroups() {
        let groupNames = EmojiCatalog.groups.map(\.name)

        #expect(!EmojiCatalog.groups.isEmpty)
        #expect(groupNames.contains("笑脸与情感"))
        #expect(groupNames.contains("旅行与地点"))
        #expect(groupNames.contains("旗帜"))
        #expect(groupNames.contains(EmojiCatalog.specialSymbolGroupName))
        #expect(EmojiCatalog.groups.allSatisfy { !$0.entries.isEmpty })
    }

    @Test func allEntriesMatchesGroupContents() {
        let groupedCount = EmojiCatalog.groups.reduce(0) { $0 + $1.entries.count }
        let uniqueBaseCount = Set(EmojiCatalog.allEntries.map(\.base)).count

        #expect(EmojiCatalog.allEntries.count == groupedCount)
        #expect(uniqueBaseCount == EmojiCatalog.allEntries.count)
    }

    @Test func searchFindsKnownEmojiHonorsLimitAndReportsTruncation() {
        let rocketSearch = EmojiCatalog.search(matching: " 🚀 ", limit: 1)
        let broadSearch = EmojiCatalog.search(matching: "e", limit: 3)
        let emptySearch = EmojiCatalog.search(matching: " ", limit: 10)
        let zeroLimitSearch = EmojiCatalog.search(matching: "e", limit: 0)

        #expect(rocketSearch.entries.contains { $0.base == "🚀" })
        #expect(rocketSearch.isTruncated == false)
        #expect(broadSearch.entries.count == 3)
        #expect(broadSearch.isTruncated)
        #expect(emptySearch.entries.isEmpty)
        #expect(emptySearch.isTruncated == false)
        #expect(zeroLimitSearch.entries.isEmpty)
        #expect(zeroLimitSearch.isTruncated == false)
        #expect(EmojiCatalog.entries(matching: "e", limit: 3) == broadSearch.entries)

        let flagMatches = EmojiCatalog.entries(matching: "united states", limit: 10)
        #expect(flagMatches.contains { $0.base == "🇺🇸" })
    }

    @Test func entryHelpTextPreservesEveryUnicodeScalar() {
        let technologist = EmojiEntry(
            base: "👩‍💻",
            name: "woman technologist",
            skinToneCapable: true
        )
        let heart = EmojiEntry(base: "❤️", name: "red heart", skinToneCapable: false)
        let unnamed = EmojiEntry(base: "→", name: "   ", skinToneCapable: false)

        #expect(technologist.codePointDescription == "U+1F469 U+200D U+1F4BB")
        #expect(technologist.helpText == "woman technologist · U+1F469 U+200D U+1F4BB")
        #expect(technologist.helpText(for: "👩🏽‍💻") == "woman technologist · U+1F469 U+1F3FD U+200D U+1F4BB")
        #expect(heart.codePointDescription == "U+2764 U+FE0F")
        #expect(heart.helpText == "red heart · U+2764 U+FE0F")
        #expect(unnamed.helpText == "U+2192")
    }

    @Test func specialSymbolGroupPreservesBrowseSectionsAndUniqueCount() throws {
        let group = try #require(EmojiCatalog.groups.first { $0.name == EmojiCatalog.specialSymbolGroupName })
        let browseSymbols = group.sections.flatMap { section in
            section.subsections.flatMap { subsection in
                subsection.entries.map(\.base)
            }
        }

        #expect(!group.sections.isEmpty)
        #expect(group.sections.contains { $0.name == "箭头与方向符号" })
        #expect(group.sections.contains { $0.name == "数字序号与带圈字符" })
        #expect(browseSymbols.contains("→"))
        #expect(browseSymbols.contains("₿"))
        #expect(browseSymbols.contains("㎡"))
        #expect(browseSymbols.filter { $0 == "▶" }.count == 2)
        #expect(EmojiCatalog.specialSymbolCount == Set(browseSymbols).count)
        #expect(group.entries.count == EmojiCatalog.specialSymbolCount)
    }

    @Test func bilingualSearchFindsEmojiAndSpecialSymbols() {
        let rightMatches = EmojiCatalog.entries(matching: "right", limit: 50)
        let chineseRightMatches = EmojiCatalog.entries(matching: "右边", limit: 50)
        let directionalChineseMatches = EmojiCatalog.entries(matching: "向右", limit: 50)
        let playMatches = EmojiCatalog.entries(matching: "播放", limit: 50)
        let checkMatches = EmojiCatalog.entries(matching: "正确", limit: 50)
        let currencyMatches = EmojiCatalog.entries(matching: "钱", limit: 50)

        #expect(rightMatches.contains { canonicalGlyph($0.base) == "👉" })
        #expect(rightMatches.contains { canonicalGlyph($0.base) == "→" || canonicalGlyph($0.base) == "➡" })
        #expect(chineseRightMatches.contains { canonicalGlyph($0.base) == "👉" })
        #expect(directionalChineseMatches.contains { canonicalGlyph($0.base) == "→" || canonicalGlyph($0.base) == "➡" })
        #expect(playMatches.contains { canonicalGlyph($0.base) == "▶" })
        #expect(checkMatches.contains { ["✓", "✔", "☑", "✅"].contains(canonicalGlyph($0.base)) })
        #expect(currencyMatches.contains { ["￥", "$", "€", "₿"].contains(canonicalGlyph($0.base)) })
    }

    @Test func searchSupportsDirectGlyphsAndDeduplicatesBrowseDuplicates() {
        let pointingMatches = EmojiCatalog.entries(matching: "👉", limit: 10)
        let arrowMatches = EmojiCatalog.entries(matching: "→", limit: 10)
        let playMatches = EmojiCatalog.entries(matching: "播放", limit: 50)

        #expect(pointingMatches.contains { $0.base == "👉" })
        #expect(arrowMatches.contains { canonicalGlyph($0.base) == "→" })
        #expect(playMatches.filter { canonicalGlyph($0.base) == "▶" }.count == 1)
    }

    @Test func chineseDirectionAliasesDoNotComeFromEnglishSubstrings() {
        let rightMatches = EmojiCatalog.entries(matching: "右", limit: 200)
        let upwardMatches = EmojiCatalog.entries(matching: "向上", limit: 200)

        #expect(!rightMatches.contains { canonicalGlyph($0.base) == "©" })
        #expect(!upwardMatches.contains { ["🧁", "🍵", "🥤"].contains(canonicalGlyph($0.base)) })
    }

    @Test func browseGroupsExposeSkinToneCapabilityOnlyForPeopleAndBody() {
        let capableGroups = EmojiCatalog.groups
            .filter { $0.entries.contains(where: \.skinToneCapable) }
            .map(\.name)

        #expect(capableGroups == ["人物与身体"])
    }

    @Test func skinToneListUsesSafeScalars() {
        #expect(EmojiCatalog.skinTones.count == 6) // default + 5 tones
        #expect(EmojiCatalog.skinTones.first?.label == "默认")
        #expect(EmojiCatalog.skinTones.first?.scalar == nil)
        #expect(EmojiCatalog.skinTones.dropFirst().compactMap(\.scalar).count == 5)
    }

    @Test func skinToneApplicationRespectsEntryCapability() throws {
        let wave = try #require(EmojiCatalog.allEntries.first(where: { $0.base == "👋" }))
        let rocket = try #require(EmojiCatalog.allEntries.first(where: { $0.base == "🚀" }))
        let lightTone = EmojiCatalog.skinTones[1].scalar

        #expect(wave.skinToneCapable == true)
        #expect(EmojiCatalog.apply(tone: lightTone, to: wave) == "👋🏻")
        #expect(EmojiCatalog.apply(tone: lightTone, to: rocket) == "🚀") // non-capable emoji unchanged
    }

    @Test func skinToneApplicationLeavesPlainSymbolsUnchanged() throws {
        let arrow = try #require(EmojiCatalog.allEntries.first(where: { $0.base == "→" }))
        let lightTone = EmojiCatalog.skinTones[1].scalar

        #expect(arrow.skinToneCapable == false)
        #expect(EmojiCatalog.apply(tone: lightTone, to: arrow) == "→")
    }

    @Test func catalogIncludesFullyQualifiedEmojiSequences() throws {
        let redHeart = try #require(EmojiCatalog.allEntries.first(where: { $0.base == "❤️" }))
        let keycap = try #require(EmojiCatalog.allEntries.first(where: { $0.base == "#️⃣" }))
        let flag = try #require(EmojiCatalog.allEntries.first(where: { $0.base == "🇺🇸" }))
        let healthWorker = try #require(EmojiCatalog.allEntries.first(where: { $0.base == "🧑‍⚕️" }))

        #expect(redHeart.name == "red heart")
        #expect(keycap.name == "keycap: #")
        #expect(flag.name == "flag: united states")
        #expect(healthWorker.name == "health worker")
        #expect(healthWorker.skinToneCapable)
    }

    @Test func skinToneApplicationHandlesZWJSequences() throws {
        let healthWorker = try #require(EmojiCatalog.allEntries.first(where: { $0.base == "🧑‍⚕️" }))
        let lightTone = EmojiCatalog.skinTones[1].scalar

        #expect(EmojiCatalog.apply(tone: lightTone, to: healthWorker) == "🧑🏻‍⚕️")
    }

    @Test func totalProducibleCountsSkinToneVariants() {
        let expected = EmojiCatalog.groups
            .filter { $0.name != EmojiCatalog.specialSymbolGroupName }
            .reduce(0) { total, group in
            total + group.entries.reduce(0) { entryTotal, entry in
                entryTotal + (entry.skinToneCapable ? EmojiCatalog.skinTones.count : 1)
            }
        }

        #expect(EmojiCatalog.totalProducible == expected)
        #expect(EmojiCatalog.totalProducible >= EmojiCatalog.allEntries.count)
    }

    private func canonicalGlyph(_ glyph: String) -> String {
        String(String.UnicodeScalarView(glyph.unicodeScalars.filter { scalar in
            scalar.value != 0xFE0E && scalar.value != 0xFE0F
        }))
    }
}
