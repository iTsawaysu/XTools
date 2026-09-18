import Foundation

extension DiffAlignedRow {
    static func inlineSegments(left: String, right: String) -> (left: [DiffTextSegment], right: [DiffTextSegment]) {
        LineDiffer.withoutCancellation {
            try inlineSegments(left: left, right: right, cancellation: $0)
        }
    }

    static func inlineSegments(
        left: String,
        right: String,
        cancellation: DiffCancellationChecker
    ) throws -> (left: [DiffTextSegment], right: [DiffTextSegment]) {
        try cancellation.check()
        guard JSONExactTextIdentity(left) != JSONExactTextIdentity(right) else {
            return (
                [DiffTextSegment(text: left, kind: .unchanged)],
                [DiffTextSegment(text: right, kind: .unchanged)]
            )
        }

        let leftScalars = Array(left.unicodeScalars)
        let rightScalars = Array(right.unicodeScalars)

        guard !leftScalars.isEmpty else {
            return (
                [],
                [DiffTextSegment(text: right, kind: .added)]
            )
        }

        guard !rightScalars.isEmpty else {
            return (
                [DiffTextSegment(text: left, kind: .removed)],
                []
            )
        }

        var prefixCount = 0
        while prefixCount < leftScalars.count,
              prefixCount < rightScalars.count,
              leftScalars[prefixCount] == rightScalars[prefixCount] {
            try cancellation.check()
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < leftScalars.count - prefixCount,
              suffixCount < rightScalars.count - prefixCount,
              leftScalars[leftScalars.count - suffixCount - 1] == rightScalars[rightScalars.count - suffixCount - 1] {
            try cancellation.check()
            suffixCount += 1
        }

        var leftSegments: [DiffTextSegment] = []
        var rightSegments: [DiffTextSegment] = []

        if prefixCount > 0 {
            let prefix = scalarText(leftScalars[0..<prefixCount])
            append(prefix, kind: .unchanged, to: &leftSegments)
            append(prefix, kind: .unchanged, to: &rightSegments)
        }

        let leftMiddleEnd = leftScalars.count - suffixCount
        let rightMiddleEnd = rightScalars.count - suffixCount

        try appendInlineMiddle(
            left: Array(leftScalars[prefixCount..<leftMiddleEnd]),
            right: Array(rightScalars[prefixCount..<rightMiddleEnd]),
            leftSegments: &leftSegments,
            rightSegments: &rightSegments,
            cancellation: cancellation
        )

        if suffixCount > 0 {
            let leftSuffix = scalarText(leftScalars[leftMiddleEnd..<leftScalars.count])
            let rightSuffix = scalarText(rightScalars[rightMiddleEnd..<rightScalars.count])
            append(leftSuffix, kind: .unchanged, to: &leftSegments)
            append(rightSuffix, kind: .unchanged, to: &rightSegments)
        }

        return (leftSegments, rightSegments)
    }

    static func appendInlineMiddle(
        left: [Unicode.Scalar],
        right: [Unicode.Scalar],
        leftSegments: inout [DiffTextSegment],
        rightSegments: inout [DiffTextSegment],
        cancellation: DiffCancellationChecker
    ) throws {
        try cancellation.check()
        guard !left.isEmpty else {
            append(scalarText(right), kind: .added, to: &rightSegments)
            return
        }

        guard !right.isEmpty else {
            append(scalarText(left), kind: .removed, to: &leftSegments)
            return
        }

        let maxInlineDiffCells = 120_000
        guard left.count <= maxInlineDiffCells / max(1, right.count) else {
            append(scalarText(left), kind: .removed, to: &leftSegments)
            append(scalarText(right), kind: .added, to: &rightSegments)
            return
        }

        let table = try inlineLCSLengths(
            left: left,
            right: right,
            cancellation: cancellation
        )
        var operations: [InlineDiffOperation] = []
        var leftIndex = 0
        var rightIndex = 0

        while leftIndex < left.count || rightIndex < right.count {
            try cancellation.check()
            if leftIndex < left.count,
               rightIndex < right.count,
               left[leftIndex] == right[rightIndex] {
                let value = String(left[leftIndex])
                appendOperation(.unchanged(value), to: &operations)
                leftIndex += 1
                rightIndex += 1
            } else if rightIndex < right.count,
                      (leftIndex == left.count || table[leftIndex][rightIndex + 1] >= table[leftIndex + 1][rightIndex]) {
                appendOperation(.added(String(right[rightIndex])), to: &operations)
                rightIndex += 1
            } else if leftIndex < left.count {
                appendOperation(.removed(String(left[leftIndex])), to: &operations)
                leftIndex += 1
            }
        }

        for operation in try cleanupInlineOperations(
            operations,
            cancellation: cancellation
        ) {
            try cancellation.check()
            switch operation {
            case .unchanged(let text):
                append(text, kind: .unchanged, to: &leftSegments)
                append(text, kind: .unchanged, to: &rightSegments)
            case .removed(let text):
                append(text, kind: .removed, to: &leftSegments)
            case .added(let text):
                append(text, kind: .added, to: &rightSegments)
            case .changed(let text):
                append(text, kind: .removed, to: &leftSegments)
                append(text, kind: .added, to: &rightSegments)
            }
        }
    }

    static func inlineLCSLengths<Element: Equatable>(left: [Element], right: [Element]) -> [[Int]] {
        LineDiffer.withoutCancellation {
            try inlineLCSLengths(left: left, right: right, cancellation: $0)
        }
    }

    static func inlineLCSLengths<Element: Equatable>(
        left: [Element],
        right: [Element],
        cancellation: DiffCancellationChecker
    ) throws -> [[Int]] {
        try cancellation.check()
        var table = Array(
            repeating: Array(repeating: 0, count: right.count + 1),
            count: left.count + 1
        )

        for leftIndex in stride(from: left.count - 1, through: 0, by: -1) {
            try cancellation.check()
            for rightIndex in stride(from: right.count - 1, through: 0, by: -1) {
                if rightIndex.isMultiple(of: 256) {
                    try cancellation.check()
                }
                if left[leftIndex] == right[rightIndex] {
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

    private static func scalarText<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        String(String.UnicodeScalarView(scalars))
    }

    static func cleanupInlineOperations(_ operations: [InlineDiffOperation]) -> [InlineDiffOperation] {
        LineDiffer.withoutCancellation {
            try cleanupInlineOperations(operations, cancellation: $0)
        }
    }

    static func cleanupInlineOperations(
        _ operations: [InlineDiffOperation],
        cancellation: DiffCancellationChecker
    ) throws -> [InlineDiffOperation] {
        let minimumStableIslandLength = 5
        var cleaned: [InlineDiffOperation] = []
        cleaned.reserveCapacity(operations.count)

        for (index, operation) in operations.enumerated() {
            try cancellation.check()
            guard case .unchanged(let text) = operation,
                  text.count < minimumStableIslandLength,
                  hasChange(on: operations[..<index]),
                  hasChange(on: operations[(index + 1)...]),
                  surroundingChangesIncludeInsertAndDelete(operations, around: index) else {
                cleaned.append(operation)
                continue
            }

            cleaned.append(.changed(text))
        }

        return cleaned
    }

    static func surroundingChangesIncludeInsertAndDelete(_ operations: [InlineDiffOperation], around index: Int) -> Bool {
        var hasInsertion = false
        var hasDeletion = false

        for operation in operations[..<index].reversed() {
            if operation.isChange {
                hasInsertion = hasInsertion || operation.isInsertion
                hasDeletion = hasDeletion || operation.isDeletion
            }
        }

        for operation in operations[(index + 1)...] {
            if operation.isChange {
                hasInsertion = hasInsertion || operation.isInsertion
                hasDeletion = hasDeletion || operation.isDeletion
            }
        }

        return hasInsertion && hasDeletion
    }

    static func hasChange<S: Sequence>(on operations: S) -> Bool where S.Element == InlineDiffOperation {
        operations.contains { $0.isChange }
    }

    static func appendOperation(_ operation: InlineDiffOperation, to operations: inout [InlineDiffOperation]) {
        guard let last = operations.last, last.kind == operation.kind else {
            operations.append(operation)
            return
        }

        operations[operations.count - 1] = last.merged(with: operation)
    }

    static func append(_ text: String, kind: DiffTextSegment.Kind, to segments: inout [DiffTextSegment]) {
        guard !text.isEmpty else {
            return
        }

        if let last = segments.last, last.kind == kind {
            segments[segments.count - 1] = DiffTextSegment(text: last.text + text, kind: kind)
        } else {
            segments.append(DiffTextSegment(text: text, kind: kind))
        }
    }

    enum InlineDiffOperation: Equatable {
        case unchanged(String)
        case removed(String)
        case added(String)
        case changed(String)

        enum Kind {
            case unchanged
            case removed
            case added
            case changed
        }

        var kind: Kind {
            switch self {
            case .unchanged:
                return .unchanged
            case .removed:
                return .removed
            case .added:
                return .added
            case .changed:
                return .changed
            }
        }

        var isChange: Bool {
            kind != .unchanged
        }

        var isInsertion: Bool {
            switch self {
            case .added, .changed:
                return true
            case .unchanged, .removed:
                return false
            }
        }

        var isDeletion: Bool {
            switch self {
            case .removed, .changed:
                return true
            case .unchanged, .added:
                return false
            }
        }

        func merged(with other: InlineDiffOperation) -> InlineDiffOperation {
            switch (self, other) {
            case (.unchanged(let left), .unchanged(let right)):
                return .unchanged(left + right)
            case (.removed(let left), .removed(let right)):
                return .removed(left + right)
            case (.added(let left), .added(let right)):
                return .added(left + right)
            case (.changed(let left), .changed(let right)):
                return .changed(left + right)
            default:
                return self
            }
        }
    }
}
