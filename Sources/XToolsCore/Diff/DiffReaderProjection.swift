import Foundation

public protocol DiffReaderProjectedRow: Sendable {
    var kind: DiffRowKind { get }
}

extension DiffDisplayLine: DiffReaderProjectedRow {}
extension DiffAlignedRow: DiffReaderProjectedRow {}

public struct DiffReaderProjection<Row: DiffReaderProjectedRow>: Sendable {
    public let items: [DiffReaderProjectionItem<Row>]

    public init(
        rows: [Row],
        onlyShowsDifferences: Bool,
        preservesStructure: Bool,
        enableCollapse: Bool = true,
        collapseThreshold: Int = 7,
        contextRows: Int = 3,
        expandedRangeIDs: Set<Int> = []
    ) {
        let visibleRows = Self.visibleRows(
            rows,
            onlyShowsDifferences: onlyShowsDifferences,
            preservesStructure: preservesStructure
        )
        let collapsedRanges = enableCollapse
            ? Self.collapsedRanges(
                rows: visibleRows,
                collapseThreshold: collapseThreshold,
                contextRows: contextRows
            )
            : []

        self.items = Self.items(
            rows: visibleRows,
            collapsedRanges: collapsedRanges,
            expandedRangeIDs: expandedRangeIDs
        )
    }

    private static func visibleRows(
        _ rows: [Row],
        onlyShowsDifferences: Bool,
        preservesStructure: Bool
    ) -> [Row] {
        guard onlyShowsDifferences else {
            return rows
        }

        return rows.filter { row in
            row.kind.isDifference || (preservesStructure && row.kind == .structure)
        }
    }

    private static func collapsedRanges(
        rows: [Row],
        collapseThreshold: Int,
        contextRows: Int
    ) -> [DiffCollapsedRange] {
        var ranges: [DiffCollapsedRange] = []
        var unchangedStart: Int?
        var unchangedCount = 0

        func appendRangeIfNeeded(start: Int, count: Int, isTrailing: Bool) {
            guard count >= collapseThreshold else {
                return
            }

            let actualStart: Int
            let actualCount: Int

            if start == 0 {
                actualStart = 0
                actualCount = max(0, count - contextRows)
            } else if isTrailing {
                actualStart = start + contextRows
                actualCount = max(0, count - contextRows)
            } else {
                actualStart = start + contextRows
                actualCount = max(0, count - 2 * contextRows)
            }

            if actualCount > 0 {
                ranges.append(DiffCollapsedRange(
                    id: actualStart,
                    startIndex: actualStart,
                    count: actualCount
                ))
            }
        }

        for (index, row) in rows.enumerated() {
            if row.kind == .unchanged || row.kind == .context {
                if unchangedStart == nil {
                    unchangedStart = index
                    unchangedCount = 1
                } else {
                    unchangedCount += 1
                }
            } else {
                if let start = unchangedStart {
                    appendRangeIfNeeded(start: start, count: unchangedCount, isTrailing: false)
                }
                unchangedStart = nil
                unchangedCount = 0
            }
        }

        if let start = unchangedStart {
            appendRangeIfNeeded(start: start, count: unchangedCount, isTrailing: true)
        }

        return ranges
    }

    private static func items(
        rows: [Row],
        collapsedRanges: [DiffCollapsedRange],
        expandedRangeIDs: Set<Int>
    ) -> [DiffReaderProjectionItem<Row>] {
        var items: [DiffReaderProjectionItem<Row>] = []
        var index = 0

        while index < rows.count {
            if let range = collapsedRanges.first(where: { $0.startIndex == index && !expandedRangeIDs.contains($0.id) }) {
                items.append(.collapsed(id: range.id, count: range.count))
                index += range.count
                continue
            }

            if index > 0 && !rows[index - 1].kind.isDifference && rows[index].kind.isDifference {
                items.append(.separator)
            }

            items.append(.row(rows[index]))
            index += 1
        }

        return items
    }
}

public struct DiffReaderProjectionItem<Row: DiffReaderProjectedRow>: Sendable {
    public enum Kind: Equatable, Sendable {
        case row
        case collapsed
        case separator
    }

    public let kind: Kind
    public let row: Row?
    public let collapsedID: Int?
    public let collapsedCount: Int?

    public static func row(_ row: Row) -> Self {
        Self(kind: .row, row: row, collapsedID: nil, collapsedCount: nil)
    }

    public static func collapsed(id: Int, count: Int) -> Self {
        Self(kind: .collapsed, row: nil, collapsedID: id, collapsedCount: count)
    }

    public static var separator: Self {
        Self(kind: .separator, row: nil, collapsedID: nil, collapsedCount: nil)
    }
}

private struct DiffCollapsedRange {
    let id: Int
    let startIndex: Int
    let count: Int
}
