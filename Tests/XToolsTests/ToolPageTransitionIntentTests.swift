import Testing
import XToolsDesign
@testable import XTools

struct ToolPageTransitionIntentTests {
    @Test func crossingCategoriesUsesSharedAxis() {
        #expect(
            ToolPageTransitionIntent.resolved(
                previousCategory: .crypto,
                nextCategory: .development
            ) == .sharedAxis
        )
    }

    @Test func stayingInsideACategoryKeepsDepth() {
        #expect(
            ToolPageTransitionIntent.resolved(
                previousCategory: .crypto,
                nextCategory: .crypto
            ) == .depth
        )
    }

    @Test func firstSelectionKeepsDepth() {
        #expect(
            ToolPageTransitionIntent.resolved(
                previousCategory: nil,
                nextCategory: .crypto
            ) == .depth
        )
    }
}
