#if DEBUG
import Foundation
@testable import XToolsCore

extension LineDiffer {
    static func diff(left: String, right: String) -> String {
        guard !left.isEmpty || !right.isEmpty else { return "" }
        let leftLines = left.components(separatedBy: .newlines)
        let rightLines = right.components(separatedBy: .newlines)
        let count = max(leftLines.count, rightLines.count)
        var differenceCount = 0
        var lines: [String] = []

        for index in 0..<count {
            let leftLine = index < leftLines.count ? leftLines[index] : ""
            let rightLine = index < rightLines.count ? rightLines[index] : ""

            if leftLine == rightLine {
                lines.append("  \(leftLine)")
            } else {
                differenceCount += 1
                if !leftLine.isEmpty { lines.append("− \(leftLine)") }
                if !rightLine.isEmpty { lines.append("+ \(rightLine)") }
            }
        }
        return "共 \(differenceCount) 行不同\n\n" + lines.joined(separator: "\n")
    }

    static func alignedDiff(left: String, right: String) -> [DiffAlignedRow] {
        try! safeAlignedDiff(left: left, right: right, budget: LineDiffBudget(maximumLCSCells: .max), shouldCancel: { false })
    }
}
#endif
