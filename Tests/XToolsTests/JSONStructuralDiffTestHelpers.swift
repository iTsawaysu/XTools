#if DEBUG
import Foundation
@testable import XToolsCore

extension JSONStructuralDiff {
    static func alignedDiff(left: String, right: String, labels: JSONDiffValidation.SideLabels, budget: LineDiffBudget = LineDiffBudget(maximumLCSCells: .max)) -> Decision {
        try! cancellableAlignedDiff(left: left, right: right, labels: labels, budget: budget, shouldCancel: { false })
    }
}
#endif
