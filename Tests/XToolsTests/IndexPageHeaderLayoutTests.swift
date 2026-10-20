import Testing
@testable import XTools

struct IndexPageHeaderLayoutTests {
    @Test func narrowContentStacksTheAccessory() {
        #expect(IndexPageHeaderLayout.stacksAccessory(forContentWidth: 640))
    }

    @Test func wideContentKeepsTheAccessoryInline() {
        #expect(!IndexPageHeaderLayout.stacksAccessory(forContentWidth: 880))
    }

    @Test func unmeasuredContentKeepsTheInlineArrangement() {
        #expect(!IndexPageHeaderLayout.stacksAccessory(forContentWidth: 0))
    }
}
