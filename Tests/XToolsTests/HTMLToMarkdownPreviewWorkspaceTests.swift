import SwiftUI
import Testing
@testable import XTools

struct HTMLToMarkdownPreviewWorkspaceTests {
    @MainActor
    @Test func renderedPreviewPreferenceRoundTripsThroughStore() {
        let defaults = UserDefaults(suiteName: "HTMLToMarkdownPreviewWorkspaceTests.\(UUID().uuidString)")!
        let store = ToolPreferenceStore(defaults: defaults)

        let model = HTMLToMarkdownToolWorkspaceModel(preferences: store)
        #expect(model.showsRenderedPreview == true, "Preview mode is the default presentation")

        model.showsRenderedPreview = false
        let rehydrated = HTMLToMarkdownToolWorkspaceModel(preferences: store)
        #expect(rehydrated.showsRenderedPreview == false, "The source/preview choice persists across workspace rehydration")

        rehydrated.showsRenderedPreview = true
        let restored = HTMLToMarkdownToolWorkspaceModel(preferences: store)
        #expect(restored.showsRenderedPreview == true)
    }

    @MainActor
    @Test func pageMountsWithoutOverflowAtStandardDetailWidth() {
        let defaults = UserDefaults(suiteName: "HTMLToMarkdownPreviewWorkspaceTests.Mount.\(UUID().uuidString)")!
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let view = IndexHTMLToMarkdownPage().environmentObject(repository)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 680, height: 600)
        hostingView.layoutSubtreeIfNeeded()

        func checkOverflows(_ v: NSView) {
            #expect(v.frame.maxX <= 680, "View \(type(of: v)) frame \(v.frame) exceeds container width 680")
            for sub in v.subviews {
                checkOverflows(sub)
            }
        }
        checkOverflows(hostingView)
    }
}
