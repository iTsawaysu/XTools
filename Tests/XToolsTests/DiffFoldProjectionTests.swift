import Testing
@testable import XToolsCore

struct DiffFoldProjectionTests {
    private func makeRows(_ kinds: [DiffRowKind]) -> [DiffAlignedRow] {
        kinds.enumerated().map { index, kind in
            let number = index + 1
            let cell = DiffAlignedCell(
                lineNumber: number,
                text: "line \(number)",
                indent: 0,
                originalLineNumber: number
            )
            return DiffAlignedRow(kind: kind, left: cell, right: cell)
        }
    }

    @Test func regionsPlanDocumentEdgesWithoutContext() {
        // 8 unchanged · 1 changed · 8 unchanged
        var kinds = Array(repeating: DiffRowKind.unchanged, count: 8)
        kinds.append(.changed)
        kinds.append(contentsOf: Array(repeating: DiffRowKind.unchanged, count: 8))
        let rows = makeRows(kinds)

        let regions = DiffFoldProjection.regions(in: rows)
        #expect(regions.count == 2)

        // Leading run: document-start edge keeps no head context.
        #expect(regions[0].id == 1)
        #expect(regions[0].hiddenRowCount == 8 - DiffFoldProjection.contextLines)

        // Trailing run: document-end edge keeps no tail context.
        #expect(regions[1].id == 9 + 1 + DiffFoldProjection.contextLines)
        #expect(regions[1].hiddenRowCount == 8 - DiffFoldProjection.contextLines)
    }

    @Test func shortRunsAreNotFolded() {
        // 3 unchanged · changed · 3 unchanged: hidden counts fall under the
        // minimum once context is reserved.
        let kinds: [DiffRowKind] = [.unchanged, .unchanged, .unchanged, .changed, .unchanged, .unchanged, .unchanged]
        let regions = DiffFoldProjection.regions(in: makeRows(kinds))
        #expect(regions.isEmpty)
    }

    @Test func identicalRowsNeverFold() {
        let rows = makeRows(Array(repeating: .unchanged, count: 50))
        #expect(DiffFoldProjection.regions(in: rows).isEmpty)
        let applied = DiffFoldProjection.apply(rows: rows, expandedRegionIDs: [])
        #expect(applied.rows.count == rows.count)
        #expect(applied.leftText.components(separatedBy: "\n").count == 50)
    }

    @Test func applyCollapsesUnchangedRegionsWithPlaceholders() {
        var kinds = Array(repeating: DiffRowKind.unchanged, count: 8)
        kinds.append(.changed)
        kinds.append(contentsOf: Array(repeating: DiffRowKind.unchanged, count: 8))
        let rows = makeRows(kinds)

        let applied = DiffFoldProjection.apply(rows: rows, expandedRegionIDs: [])
        let placeholders = applied.rows.filter { $0.foldRegion != nil }
        #expect(placeholders.count == 2)
        #expect(placeholders.allSatisfy { $0.kind == .structure })
        #expect(placeholders.allSatisfy { $0.left?.text.contains("已折叠") == true })
        #expect(placeholders.allSatisfy { $0.left?.originalLineNumber == nil })

        // 3 tail context + 1 changed + 3 head context + 2 placeholders.
        #expect(applied.rows.count == 9)
        #expect(applied.leftText.components(separatedBy: "\n").count == 9)

        // Visual line numbers are re-indexed sequentially.
        let visualNumbers = applied.rows.compactMap { $0.left?.lineNumber }
        #expect(visualNumbers == Array(1...9))
    }

    @Test func expandedRegionRestoresItsRows() {
        var kinds = Array(repeating: DiffRowKind.unchanged, count: 8)
        kinds.append(.changed)
        kinds.append(contentsOf: Array(repeating: DiffRowKind.unchanged, count: 8))
        let rows = makeRows(kinds)

        let applied = DiffFoldProjection.apply(rows: rows, expandedRegionIDs: [1])
        let placeholders = applied.rows.filter { $0.foldRegion != nil }
        #expect(placeholders.count == 1, "only the trailing region stays collapsed")
        #expect(placeholders.first?.foldRegion?.id == 13)

        // Leading run restored: 8 + 1 changed + 3 head + 1 placeholder.
        #expect(applied.rows.count == 13)
        #expect(applied.leftText.components(separatedBy: "\n").count == 13)
    }

    @Test func regionIdentitySurvivesRowRecomputation() {
        // The identity is the original line number of the first hidden row,
        // so a re-run diff of unchanged content keeps expansion state valid.
        var kinds = Array(repeating: DiffRowKind.unchanged, count: 10)
        kinds.append(.changed)
        let rows = makeRows(kinds)
        let regions = DiffFoldProjection.regions(in: rows)
        #expect(regions.count == 1)

        let recomputed = makeRows(kinds)
        let reapplied = DiffFoldProjection.apply(rows: recomputed, expandedRegionIDs: [regions[0].id])
        #expect(reapplied.rows.contains { $0.foldRegion == nil && $0.left?.text == "line 1" },
                "expanded region keeps its first hidden row visible")
    }
}
