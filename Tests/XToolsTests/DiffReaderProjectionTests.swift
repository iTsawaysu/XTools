import XToolsCore
import Testing

struct DiffReaderProjectionTests {
    @Test func filtersToDifferencesAndOptionalStructureRows() {
        let rows = Self.rows([
            .unchanged,
            .structure,
            .removed,
            .added,
            .context
        ])

        let textProjection = DiffReaderProjection(rows: rows, onlyShowsDifferences: true, preservesStructure: false)
        #expect(textProjection.items.compactMap(\.row?.kind) == [.removed, .added])

        let jsonProjection = DiffReaderProjection(rows: rows, onlyShowsDifferences: true, preservesStructure: true)
        #expect(jsonProjection.items.compactMap(\.row?.kind) == [.structure, .removed, .added])
    }

    @Test func collapsesBoundaryUnchangedRunsWithOneSidedContextRows() {
        let rows = Self.rows([
            .unchanged,
            .unchanged,
            .unchanged,
            .unchanged,
            .unchanged,
            .changed,
            .unchanged,
            .unchanged,
            .unchanged,
            .unchanged,
            .unchanged
        ])

        let projection = DiffReaderProjection(
            rows: rows,
            onlyShowsDifferences: false,
            preservesStructure: false,
            collapseThreshold: 5,
            contextRows: 1
        )

        #expect(projection.items.map(\.kind) == [
            .collapsed,
            .row,
            .separator,
            .row,
            .row,
            .collapsed
        ])
        #expect(projection.items.compactMap(\.collapsedCount) == [4, 4])
    }

    @Test func collapsesMiddleUnchangedRunsWithTwoSidedContextRows() {
        let rows = Self.rows([
            .removed,
            .unchanged,
            .unchanged,
            .unchanged,
            .unchanged,
            .unchanged,
            .added
        ])

        let projection = DiffReaderProjection(
            rows: rows,
            onlyShowsDifferences: false,
            preservesStructure: false,
            collapseThreshold: 5,
            contextRows: 1
        )

        #expect(projection.items.map(\.kind) == [
            .row,
            .row,
            .collapsed,
            .row,
            .separator,
            .row
        ])
        #expect(projection.items.compactMap(\.collapsedCount) == [3])
    }

    @Test func marksSeparatorsWhenDiffBlockStartsAfterContext() {
        let rows = Self.rows([.unchanged, .changed, .added])

        let projection = DiffReaderProjection(rows: rows, onlyShowsDifferences: false, preservesStructure: false)

        #expect(projection.items.map(\.kind) == [.row, .separator, .row, .row])
        #expect(projection.items.compactMap(\.row?.kind) == [.unchanged, .changed, .added])
    }

    private static func rows(_ kinds: [DiffRowKind]) -> [DiffAlignedRow] {
        kinds.enumerated().map { index, kind in
            DiffAlignedRow(
                kind: kind,
                left: DiffAlignedCell(lineNumber: index + 1, text: "left \(index)", indent: 0),
                right: DiffAlignedCell(lineNumber: index + 1, text: "right \(index)", indent: 0)
            )
        }
    }
}
