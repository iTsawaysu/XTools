import Foundation

/// A collapsible run of unchanged rows. The identity is the left original
/// line number of the first hidden row, which stays stable across typing in
/// the other pane and therefore survives diff recomputation.
public struct DiffFoldRegion: Equatable, Sendable {
    public let id: Int
    public let hiddenRowCount: Int

    public init(id: Int, hiddenRowCount: Int) {
        self.id = id
        self.hiddenRowCount = hiddenRowCount
    }
}

/// Plans and applies "collapse unchanged regions" projections over aligned
/// diff rows. Folding is a pure view-mode projection: the binding keeps the
/// full canonical rows and display text, and this type re-projects them with
/// a set of expanded region IDs. Re-projecting after an expand click is a
/// local operation — the diff itself never re-runs.
public enum DiffFoldProjection {
    /// Context lines kept visible around a change inside a folded region.
    public static let contextLines = 3
    /// Minimum hidden lines for a run to be worth folding.
    public static let minimumHiddenLines = 2

    /// All foldable regions in `rows`, in document order.
    public static func regions(in rows: [DiffAlignedRow]) -> [DiffFoldRegion] {
        guard rows.contains(where: { $0.kind.isDifference }) else {
            return []
        }

        var planned: [DiffFoldRegion] = []
        var runStart: Int?
        let total = rows.count

        func flush(runEnd: Int) {
            guard let start = runStart else { return }
            runStart = nil

            let atDocumentStart = start == 0
            let atDocumentEnd = runEnd == total
            let head = atDocumentStart ? 0 : contextLines
            let tail = atDocumentEnd ? 0 : contextLines
            let hiddenCount = (runEnd - start) - head - tail
            guard hiddenCount >= minimumHiddenLines else { return }

            let firstHidden = rows[start + head]
            let identity = firstHidden.left?.originalLineNumber
                ?? firstHidden.right?.originalLineNumber
                ?? (start + head + 1)
            planned.append(DiffFoldRegion(id: identity, hiddenRowCount: hiddenCount))
        }

        for (index, row) in rows.enumerated() {
            if row.kind.isDifference {
                flush(runEnd: index)
            } else {
                if runStart == nil {
                    runStart = index
                }
            }
        }
        flush(runEnd: total)
        return planned
    }

    /// Projects `rows` with all regions collapsed except those in
    /// `expandedRegionIDs`. Returns the visible rows plus the per-side
    /// display texts (visual line numbers re-indexed, placeholder rows carry
    /// their region metadata for click-to-expand).
    public static func apply(
        rows: [DiffAlignedRow],
        expandedRegionIDs: Set<Int>
    ) -> (rows: [DiffAlignedRow], leftText: String, rightText: String) {
        guard rows.contains(where: { $0.kind.isDifference }) else {
            return (rows, sideText(rows, \.left), sideText(rows, \.right))
        }

        var resultRows: [DiffAlignedRow] = []
        var run: [DiffAlignedRow] = []
        let total = rows.count

        func flush(runEnd: Int) {
            guard !run.isEmpty else { return }
            defer { run.removeAll() }

            let atDocumentStart = resultRows.isEmpty
            let atDocumentEnd = runEnd == total
            let head = atDocumentStart ? 0 : contextLines
            let tail = atDocumentEnd ? 0 : contextLines
            let hiddenCount = run.count - head - tail
            guard hiddenCount >= minimumHiddenLines else {
                resultRows.append(contentsOf: run)
                return
            }

            let firstHidden = run[head]
            let identity = firstHidden.left?.originalLineNumber
                ?? firstHidden.right?.originalLineNumber
                ?? (resultRows.count + 1)
            guard !expandedRegionIDs.contains(identity) else {
                resultRows.append(contentsOf: run)
                return
            }

            resultRows.append(contentsOf: run.prefix(head))

            let placeholderText = "  ⋯ 已折叠 \(hiddenCount) 行未变更，点击展开 ⋯"
            let placeholderCell = DiffAlignedCell(
                lineNumber: nil,
                text: placeholderText,
                indent: 0,
                originalLineNumber: nil
            )
            resultRows.append(DiffAlignedRow(
                kind: .structure,
                left: placeholderCell,
                right: placeholderCell,
                foldRegion: DiffFoldRegion(id: identity, hiddenRowCount: hiddenCount)
            ))

            if tail > 0 {
                resultRows.append(contentsOf: run.suffix(tail))
            }
        }

        for (index, row) in rows.enumerated() {
            if row.kind.isDifference {
                flush(runEnd: index)
                resultRows.append(row)
            } else {
                run.append(row)
            }
        }
        flush(runEnd: total)

        return reindexed(resultRows)
    }

    /// Re-assigns visual line numbers and rebuilds the per-side texts from
    /// the projected rows. Placeholder rows keep `originalLineNumber` nil so
    /// the gutter suppresses their number.
    private static func reindexed(_ rows: [DiffAlignedRow]) -> (rows: [DiffAlignedRow], leftText: String, rightText: String) {
        var leftLine = 1
        var rightLine = 1
        var reindexedRows: [DiffAlignedRow] = []
        var leftLines: [String] = []
        var rightLines: [String] = []

        for row in rows {
            let isPlaceholder = row.foldRegion != nil

            var newLeftCell: DiffAlignedCell?
            if let left = row.left {
                newLeftCell = isPlaceholder
                    ? DiffAlignedCell(foldPlaceholderLineNumber: leftLine, text: left.text)
                    : DiffAlignedCell(
                        lineNumber: leftLine,
                        text: left.text,
                        indent: left.indent,
                        segments: left.segments,
                        originalLineNumber: left.originalLineNumber
                    )
                leftLines.append(left.text)
                leftLine += 1
            }

            var newRightCell: DiffAlignedCell?
            if let right = row.right {
                newRightCell = isPlaceholder
                    ? DiffAlignedCell(foldPlaceholderLineNumber: rightLine, text: right.text)
                    : DiffAlignedCell(
                        lineNumber: rightLine,
                        text: right.text,
                        indent: right.indent,
                        segments: right.segments,
                        originalLineNumber: right.originalLineNumber
                    )
                rightLines.append(right.text)
                rightLine += 1
            }

            reindexedRows.append(DiffAlignedRow(
                id: row.id,
                kind: row.kind,
                left: newLeftCell,
                right: newRightCell,
                foldRegion: row.foldRegion
            ))
        }

        return (reindexedRows, leftLines.joined(separator: "\n"), rightLines.joined(separator: "\n"))
    }

    private static func sideText(
        _ rows: [DiffAlignedRow],
        _ cell: (DiffAlignedRow) -> DiffAlignedCell?
    ) -> String {
        rows.compactMap { cell($0)?.text }.joined(separator: "\n")
    }
}
