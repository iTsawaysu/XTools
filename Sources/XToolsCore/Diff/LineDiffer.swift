import Foundation

public struct LineDiffBudget: Equatable, Sendable {
    public static let standard = LineDiffBudget(
        maximumLCSCells: 12_000_000,
        maximumInputBytesPerSide: 16_000_000,
        maximumInputLinesPerSide: 100_000
    )

    public let maximumLCSCells: Int
    public let maximumInputBytesPerSide: Int
    public let maximumInputLinesPerSide: Int

    public init(
        maximumLCSCells: Int,
        maximumInputBytesPerSide: Int = 16_000_000,
        maximumInputLinesPerSide: Int = 100_000
    ) {
        self.maximumLCSCells = max(1, maximumLCSCells)
        self.maximumInputBytesPerSide = max(1, maximumInputBytesPerSide)
        self.maximumInputLinesPerSide = max(1, maximumInputLinesPerSide)
    }

    func validateInputBytes(leftByteCount: Int, rightByteCount: Int) throws {
        guard leftByteCount <= maximumInputBytesPerSide,
              rightByteCount <= maximumInputBytesPerSide else {
            throw LineDiffError.inputTooLarge(
                leftLineCount: 0,
                rightLineCount: 0,
                maximumLCSCells: maximumLCSCells
            )
        }
    }

    func validateInputLines(leftLineCount: Int, rightLineCount: Int) throws {
        guard leftLineCount <= maximumInputLinesPerSide,
              rightLineCount <= maximumInputLinesPerSide else {
            throw LineDiffError.inputTooLarge(
                leftLineCount: leftLineCount,
                rightLineCount: rightLineCount,
                maximumLCSCells: maximumLCSCells
            )
        }
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
    private struct LineInput: Sendable {
        let rawText: String
        let comparisonKey: JSONExactTextIdentity
    }

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
        try safeAlignedDiff(
            left: left,
            right: right,
            options: options,
            budget: budget,
            shouldCancel: shouldCancel,
            comparisonKeyCreated: nil,
            lineCreated: nil
        )
    }

    /// Internal instrumentation seam used to prove that comparison keys are
    /// created once per input line rather than inside the LCS matrix loop.
    static func safeAlignedDiff(
        left: String,
        right: String,
        options: TextDiffOptions = TextDiffOptions(),
        budget: LineDiffBudget = .standard,
        shouldCancel: @escaping @Sendable () -> Bool = { Task.isCancelled },
        comparisonKeyCreated: (@Sendable () -> Void)?,
        lineCreated: (@Sendable () -> Void)? = nil
    ) throws -> [DiffAlignedRow] {
        let cancellation = DiffCancellationChecker(shouldCancel: shouldCancel)
        try cancellation.check()

        guard !left.isEmpty || !right.isEmpty else {
            return []
        }

        // Reject oversized byte payloads before newline normalization or line
        // storage can duplicate the input in memory.
        try budget.validateInputBytes(
            leftByteCount: left.utf8.count,
            rightByteCount: right.utf8.count
        )
        try cancellation.check()

        let leftLines = try scanDisplayLines(
            from: left,
            maximumLineCount: budget.maximumInputLinesPerSide,
            maximumLCSCells: budget.maximumLCSCells,
            cancellation: cancellation,
            lineCreated: lineCreated
        )
        let rightLines = try scanDisplayLines(
            from: right,
            maximumLineCount: budget.maximumInputLinesPerSide,
            maximumLCSCells: budget.maximumLCSCells,
            cancellation: cancellation,
            lineCreated: lineCreated
        )
        try budget.validateInputLines(
            leftLineCount: leftLines.count,
            rightLineCount: rightLines.count
        )

        let preparedLeft = try prepareLines(
            leftLines,
            options: options,
            cancellation: cancellation,
            comparisonKeyCreated: comparisonKeyCreated
        )
        let preparedRight = try prepareLines(
            rightLines,
            options: options,
            cancellation: cancellation,
            comparisonKeyCreated: comparisonKeyCreated
        )

        return try DiffAlignedRow.rows(
            from: displayDiff(
                leftLines: preparedLeft,
                rightLines: preparedRight,
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
                leftLines: prepareLines(
                    try scanDisplayLines(
                        from: left,
                        maximumLineCount: .max,
                        maximumLCSCells: .max,
                        cancellation: $0,
                        lineCreated: nil
                    ),
                    options: options,
                    cancellation: $0,
                    comparisonKeyCreated: nil
                ),
                rightLines: prepareLines(
                    try scanDisplayLines(
                        from: right,
                        maximumLineCount: .max,
                        maximumLCSCells: .max,
                        cancellation: $0,
                        lineCreated: nil
                    ),
                    options: options,
                    cancellation: $0,
                    comparisonKeyCreated: nil
                ),
                budget: LineDiffBudget(maximumLCSCells: .max),
                cancellation: $0
            )
        }
    }

    private static func displayDiff(
        leftLines: [LineInput],
        rightLines: [LineInput],
        budget: LineDiffBudget,
        cancellation: DiffCancellationChecker
    ) throws -> [DiffDisplayLine] {
        guard !leftLines.isEmpty || !rightLines.isEmpty else {
            return []
        }

        var prefixCount = 0
        while prefixCount < leftLines.count && prefixCount < rightLines.count
            && leftLines[prefixCount].comparisonKey == rightLines[prefixCount].comparisonKey {
            if prefixCount.isMultiple(of: 256) {
                try cancellation.check()
            }
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < (leftLines.count - prefixCount) && suffixCount < (rightLines.count - prefixCount)
            && leftLines[leftLines.count - 1 - suffixCount].comparisonKey
                == rightLines[rightLines.count - 1 - suffixCount].comparisonKey {
            if suffixCount.isMultiple(of: 256) {
                try cancellation.check()
            }
            suffixCount += 1
        }

        var result: [DiffDisplayLine] = []
        result.reserveCapacity(max(leftLines.count, rightLines.count))

        for i in 0..<prefixCount {
            if i.isMultiple(of: 256) {
                try cancellation.check()
            }
            result.append(DiffDisplayLine(
                kind: .unchanged,
                oldLineNumber: i + 1,
                newLineNumber: i + 1,
                leftText: leftLines[i].rawText,
                rightText: rightLines[i].rawText,
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
                    leftText: leftLines[prefixCount + i].rawText,
                    rightText: nil,
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
                    leftText: nil,
                    rightText: rightLines[prefixCount + j].rawText,
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
                   trimmedLeft[leftIndex].comparisonKey == trimmedRight[rightIndex].comparisonKey {
                    result.append(DiffDisplayLine(
                        kind: .unchanged,
                        oldLineNumber: oldLineNumber,
                        newLineNumber: newLineNumber,
                        leftText: trimmedLeft[leftIndex].rawText,
                        rightText: trimmedRight[rightIndex].rawText,
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
                        leftText: trimmedLeft[leftIndex].rawText,
                        rightText: nil,
                        indent: 0
                    ))
                    leftIndex += 1
                    oldLineNumber += 1
                } else if rightIndex < trimmedRight.count {
                    result.append(DiffDisplayLine(
                        kind: .added,
                        oldLineNumber: nil,
                        newLineNumber: newLineNumber,
                        leftText: nil,
                        rightText: trimmedRight[rightIndex].rawText,
                        indent: 0
                    ))
                    rightIndex += 1
                    newLineNumber += 1
                }
            }
        }

        for k in 0..<suffixCount {
            if k.isMultiple(of: 256) {
                try cancellation.check()
            }
            let leftIdx = leftLines.count - suffixCount + k
            let rightIdx = rightLines.count - suffixCount + k
            result.append(DiffDisplayLine(
                kind: .unchanged,
                oldLineNumber: leftIdx + 1,
                newLineNumber: rightIdx + 1,
                leftText: leftLines[leftIdx].rawText,
                rightText: rightLines[rightIdx].rawText,
                indent: 0
            ))
        }

        return result
    }

    private static func lcsLengths(
        leftLines: [LineInput],
        rightLines: [LineInput],
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
            let leftKey = leftLines[leftIndex].comparisonKey
            for rightIndex in stride(from: cols - 1, through: 0, by: -1) {
                if rightIndex.isMultiple(of: 256) {
                    try cancellation.check()
                }
                if leftKey == rightLines[rightIndex].comparisonKey {
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

    private static func prepareLines(
        _ lines: [String],
        options: TextDiffOptions,
        cancellation: DiffCancellationChecker,
        comparisonKeyCreated: (@Sendable () -> Void)?
    ) throws -> [LineInput] {
        var prepared: [LineInput] = []
        prepared.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            if index.isMultiple(of: 256) {
                try cancellation.check()
            }
            prepared.append(LineInput(
                rawText: line,
                comparisonKey: comparisonKey(for: line, options: options)
            ))
            comparisonKeyCreated?()
        }
        return prepared
    }

    private static func comparisonKey(for line: String, options: TextDiffOptions) -> JSONExactTextIdentity {
        var value = line
        if options.ignoreWhitespace {
            value = normalizeWhitespace(value)
        }
        if options.ignoreCase {
            value = value.folding(options: .caseInsensitive, locale: nil)
        }
        return JSONExactTextIdentity(value)
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func scanDisplayLines(
        from text: String,
        maximumLineCount: Int,
        maximumLCSCells: Int,
        cancellation: DiffCancellationChecker,
        lineCreated: (@Sendable () -> Void)?
    ) throws -> [String] {
        guard !text.isEmpty else { return [] }

        let utf8 = text.utf8
        var lines: [String] = []
        var lineStart = utf8.startIndex
        var cursor = lineStart
        var scannedByteCount = 0

        func inputTooLarge(lineCount: Int) -> LineDiffError {
            LineDiffError.inputTooLarge(
                leftLineCount: lineCount,
                rightLineCount: lineCount,
                maximumLCSCells: maximumLCSCells
            )
        }

        while cursor < utf8.endIndex {
            if scannedByteCount.isMultiple(of: 4_096) {
                try cancellation.check()
            }

            let byte = utf8[cursor]
            guard byte == 0x0A || byte == 0x0D else {
                cursor = utf8.index(after: cursor)
                scannedByteCount += 1
                continue
            }

            guard lines.count < maximumLineCount else {
                throw inputTooLarge(lineCount: lines.count + 1)
            }
            lines.append(String(decoding: utf8[lineStart..<cursor], as: UTF8.self))
            lineCreated?()

            var next = utf8.index(after: cursor)
            scannedByteCount += 1
            if byte == 0x0D, next < utf8.endIndex, utf8[next] == 0x0A {
                next = utf8.index(after: next)
                scannedByteCount += 1
            }
            cursor = next
            lineStart = next
        }

        guard lines.count < maximumLineCount else {
            throw inputTooLarge(lineCount: lines.count + 1)
        }
        lines.append(String(decoding: utf8[lineStart..<utf8.endIndex], as: UTF8.self))
        lineCreated?()
        try cancellation.check()
        return lines
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
