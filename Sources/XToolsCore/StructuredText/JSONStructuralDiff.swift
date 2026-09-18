import Foundation

public struct JSONDiffOptions: Equatable, Sendable {
    public let ignoreArrayOrder: Bool
    public let foldUnchanged: Bool

    public init(ignoreArrayOrder: Bool = false, foldUnchanged: Bool = false) {
        self.ignoreArrayOrder = ignoreArrayOrder
        self.foldUnchanged = foldUnchanged
    }
}

public enum JSONStructuralDiff {
    public enum Decision: Equatable, Sendable {
        case empty
        case invalid(String)
        case tooLarge(String)
        case comparable([DiffAlignedRow])
    }

    public static func cancellableAlignedDiff(
        left: String,
        right: String,
        labels: JSONDiffValidation.SideLabels,
        options: JSONDiffOptions = JSONDiffOptions(),
        budget: LineDiffBudget = .standard,
        shouldCancel: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) throws -> Decision {
        let cancellation = DiffCancellationChecker(shouldCancel: shouldCancel)
        try cancellation.check()

        switch JSONDiffValidation.evaluate(left: left, right: right, labels: labels) {
        case .empty:
            return .empty
        case .invalid(let message):
            return .invalid(message)
        case .comparable:
            try cancellation.check()
            if areStructurallyEquivalent(left: left, right: right, options: options) {
                return .comparable([])
            }

            try cancellation.check()
            let leftDisplayText = displayTextForDiff(left, options: options) ?? left
            try cancellation.check()
            let rightDisplayText = displayTextForDiff(right, options: options) ?? right
            try cancellation.check()

            do {
                return .comparable(try LineDiffer.safeAlignedDiff(
                    left: leftDisplayText,
                    right: rightDisplayText,
                    budget: budget,
                    shouldCancel: shouldCancel
                ))
            } catch let error as LineDiffError {
                return .tooLarge(error.errorDescription ?? LineDiffError.inputTooLargeMessage)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return .tooLarge(LineDiffError.inputTooLargeMessage)
            }
        }
    }

    private static func areStructurallyEquivalent(left: String, right: String, options: JSONDiffOptions) -> Bool {
        let leftTrimmed = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightTrimmed = right.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !leftTrimmed.isEmpty && !rightTrimmed.isEmpty else {
            return false
        }

        do {
            return try canonicalJSON(leftTrimmed, options: options) == canonicalJSON(rightTrimmed, options: options)
        } catch {
            return false
        }
    }

    private static func canonicalJSON(_ text: String, options: JSONDiffOptions) throws -> String {
        try JSONFormatting.format(text, sortKeys: true, sortArrays: options.ignoreArrayOrder, indentWidth: 2)
    }

    public static func displayTextForDiff(_ text: String, options: JSONDiffOptions = JSONDiffOptions()) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return try? canonicalJSON(trimmed, options: options)
    }

    public static func foldUnchangedRows(
        _ rows: [DiffAlignedRow],
        contextLines: Int = 2,
        minFoldThreshold: Int = 5
    ) -> (rows: [DiffAlignedRow], leftDisplayText: String, rightDisplayText: String) {
        guard rows.contains(where: { $0.kind.isDifference }) else {
            let leftText = rows.compactMap { $0.left?.text }.joined(separator: "\n")
            let rightText = rows.compactMap { $0.right?.text }.joined(separator: "\n")
            return (rows, leftText, rightText)
        }

        var resultRows: [DiffAlignedRow] = []
        var unchangedRun: [DiffAlignedRow] = []

        func flushUnchangedRun(isEnd: Bool) {
            guard !unchangedRun.isEmpty else { return }
            let isStart = resultRows.isEmpty
            let headCount = isStart ? 1 : contextLines
            let tailCount = isEnd ? 1 : contextLines
            let foldedCount = unchangedRun.count - (headCount + tailCount)
            if unchangedRun.count >= minFoldThreshold, foldedCount >= 2 {
                let head = Array(unchangedRun.prefix(headCount))
                let tail = Array(unchangedRun.suffix(tailCount))

                resultRows.append(contentsOf: head)
                let placeholderText = "  ⋯ 折叠 \(foldedCount) 行未变更内容 ⋯"
                let foldedRow = DiffAlignedRow(
                    kind: .structure,
                    left: DiffAlignedCell(lineNumber: nil, text: placeholderText, indent: 0, originalLineNumber: nil),
                    right: DiffAlignedCell(lineNumber: nil, text: placeholderText, indent: 0, originalLineNumber: nil)
                )
                resultRows.append(foldedRow)
                resultRows.append(contentsOf: tail)
            } else {
                resultRows.append(contentsOf: unchangedRun)
            }
            unchangedRun.removeAll()
        }

        for row in rows {
            if !row.kind.isDifference {
                unchangedRun.append(row)
            } else {
                flushUnchangedRun(isEnd: false)
                resultRows.append(row)
            }
        }
        flushUnchangedRun(isEnd: true)

        var leftLine = 1
        var rightLine = 1
        var reindexedRows: [DiffAlignedRow] = []
        var leftLines: [String] = []
        var rightLines: [String] = []

        for row in resultRows {
            var newLeftCell: DiffAlignedCell? = nil
            var newRightCell: DiffAlignedCell? = nil
            let isPlaceholder = row.kind == .structure && (row.left?.lineNumber == nil || row.left?.originalLineNumber == nil)

            if let left = row.left {
                newLeftCell = DiffAlignedCell(
                    lineNumber: leftLine,
                    text: left.text,
                    indent: left.indent,
                    segments: left.segments,
                    originalLineNumber: isPlaceholder ? nil : left.originalLineNumber
                )
                leftLines.append(left.text)
                leftLine += 1
            }

            if let right = row.right {
                newRightCell = DiffAlignedCell(
                    lineNumber: rightLine,
                    text: right.text,
                    indent: right.indent,
                    segments: right.segments,
                    originalLineNumber: isPlaceholder ? nil : right.originalLineNumber
                )
                rightLines.append(right.text)
                rightLine += 1
            }

            reindexedRows.append(DiffAlignedRow(
                id: row.id,
                kind: row.kind,
                left: newLeftCell,
                right: newRightCell
            ))
        }

        return (
            rows: reindexedRows,
            leftDisplayText: leftLines.joined(separator: "\n"),
            rightDisplayText: rightLines.joined(separator: "\n")
        )
    }
}
