import Foundation
import SwiftUI
import Testing
@testable import XTools

/// Alias-aware search behavior: keyword-tier hits report the matched alias
/// (display label, hub segment, label highlight ranges) without changing the
/// locked tier/score ranking, hub aliases stay aligned with their page
/// segments, and palette snapshots compose the match-reason subtitle.
struct ToolAliasSearchTests {
    // MARK: - Engine: alias reporting

    @Test func aliasLabelMatchReportsLabelRangesAndSegment() {
        let record = ToolSearchRecord(
            title: "文本编码",
            keywords: ["encode"],
            aliases: [ToolAlias("Base64", matching: [], segment: "base64")]
        )

        let match = ToolSearchEngine.match(record: record, query: "base64")

        #expect(match?.tier == .keywordContains)
        #expect(match?.titleRanges.isEmpty == true)
        #expect(match?.aliasMatches.map(\.label) == ["Base64"])
        #expect(match?.aliasMatches.first?.segment == "base64")
        #expect(match?.deepLinkSegment == "base64")
        // Label-local ranges map back into the original label string.
        #expect(
            match?.aliasMatches.first?.labelRanges
                .map { String("Base64"[$0]) } == ["Base64"]
        )
    }

    @Test func variantMatchReportsLabelWithoutRanges() {
        let record = ToolSearchRecord(
            title: "文本编码",
            keywords: [],
            aliases: [ToolAlias("URL", matching: ["percent"], segment: "url")]
        )

        let match = ToolSearchEngine.match(record: record, query: "percent")

        #expect(match?.tier == .keywordContains)
        #expect(match?.aliasMatches.map(\.label) == ["URL"])
        #expect(match?.aliasMatches.first?.labelRanges.isEmpty == true)
        #expect(match?.deepLinkSegment == "url")
    }

    @Test func sameLabelAcrossTokensFusesIntoOneAliasMatchWithMergedRanges() {
        let record = ToolSearchRecord(
            title: "文本编码",
            keywords: [],
            aliases: [ToolAlias("URL", matching: ["percent"], segment: "url")]
        )

        // "url" hits the label surface (ranges), "percent" the variant (no
        // ranges): one fused alias keeps the ranges.
        let match = ToolSearchEngine.match(record: record, query: "url percent")

        #expect(match?.aliasMatches.count == 1)
        #expect(match?.aliasMatches.first?.label == "URL")
        #expect(
            match?.aliasMatches.first?.labelRanges
                .map { String("URL"[$0]) } == ["URL"]
        )
        #expect(match?.deepLinkSegment == "url")
    }

    @Test func distinctAliasesRankByContributionAndCapDisplayAtTwo() {
        let record = ToolSearchRecord(
            title: "文本编码",
            keywords: [],
            aliases: [
                ToolAlias("Base64", matching: [], segment: "base64"),
                ToolAlias("URL", matching: [], segment: "url"),
                ToolAlias("Unicode", matching: [], segment: "unicode")
            ]
        )

        // Contiguous-at-boundary scores: unicode (7 chars) > base64 (6) >
        // url (3), so display caps at [Unicode, Base64] while the deep link
        // takes the best-scoring segment-bearing alias.
        let match = ToolSearchEngine.match(record: record, query: "base64 url unicode")

        #expect(match?.aliasMatches.map(\.label) == ["Unicode", "Base64"])
        #expect(match?.deepLinkSegment == "unicode")
    }

    @Test func titleTierMatchesCarryNoAliases() {
        let record = ToolSearchRecord(
            title: "Base64 文件",
            keywords: [],
            aliases: [ToolAlias("Data URL", matching: ["dataurl"])]
        )

        let match = ToolSearchEngine.match(record: record, query: "base64")

        #expect(match?.tier == .titlePrefix)
        #expect(match?.aliasMatches.isEmpty == true)
        #expect(match?.deepLinkSegment == nil)
    }

    @Test func plainKeywordMatchesStillReportNothing() {
        let record = ToolSearchRecord(title: "文本编码", keywords: ["encode"])

        let match = ToolSearchEngine.match(record: record, query: "encode")

        #expect(match?.tier == .keywordContains)
        #expect(match?.aliasMatches.isEmpty == true)
        #expect(match?.deepLinkSegment == nil)
    }

    @Test func pinyinProjectionOfAliasLabelInheritsOwnershipWithoutRanges() {
        let record = ToolSearchRecord(
            title: "生成器",
            keywords: [],
            aliases: [ToolAlias("密码", matching: [], segment: "password")]
        )

        let match = ToolSearchEngine.match(record: record, query: "mm")

        #expect(match?.aliasMatches.map(\.label) == ["密码"])
        #expect(match?.aliasMatches.first?.labelRanges.isEmpty == true)
        #expect(match?.deepLinkSegment == "password")
    }

    // MARK: - Engine: ranking regression

    private static func registry(
        _ entries: [(ToolID, String, [String], [ToolAlias])]
    ) -> ToolRegistry {
        ToolRegistry(
            categories: [
                ToolCategory(id: .development, title: "Development", systemImage: "hammer")
            ],
            tools: entries.map { id, title, keywords, aliases in
                RegisteredTool(
                    id: id,
                    title: title,
                    categoryID: .development,
                    systemImage: "gear",
                    keywords: keywords,
                    aliases: aliases
                ) {
                    EmptyView()
                }
            }
        )
    }

    @Test func keywordAbsorbedByAliasKeepsTierScoreAndOrder() {
        // The alias variant carries the absorbed keyword verbatim, so the
        // alias tool and a keyword-only tool score identically and the
        // original registration order decides.
        let registry = Self.registry([
            ("alias-tool", "文本编码", [], [ToolAlias("Base64", matching: ["base64"])]),
            ("keyword-tool", "Some Tool", ["base64"], [])
        ])

        let matches = registry.matchingToolMatches(query: "base64")

        #expect(matches.map(\.tool.id) == ["alias-tool", "keyword-tool"])
        #expect(matches.allSatisfy { $0.match?.tier == .keywordContains })
        #expect(matches[0].match?.score == matches[1].match?.score)
        // Only the alias tool reports its label.
        #expect(matches[0].match?.aliasMatches.map(\.label) == ["Base64"])
        #expect(matches[1].match?.aliasMatches.isEmpty == true)
    }

    // MARK: - Registry contract: hub aliases ↔ page segments

    @MainActor
    @Test func defaultRegistryHubAliasesMirrorPageSegments() {
        let expectations: [(ToolID, [String], [String])] = [
            (
                "text-encoding",
                EncodingHubWorkspaceModel.Segment.allCases.map(\.label),
                EncodingHubWorkspaceModel.Segment.allCases.map(\.rawValue)
            ),
            (
                "formatter",
                FormatterHubWorkspaceModel.Segment.allCases.map(\.label),
                FormatterHubWorkspaceModel.Segment.allCases.map(\.rawValue)
            ),
            (
                "generator",
                GeneratorHubWorkspaceModel.Segment.allCases.map(\.label),
                GeneratorHubWorkspaceModel.Segment.allCases.map(\.rawValue)
            ),
            (
                "diff",
                DiffHubWorkspaceModel.Segment.allCases.map(\.label),
                DiffHubWorkspaceModel.Segment.allCases.map(\.rawValue)
            ),
            (
                "image-tools",
                ImageHubWorkspaceModel.Segment.allCases.map(\.label),
                ImageHubWorkspaceModel.Segment.allCases.map(\.rawValue)
            )
        ]

        for (toolID, labels, segments) in expectations {
            let tool = ToolRegistry.default.tool(for: toolID)
            #expect(tool != nil)
            guard let tool else { continue }
            #expect(tool.aliases.map(\.label) == labels)
            #expect(tool.aliases.compactMap(\.segment) == segments)
        }
    }

    @Test func nonHubAliasesCarryNoSegments() {
        let segmentedToolIDs: Set<String> = [
            "text-encoding", "formatter", "generator", "diff", "image-tools"
        ]

        for group in ToolRegistry.default.categoryGroups() {
            for tool in group.tools where !segmentedToolIDs.contains(tool.id.rawValue) {
                #expect(
                    tool.aliases.allSatisfy { $0.segment == nil },
                    "\(tool.id.rawValue) carries an unexpected segment"
                )
            }
        }
    }

    // MARK: - Palette snapshot: match-reason subtitle composition

    @MainActor
    @Test func snapshotComposesAliasSubtitleWithHighlightAndDeepLink() {
        let model = CommandPaletteSessionModel(registry: .default, actions: [], session: 1)

        #expect(model.setQuery("base64"))

        let annotation = model.snapshot.subtitleAnnotationsByID["tool.text-encoding"]
        #expect(annotation?.text == "编码与转换 · Base64")
        #expect(annotation?.highlightRanges.count == 1)
        #expect(annotation.map { String($0.text[$0.highlightRanges[0]]) } == "Base64")
        #expect(model.snapshot.deepLinkSegmentsByID["tool.text-encoding"] == "base64")
        // A title-tier hit keeps its plain category subtitle.
        #expect(
            model.snapshot.subtitleAnnotationsByID["tool.base64-file-converter"] == nil
        )
    }

    @MainActor
    @Test func snapshotComposesMultipleAliasLabelsRankedByScore() {
        let model = CommandPaletteSessionModel(registry: .default, actions: [], session: 1)

        #expect(model.setQuery("url unicode"))

        let annotation = model.snapshot.subtitleAnnotationsByID["tool.text-encoding"]
        #expect(annotation?.text == "编码与转换 · Unicode · URL")
        #expect(model.snapshot.deepLinkSegmentsByID["tool.text-encoding"] == "unicode")
    }

    @MainActor
    @Test func blankQueryLandingKeepsPlainCategorySubtitles() {
        let model = CommandPaletteSessionModel(registry: .default, actions: [], session: 1)

        #expect(model.snapshot.subtitleAnnotationsByID.isEmpty)
        #expect(model.snapshot.deepLinkSegmentsByID.isEmpty)
    }
}
