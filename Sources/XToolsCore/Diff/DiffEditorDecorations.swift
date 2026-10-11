import Foundation

public enum DiffDecorationSide: Equatable, Sendable {
    case left
    case right
}

public enum DiffLineStatus: Equatable, Sendable {
    case unchanged
    case added
    case removed
    case changedLeft
    case changedRight
}

public struct DiffLineDecoration: Equatable, Sendable {
    public let status: DiffLineStatus
    public let segments: [DiffTextSegment]

    public init(status: DiffLineStatus, segments: [DiffTextSegment]) {
        self.status = status
        self.segments = segments
    }
}

public struct DiffEditorDecorations: Equatable, Sendable {
    public var left: [Int: DiffLineDecoration] = [:]
    public var right: [Int: DiffLineDecoration] = [:]

    public init(rows: [DiffAlignedRow]) {
        for row in rows {
            if let cell = row.left, let lineNumber = cell.lineNumber {
                left[lineNumber] = DiffLineDecoration(
                    status: Self.status(for: row.kind, side: .left),
                    segments: cell.segments
                )
            }

            if let cell = row.right, let lineNumber = cell.lineNumber {
                right[lineNumber] = DiffLineDecoration(
                    status: Self.status(for: row.kind, side: .right),
                    segments: cell.segments
                )
            }
        }
    }

    private static func status(for kind: DiffAlignedRow.Kind, side: DiffDecorationSide) -> DiffLineStatus {
        switch (kind, side) {
        case (.added, .right):
            return .added
        case (.removed, .left):
            return .removed
        case (.changed, .left):
            return .changedLeft
        case (.changed, .right):
            return .changedRight
        default:
            return .unchanged
        }
    }
}

public enum DiffSourceText {
    public static func sourceLines(in text: String) -> [String] {
        var lines: [String] = []
        forEachLine(in: text, checkpoint: {}) { range, _ in lines.append(String(text[range])) }
        return lines
    }

    public static func lineRanges(in text: String) -> [NSRange] {
        guard !text.isEmpty else { return [NSRange(location: 0, length: 0)] }
        var ranges: [NSRange] = []
        var offset = 0
        forEachLine(in: text, checkpoint: {}) { range, terminatorLength in
            let length = text[range].utf16.count
            ranges.append(NSRange(location: offset, length: length))
            offset += length + terminatorLength
        }
        return ranges
    }

    /// Shared logical lines for the algorithm and editor decorations. Only CR,
    /// LF and CRLF delimit lines; Unicode separators remain literal content.
    /// Yields before allocating line strings so callers can enforce budgets.
    static func forEachLine(
        in text: String,
        checkpoint: () throws -> Void = {},
        body: (Range<String.Index>, Int) throws -> Void
    ) rethrows {
        guard !text.isEmpty else { return }
        let utf8 = text.utf8
        var start = utf8.startIndex
        var cursor = start
        var scanned = 0
        var nextCheckpoint = 0
        while cursor < utf8.endIndex {
            if scanned >= nextCheckpoint {
                try checkpoint()
                nextCheckpoint = scanned + 4_096
            }
            let byte = utf8[cursor]
            guard byte == 0x0A || byte == 0x0D else {
                cursor = utf8.index(after: cursor)
                scanned += 1
                continue
            }
            var next = utf8.index(after: cursor)
            var terminatorLength = 1
            if byte == 0x0D, next < utf8.endIndex, utf8[next] == 0x0A {
                next = utf8.index(after: next)
                terminatorLength = 2
            }
            try body(start..<cursor, terminatorLength)
            scanned += terminatorLength
            cursor = next
            start = next
        }
        try body(start..<utf8.endIndex, 0)
        try checkpoint()
    }
}

public enum DiffDecorationFreshness {
    public static func rowsMatchVisibleText(
        rows: [DiffAlignedRow],
        side: DiffDecorationSide,
        text: String
    ) -> Bool {
        let lines = DiffSourceText.sourceLines(in: text)
        guard !lines.isEmpty else {
            return rows.allSatisfy { row in
                switch side {
                case .left:
                    return row.left == nil
                case .right:
                    return row.right == nil
                }
            }
        }

        var matchedLines = Set<Int>()

        for row in rows {
            let cell: DiffAlignedCell?
            switch side {
            case .left:
                cell = row.left
            case .right:
                cell = row.right
            }

            guard let cell, let lineNumber = cell.lineNumber else {
                continue
            }

            let index = lineNumber - 1
            guard lines.indices.contains(index),
                  JSONExactTextIdentity(lines[index]) == JSONExactTextIdentity(cell.text) else {
                return false
            }

            matchedLines.insert(lineNumber)
        }

        return matchedLines.count == lines.count
    }
}
