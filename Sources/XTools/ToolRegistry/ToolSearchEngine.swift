import Foundation
import os

/// Alias ownership attached to one keyword-tier match surface: the display
/// label to report, the hub segment to deep-link, and — only when the surface
/// IS the label's own text — the label text so highlight ranges can map back
/// to the original label string. Variants and pinyin projections inherit the
/// label/segment but carry no label text, so their hits show the label
/// unhighlighted.
struct ToolSearchAliasSurface: Sendable {
    let label: String
    let segment: String?
    let labelText: ToolSearchText?
}

/// One keyword-tier match surface plus the alias it reports for (nil = a
/// plain recall keyword with nothing to display).
struct ToolSearchKeywordEntry: Sendable {
    let text: ToolSearchText
    let alias: ToolSearchAliasSurface?
}

/// One prebuilt searchable corpus: a title plus alias-owned surfaces and
/// alias keywords.
///
/// Records fold (case- and diacritic-insensitive) their text at build time,
/// so registry construction stays cheap and every keystroke only runs
/// comparisons against the folded forms. Alias labels join the corpus in
/// title form (they carry a grapheme map, so label hits report highlight
/// ranges); variants and plain keywords are fold-only. Exact folded
/// duplicates drop out here — the earlier surface wins, and alias labels are
/// appended before their variants, so an alias label beats its own identical
/// variant and reports ranges. Pinyin projection is deliberately NOT part of
/// construction: the first ICU Han→Latin transliteration in a process costs
/// ~45ms of engine construction (subsequent calls ~35µs), so pinning it to
/// registry init would tax app launch. It materializes lazily, once per
/// record, on the first query that falls through to the keyword tier — the
/// app prewarms the engine in the background at startup
/// (`ToolSearchEngine.prewarmTransliterationEngine`), making even that first
/// materialization cheap. A pinyin variant inherits its source's alias
/// ownership (label + segment, no label ranges).
final class ToolSearchRecord: Sendable {
    let titleText: ToolSearchText

    private struct PinyinSource {
        let source: String
        let alias: ToolSearchAliasSurface?
    }

    private struct KeywordState {
        var folded: [ToolSearchKeywordEntry]
        var pinyinSources: [PinyinSource]
        var combined: [ToolSearchKeywordEntry]?
    }

    private let keywordState: OSAllocatedUnfairLock<KeywordState>

    init(title: String, keywords: [String], aliases: [ToolAlias] = []) {
        self.titleText = ToolSearchText(title: title)

        var folded: [ToolSearchKeywordEntry] = []
        var pinyinSources: [PinyinSource] = [PinyinSource(source: title, alias: nil)]
        var seenFolded: Set<[Character]> = []

        func appendSurface(
            _ source: String,
            text: ToolSearchText,
            alias: ToolSearchAliasSurface?
        ) {
            guard !source.isEmpty, seenFolded.insert(text.folded).inserted else { return }
            folded.append(ToolSearchKeywordEntry(text: text, alias: alias))
            if source.containsIdeograph {
                pinyinSources.append(PinyinSource(source: source, alias: alias))
            }
        }

        for alias in aliases {
            let labelText = ToolSearchText(title: alias.label)
            appendSurface(
                alias.label,
                text: labelText,
                alias: ToolSearchAliasSurface(
                    label: alias.label,
                    segment: alias.segment,
                    labelText: labelText
                )
            )
            for variant in alias.matching {
                appendSurface(
                    variant,
                    text: ToolSearchText(foldedSource: variant),
                    alias: ToolSearchAliasSurface(
                        label: alias.label,
                        segment: alias.segment,
                        labelText: nil
                    )
                )
            }
        }
        for keyword in keywords {
            appendSurface(keyword, text: ToolSearchText(foldedSource: keyword), alias: nil)
        }

        self.keywordState = OSAllocatedUnfairLock(
            initialState: KeywordState(
                folded: folded,
                pinyinSources: pinyinSources,
                combined: nil
            )
        )
    }

    /// Folded alias/keyword surfaces plus engine-generated pinyin projections
    /// (full syllables + initials), so “时间戳转换” also matches “sjz” and
    /// “shijian”. Engine-uniform for every record — there is deliberately no
    /// per-entry alias configuration. Builds the pinyin layer once per record
    /// under the lock; later calls return the cached combined list.
    func keywordEntriesForMatching() -> [ToolSearchKeywordEntry] {
        keywordState.withLock { state in
            if let combined = state.combined {
                return combined
            }
            let combined = state.folded
                + Self.pinyinKeywordEntries(for: state.pinyinSources)
            state.combined = combined
            return combined
        }
    }

    /// Pinyin projection turns Han titles and aliases into latin
    /// searchables. `toLatin` is the ICU Han→Latin (Mandarin pinyin)
    /// channel: it transliterates Han characters and leaves other scripts
    /// alone. Each projection keeps its source's alias ownership minus the
    /// label text — a pinyin hit displays the label but cannot highlight
    /// inside it.
    private static func pinyinKeywordEntries(
        for sources: [PinyinSource]
    ) -> [ToolSearchKeywordEntry] {
        var variants: [(String, ToolSearchAliasSurface?)] = []
        var seen: Set<String> = []

        func append(_ variant: String, alias: ToolSearchAliasSurface?) {
            guard !variant.isEmpty, seen.insert(variant).inserted else { return }
            variants.append((variant, alias))
        }

        for entry in sources {
            guard entry.source.containsIdeograph,
                  let latin = entry.source
                .applyingTransform(.toLatin, reverse: false)?
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            else { continue }
            let syllables = latin.split { $0.isWhitespace }
            guard !syllables.isEmpty else { continue }

            let aliasWithoutLabel = entry.alias.map { alias in
                ToolSearchAliasSurface(label: alias.label, segment: alias.segment, labelText: nil)
            }
            append(
                syllables.map(String.init).joined(),
                alias: aliasWithoutLabel
            )
            append(
                syllables.compactMap { $0.first { $0.isLetter } }.map(String.init).joined(),
                alias: aliasWithoutLabel
            )
        }

        return variants.map { variant, alias in
            ToolSearchKeywordEntry(
                text: ToolSearchText(foldedSource: variant),
                alias: alias
            )
        }
    }
}

/// A folded text plus, per folded character, the originating grapheme's range
/// in the original string and its word-boundary bonus. The grapheme map lets
/// the engine report title highlight ranges as original `String.Index` ranges
/// even though matching runs on folded characters.
struct ToolSearchText: Equatable {
    let folded: [Character]
    let graphemes: [Range<String.Index>]
    let bonuses: [Int]

    /// Title form: fold the whole string once and, when the folded character
    /// count matches the original grapheme count (the overwhelmingly common
    /// case for ASCII + Han text), map positions directly. Length-changing
    /// folds (ß → ss, decomposed accents) fall back to per-grapheme folding.
    /// Bonuses are indexed in FOLDED space in both branches — matching
    /// (`contiguousScore` / `fuzzyAlign`) consumes folded positions, so a
    /// grapheme-indexed array would read out of bounds whenever a fold
    /// expands the text.
    init(title: String) {
        let graphemes = Array(title)
        let folded = Array(
            title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        )

        var foldedCharacters: [Character] = []
        var graphemeRanges: [Range<String.Index>] = []
        var foldedBonuses: [Int] = []

        if folded.count == graphemes.count {
            foldedCharacters = folded
            graphemeRanges = title.indices.map { index in
                index..<title.index(after: index)
            }
            foldedBonuses = Self.boundaryBonuses(for: foldedCharacters)
        } else {
            var previousFolded: Character?
            var index = title.startIndex
            while index < title.endIndex {
                let next = title.index(after: index)
                let foldedGrapheme = String(title[index])
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                // The expansion's first folded character carries the boundary
                // bonus against the previous grapheme's last folded character;
                // characters inside one grapheme's expansion are a continuous
                // run and earn nothing. One bonus per written folded character
                // keeps folded/bonuses/graphemes the same length.
                var isFirstInGrapheme = true
                for foldedCharacter in foldedGrapheme {
                    foldedBonuses.append(isFirstInGrapheme
                        ? Self.bonus(for: foldedCharacter, after: previousFolded)
                        : 0)
                    previousFolded = foldedCharacter
                    isFirstInGrapheme = false
                }
                foldedCharacters.append(contentsOf: foldedGrapheme)
                graphemeRanges.append(contentsOf: Array(repeating: index..<next, count: foldedGrapheme.count))
                index = next
            }
        }

        self.folded = foldedCharacters
        self.graphemes = graphemeRanges
        self.bonuses = foldedBonuses
    }

    /// Keyword form: no highlight mapping needed, so fold once and classify
    /// boundaries on the folded characters themselves.
    init(foldedSource: String) {
        let folded = Array(
            foldedSource.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        )
        self.folded = folded
        self.graphemes = []
        self.bonuses = Self.boundaryBonuses(for: folded)
    }

    private static func boundaryBonuses(for graphemes: [Character]) -> [Int] {
        var bonuses: [Int] = []
        bonuses.reserveCapacity(graphemes.count)

        var previous: Character?
        for current in graphemes {
            bonuses.append(Self.bonus(for: current, after: previous))
            previous = current
        }
        return bonuses
    }

    /// fzf-style boundary classification: matches at the start of the text or
    /// after whitespace outrank delimiter boundaries, which outrank camelCase
    /// humps. Matching inside a run of ordinary characters earns nothing.
    private static func bonus(for current: Character, after previous: Character?) -> Int {
        guard let previous else { return ToolSearchEngine.bonusBoundaryWhite }
        if previous.isWhitespace { return ToolSearchEngine.bonusBoundaryWhite }
        if !previous.isLetter && !previous.isNumber { return ToolSearchEngine.bonusBoundary }
        if previous.isLowercase && current.isUppercase { return ToolSearchEngine.bonusCamel }
        if previous.isLetter && current.isNumber { return ToolSearchEngine.bonusCamel }
        if previous.isNumber && current.isLetter { return ToolSearchEngine.bonusCamel }
        return 0
    }
}

/// The single ranked-match engine behind palette tool search, sidebar search,
/// and command matching (one matcher, three consumers — do not grow a fourth).
///
/// Ranking keeps the locked tier order title-prefix > title-contains >
/// keyword-contains, then widens recall below it: title subsequence >
/// keyword subsequence (fzf-style fuzzy matching, so “two or three characters
/// are enough”). Whitespace-separated query tokens must all match (AND
/// semantics); each token contributes its best alignment and the record's
/// tier is its worst token's tier. Within one tier, higher fzf scores rank
/// first and registry order breaks exact ties.
enum ToolSearchEngine {
    /// Lower raw values rank earlier. The first three tiers preserve the
    /// historical prefix/contains/keyword contract; the fuzzy tiers only add
    /// results below every contains match.
    enum Tier: Int, Comparable, Equatable {
        case titlePrefix = 0
        case titleContains = 1
        case keywordContains = 2
        case titleSubsequence = 3
        case keywordSubsequence = 4

        static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// One alias that the query matched: the display label, its hub segment
    /// (for deep-link activation), and — when the match landed on the label's
    /// own surface — merged highlight ranges into the original label string.
    struct AliasMatch: Equatable {
        let label: String
        let segment: String?
        let labelRanges: [Range<String.Index>]
    }

    /// One record's combined result for a whole query. `titleRanges` are
    /// merged, sorted ranges into the ORIGINAL title string, ready for
    /// highlight rendering; keyword-tier matches carry none. `aliasMatches`
    /// are the query's keyword-tier alias hits (deduped by label, ranked by
    /// contribution score, capped) for match-reason display, and
    /// `deepLinkSegment` is the best-scoring matched alias that owns a hub
    /// segment. Ranking reads only `tier`/`score` — alias reporting is
    /// display metadata and never reorders results.
    struct Match: Equatable {
        let tier: Tier
        let score: Int
        let titleRanges: [Range<String.Index>]
        let aliasMatches: [AliasMatch]
        let deepLinkSegment: String?
    }

    /// How many distinct matched aliases a row displays; more than two
    /// crowds the subtitle past its one-line budget.
    static let aliasDisplayLimit = 2

    /// fzf scoring constants (see fzf's algo.go): a boundary bonus is
    /// deliberately cancelled by ~8 characters of gap, which keeps this a
    /// fuzzy finder rather than an acronym matcher.
    static let scoreMatch = 16
    static let bonusBoundaryWhite = 10
    static let bonusBoundary = 8
    static let bonusCamel = 7
    static let bonusConsecutive = 4
    static let penaltyGapStart = -3
    static let penaltyGapExtension = -1
    static let firstCharMultiplier = 2

    /// Pays the process-wide ICU Han→Latin engine construction (~45ms)
    /// off the main thread. Call once at app startup; afterwards every
    /// record's lazy pinyin materialization costs only microseconds.
    /// ("\u{6587}" is 文, written as an escape so the string stays out of
    /// the localized-catalog surface — it is engine warmup, not UI copy.)
    static func prewarmTransliterationEngine() {
        Task.detached(priority: .userInitiated) {
            _ = "\u{6587}".applyingTransform(.toLatin, reverse: false)
        }
    }

    /// Returns nil when the query is blank or any token fails to match.
    /// The query folds exactly like record text, so "café" matches "Cafe".
    static func match(record: ToolSearchRecord, query rawQuery: String) -> Match? {
        let tokens = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split { $0.isWhitespace }
        guard !tokens.isEmpty else { return nil }

        var tier = Tier.titlePrefix
        var score = 0
        var titleRanges: [Range<String.Index>] = []
        var aliasContributions: [(alias: AliasMatch, score: Int, position: Int)] = []

        for token in tokens {
            guard let tokenMatch = matchToken(Array(token), in: record) else { return nil }
            tier = max(tier, tokenMatch.tier)
            score += tokenMatch.score
            titleRanges.append(contentsOf: tokenMatch.titleRanges)
            if let alias = tokenMatch.alias {
                aliasContributions.append((alias, tokenMatch.score, aliasContributions.count))
            }
        }

        let aliases = aggregateAliases(aliasContributions)

        return Match(
            tier: tier,
            score: score,
            titleRanges: mergeSorted(titleRanges),
            aliasMatches: Array(aliases.prefix(aliasDisplayLimit)).map(\.alias),
            deepLinkSegment: aliases
                .first(where: { $0.alias.segment != nil })?.alias.segment
        )
    }

    /// Fuses per-token alias hits into per-label results: a label matched by
    /// several tokens merges its label-surface highlight ranges (they all map
    /// into the same label string) and keeps the best contribution score;
    /// labels order by score with first-seen as the tiebreak.
    private static func aggregateAliases(
        _ contributions: [(alias: AliasMatch, score: Int, position: Int)]
    ) -> [(alias: AliasMatch, score: Int, position: Int)] {
        var bestByLabel: [String: (alias: AliasMatch, score: Int, position: Int)] = [:]
        bestByLabel.reserveCapacity(contributions.count)

        for contribution in contributions {
            guard var accumulated = bestByLabel[contribution.alias.label] else {
                bestByLabel[contribution.alias.label] = contribution
                continue
            }
            if !contribution.alias.labelRanges.isEmpty {
                accumulated.alias = AliasMatch(
                    label: accumulated.alias.label,
                    segment: accumulated.alias.segment,
                    labelRanges: mergeSorted(
                        accumulated.alias.labelRanges + contribution.alias.labelRanges
                    )
                )
            }
            if contribution.score > accumulated.score {
                accumulated.score = contribution.score
            }
            bestByLabel[contribution.alias.label] = accumulated
        }

        return bestByLabel.values.sorted { left, right in
            if left.score != right.score {
                return left.score > right.score
            }
            return left.position < right.position
        }
    }

    // MARK: - Tokens

    private struct TokenMatch {
        let tier: Tier
        let score: Int
        let titleRanges: [Range<String.Index>]
        let alias: AliasMatch?
    }

    private static func matchToken(
        _ token: [Character],
        in record: ToolSearchRecord
    ) -> TokenMatch? {
        let title = record.titleText

        if let best = bestContiguous(token, in: title) {
            let tier: Tier = best.range.lowerBound == 0 ? .titlePrefix : .titleContains
            return TokenMatch(
                tier: tier,
                score: best.score,
                titleRanges: [title.originalRange(for: best.range)],
                alias: nil
            )
        }

        if let best = record.keywordEntriesForMatching()
            .compactMap({ entry -> (entry: ToolSearchKeywordEntry, match: ContiguousMatch)? in
                bestContiguous(token, in: entry.text).map { (entry, $0) }
            })
            .max(by: { $0.match.score > $1.match.score })
        {
            return TokenMatch(
                tier: .keywordContains,
                score: best.match.score,
                titleRanges: [],
                alias: aliasMatch(for: best.entry, contiguous: best.match)
            )
        }

        if let alignment = fuzzyAlign(token, in: title) {
            return TokenMatch(
                tier: .titleSubsequence,
                score: alignment.score,
                titleRanges: alignment.positions.map { title.originalRange(for: $0..<$0 + 1) },
                alias: nil
            )
        }

        if let best = record.keywordEntriesForMatching()
            .compactMap({ entry -> (entry: ToolSearchKeywordEntry, alignment: Alignment)? in
                fuzzyAlign(token, in: entry.text).map { (entry, $0) }
            })
            .max(by: { $0.alignment.score > $1.alignment.score })
        {
            return TokenMatch(
                tier: .keywordSubsequence,
                score: best.alignment.score,
                titleRanges: [],
                alias: aliasMatch(for: best.entry, alignment: best.alignment)
            )
        }

        return nil
    }

    /// Projects a winning keyword-tier alignment onto its entry's alias.
    /// Label ranges only exist when the winning surface is the label's own
    /// text (title form, grapheme-mapped); variant and pinyin hits display
    /// the label without inner highlighting.
    private static func aliasMatch(
        for entry: ToolSearchKeywordEntry,
        contiguous: ContiguousMatch
    ) -> AliasMatch? {
        guard let alias = entry.alias else { return nil }
        let ranges: [Range<String.Index>]
        if let labelText = alias.labelText {
            ranges = [labelText.originalRange(for: contiguous.range)]
        } else {
            ranges = []
        }
        return AliasMatch(label: alias.label, segment: alias.segment, labelRanges: ranges)
    }

    private static func aliasMatch(
        for entry: ToolSearchKeywordEntry,
        alignment: Alignment
    ) -> AliasMatch? {
        guard let alias = entry.alias else { return nil }
        let ranges: [Range<String.Index>]
        if let labelText = alias.labelText {
            ranges = mergeSorted(
                alignment.positions.map { labelText.originalRange(for: $0..<$0 + 1) }
            )
        } else {
            ranges = []
        }
        return AliasMatch(label: alias.label, segment: alias.segment, labelRanges: ranges)
    }

    // MARK: - Contiguous matching

    private struct ContiguousMatch {
        let range: Range<Int>
        let score: Int
    }

    /// Scores every occurrence of the token as a contiguous substring and
    /// keeps the highest-scoring one (occurrences at boundaries beat
    /// mid-word ones).
    private static func bestContiguous(
        _ token: [Character],
        in text: ToolSearchText
    ) -> ContiguousMatch? {
        let folded = text.folded
        guard !token.isEmpty, token.count <= folded.count else { return nil }

        var best: ContiguousMatch?
        var searchStart = folded.startIndex

        while searchStart + token.count <= folded.count {
            guard let offset = firstOccurrence(of: token, in: folded, from: searchStart) else {
                break
            }
            let range = offset..<(offset + token.count)
            let score = contiguousScore(token: token, in: text, range: range)
            if best == nil || score > best!.score {
                best = ContiguousMatch(range: range, score: score)
            }
            searchStart = range.lowerBound + 1
        }

        return best
    }

    private static func firstOccurrence(
        of token: [Character],
        in folded: [Character],
        from start: Int
    ) -> Int? {
        guard !token.isEmpty else { return nil }
        var index = start
        while index + token.count <= folded.count {
            if folded[index] == token[0],
               folded[index..<(index + token.count)] == token[0...] {
                return index
            }
            index += 1
        }
        return nil
    }

    /// A contiguous occurrence scores as one unbroken fzf run: every matched
    /// character earns `scoreMatch`, the first earns its boundary bonus
    /// (doubled), and the rest earn the consecutive upgrade.
    private static func contiguousScore(
        token: [Character],
        in text: ToolSearchText,
        range: Range<Int>
    ) -> Int {
        let rawFirstBonus = text.bonuses[range.lowerBound]
        let runBonus = max(bonusConsecutive, rawFirstBonus)
        return scoreMatch + rawFirstBonus * firstCharMultiplier
            + (token.count - 1) * (scoreMatch + runBonus)
    }

    // MARK: - Fuzzy (subsequence) matching

    struct Alignment {
        let score: Int
        let positions: [Int]
    }

    /// Greedy forward alignment (fzf V1 lineage): consume pattern characters
    /// in order, accumulate gap penalties between matches, and upgrade runs
    /// of consecutive matches. Leading and trailing unmatched text is free,
    /// so match position matters only through boundary bonuses.
    static func fuzzyAlign(
        _ token: [Character],
        in text: ToolSearchText
    ) -> Alignment? {
        let folded = text.folded
        guard !token.isEmpty, token.count <= folded.count else { return nil }

        var score = 0
        var positions: [Int] = []
        positions.reserveCapacity(token.count)
        var patternIndex = 0
        var consecutive = 0
        var runFirstBonus = 0
        var inGap = false

        for index in folded.indices {
            guard patternIndex < token.count else { break }

            if folded[index] == token[patternIndex] {
                var bonus = text.bonuses[index]
                if consecutive == 0 {
                    runFirstBonus = bonus
                } else {
                    bonus = max(bonus, bonusConsecutive, runFirstBonus)
                }
                if patternIndex == 0 {
                    bonus *= firstCharMultiplier
                }
                score += scoreMatch + bonus
                positions.append(index)
                patternIndex += 1
                consecutive += 1
                inGap = false
            } else {
                consecutive = 0
                // Gaps between matches are penalized; text before the first
                // and after the last match is free.
                if !positions.isEmpty {
                    score += inGap ? penaltyGapExtension : penaltyGapStart
                    inGap = true
                }
            }
        }

        guard patternIndex == token.count else { return nil }
        return Alignment(score: score, positions: positions)
    }

    // MARK: - Helpers

    private static func mergeSorted(
        _ ranges: [Range<String.Index>]
    ) -> [Range<String.Index>] {
        let sorted = ranges.sorted { lhs, rhs in
            lhs.lowerBound < rhs.lowerBound
        }

        var merged: [Range<String.Index>] = []
        merged.reserveCapacity(sorted.count)
        for range in sorted {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }
            // Overlapping (or touching) highlight ranges fuse into one so
            // adjacent tokens never double-paint a grapheme.
            if range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<Swift.max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}

private extension ToolSearchText {
    /// Maps a folded-character range back to the original string's grapheme
    /// range. Only title texts (which always carry a full map) call this,
    /// and folded indexes come from the same text's storage, so the inputs
    /// are valid by construction.
    func originalRange(for foldedRange: Range<Int>) -> Range<String.Index> {
        graphemes[foldedRange.lowerBound].lowerBound
            ..< graphemes[foldedRange.upperBound - 1].upperBound
    }
}

private extension String {
    var containsIdeograph: Bool {
        unicodeScalars.contains { $0.properties.isIdeographic }
    }
}
