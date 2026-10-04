import Foundation
import XToolsCore

package enum EmojiCatalogCompiler {
    package static func compilePrecompiledCatalogData(
        sourceData: String,
        chineseAnnotationsXML: String? = nil
    ) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(
            EmojiCatalog.PrecompiledCatalog(
                groups: buildSourceCatalog(
                    sourceData: sourceData,
                    chineseAnnotationsXML: chineseAnnotationsXML
                )
            )
        )
    }

    static func buildSourceCatalog(
        sourceData: String?,
        chineseAnnotationsXML: String? = nil
    ) -> [EmojiGroup] {
        var groups: [EmojiGroup]
        if let sourceData, !sourceData.isEmpty {
            let parsed = parseEmojiTestData(sourceData)
            groups = parsed.isEmpty ? EmojiCatalog.buildFallbackFromScalarProperties() : parsed
        } else {
            groups = EmojiCatalog.buildFallbackFromScalarProperties()
        }
        groups.append(EmojiCatalog.buildSpecialSymbolGroup())

        if let chineseAnnotationsXML, !chineseAnnotationsXML.isEmpty {
            groups = applyingChineseAnnotations(chineseAnnotationsXML, to: groups)
        }
        return groups
    }

    private static func applyingChineseAnnotations(_ xml: String, to groups: [EmojiGroup]) -> [EmojiGroup] {
        let keywordsByGlyph = parseChineseAnnotations(xml)
        guard !keywordsByGlyph.isEmpty else { return groups }

        func entryWithAnnotations(_ entry: EmojiEntry) -> EmojiEntry {
            guard let keywords = keywordsByGlyph[EmojiCatalog.canonicalGlyphKey(entry.base)], !keywords.isEmpty else {
                return entry
            }
            var seen = Set(entry.searchText.split(separator: " ").map(String.init))
            var additions: [String] = []
            for keyword in keywords {
                let normalized = normalizedEmojiSearchText(keyword)
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
                additions.append(normalized)
            }
            guard !additions.isEmpty else { return entry }

            let searchText = ((entry.searchText.isEmpty ? [] : [entry.searchText]) + additions)
                .joined(separator: " ")
            return EmojiEntry(
                base: entry.base,
                name: entry.name,
                aliases: entry.aliases,
                skinToneCapable: entry.skinToneCapable,
                searchText: searchText
            )
        }

        return groups.map { group in
            EmojiGroup(
                name: group.name,
                entries: group.entries.map(entryWithAnnotations),
                sections: group.sections.map { section in
                    EmojiSection(
                        name: section.name,
                        subsections: section.subsections.map { subsection in
                            EmojiSubsection(
                                name: subsection.name,
                                entries: subsection.entries.map(entryWithAnnotations)
                            )
                        }
                    )
                }
            )
        }
    }

    private static func parseChineseAnnotations(_ xml: String) -> [String: [String]] {
        guard let data = xml.data(using: .utf8) else { return [:] }
        let collector = ChineseAnnotationCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        guard parser.parse() else { return [:] }
        return collector.keywordsByGlyph
    }

    private final class ChineseAnnotationCollector: NSObject, XMLParserDelegate {
        private var seenKeywords: [String: Set<String>] = [:]
        private(set) var keywordsByGlyph: [String: [String]] = [:]
        private var glyph: String?
        private var text = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            guard elementName == "annotation", let cp = attributeDict["cp"] else {
                glyph = nil
                return
            }
            glyph = cp
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard glyph != nil else { return }
            text += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            defer { glyph = nil }
            guard elementName == "annotation", let glyph else { return }

            let keywords = text
                .split(separator: "|", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let key = EmojiCatalog.canonicalGlyphKey(glyph)
            for keyword in keywords where seenKeywords[key, default: []].insert(keyword).inserted {
                keywordsByGlyph[key, default: []].append(keyword)
            }
        }
    }

    private static func parseEmojiTestData(_ data: String) -> [EmojiGroup] {
        var currentGroup: String?
        var orderedGroupNames: [String] = []
        var buckets: [String: [EmojiEntry]] = [:]
        var seen = Set<String>()

        for rawLine in data.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)

            if line.hasPrefix("# group:") {
                currentGroup = localizedGroupName(
                    String(line.dropFirst("# group:".count)).trimmingCharacters(in: .whitespaces)
                )
                if let currentGroup, !orderedGroupNames.contains(currentGroup) {
                    orderedGroupNames.append(currentGroup)
                }
                continue
            }

            guard let currentGroup,
                  let parsed = parseEmojiLine(line),
                  !containsSkinToneModifier(parsed.codePoints),
                  seen.insert(parsed.base).inserted else {
                continue
            }

            buckets[currentGroup, default: []].append(
                EmojiEntry(
                    base: parsed.base,
                    name: parsed.name,
                    skinToneCapable: canApplySkinTone(to: parsed.base),
                    aliases: EmojiCatalog.aliases(forUnicodeName: parsed.name)
                )
            )
        }

        return orderedGroupNames.compactMap { groupName in
            guard let entries = buckets[groupName], !entries.isEmpty else { return nil }
            return EmojiGroup(name: groupName, entries: entries)
        }
    }

    private static func localizedGroupName(_ name: String) -> String? {
        switch name {
        case "Smileys & Emotion": return "笑脸与情感"
        case "People & Body": return "人物与身体"
        case "Animals & Nature": return "动物与自然"
        case "Food & Drink": return "食物与饮品"
        case "Travel & Places": return "旅行与地点"
        case "Activities": return "活动与运动"
        case "Objects": return "物品与工具"
        case "Symbols": return "符号与标志"
        case "Flags": return "旗帜"
        case "Component": return nil
        default: return "其他"
        }
    }

    private static func parseEmojiLine(_ line: String) -> (base: String, name: String, codePoints: [UInt32])? {
        let declarationAndComment = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard declarationAndComment.count == 2 else {
            return nil
        }

        let declaration = declarationAndComment[0].split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard declaration.count == 2 else {
            return nil
        }

        let status = declaration[1].trimmingCharacters(in: .whitespaces)
        guard status == "fully-qualified" else {
            return nil
        }

        let codePointText = declaration[0].trimmingCharacters(in: .whitespaces)
        let codePoints = codePointText.split(separator: " ").compactMap { UInt32($0, radix: 16) }
        guard !codePoints.isEmpty,
              codePoints.count == codePointText.split(separator: " ").count else {
            return nil
        }

        let scalars = codePoints.compactMap(Unicode.Scalar.init)
        guard scalars.count == codePoints.count else {
            return nil
        }

        let comment = declarationAndComment[1].trimmingCharacters(in: .whitespaces)
        let nameParts = comment.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        let name = nameParts.count == 3 ? String(nameParts[2]).lowercased() : comment.lowercased()

        return (String(String.UnicodeScalarView(scalars)), name, codePoints)
    }

    private static func containsSkinToneModifier(_ codePoints: [UInt32]) -> Bool {
        codePoints.contains { 0x1F3FB...0x1F3FF ~= $0 }
    }

    private static func canApplySkinTone(to emoji: String) -> Bool {
        emoji.unicodeScalars.contains { $0.properties.isEmojiModifierBase }
    }
}
