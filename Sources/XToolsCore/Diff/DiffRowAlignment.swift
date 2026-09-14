import Foundation

extension DiffAlignedRow {
    static func row(from line: DiffDisplayLine) -> DiffAlignedRow {
        let kind = alignedKind(from: line.kind)
        let left = line.oldLineNumber.map { DiffAlignedCell(lineNumber: $0, text: line.text, indent: line.indent) } ?? cellIfStructure(line, side: .left)
        let right = line.newLineNumber.map { DiffAlignedCell(lineNumber: $0, text: line.text, indent: line.indent) } ?? cellIfStructure(line, side: .right)

        return DiffAlignedRow(kind: kind, left: left, right: right)
    }

    static func pairedRows(
        removed: [DiffDisplayLine],
        added: [DiffDisplayLine],
        cancellation: DiffCancellationChecker
    ) throws -> [DiffAlignedRow] {
        try cancellation.check()
        guard !removed.isEmpty else {
            var rows: [DiffAlignedRow] = []
            rows.reserveCapacity(added.count)
            for line in added {
                try cancellation.check()
                rows.append(addedRow(from: line))
            }
            return rows
        }

        guard !added.isEmpty else {
            var rows: [DiffAlignedRow] = []
            rows.reserveCapacity(removed.count)
            for line in removed {
                try cancellation.check()
                rows.append(removedRow(from: line))
            }
            return rows
        }

        if removed.count == 1, added.count == 1 {
            return [try changedRow(
                leftLine: removed[0],
                rightLine: added[0],
                cancellation: cancellation
            )]
        }

        guard usesDynamicChangeAlignment(removedCount: removed.count, addedCount: added.count) else {
            var rows: [DiffAlignedRow] = []
            rows.reserveCapacity(removed.count + added.count)
            for line in removed {
                try cancellation.check()
                rows.append(removedRow(from: line))
            }
            for line in added {
                try cancellation.check()
                rows.append(addedRow(from: line))
            }
            return rows
        }

        let steps = try alignedChangeSteps(
            removed: removed,
            added: added,
            cancellation: cancellation
        )
        return try steps.map { step in
            try cancellation.check()
            switch step {
            case .removed(let index):
                return removedRow(from: removed[index])
            case .added(let index):
                return addedRow(from: added[index])
            case .changed(let removedIndex, let addedIndex):
                return try changedRow(
                    leftLine: removed[removedIndex],
                    rightLine: added[addedIndex],
                    cancellation: cancellation
                )
            }
        }
    }

    static func removedRow(from line: DiffDisplayLine) -> DiffAlignedRow {
        DiffAlignedRow(
            kind: .removed,
            left: DiffAlignedCell(
                lineNumber: line.oldLineNumber,
                text: line.text,
                indent: line.indent,
                segments: [DiffTextSegment(text: line.text, kind: .removed)]
            ),
            right: nil
        )
    }

    static func addedRow(from line: DiffDisplayLine) -> DiffAlignedRow {
        DiffAlignedRow(
            kind: .added,
            left: nil,
            right: DiffAlignedCell(
                lineNumber: line.newLineNumber,
                text: line.text,
                indent: line.indent,
                segments: [DiffTextSegment(text: line.text, kind: .added)]
            )
        )
    }

    static func changedRow(
        leftLine: DiffDisplayLine,
        rightLine: DiffDisplayLine,
        cancellation: DiffCancellationChecker
    ) throws -> DiffAlignedRow {
        let segments = try inlineSegments(
            left: leftLine.text,
            right: rightLine.text,
            cancellation: cancellation
        )

        return DiffAlignedRow(
            kind: .changed,
            left: DiffAlignedCell(
                lineNumber: leftLine.oldLineNumber,
                text: leftLine.text,
                indent: leftLine.indent,
                segments: segments.left
            ),
            right: DiffAlignedCell(
                lineNumber: rightLine.newLineNumber,
                text: rightLine.text,
                indent: rightLine.indent,
                segments: segments.right
            )
        )
    }

    enum ChangeAlignmentStep {
        case removed(Int)
        case added(Int)
        case changed(Int, Int)
    }

    static let maximumDynamicChangeAlignmentCells = 250_000
    static let minimumLinePairSimilarity = 0.58
    static let highConfidenceLinePairSimilarity = 0.72
    static let minimumSimilarityForLCSProbe = 0.45
    static let maximumLineSimilarityLCSCells = 4_096

    static func usesDynamicChangeAlignment(removedCount: Int, addedCount: Int) -> Bool {
        let product = removedCount.multipliedReportingOverflow(by: addedCount)
        guard !product.overflow else {
            return false
        }

        return product.partialValue <= maximumDynamicChangeAlignmentCells
    }

    static func alignedChangeSteps(
        removed: [DiffDisplayLine],
        added: [DiffDisplayLine],
        cancellation: DiffCancellationChecker
    ) throws -> [ChangeAlignmentStep] {
        try cancellation.check()
        var removedProfiles: [LinePairingProfile] = []
        removedProfiles.reserveCapacity(removed.count)
        for line in removed {
            try cancellation.check()
            removedProfiles.append(linePairingProfile(for: line.text))
        }

        var addedProfiles: [LinePairingProfile] = []
        addedProfiles.reserveCapacity(added.count)
        for line in added {
            try cancellation.check()
            addedProfiles.append(linePairingProfile(for: line.text))
        }
        var costs = Array(
            repeating: Array(repeating: 0.0, count: added.count + 1),
            count: removed.count + 1
        )
        var decisions = Array(
            repeating: Array<ChangeAlignmentStep?>(repeating: nil, count: added.count + 1),
            count: removed.count + 1
        )

        for removedIndex in stride(from: removed.count - 1, through: 0, by: -1) {
            try cancellation.check()
            costs[removedIndex][added.count] = Double(removed.count - removedIndex)
            decisions[removedIndex][added.count] = .removed(removedIndex)
        }

        for addedIndex in stride(from: added.count - 1, through: 0, by: -1) {
            try cancellation.check()
            costs[removed.count][addedIndex] = Double(added.count - addedIndex)
            decisions[removed.count][addedIndex] = .added(addedIndex)
        }

        for removedIndex in stride(from: removed.count - 1, through: 0, by: -1) {
            try cancellation.check()
            for addedIndex in stride(from: added.count - 1, through: 0, by: -1) {
                if addedIndex.isMultiple(of: 64) {
                    try cancellation.check()
                }
                var bestCost = 1.0 + costs[removedIndex + 1][addedIndex]
                var bestStep = ChangeAlignmentStep.removed(removedIndex)

                let insertionCost = 1.0 + costs[removedIndex][addedIndex + 1]
                if insertionCost < bestCost {
                    bestCost = insertionCost
                    bestStep = .added(addedIndex)
                }

                let similarity = try linePairSimilarity(
                    left: removedProfiles[removedIndex],
                    right: addedProfiles[addedIndex],
                    cancellation: cancellation
                )
                if similarity >= minimumLinePairSimilarity {
                    let replacementCost = lineReplacementCost(similarity: similarity)
                        + costs[removedIndex + 1][addedIndex + 1]
                    if replacementCost <= bestCost {
                        bestCost = replacementCost
                        bestStep = .changed(removedIndex, addedIndex)
                    }
                }

                costs[removedIndex][addedIndex] = bestCost
                decisions[removedIndex][addedIndex] = bestStep
            }
        }

        var steps: [ChangeAlignmentStep] = []
        var removedIndex = 0
        var addedIndex = 0

        while removedIndex < removed.count || addedIndex < added.count {
            try cancellation.check()
            guard let step = decisions[removedIndex][addedIndex] else {
                break
            }

            steps.append(step)

            switch step {
            case .removed:
                removedIndex += 1
            case .added:
                addedIndex += 1
            case .changed:
                removedIndex += 1
                addedIndex += 1
            }
        }

        return steps
    }

    static func lineReplacementCost(similarity: Double) -> Double {
        0.15 + (1.0 - similarity)
    }

    struct LinePairingProfile {
        let source: String
        let normalized: String
        let characters: [Character]
        let tokens: Set<String>
    }

    static func linePairingProfile(for line: String) -> LinePairingProfile {
        let normalized = normalizedLineForPairing(line)
        return LinePairingProfile(
            source: line,
            normalized: normalized,
            characters: Array(normalized),
            tokens: Set(linePairingTokens(from: normalized))
        )
    }

    static func linePairSimilarity(
        left: LinePairingProfile,
        right: LinePairingProfile,
        cancellation: DiffCancellationChecker
    ) throws -> Double {
        try cancellation.check()
        guard left.source != right.source else {
            return 1.0
        }

        guard !left.normalized.isEmpty || !right.normalized.isEmpty else {
            return 1.0
        }

        guard !left.normalized.isEmpty, !right.normalized.isEmpty else {
            return 0.0
        }

        guard left.normalized != right.normalized else {
            return 1.0
        }

        let anchoredSimilarity = try anchoredLineSimilarity(
            left: left.characters,
            right: right.characters,
            cancellation: cancellation
        )
        let tokenSimilarity = tokenDiceSimilarity(left: left.tokens, right: right.tokens)
        let cheapSimilarity = max(anchoredSimilarity, tokenSimilarity)

        guard cheapSimilarity < highConfidenceLinePairSimilarity else {
            return cheapSimilarity
        }

        guard cheapSimilarity >= minimumSimilarityForLCSProbe,
              let lcsSimilarity = try boundedLCSLineSimilarity(
                  left: left.characters,
                  right: right.characters,
                  cancellation: cancellation
              ) else {
            return cheapSimilarity
        }

        return max(cheapSimilarity, lcsSimilarity * 0.65 + tokenSimilarity * 0.35)
    }

    static func normalizedLineForPairing(_ line: String) -> String {
        var normalized = ""
        var previousWasWhitespace = false

        for character in line.lowercased() {
            if character.isWhitespace {
                if !previousWasWhitespace {
                    normalized.append(" ")
                }
                previousWasWhitespace = true
            } else {
                normalized.append(character)
                previousWasWhitespace = false
            }
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func anchoredLineSimilarity(
        left: [Character],
        right: [Character],
        cancellation: DiffCancellationChecker
    ) throws -> Double {
        try cancellation.check()
        let totalCount = left.count + right.count

        guard totalCount > 0 else {
            return 1.0
        }

        var prefixCount = 0
        while prefixCount < left.count,
              prefixCount < right.count,
              left[prefixCount] == right[prefixCount] {
            try cancellation.check()
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < left.count - prefixCount,
              suffixCount < right.count - prefixCount,
              left[left.count - suffixCount - 1] == right[right.count - suffixCount - 1] {
            try cancellation.check()
            suffixCount += 1
        }

        return (2.0 * Double(prefixCount + suffixCount)) / Double(totalCount)
    }

    static func tokenDiceSimilarity(left: Set<String>, right: Set<String>) -> Double {
        guard !left.isEmpty || !right.isEmpty else {
            return 0.0
        }

        guard !left.isEmpty, !right.isEmpty else {
            return 0.0
        }

        let sharedCount = left.intersection(right).count
        return (2.0 * Double(sharedCount)) / Double(left.count + right.count)
    }

    static func linePairingTokens(from line: String) -> [String] {
        line.split { character in
            !character.isLetter && !character.isNumber
        }.map(String.init)
    }

    static func boundedLCSLineSimilarity(
        left: [Character],
        right: [Character],
        cancellation: DiffCancellationChecker
    ) throws -> Double? {
        try cancellation.check()
        guard !left.isEmpty || !right.isEmpty else {
            return 1.0
        }

        guard !left.isEmpty, !right.isEmpty else {
            return 0.0
        }

        guard left.count <= maximumLineSimilarityLCSCells / max(1, right.count) else {
            return nil
        }

        let table = try inlineLCSLengths(
            left: left,
            right: right,
            cancellation: cancellation
        )
        let lcsLength = table[0][0]

        return (2.0 * Double(lcsLength)) / Double(left.count + right.count)
    }

    enum Side {
        case left
        case right
    }

    static func cellIfStructure(_ line: DiffDisplayLine, side: Side) -> DiffAlignedCell? {
        guard line.kind == .structure else {
            return nil
        }

        let number: Int?
        switch side {
        case .left:
            number = line.oldLineNumber
        case .right:
            number = line.newLineNumber
        }

        return DiffAlignedCell(lineNumber: number, text: line.text, indent: line.indent)
    }

    static func alignedKind(from kind: DiffDisplayLine.Kind) -> Kind {
        switch kind {
        case .unchanged:
            return .unchanged
        case .added:
            return .added
        case .removed:
            return .removed
        case .changed:
            return .changed
        case .context:
            return .context
        case .structure:
            return .structure
        }
    }
}
