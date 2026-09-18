import Foundation

public enum DiffRowKind: Equatable, Sendable {
    case unchanged
    case added
    case removed
    case changed
    case context
    case structure

    public var isDifference: Bool {
        switch self {
        case .added, .removed, .changed:
            return true
        case .unchanged, .context, .structure:
            return false
        }
    }
}

public struct DiffDisplayLine: Identifiable, Equatable, Sendable {
    public typealias Kind = DiffRowKind

    public let id: UUID
    public let kind: Kind
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let text: String
    public let indent: Int

    public init(
        id: UUID = UUID(),
        kind: Kind,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        text: String,
        indent: Int
    ) {
        self.id = id
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.text = text
        self.indent = indent
    }

    public static func == (lhs: DiffDisplayLine, rhs: DiffDisplayLine) -> Bool {
        lhs.kind == rhs.kind
            && lhs.oldLineNumber == rhs.oldLineNumber
            && lhs.newLineNumber == rhs.newLineNumber
            && lhs.text == rhs.text
            && lhs.indent == rhs.indent
    }
}

public extension Array where Element == DiffDisplayLine {
    func diffFiltered(preservesStructure: Bool) -> [DiffDisplayLine] {
        DiffReaderProjection(
            rows: self,
            onlyShowsDifferences: true,
            preservesStructure: preservesStructure,
            enableCollapse: false
        ).items.compactMap(\.row)
    }
}

public struct DiffTextSegment: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case unchanged
        case added
        case removed
    }

    public let text: String
    public let kind: Kind

    public init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }
}

public struct DiffAlignedCell: Equatable, Sendable {
    public let lineNumber: Int?
    public let text: String
    public let indent: Int
    public let segments: [DiffTextSegment]
    public let originalLineNumber: Int?

    public init(
        lineNumber: Int?,
        text: String,
        indent: Int,
        segments: [DiffTextSegment]? = nil,
        originalLineNumber: Int? = nil
    ) {
        self.lineNumber = lineNumber
        self.text = text
        self.indent = indent
        self.segments = segments ?? [DiffTextSegment(text: text, kind: .unchanged)]
        self.originalLineNumber = originalLineNumber ?? lineNumber
    }
}

public struct DiffAlignedRow: Identifiable, Equatable, Sendable {
    public typealias Kind = DiffRowKind

    public let id: UUID
    public let kind: Kind
    public let left: DiffAlignedCell?
    public let right: DiffAlignedCell?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        left: DiffAlignedCell?,
        right: DiffAlignedCell?
    ) {
        self.id = id
        self.kind = kind
        self.left = left
        self.right = right
    }

    public static func == (lhs: DiffAlignedRow, rhs: DiffAlignedRow) -> Bool {
        lhs.kind == rhs.kind
            && lhs.left == rhs.left
            && lhs.right == rhs.right
    }

    public static func rows(from lines: [DiffDisplayLine]) -> [DiffAlignedRow] {
        LineDiffer.withoutCancellation {
            try rows(from: lines, cancellation: $0)
        }
    }

    static func rows(
        from lines: [DiffDisplayLine],
        cancellation: DiffCancellationChecker
    ) throws -> [DiffAlignedRow] {
        var rows: [DiffAlignedRow] = []
        var index = 0

        while index < lines.count {
            try cancellation.check()
            let line = lines[index]

            if line.kind == .removed {
                let removedStart = index
                while index < lines.count, lines[index].kind == .removed {
                    index += 1
                }
                let removedLines = Array(lines[removedStart..<index])

                let addedStart = index
                while index < lines.count, lines[index].kind == .added {
                    index += 1
                }
                let addedLines = Array(lines[addedStart..<index])

                rows += try pairedRows(
                    removed: removedLines,
                    added: addedLines,
                    cancellation: cancellation
                )
                continue
            }

            if line.kind == .added {
                let addedStart = index
                while index < lines.count, lines[index].kind == .added {
                    index += 1
                }
                let addedLines = Array(lines[addedStart..<index])

                let removedStart = index
                while index < lines.count, lines[index].kind == .removed {
                    index += 1
                }
                let removedLines = Array(lines[removedStart..<index])

                rows += try pairedRows(
                    removed: removedLines,
                    added: addedLines,
                    cancellation: cancellation
                )
                continue
            }

            rows.append(row(from: line))
            index += 1
        }

        return rows
    }
}

public extension Array where Element == DiffAlignedRow {
    func diffFiltered(preservesStructure: Bool) -> [DiffAlignedRow] {
        DiffReaderProjection(
            rows: self,
            onlyShowsDifferences: true,
            preservesStructure: preservesStructure,
            enableCollapse: false
        ).items.compactMap(\.row)
    }
}
