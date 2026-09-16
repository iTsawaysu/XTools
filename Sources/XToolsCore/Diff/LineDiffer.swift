import Foundation

public struct LineDiffBudget: Equatable, Sendable {
    public static let standard = LineDiffBudget(maximumLCSCells: 12_000_000)

    public let maximumLCSCells: Int

    public init(maximumLCSCells: Int) {
        self.maximumLCSCells = max(1, maximumLCSCells)
    }

    public func validate(leftLineCount: Int, rightLineCount: Int) throws {
        guard let cellCount = Self.estimatedLCSCells(
            leftLineCount: leftLineCount,
            rightLineCount: rightLineCount
        ) else {
            throw LineDiffError.inputTooLarge(
                leftLineCount: leftLineCount,
                rightLineCount: rightLineCount,
                maximumLCSCells: maximumLCSCells
            )
        }

        guard cellCount <= maximumLCSCells else {
            throw LineDiffError.inputTooLarge(
                leftLineCount: leftLineCount,
                rightLineCount: rightLineCount,
                maximumLCSCells: maximumLCSCells
            )
        }
    }

    public static func estimatedLCSCells(leftLineCount: Int, rightLineCount: Int) -> Int? {
        let rows = leftLineCount.addingReportingOverflow(1)
        let columns = rightLineCount.addingReportingOverflow(1)
        guard !rows.overflow, !columns.overflow else { return nil }

        let cells = rows.partialValue.multipliedReportingOverflow(by: columns.partialValue)
        return cells.overflow ? nil : cells.partialValue
    }
}

public enum LineDiffError: Error, Equatable, LocalizedError, Sendable {
    case inputTooLarge(leftLineCount: Int, rightLineCount: Int, maximumLCSCells: Int)

    public static let inputTooLargeMessage = """
    对比内容过大，无法计算。
    """

    public var errorDescription: String? {
        switch self {
        case .inputTooLarge:
            return Self.inputTooLargeMessage
        }
    }
}

struct DiffCancellationChecker: Sendable {
    private let shouldCancel: (@Sendable () -> Bool)?

    init(shouldCancel: (@Sendable () -> Bool)? = nil) {
        self.shouldCancel = shouldCancel
    }

    static let disabled = Self()

    func check() throws {
        if shouldCancel?() == true {
            throw CancellationError()
        }
    }
}

public enum LineDiffer {
    static func withoutCancellation<T>(
        _ operation: (DiffCancellationChecker) throws -> T
    ) -> T {
        do {
            return try operation(.disabled)
        } catch {
            preconditionFailure("Non-cancellable diff path unexpectedly cancelled")
        }
    }

    public static func safeAlignedDiff(
        left: String,
        right: String,
        budget: LineDiffBudget = .standard,
        shouldCancel: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) throws -> [DiffAlignedRow] {
        let cancellation = DiffCancellationChecker(shouldCancel: shouldCancel)
        try cancellation.check()

        guard !left.isEmpty || !right.isEmpty else {
            return []
        }

        let leftLines = displayLines(from: left)
        let rightLines = displayLines(from: right)
        try budget.validate(leftLineCount: leftLines.count, rightLineCount: rightLines.count)
        try cancellation.check()

        return try DiffAlignedRow.rows(
            from: displayDiff(
                leftLines: leftLines,
                rightLines: rightLines,
                cancellation: cancellation
            ),
            cancellation: cancellation
        )
    }

    /// Test-only unbounded display rows. Prefer `safeAlignedDiff` in production.
    static func displayDiff(left: String, right: String) -> [DiffDisplayLine] {
        withoutCancellation {
            try displayDiff(
                leftLines: displayLines(from: left),
                rightLines: displayLines(from: right),
                cancellation: $0
            )
        }
    }

    private static func displayDiff(
        leftLines: [String],
        rightLines: [String],
        cancellation: DiffCancellationChecker
    ) throws -> [DiffDisplayLine] {
        guard !leftLines.isEmpty || !rightLines.isEmpty else {
            return []
        }

        let lcs = try lcsLengths(
            leftLines: leftLines,
            rightLines: rightLines,
            cancellation: cancellation
        )
        var oldLineNumber = 1
        var newLineNumber = 1
        var leftIndex = 0
        var rightIndex = 0
        var result: [DiffDisplayLine] = []

        while leftIndex < leftLines.count || rightIndex < rightLines.count {
            try cancellation.check()
            if leftIndex < leftLines.count,
               rightIndex < rightLines.count,
               leftLines[leftIndex] == rightLines[rightIndex] {
                result.append(DiffDisplayLine(
                    kind: .unchanged,
                    oldLineNumber: oldLineNumber,
                    newLineNumber: newLineNumber,
                    text: leftLines[leftIndex],
                    indent: 0
                ))
                leftIndex += 1
                rightIndex += 1
                oldLineNumber += 1
                newLineNumber += 1
            } else if leftIndex < leftLines.count,
                      (rightIndex == rightLines.count || lcs[leftIndex + 1][rightIndex] >= lcs[leftIndex][rightIndex + 1]) {
                result.append(DiffDisplayLine(
                    kind: .removed,
                    oldLineNumber: oldLineNumber,
                    newLineNumber: nil,
                    text: leftLines[leftIndex],
                    indent: 0
                ))
                leftIndex += 1
                oldLineNumber += 1
            } else if rightIndex < rightLines.count {
                result.append(DiffDisplayLine(
                    kind: .added,
                    oldLineNumber: nil,
                    newLineNumber: newLineNumber,
                    text: rightLines[rightIndex],
                    indent: 0
                ))
                rightIndex += 1
                newLineNumber += 1
            }
        }

        return result
    }

    private static func lcsLengths(
        leftLines: [String],
        rightLines: [String],
        cancellation: DiffCancellationChecker
    ) throws -> [[Int]] {
        try cancellation.check()
        var table = Array(
            repeating: Array(repeating: 0, count: rightLines.count + 1),
            count: leftLines.count + 1
        )

        guard !leftLines.isEmpty && !rightLines.isEmpty else {
            return table
        }

        for leftIndex in stride(from: leftLines.count - 1, through: 0, by: -1) {
            try cancellation.check()
            for rightIndex in stride(from: rightLines.count - 1, through: 0, by: -1) {
                if rightIndex.isMultiple(of: 256) {
                    try cancellation.check()
                }
                if leftLines[leftIndex] == rightLines[rightIndex] {
                    table[leftIndex][rightIndex] = table[leftIndex + 1][rightIndex + 1] + 1
                } else {
                    table[leftIndex][rightIndex] = max(
                        table[leftIndex + 1][rightIndex],
                        table[leftIndex][rightIndex + 1]
                    )
                }
            }
        }

        return table
    }

    private static func displayLines(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
