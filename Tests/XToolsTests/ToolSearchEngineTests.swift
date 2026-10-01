import Foundation
import SwiftUI
import Testing
@testable import XTools

/// Unified search-engine behavior: tier ordering, multi-token AND queries,
/// fuzzy tiers, pinyin projection, and title highlight ranges.
struct ToolSearchEngineTests {
    private static func registry(
        _ entries: [(ToolID, String, [String])]
    ) -> ToolRegistry {
        ToolRegistry(
            categories: [
                ToolCategory(id: .development, title: "Development", systemImage: "hammer")
            ],
            tools: entries.map { id, title, keywords in
                RegisteredTool(
                    id: id,
                    title: title,
                    categoryID: .development,
                    systemImage: "gear",
                    keywords: keywords
                ) {
                    EmptyView()
                }
            }
        )
    }

    // MARK: - Tier contract

    @Test func tierOrderPreservesPrefixContainsKeywordContract() {
        let registry = Self.registry([
            (.contains, "Pretty JSON", []),
            (.keyword, "Beautifier", ["json"]),
            (.prefix, "JSON Formatter", [])
        ])

        #expect(registry.matchingTools(query: " json ").map(\.id) == [
            .prefix,
            .contains,
            .keyword
        ])
    }

    @Test func fuzzyTiersRankBelowEveryContainsTier() {
        let registry = Self.registry([
            (.subsequence, "aXbX", []),
            (.keywordContains, "Zed", ["ab"]),
            (.titleContains, "Table", [])
        ])

        #expect(registry.matchingTools(query: "ab").map(\.id) == [
            .titleContains,
            .keywordContains,
            .subsequence
        ])
    }

    @Test func withinTierBoundaryBeatsMidWordAndTiesKeepRegistrationOrder() {
        let registry = Self.registry([
            (.midWord, "Btoken", []),
            (.boundary, "A Token", []),
            (.equalKeywordFirst, "First Alias", ["json"]),
            (.equalKeywordSecond, "Second Alias", ["json"])
        ])

        // "A Token" (match after whitespace) outranks "Btoken" (mid-word)
        // inside the title-contains tier; equal keyword scores keep
        // registration order.
        #expect(registry.matchingTools(query: "token").map(\.id) == [
            .boundary,
            .midWord
        ])
        #expect(registry.matchingTools(query: "json").map(\.id) == [
            .equalKeywordFirst,
            .equalKeywordSecond
        ])
    }

    @Test func caseAndDiacriticInsensitiveFoldingStillApplies() {
        let registry = Self.registry([
            (.cafe, "Cafe Menu", [])
        ])

        let match = registry.matchingToolMatches(query: "CAFÉ").first

        #expect(match?.tool.id == .cafe)
        #expect(match?.match?.tier == .titlePrefix)
    }

    // MARK: - Multi-token AND queries

    @Test func multiTokenQueriesRequireEveryTokenToMatch() {
        let registry = Self.registry([
            (.formatter, "格式化", ["json"]),
            (.diff, "对比", ["json"])
        ])

        #expect(
            registry.matchingTools(query: "json 格式化").map(\.id) == [.formatter]
        )
        #expect(registry.matchingTools(query: "json 不存在的词").isEmpty)
    }

    // MARK: - Fuzzy + pinyin recall (default registry)

    @Test func titleSubsequenceMatchesScatteredLatinQueries() {
        let matches = ToolRegistry.default.matchingTools(query: "dkr")

        #expect(matches.map(\.id).contains("docker-run-to-docker-compose-converter"))
    }

    @Test func pinyinInitialsAndSyllablesMatchChineseTitles() {
        let defaultRegistry = ToolRegistry.default

        // 时间戳转换 → "shijianchuozhuanhuan" / initials "sjczh".
        for query in ["sjc", "sjz", "shijian"] {
            #expect(
                defaultRegistry.matchingTools(query: query)
                    .map(\.id)
                    .contains("date-time-converter"),
                "query \(query) should reach the timestamp converter"
            )
        }

        // Hash 文本 → initials "hwb".
        #expect(
            defaultRegistry.matchingTools(query: "hwb").map(\.id).contains("hash-text")
        )
    }

    @Test func pinyinMatchingAppliesToCommandActionsToo() {
        let action = CommandActionEntry(
            id: .toggleAppearance,
            title: "切换主题",
            subtitle: nil,
            systemImage: "circle.lefthalf.filled"
        )

        #expect(action.matches(query: "qieh"))
        #expect(action.matches(query: "qhzht"))
        #expect(!action.matches(query: "jwt"))
    }

    // MARK: - Title highlight ranges

    @Test func highlightRangesMapBackToOriginalTitleIndices() {
        let title = "JSON Formatter"
        let record = ToolSearchRecord(title: title, keywords: [])
        let match = ToolSearchEngine.match(record: record, query: "json")

        let expected = title.startIndex..<title.index(title.startIndex, offsetBy: 4)
        #expect(match?.tier == .titlePrefix)
        #expect(match?.titleRanges == [expected])
    }

    /// Length-changing folds (ß → ss) expand the folded text past the original
    /// grapheme count; bonuses and matching must stay aligned to folded space
    /// or the last folded positions read out of bounds.
    @Test func variableLengthFoldTitlesDoNotTrapAndStillMatch() {
        let title = "Straße Format"
        let record = ToolSearchRecord(title: title, keywords: [])

        // Plain prefix on the un-expanded head keeps the fast-path contract.
        let prefix = ToolSearchEngine.match(record: record, query: "stra")
        #expect(prefix?.tier == .titlePrefix)

        // "ss" lands on the ß expansion (folded positions 4-5) and must match
        // without trapping on the shortened bonus array.
        let expanded = ToolSearchEngine.match(record: record, query: "ss")
        #expect(expanded != nil)

        // The trailing "Format" sits beyond the original grapheme count in
        // folded space; its highlight range must map back to original text.
        let tail = ToolSearchEngine.match(record: record, query: "format")
        #expect(tail?.titleRanges.count == 1)
        #expect(tail.map { String(title[$0.titleRanges[0]]) } == "Format")

        // "t" scores BOTH folded occurrences (indices 1 and 13); the tail
        // occurrence indexes the last bonus — the exact read that trapped
        // (and silently mis-scored) before bonuses were fold-aligned.
        let lastPosition = ToolSearchEngine.match(record: record, query: "t")
        #expect(lastPosition != nil)
        #expect(lastPosition?.tier == .titleContains)
    }

    @Test func multiTokenQueriesCarrySortedDisjointHighlightRanges() {
        let title = "JSON Formatter"
        let record = ToolSearchRecord(title: title, keywords: [])
        let match = ToolSearchEngine.match(record: record, query: "js fmt")

        #expect(match != nil)
        guard let match else { return }
        // "js" is contiguous (one range); "fmt" is a fuzzy token (one range
        // per matched character).
        #expect(match.titleRanges.count == 4)
        #expect(String(title[match.titleRanges[0]]) == "JS")
        #expect(String(title[match.titleRanges[3]]) == "t")
        for index in 1..<match.titleRanges.count {
            #expect(
                match.titleRanges[index - 1].upperBound
                    <= match.titleRanges[index].lowerBound
            )
        }
    }

    @Test func keywordOnlyMatchesCarryNoHighlightRanges() {
        let record = ToolSearchRecord(title: "格式化", keywords: ["json"])
        let match = ToolSearchEngine.match(record: record, query: "json")

        #expect(match?.tier == .keywordContains)
        #expect(match?.titleRanges.isEmpty == true)
    }

    @Test func highlightRangesMergeWhenTokensPaintTheSameGraphemes() {
        let title = "Hash 文本"
        let record = ToolSearchRecord(title: title, keywords: [])
        // "hash" (title contains) and "h" (inside the same prefix) overlap.
        let match = ToolSearchEngine.match(record: record, query: "hash h")

        #expect(match != nil)
        #expect(match?.titleRanges.count == 1)
        guard let merged = match?.titleRanges.first else { return }
        #expect(String(title[merged]) == "Hash")
    }

    // MARK: - Scoring sanity

    @Test func fuzzyAlignmentRewardsConsecutiveRunsOverScatteredOnes() {
        let text = ToolSearchText(foldedSource: "json formatter")

        let contiguous = ToolSearchEngine.fuzzyAlign(Array("json"), in: text)
        let scattered = ToolSearchEngine.fuzzyAlign(Array("jtr"), in: text)

        #expect(contiguous != nil)
        #expect(scattered != nil)
        guard let contiguousScore = contiguous?.score,
              let scatteredScore = scattered?.score
        else { return }
        #expect(contiguousScore > scatteredScore)
    }

    @Test func longGarbageQueriesStillFailToMatch() {
        let registry = Self.registry([
            (.json, "JSON Formatter", ["pretty", "token"])
        ])

        #expect(registry.matchingTools(query: "definitely-missing").isEmpty)
        #expect(registry.matchingTools(query: "zzzqqq").isEmpty)
    }

    // MARK: - Opt-in microbenchmark

    /// Run with TOOLS_COMMAND_PALETTE_BENCHMARK=1. Measures registry init
    /// (folding + pinyin projection) and per-query engine cost on the real
    /// default registry. Percentages here do not establish end-to-end
    /// latency.
    @Test func searchEngineBenchmark() {
        guard ProcessInfo.processInfo.environment["TOOLS_COMMAND_PALETTE_BENCHMARK"] == "1" else {
            return
        }

        let initStartedAt = ContinuousClock.now
        let registry = ToolRegistry.default
        let initElapsed = ContinuousClock.now - initStartedAt

        let queries = ["json", "sjz", "时间戳", "uuid 生成", "dkr"]
        let iterations = 1_000
        let queryStartedAt = ContinuousClock.now
        for _ in 0..<iterations {
            for query in queries {
                _ = registry.matchingToolMatches(query: query)
            }
        }
        let queryElapsed = ContinuousClock.now - queryStartedAt

        func milliseconds(_ duration: Duration) -> Double {
            let components = duration.components
            return Double(components.seconds) * 1_000
                + Double(components.attoseconds) / 1_000_000_000_000_000
        }

        FileHandle.standardError.write(Data(String(
            format: "TOOL_SEARCH_ENGINE_BENCHMARK initMs=%.3f queries=%d iterations=%d perQueryMs=%.4f\n",
            milliseconds(initElapsed),
            queries.count,
            iterations,
            milliseconds(queryElapsed) / Double(iterations * queries.count)
        ).utf8))
    }
}

private extension ToolID {
    static let prefix = ToolID(rawValue: "prefix")
    static let contains = ToolID(rawValue: "contains")
    static let keyword = ToolID(rawValue: "keyword")
    static let titleContains = ToolID(rawValue: "title-contains")
    static let keywordContains = ToolID(rawValue: "keyword-contains")
    static let subsequence = ToolID(rawValue: "subsequence")
    static let boundary = ToolID(rawValue: "boundary")
    static let midWord = ToolID(rawValue: "mid-word")
    static let equalKeywordFirst = ToolID(rawValue: "equal-keyword-first")
    static let equalKeywordSecond = ToolID(rawValue: "equal-keyword-second")
    static let formatter = ToolID(rawValue: "formatter")
    static let diff = ToolID(rawValue: "diff")
    static let cafe = ToolID(rawValue: "cafe")
    static let json = ToolID(rawValue: "json")
}
