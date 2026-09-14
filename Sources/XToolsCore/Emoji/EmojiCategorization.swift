import Foundation

private let emojiSearchLocale = Locale(identifier: "zh_CN")

private func normalizedEmojiSearchText(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: emojiSearchLocale)
        .lowercased()
}

public struct EmojiEntry: Identifiable, Equatable, Sendable {
    public let base: String
    public let name: String
    public let aliases: [String]
    public let skinToneCapable: Bool
    let searchText: String

    public var id: String { base }

    public var codePointDescription: String {
        Self.codePointDescription(for: base)
    }

    public var helpText: String {
        helpText(for: base)
    }

    public func helpText(for renderedGlyph: String) -> String {
        let codePoints = Self.codePointDescription(for: renderedGlyph)
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return codePoints }
        return "\(displayName) · \(codePoints)"
    }

    private static func codePointDescription(for glyph: String) -> String {
        glyph.unicodeScalars
            .map { String(format: "U+%04X", $0.value) }
            .joined(separator: " ")
    }

    public init(base: String, name: String, skinToneCapable: Bool, aliases: [String] = []) {
        self.base = base
        self.name = name
        self.aliases = aliases
        self.skinToneCapable = skinToneCapable
        self.searchText = ([base, name] + aliases)
            .map(normalizedEmojiSearchText)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    fileprivate init(
        base: String,
        name: String,
        aliases: [String],
        skinToneCapable: Bool,
        searchText: String
    ) {
        self.base = base
        self.name = name
        self.aliases = aliases
        self.skinToneCapable = skinToneCapable
        self.searchText = searchText
    }

    func matches(normalized query: String) -> Bool {
        searchText.contains(query) || base.contains(query)
    }
}

/// A bounded catalog search result. `isTruncated` means one additional unique
/// match exists beyond `entries`; it deliberately does not imply a total count.
public struct EmojiSearchResult: Equatable, Sendable {
    public let entries: [EmojiEntry]
    public let isTruncated: Bool

    public init(entries: [EmojiEntry], isTruncated: Bool) {
        self.entries = entries
        self.isTruncated = isTruncated
    }
}

public struct EmojiSubsection: Identifiable, Equatable, Sendable {
    public let name: String
    public let entries: [EmojiEntry]

    public var id: String { name }

    public init(name: String, entries: [EmojiEntry]) {
        self.name = name
        self.entries = entries
    }
}

public struct EmojiSection: Identifiable, Equatable, Sendable {
    public let name: String
    public let subsections: [EmojiSubsection]

    public var id: String { name }

    public init(name: String, subsections: [EmojiSubsection]) {
        self.name = name
        self.subsections = subsections
    }
}

public struct EmojiGroup: Identifiable, Equatable, Sendable {
    public let name: String
    public let entries: [EmojiEntry]
    public let sections: [EmojiSection]

    public var id: String { name }

    public init(name: String, entries: [EmojiEntry]) {
        self.name = name
        self.entries = entries
        self.sections = []
    }

    public init(name: String, sections: [EmojiSection]) {
        self.name = name
        self.sections = sections

        var seen = Set<String>()
        var uniqueEntries: [EmojiEntry] = []
        for entry in sections.flatMap({ $0.subsections }).flatMap(\.entries) where seen.insert(entry.base).inserted {
            uniqueEntries.append(entry)
        }
        self.entries = uniqueEntries
    }

    fileprivate init(name: String, entries: [EmojiEntry], sections: [EmojiSection]) {
        self.name = name
        self.entries = entries
        self.sections = sections
    }
}

public struct EmojiSkinTone: Identifiable, Equatable, Sendable {
    public let label: String
    public let scalar: Unicode.Scalar?

    public var id: String { label }

    public init(label: String, scalar: Unicode.Scalar?) {
        self.label = label
        self.scalar = scalar
    }
}

/// Emoji catalog generated once from the OS Unicode tables and cached in a
/// static, so the picker loads instantly. The primary source is Unicode's
/// emoji-test.txt data, which includes multi-scalar emoji sequences in CLDR
/// keyboard order. A scalar-property fallback remains for missing resources.
public enum EmojiCatalog {
    public static let specialSymbolGroupName = "特殊符号"

    private static let precompiledCatalogSchemaVersion = 1
    private static let precompiledCatalogResourceName = "emoji-catalog-v1"

    private struct PrecompiledCatalog: Codable {
        let schemaVersion: Int
        let groups: [PrecompiledGroup]

        init(groups: [EmojiGroup]) {
            schemaVersion = EmojiCatalog.precompiledCatalogSchemaVersion
            self.groups = groups.map(PrecompiledGroup.init)
        }
    }

    private struct PrecompiledGroup: Codable {
        let name: String
        let entries: [PrecompiledEntry]
        let sections: [PrecompiledSection]

        init(_ group: EmojiGroup) {
            name = group.name
            entries = group.entries.map(PrecompiledEntry.init)
            sections = group.sections.map(PrecompiledSection.init)
        }

        var domainValue: EmojiGroup {
            EmojiGroup(
                name: name,
                entries: entries.map(\.domainValue),
                sections: sections.map(\.domainValue)
            )
        }
    }

    private struct PrecompiledSection: Codable {
        let name: String
        let subsections: [PrecompiledSubsection]

        init(_ section: EmojiSection) {
            name = section.name
            subsections = section.subsections.map(PrecompiledSubsection.init)
        }

        var domainValue: EmojiSection {
            EmojiSection(name: name, subsections: subsections.map(\.domainValue))
        }
    }

    private struct PrecompiledSubsection: Codable {
        let name: String
        let entries: [PrecompiledEntry]

        init(_ subsection: EmojiSubsection) {
            name = subsection.name
            entries = subsection.entries.map(PrecompiledEntry.init)
        }

        var domainValue: EmojiSubsection {
            EmojiSubsection(name: name, entries: entries.map(\.domainValue))
        }
    }

    private struct PrecompiledEntry: Codable {
        let base: String
        let name: String
        let aliases: [String]
        let skinToneCapable: Bool
        let searchText: String

        init(_ entry: EmojiEntry) {
            base = entry.base
            name = entry.name
            aliases = entry.aliases
            skinToneCapable = entry.skinToneCapable
            searchText = entry.searchText
        }

        var domainValue: EmojiEntry {
            EmojiEntry(
                base: base,
                name: name,
                aliases: aliases,
                skinToneCapable: skinToneCapable,
                searchText: searchText
            )
        }
    }

    public static let skinTones: [EmojiSkinTone] = [
        EmojiSkinTone(label: "默认", scalar: nil)
    ] + skinToneModifiers.map { EmojiSkinTone(label: $0.label, scalar: $0.scalar) }

    public static func apply(tone: Unicode.Scalar?, to entry: EmojiEntry) -> String {
        guard let tone, entry.skinToneCapable else { return entry.base }

        var output = String.UnicodeScalarView()
        let scalars = entry.base.unicodeScalars
        var index = scalars.startIndex

        while index < scalars.endIndex {
            let scalar = scalars[index]
            output.append(scalar)

            if scalar.properties.isEmojiModifierBase {
                let nextIndex = scalars.index(after: index)
                if nextIndex == scalars.endIndex || !scalars[nextIndex].properties.isEmojiModifier {
                    output.append(tone)
                }
            }

            index = scalars.index(after: index)
        }

        return String(output)
    }

    public static func search(matching query: String, limit: Int) -> EmojiSearchResult {
        let trimmed = normalizedEmojiSearchText(query)
        guard !trimmed.isEmpty, limit > 0 else {
            return EmojiSearchResult(entries: [], isTruncated: false)
        }

        var matches: [EmojiEntry] = []
        var seen = Set<String>()
        matches.reserveCapacity(min(limit, allEntries.count))
        for entry in allEntries where entry.matches(normalized: trimmed) {
            guard seen.insert(canonicalGlyphKey(entry.base)).inserted else { continue }
            guard matches.count < limit else {
                return EmojiSearchResult(entries: matches, isTruncated: true)
            }
            matches.append(entry)
        }
        return EmojiSearchResult(entries: matches, isTruncated: false)
    }

    public static func entries(matching query: String, limit: Int) -> [EmojiEntry] {
        search(matching: query, limit: limit).entries
    }

    private struct RangeCategory: Sendable {
        let name: String
        let ranges: [ClosedRange<UInt32>]
    }

    // Fallback category ranges for environments where the bundled Unicode
    // resource is unavailable. The normal build path uses emoji-test.txt.
    private static let rangeCategories: [RangeCategory] = [
        RangeCategory(name: "笑脸与情感", ranges: [0x1F600...0x1F64F, 0x1F910...0x1F92F, 0x1F970...0x1F97A, 0x2639...0x263A]),
        RangeCategory(name: "人物与身体", ranges: [0x1F440...0x1F487, 0x1F574...0x1F575, 0x1F9B0...0x1F9FF, 0x1F90C...0x1F90F, 0x1F930...0x1F945, 0x1F48B...0x1F48F, 0x261D...0x261D, 0x270A...0x270D]),
        RangeCategory(name: "动物与自然", ranges: [0x1F400...0x1F43F, 0x1F980...0x1F9AE, 0x1F330...0x1F344, 0x1FAB0...0x1FABF, 0x1F300...0x1F320, 0x2600...0x2604, 0x26C4...0x26C8]),
        RangeCategory(name: "食物与饮品", ranges: [0x1F345...0x1F37F, 0x1F950...0x1F96F, 0x1F32D...0x1F32F, 0x1FAD0...0x1FADF]),
        RangeCategory(name: "旅行与地点", ranges: [0x1F680...0x1F6FF, 0x1F3D4...0x1F3F0, 0x1F30D...0x1F320, 0x1F5FA...0x1F5FA, 0x26F0...0x26FA, 0x2708...0x2709]),
        RangeCategory(name: "活动与运动", ranges: [0x1F380...0x1F3D3, 0x1F946...0x1F94F, 0x26BD...0x26BE, 0x26F3...0x26F9, 0x1F3AB...0x1F3B0]),
        RangeCategory(name: "物品与工具", ranges: [0x1F4F1...0x1F4FF, 0x1F50A...0x1F53D, 0x1F6E0...0x1F6EF, 0x1FA70...0x1FAAF, 0x1F9F0...0x1F9FF, 0x1F4A1...0x1F4FC, 0x231A...0x231B, 0x2328...0x2328, 0x260E...0x260E]),
        RangeCategory(name: "符号与标志", ranges: [0x1F500...0x1F509, 0x1F5FB...0x1F5FF, 0x1F4AC...0x1F4B0, 0x2700...0x27BF, 0x2614...0x2697, 0x2B00...0x2BFF, 0x1F170...0x1F251, 0x00A9...0x00AE]),
    ]

    private static let skinToneModifiers: [(label: String, scalar: Unicode.Scalar)] = [
        0x1F3FB,
        0x1F3FC,
        0x1F3FD,
        0x1F3FE,
        0x1F3FF
    ].compactMap { code in
        guard let scalar = Unicode.Scalar(code) else { return nil }
        return (String(scalar), scalar)
    }

    private static let scanRange: ClosedRange<UInt32> = 0x00A9...0x1FAFF
    private static let otherCategoryName = "其他"

    /// All groups in display order. The checked-in binary catalog keeps normal
    /// startup off the Unicode text parser; source parsing remains the exact
    /// runtime fallback when the resource is absent, corrupt, or incompatible.
    public static let groups: [EmojiGroup] = {
        guard let data = bundledPrecompiledCatalogData(),
              let groups = decodePrecompiledCatalog(data) else {
            return buildSourceCatalog()
        }
        return groups
    }()

    /// Flat list of every entry across all groups, cached so search doesn't
    /// reallocate the combined array on each keystroke.
    public static let allEntries: [EmojiEntry] = groups.flatMap(\.entries)

    public static let totalProducible: Int = {
        groups.filter { $0.name != specialSymbolGroupName }.reduce(0) { acc, group in
            acc + group.entries.reduce(0) { $0 + ($1.skinToneCapable ? skinTones.count : 1) }
        }
    }()

    public static let specialSymbolCount: Int = {
        groups.first { $0.name == specialSymbolGroupName }?.entries.count ?? 0
    }()

    private static func categoryName(for codePoint: UInt32) -> String {
        for category in rangeCategories {
            for range in category.ranges where range.contains(codePoint) {
                return category.name
            }
        }
        return otherCategoryName
    }

    package static func bundledPrecompiledCatalogData() -> Data? {
        guard let url = Bundle.module.url(
            forResource: precompiledCatalogResourceName,
            withExtension: "plist"
        ) else {
            return nil
        }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    package static func decodePrecompiledCatalog(_ data: Data) -> [EmojiGroup]? {
        guard let catalog = try? PropertyListDecoder().decode(PrecompiledCatalog.self, from: data),
              catalog.schemaVersion == precompiledCatalogSchemaVersion,
              !catalog.groups.isEmpty else {
            return nil
        }
        return catalog.groups.map(\.domainValue)
    }

    package static func buildSourceCatalog() -> [EmojiGroup] {
        if let data = loadEmojiTestData() {
            let groups = parseEmojiTestData(data)
            if !groups.isEmpty {
                return groups + [buildSpecialSymbolGroup()]
            }
        }

        return buildFallbackFromScalarProperties() + [buildSpecialSymbolGroup()]
    }

    package static func compilePrecompiledCatalogData() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(PrecompiledCatalog(groups: buildSourceCatalog()))
    }

    private static func loadEmojiTestData() -> String? {
        guard let url = Bundle.module.url(forResource: "emoji-test", withExtension: "txt") else {
            return nil
        }

        return try? String(contentsOf: url, encoding: .utf8)
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
                    aliases: aliases(forUnicodeName: parsed.name)
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
        default: return otherCategoryName
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

    private static func buildFallbackFromScalarProperties() -> [EmojiGroup] {
        var buckets: [String: [EmojiEntry]] = [:]
        var seen = Set<UInt32>()

        for codePoint in scanRange {
            guard let scalar = Unicode.Scalar(codePoint),
                  scalar.properties.isEmojiPresentation else { continue }
            guard !scalar.properties.isEmojiModifier else { continue }
            guard seen.insert(codePoint).inserted else { continue }

            let entry = EmojiEntry(
                base: String(scalar),
                name: (scalar.properties.name ?? "").lowercased(),
                skinToneCapable: scalar.properties.isEmojiModifierBase,
                aliases: aliases(forUnicodeName: scalar.properties.name ?? "")
            )
            buckets[categoryName(for: codePoint), default: []].append(entry)
        }

        var ordered: [EmojiGroup] = rangeCategories.compactMap { category in
            guard let entries = buckets[category.name], !entries.isEmpty else { return nil }
            return EmojiGroup(name: category.name, entries: entries)
        }
        if let others = buckets[otherCategoryName], !others.isEmpty {
            ordered.append(EmojiGroup(name: otherCategoryName, entries: others))
        }
        return ordered
    }

    private struct SpecialSymbolSectionSpec: Sendable {
        let name: String
        let aliases: [String]
        let subsections: [SpecialSymbolSubsectionSpec]
    }

    private struct SpecialSymbolSubsectionSpec: Sendable {
        let name: String
        let symbols: String
        let aliases: [String]
    }

    private static func buildSpecialSymbolGroup() -> EmojiGroup {
        EmojiGroup(
            name: specialSymbolGroupName,
            sections: specialSymbolSections.map { section in
                EmojiSection(
                    name: section.name,
                    subsections: section.subsections.map { subsection in
                        EmojiSubsection(
                            name: subsection.name,
                            entries: subsection.symbols.map { character in
                                let glyph = String(character)
                                let name = unicodeName(for: glyph)
                                return EmojiEntry(
                                    base: glyph,
                                    name: name.lowercased(),
                                    skinToneCapable: false,
                                    aliases: baseSymbolAliases
                                        + section.aliases
                                        + subsection.aliases
                                        + aliases(forUnicodeName: name)
                                )
                            }
                        )
                    }
                )
            }
        )
    }

    private static let baseSymbolAliases = ["symbol", "symbols", "special symbol", "符号", "特殊符号"]

    private static let specialSymbolSections: [SpecialSymbolSectionSpec] = [
        SpecialSymbolSectionSpec(
            name: "箭头与方向符号",
            aliases: ["arrow", "arrows", "direction", "directions", "箭头", "方向", "指向"],
            subsections: [
                SpecialSymbolSubsectionSpec(name: "基础单向", symbols: "↑↓←→↖↗↘↙", aliases: ["basic", "single direction", "基础", "单向"]),
                SpecialSymbolSubsectionSpec(name: "空心箭头", symbols: "⇧⇩⇦⇨⇗⇖⇘⇙➪➬➮⇳", aliases: ["white arrow", "outline arrow", "空心"]),
                SpecialSymbolSubsectionSpec(name: "双向与双线", symbols: "↔↕⇄⇆⇅⇇⇉⇈⇊⇐⇒⇔⇕⇖⇗⇘⇙⇑⇓", aliases: ["double arrow", "bidirectional", "双向", "双线"]),
                SpecialSymbolSubsectionSpec(name: "加粗/实心块状", symbols: "➔➘➙➚➛➜➝➞➟➡➢➣➤➥➦", aliases: ["bold arrow", "black arrow", "block arrow", "加粗", "实心", "块状"]),
                SpecialSymbolSubsectionSpec(name: "循环与弯曲", symbols: "↻↺↩↪↶↷↹", aliases: ["loop", "curved arrow", "return arrow", "循环", "弯曲", "返回", "撤回"])
            ]
        ),
        SpecialSymbolSectionSpec(
            name: "手指指向",
            aliases: ["pointing", "finger", "index", "hand", "手指", "指向"],
            subsections: [
                SpecialSymbolSubsectionSpec(name: "经典手指", symbols: "☝☟☜☞", aliases: ["classic", "经典"])
            ]
        ),
        SpecialSymbolSectionSpec(
            name: "勾叉",
            aliases: ["check", "cross", "tick", "correct", "wrong", "勾", "叉", "对", "错", "正确", "错误"],
            subsections: [
                SpecialSymbolSubsectionSpec(name: "打勾/正确", symbols: "✓✔☑", aliases: ["check mark", "tick", "correct", "yes", "打勾", "勾", "正确", "对"]),
                SpecialSymbolSubsectionSpec(name: "打叉/错误", symbols: "✗✘☒✖✕", aliases: ["cross mark", "wrong", "no", "x", "打叉", "叉", "错误", "错"])
            ]
        ),
        SpecialSymbolSectionSpec(
            name: "货币",
            aliases: ["currency", "money", "cash", "货币", "钱", "金额"],
            subsections: [
                SpecialSymbolSubsectionSpec(name: "主要主权货币", symbols: "￥$€£₩฿₽₹₫", aliases: ["currency", "money", "fiat", "主权货币", "货币", "钱"]),
                SpecialSymbolSubsectionSpec(name: "数字货币", symbols: "₿", aliases: ["bitcoin", "crypto", "cryptocurrency", "digital currency", "比特币", "数字货币", "加密货币"])
            ]
        ),
        SpecialSymbolSectionSpec(
            name: "天气与自然",
            aliases: ["weather", "nature", "sky", "天气", "自然", "气象", "天体"],
            subsections: [
                SpecialSymbolSubsectionSpec(name: "气象与天体", symbols: "☀☁☃❄☼☽☾", aliases: ["sun", "cloud", "snow", "moon", "weather", "气象", "天体", "太阳", "云", "雪", "月亮"])
            ]
        ),
        SpecialSymbolSectionSpec(
            name: "音符与视听娱乐",
            aliases: ["music", "media", "audio", "video", "entertainment", "音乐", "音符", "媒体", "视听", "娱乐"],
            subsections: [
                SpecialSymbolSubsectionSpec(name: "音乐音符", symbols: "♩♪♫♬", aliases: ["music", "note", "notes", "音乐", "音符"]),
                SpecialSymbolSubsectionSpec(name: "多媒体播放", symbols: "▶⏸⏹⏮⏭◀", aliases: ["play", "pause", "stop", "previous", "next", "media", "播放", "暂停", "停止", "上一首", "下一首", "多媒体"])
            ]
        ),
        SpecialSymbolSectionSpec(
            name: "商业、版权与办公图标",
            aliases: ["business", "copyright", "trademark", "office", "communication", "商业", "版权", "商标", "办公", "通讯"],
            subsections: [
                SpecialSymbolSubsectionSpec(name: "版权与商标", symbols: "©®™℗℠", aliases: ["copyright", "registered", "trademark", "service mark", "版权", "商标", "注册"]),
                SpecialSymbolSubsectionSpec(name: "办公通讯", symbols: "✉☎☏✂✏✒", aliases: ["mail", "phone", "scissors", "pencil", "office", "envelope", "办公", "通讯", "邮件", "电话", "剪刀", "铅笔"])
            ]
        ),
        SpecialSymbolSectionSpec(
            name: "几何图形与列表修饰",
            aliases: ["geometric", "shape", "bullet", "list", "几何", "图形", "列表", "修饰"],
            subsections: [
                SpecialSymbolSubsectionSpec(name: "圆点与圆圈", symbols: "●○◎◌◍◐◑◒◓◯", aliases: ["circle", "dot", "bullet", "round", "圆", "圆点", "圆圈"]),
                SpecialSymbolSubsectionSpec(name: "方块与菱形", symbols: "■□▰▱▣◧◨◩◪◆◇◈", aliases: ["square", "diamond", "box", "方块", "方形", "菱形"]),
                SpecialSymbolSubsectionSpec(name: "三角形与指针", symbols: "▲▼◀▶△▽◁▷◄►", aliases: ["triangle", "pointer", "play", "三角形", "指针", "播放"]),
                SpecialSymbolSubsectionSpec(name: "星形与闪烁", symbols: "★☆✦✧✪✫✬✭❖", aliases: ["star", "sparkle", "shine", "星形", "星星", "闪烁"])
            ]
        ),
        SpecialSymbolSectionSpec(
            name: "数字序号与带圈字符",
            aliases: ["number", "ordinal", "circled", "roman", "数字", "序号", "带圈", "罗马数字"],
            subsections: [
                SpecialSymbolSubsectionSpec(name: "带圈数字（1-20）", symbols: "①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳", aliases: ["circled number", "number", "带圈数字", "序号"]),
                SpecialSymbolSubsectionSpec(name: "黑底白字带圈", symbols: "❶❷❸❹❺❻❼❽❾❿", aliases: ["negative circled number", "black circled number", "黑底", "白字", "带圈"]),
                SpecialSymbolSubsectionSpec(name: "括号数字（1-10）", symbols: "⑴⑵⑶⑷⑸⑹⑺⑻⑼⑽", aliases: ["parenthesized number", "bracket number", "括号数字"]),
                SpecialSymbolSubsectionSpec(name: "罗马数字（大写）", symbols: "ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩⅪⅫ", aliases: ["roman numeral", "uppercase roman", "罗马数字", "大写"]),
                SpecialSymbolSubsectionSpec(name: "罗马数字（小写）", symbols: "ⅰⅱⅲⅳⅴⅵⅶⅷⅸⅹ", aliases: ["roman numeral", "lowercase roman", "罗马数字", "小写"])
            ]
        ),
        SpecialSymbolSectionSpec(
            name: "常用数学运算与度量单位",
            aliases: ["math", "operator", "unit", "measure", "数学", "运算", "单位", "度量"],
            subsections: [
                SpecialSymbolSubsectionSpec(name: "基础运算", symbols: "＋－×÷＝≠≈≒±＜＞≤≥≡≌∽", aliases: ["math", "operator", "plus", "minus", "equals", "基础运算", "运算", "加减乘除", "等于"]),
                SpecialSymbolSubsectionSpec(name: "常用数学", symbols: "∞∝∵∴∑√π∆", aliases: ["math", "infinity", "sum", "sqrt", "pi", "常用数学", "无穷", "求和", "平方根"]),
                SpecialSymbolSubsectionSpec(name: "单位度量", symbols: "°℃℉㎡³²", aliases: ["unit", "degree", "celsius", "fahrenheit", "square meter", "单位", "度量", "摄氏度", "华氏度", "平方米"])
            ]
        ),
        SpecialSymbolSectionSpec(
            name: "社交、性别与卡牌娱乐",
            aliases: ["social", "gender", "card", "suit", "face", "社交", "性别", "卡牌", "娱乐", "表情"],
            subsections: [
                SpecialSymbolSubsectionSpec(name: "性别符号", symbols: "♂♀⚧", aliases: ["gender", "male", "female", "transgender", "性别", "男性", "女性", "跨性别"]),
                SpecialSymbolSubsectionSpec(name: "扑克牌花色", symbols: "♠♥♦♣♤♡♢♧", aliases: ["card suit", "spade", "heart", "diamond", "club", "扑克牌", "花色", "黑桃", "红心", "方块", "梅花"]),
                SpecialSymbolSubsectionSpec(name: "经典表情", symbols: "☺☹☻", aliases: ["face", "smile", "frown", "classic face", "表情", "笑脸", "哭脸"])
            ]
        )
    ]

    private static func unicodeName(for glyph: String) -> String {
        glyph.unicodeScalars
            .compactMap(\.properties.name)
            .joined(separator: " ")
    }

    private static func canonicalGlyphKey(_ glyph: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in glyph.unicodeScalars where scalar.value != 0xFE0E && scalar.value != 0xFE0F {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func aliases(forUnicodeName name: String) -> [String] {
        let lowercased = name.lowercased()
        let tokens = Set(lowercased.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        var aliases: [String] = []

        if tokens.contains("right") || tokens.contains("rightwards") || tokens.contains("rightward") {
            aliases += ["right", "右", "右边", "向右"]
        }
        if tokens.contains("left") || tokens.contains("leftwards") || tokens.contains("leftward") {
            aliases += ["left", "左", "左边", "向左"]
        }
        if tokens.contains("up") || tokens.contains("upwards") || tokens.contains("upward") {
            aliases += ["up", "上", "上方", "向上"]
        }
        if tokens.contains("down") || tokens.contains("downwards") || tokens.contains("downward") {
            aliases += ["down", "下", "下方", "向下"]
        }
        if tokens.contains("arrow") {
            aliases += ["arrow", "箭头", "方向"]
        }
        if tokens.contains("play") {
            aliases += ["play", "播放"]
        }
        if tokens.contains("check") {
            aliases += ["check", "tick", "correct", "勾", "正确", "对"]
        }
        if tokens.contains("cross") || tokens.contains("crossed") || lowercased.contains("multiplication x") {
            aliases += ["cross", "wrong", "叉", "错误", "错"]
        }
        if tokens.contains("currency") || tokens.contains("dollar") || tokens.contains("yen") || tokens.contains("euro") {
            aliases += ["currency", "money", "货币", "钱"]
        }

        return aliases
    }
}
