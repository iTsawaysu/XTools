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
        text.isEmpty ? [] : text.components(separatedBy: .newlines)
    }

    public static func lineRanges(in text: String) -> [NSRange] {
        let nsText = text as NSString

        guard nsText.length > 0 else {
            return [NSRange(location: 0, length: 0)]
        }

        var ranges: [NSRange] = []
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            var contentRange = lineRange

            while contentRange.length > 0 {
                let lastRange = NSRange(location: contentRange.location + contentRange.length - 1, length: 1)
                let last = nsText.substring(with: lastRange)
                if last == "\n" || last == "\r" {
                    contentRange.length -= 1
                } else {
                    break
                }
            }

            ranges.append(contentRange)
            location = NSMaxRange(lineRange)
        }

        if text.hasSuffix("\n") || text.hasSuffix("\r") {
            ranges.append(NSRange(location: nsText.length, length: 0))
        }

        return ranges
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
                  lines[index] == cell.text else {
                return false
            }

            matchedLines.insert(lineNumber)
        }

        return matchedLines.count == lines.count
    }
}
