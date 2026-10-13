import AppKit
import SwiftUI
import Testing
@testable import XTools
import XToolsCore

@Suite(.serialized)
@MainActor
struct PageScrollViewportTests {
    @Test func emptyUploadWorkspacesPreserveViewportHeight() async throws {
        for size in [NSSize(width: 1000, height: 1000), NSSize(width: 700, height: 700)] {
            for segment in ImageHubWorkspaceModel.Segment.allCases {
                let defaults = UserDefaults(suiteName: "PageScrollViewportTests.\(UUID())")!
                let repository = ToolWorkspaceRepository(defaults: defaults)
                repository.model(for: ImageHubWorkspaceModel.key).segment = segment
                let page = IndexImageHubPage()
                    .environmentObject(repository)
                    .environmentObject(HubSegmentEntryHint())
                // 图片空态原本铺满视口，上传动作在剩余工作区居中。
                try await assertFillsViewport(page, size: size, context: segment.rawValue)
            }
        }
    }

    @Test func chronometerRecordsPreserveViewportHeight() async throws {
        for lapCount in [0, 2] {
            let defaults = UserDefaults(suiteName: "PageScrollViewportTests.\(UUID())")!
            let repository = ToolWorkspaceRepository(defaults: defaults)
            var state = ChronometerState()
            if lapCount > 0 {
                state.start(at: 10)
                for lap in 1...lapCount { _ = state.recordLap(at: 10 + Double(lap)) }
                state.pause(at: 10 + Double(lapCount))
            }
            repository.model(for: ChronometerToolWorkspaceModel.key).chronometer = state
            // 计次列表在空态和少量记录时也必须保留原有的剩余工作区高度。
            try await assertFillsViewport(
                IndexChronometerPage().environmentObject(repository),
                size: NSSize(width: 1000, height: 1000), context: "chronometer, \(lapCount) laps"
            )
        }
    }

    private func assertFillsViewport<Page: View>(_ page: Page, size: NSSize, context: String) async throws {
        let hostingView = NSHostingView(rootView: page)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.close() }

        try await waitUntil(timeout: .seconds(5)) {
            hostingView.layoutSubtreeIfNeeded()
            return (findScrollView(in: hostingView)?.documentView?.frame.height ?? 0) > 0
        }
        let scrollView = try #require(findScrollView(in: hostingView))
        let documentView = try #require(scrollView.documentView)
        let viewportHeight = scrollView.contentView.bounds.height
        #expect(viewportHeight > 600)
        #expect(abs(documentView.frame.height - viewportHeight) < 0.5,
                "\(context), \(size): workspace must fill the viewport")
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
    }
}
