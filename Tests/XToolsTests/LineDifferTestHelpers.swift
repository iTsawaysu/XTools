#if DEBUG
import Foundation
@testable import XToolsCore

extension LineDiffer {
    static func alignedDiff(left: String, right: String) -> [DiffAlignedRow] {
        try! safeAlignedDiff(left: left, right: right, budget: LineDiffBudget(maximumLCSCells: .max), shouldCancel: { false })
    }
}
#endif
