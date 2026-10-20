import SwiftUI
@testable import XTools
import Testing
import XToolsDesign

struct ToolMotionTests {
    @Test func reduceMotionGateRemovesSwiftUIAnimations() {
        switch ToolMotion.animation(.easeInOut(duration: 1), reduceMotion: true) {
        case nil:
            break
        case .some:
            Issue.record("Reduce Motion must disable SwiftUI animations")
        }

        switch ToolMotion.animation(.easeInOut(duration: 1), reduceMotion: false) {
        case nil:
            Issue.record("Animations should remain available when Reduce Motion is off")
        case .some:
            break
        }
    }
}
