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

public struct TextDiffOptions: Equatable, Sendable {
    public var ignoreWhitespace: Bool
    public var ignoreCase: Bool

    public init(ignoreWhitespace: Bool = false, ignoreCase: Bool = false) {
        self.ignoreWhitespace = ignoreWhitespace
        self.ignoreCase = ignoreCase
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
        options: TextDiffOptions = TextDiffOptions(),
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
                options: options,
                budget: budget,
                cancellation: cancellation
            ),
            cancellation: cancellation
        )
    }

    /// Test-only unbounded display rows. Prefer `safeAlignedDiff` in production.
    static func displayDiff(
        left: String,
        right: String,
        options: TextDiffOptions = TextDiffOptions()
    ) -> [DiffDisplayLine] {
        withoutCancellation {
            try displayDiff(
                leftLines: displayLines(from: left),
                rightLines: displayLines(from: right),
                options: options,
                budget: LineDiffBudget(maximumLCSCells: .max),
                cancellation: $0
            )
        }
    }

    private static func displayDiff(
        leftLines: [String],
        rightLines: [String],
        options: TextDiffOptions,
        budget: LineDiffBudget,
        cancellation: DiffCancellationChecker
    ) throws -> [DiffDisplayLine] {
        guard !leftLines.isEmpty || !rightLines.isEmpty else {
            return []
        }

        var prefixCount = 0
        while prefixCount < leftLines.count && prefixCount < rightLines.count
            && areLinesEqual(leftLines[prefixCount], rightLines[prefixCount], options: options) {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < (leftLines.count - prefixCount) && suffixCount < (rightLines.count - prefixCount)
            && areLinesEqual(
                leftLines[leftLines.count - 1 - suffixCount],
                rightLines[rightLines.count - 1 - suffixCount],
                options: options
            ) {
            suffixCount += 1
        }

        var result: [DiffDisplayLine] = []
        result.reserveCapacity(max(leftLines.count, rightLines.count))

        for i in 0..<prefixCount {
            result.append(DiffDisplayLine(
                kind: .unchanged,
                oldLineNumber: i + 1,
                newLineNumber: i + 1,
                text: leftLines[i],
                indent: 0
            ))
        }

        let middleLeftCount = leftLines.count - prefixCount - suffixCount
        let middleRightCount = rightLines.count - prefixCount - suffixCount

        if middleLeftCount > 0 && middleRightCount == 0 {
            for i in 0..<middleLeftCount {
                try cancellation.check()
                result.append(DiffDisplayLine(
                    kind: .removed,
                    oldLineNumber: prefixCount + i + 1,
                    newLineNumber: nil,
                    text: leftLines[prefixCount + i],
                    indent: 0
                ))
            }
        } else if middleLeftCount == 0 && middleRightCount > 0 {
            for j in 0..<middleRightCount {
                try cancellation.check()
                result.append(DiffDisplayLine(
                    kind: .added,
                    oldLineNumber: nil,
                    newLineNumber: prefixCount + j + 1,
                    text: rightLines[prefixCount + j],
                    indent: 0
                ))
            }
        } else if middleLeftCount > 0 && middleRightCount > 0 {
            try budget.validate(leftLineCount: middleLeftCount, rightLineCount: middleRightCount)
            try cancellation.check()

            let trimmedLeft = Array(leftLines[prefixCount..<(leftLines.count - suffixCount)])
            let trimmedRight = Array(rightLines[prefixCount..<(rightLines.count - suffixCount)])

            let lcs = try lcsLengths(
                leftLines: trimmedLeft,
                rightLines: trimmedRight,
                options: options,
                cancellation: cancellation
            )

            var oldLineNumber = prefixCount + 1
            var newLineNumber = prefixCount + 1
            var leftIndex = 0
            var rightIndex = 0

            while leftIndex < trimmedLeft.count || rightIndex < trimmedRight.count {
                try cancellation.check()
                if leftIndex < trimmedLeft.count,
                   rightIndex < trimmedRight.count,
                   areLinesEqual(trimmedLeft[leftIndex], trimmedRight[rightIndex], options: options) {
                    result.append(DiffDisplayLine(
                        kind: .unchanged,
                        oldLineNumber: oldLineNumber,
                        newLineNumber: newLineNumber,
                        text: trimmedLeft[leftIndex],
                        indent: 0
                    ))
                    leftIndex += 1
                    rightIndex += 1
                    oldLineNumber += 1
                    newLineNumber += 1
                } else if leftIndex < trimmedLeft.count,
                          (rightIndex == trimmedRight.count || lcs[leftIndex + 1, rightIndex] >= lcs[leftIndex, rightIndex + 1]) {
                    result.append(DiffDisplayLine(
                        kind: .removed,
                        oldLineNumber: oldLineNumber,
                        newLineNumber: nil,
                        text: trimmedLeft[leftIndex],
                        indent: 0
                    ))
                    leftIndex += 1
                    oldLineNumber += 1
                } else if rightIndex < trimmedRight.count {
                    result.append(DiffDisplayLine(
                        kind: .added,
                        oldLineNumber: nil,
                        newLineNumber: newLineNumber,
                        text: trimmedRight[rightIndex],
                        indent: 0
                    ))
                    rightIndex += 1
                    newLineNumber += 1
                }
            }
        }

        for k in 0..<suffixCount {
            let leftIdx = leftLines.count - suffixCount + k
            let rightIdx = rightLines.count - suffixCount + k
            result.append(DiffDisplayLine(
                kind: .unchanged,
                oldLineNumber: leftIdx + 1,
                newLineNumber: rightIdx + 1,
                text: leftLines[leftIdx],
                indent: 0
            ))
        }

        return result
    }

    private static func lcsLengths(
        leftLines: [String],
        rightLines: [String],
        options: TextDiffOptions,
        cancellation: DiffCancellationChecker
    ) throws -> FlatLCSMatrix {
        try cancellation.check()
        let rows = leftLines.count
        let cols = rightLines.count
        var table = FlatLCSMatrix(rows: rows, cols: cols)

        guard rows > 0 && cols > 0 else {
            return table
        }

        for leftIndex in stride(from: rows - 1, through: 0, by: -1) {
            try cancellation.check()
            let leftLine = leftLines[leftIndex]
            for rightIndex in stride(from: cols - 1, through: 0, by: -1) {
                if rightIndex.isMultiple(of: 256) {
                    try cancellation.check()
                }
                if areLinesEqual(leftLine, rightLines[rightIndex], options: options) {
                    table[leftIndex, rightIndex] = table[leftIndex + 1, rightIndex + 1] + 1
                } else {
                    table[leftIndex, rightIndex] = max(
                        table[leftIndex + 1, rightIndex],
                        table[leftIndex, rightIndex + 1]
                    )
                }
            }
        }

        return table
    }

    private static func areLinesEqual(_ a: String, _ b: String, options: TextDiffOptions) -> Bool {
        if !options.ignoreWhitespace && !options.ignoreCase {
            return a == b
        }
        var s1 = a
        var s2 = b
        if options.ignoreWhitespace {
            s1 = normalizeWhitespace(s1)
            s2 = normalizeWhitespace(s2)
        }
        if options.ignoreCase {
            return s1.caseInsensitiveCompare(s2) == .orderedSame
        } else {
            return s1 == s2
        }
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
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

private struct FlatLCSMatrix {
    let rows: Int
    let cols: Int
    private var storage: [Int]

    init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
        self.storage = Array(repeating: 0, count: (rows + 1) * (cols + 1))
    }

    @inline(__always)
    subscript(row: Int, col: Int) -> Int {
        get {
            storage[row * (cols + 1) + col]
        }
        set {
            storage[row * (cols + 1) + col] = newValue
        }
    }
}
