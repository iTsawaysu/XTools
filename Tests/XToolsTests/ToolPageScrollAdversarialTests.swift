import AppKit
import SwiftUI
import Testing
@testable import XTools
import XToolsCore

@Suite(.serialized)
@MainActor
struct ToolPageScrollAdversarialTests {

    private func makeRepository() -> ToolWorkspaceRepository {
        let defaults = UserDefaults(suiteName: "ToolPageScrollAdversarialTests.\(UUID())")!
        return ToolWorkspaceRepository(defaults: defaults)
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let sv = view as? NSScrollView { return sv }
        for sub in view.subviews {
            if let found = findScrollView(in: sub) { return found }
        }
        return nil
    }

    @Test(.enabled(if: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
    func rapidReversalHidesParkedScrollersAndRestoresNativeScrolling() async throws {
        let selection = ScrollStageSelection()
        let recorder = ScrollStageRecorder()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: ScrollStageHost(selection: selection, recorder: recorder))
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.close() }

        try await waitUntil(timeout: .seconds(3)) {
            hostingView.layoutSubtreeIfNeeded()
            return (recorder.pages["a"]?.generation ?? 0) > 0
                && recorder.pages["a"]?.scrollView != nil
        }
        var previousGeneration = try #require(recorder.pages["a"]).generation
        var identities: [String: ObjectIdentifier] = [:]
        let firstScrollView = try #require(recorder.pages["a"]?.scrollView)
        identities["a"] = ObjectIdentifier(firstScrollView)
        // 首次进入也必须真正恢复指示器；一直隐藏不能冒充修复成功。
        try await waitUntil(timeout: .seconds(IndexPageArrivalScrollerSuppressor.settleDelay + 2)) {
            hostingView.layoutSubtreeIfNeeded()
            return firstScrollView.hasVerticalScroller
        }

        // 每次等待真实代际切换，立即反转，不把修改普通对象等同于导航成功。
        for i in 1...10 {
            let activeKey = i.isMultiple(of: 2) ? "a" : "b"
            let parkedKey = activeKey == "a" ? "b" : "a"
            selection.key = activeKey
            let oldGeneration = previousGeneration
            try await waitUntil(timeout: .seconds(3)) {
                hostingView.layoutSubtreeIfNeeded()
                return (recorder.pages[activeKey]?.generation ?? 0) > oldGeneration
                    && recorder.pages[parkedKey]?.generation == 0
                    && recorder.pages[activeKey]?.scrollView != nil
                    && recorder.pages[parkedKey]?.scrollView != nil
            }
            let activePage = try #require(recorder.pages[activeKey])
            previousGeneration = activePage.generation
            let activeScrollView = try #require(activePage.scrollView)
            let parkedScrollView = try #require(recorder.pages[parkedKey]?.scrollView)
            #expect(activeScrollView !== parkedScrollView)
            #expect(!activeScrollView.hasVerticalScroller, "The arriving page must hide its native indicator")
            #expect(!parkedScrollView.hasVerticalScroller, "The parked page must hide its native indicator")

            let identity = ObjectIdentifier(activeScrollView)
            if let retainedIdentity = identities[activeKey] {
                #expect(identity == retainedIdentity, "Revisiting must retain the page's native scroll view")
            } else {
                identities[activeKey] = identity
            }

            // 抑制指示器期间仍可移动内容，不改变原生滚动归属。
            activeScrollView.contentView.scroll(to: NSPoint(x: 0, y: 30))
            #expect(activeScrollView.contentView.bounds.origin.y == 30)
        }

        let activeScrollView = try #require(recorder.pages["a"]?.scrollView)
        let parkedScrollView = try #require(recorder.pages["b"]?.scrollView)
        try await waitUntil(timeout: .seconds(IndexPageArrivalScrollerSuppressor.settleDelay + 2)) {
            hostingView.layoutSubtreeIfNeeded()
            return activeScrollView.hasVerticalScroller
        }
        #expect(activeScrollView.autohidesScrollers)
        #expect(!parkedScrollView.hasVerticalScroller, "Cancelled arrivals must not restore a parked indicator")
        #expect(recorder.pages["b"]?.generation == 0)
        let documentView = try #require(activeScrollView.documentView)
        let maxScrollY = documentView.frame.height - activeScrollView.contentView.bounds.height
        #expect(maxScrollY > 1000)
        activeScrollView.contentView.scroll(to: NSPoint(x: 0, y: maxScrollY))
        #expect(activeScrollView.contentView.bounds.origin.y == maxScrollY)
        activeScrollView.contentView.scroll(to: .zero)
        #expect(activeScrollView.contentView.bounds.origin.y == 0)
    }

    @Test func shortResultPagesUseNaturalHeightAndRemainScrollable() async throws {
        let repository = makeRepository()
        let pages: [(String, AnyView)] = [
            ("进制转换", AnyView(IndexBaseConverterPage().environmentObject(repository))),
            ("罗马数字", AnyView(IndexRomanPage().environmentObject(repository)))
        ]

        for height in [250.0, 1000.0] {
            for (title, page) in pages {
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 800, height: height),
                    styleMask: [.titled, .resizable], backing: .buffered, defer: false
                )
                window.isReleasedWhenClosed = false
                let hostingView = NSHostingView(rootView: page.environment(\.toolPageEntryGeneration, 1))
                window.contentView = hostingView
                window.orderFront(nil)
                defer { window.close() }

                try await waitUntil(timeout: .seconds(3)) {
                    hostingView.layoutSubtreeIfNeeded()
                    guard let scrollView = findScrollView(in: hostingView) else { return false }
                    return scrollView.hasVerticalScroller && (scrollView.documentView?.frame.height ?? 0) > 0
                }
                let scrollView = try #require(findScrollView(in: hostingView))
                let documentView = try #require(scrollView.documentView)
                let viewportHeight = scrollView.contentView.bounds.height
                #expect(scrollView.autohidesScrollers, "\(title) must restore the native automatic policy")

                if height == 250 {
                    // 小视口仍须滚动到完整结果；隐藏指示器不能阻断内容滚动。
                    let maxScrollY = documentView.frame.height - viewportHeight
                    #expect(maxScrollY > 50, "\(title) must overflow the small viewport")
                    scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxScrollY))
                    #expect(scrollView.contentView.bounds.origin.y == maxScrollY)
                    scrollView.contentView.scroll(to: .zero)
                    #expect(scrollView.contentView.bounds.origin.y == 0)
                } else {
                    // 短结果页保留自然高度，不因视口最小高度触发临界溢出。
                    #expect(documentView.frame.height < viewportHeight - 100,
                            "\(title) must keep natural content height in a large viewport")
                }
            }
        }
    }
}

@MainActor
private final class ScrollStageSelection: ObservableObject {
    @Published var key = "a"
}

@MainActor
private final class ScrollStageRecorder {
    struct Page {
        let generation: Int
        weak var scrollView: NSScrollView?
    }

    var pages: [String: Page] = [:]
}

@MainActor
private struct ScrollStageHost: View {
    @ObservedObject var selection: ScrollStageSelection
    let recorder: ScrollStageRecorder

    var body: some View {
        ToolPageStage(target: .tool(ToolID(rawValue: selection.key))) { pageKey in
            if case .tool(let id) = pageKey.payload {
                IndexPage("Stage \(id.rawValue)", subtitle: "Native scroll lifecycle", layout: .scroll) {
                    VStack(spacing: 20) {
                        ForEach(0..<30) { row in
                            Text("\(id.rawValue): \(row)").frame(height: 60)
                        }
                    }
                    .background(ScrollStageNativeProbe(key: id.rawValue, recorder: recorder))
                }
            }
        }
    }
}

@MainActor
private struct ScrollStageNativeProbe: NSViewRepresentable {
    let key: String
    let recorder: ScrollStageRecorder
    @Environment(\.toolPageEntryGeneration) private var generation

    func makeNSView(context: Context) -> ScrollStageProbeView {
        ScrollStageProbeView()
    }

    func updateNSView(_ view: ScrollStageProbeView, context: Context) {
        let currentGeneration = generation
        view.onRefresh = { [weak recorder] scrollView in
            recorder?.pages[key] = ScrollStageRecorder.Page(
                generation: currentGeneration,
                scrollView: scrollView
            )
        }
        view.refresh()
    }
}

@MainActor
private final class ScrollStageProbeView: NSView {
    var onRefresh: ((NSScrollView?) -> Void)?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        refresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func refresh() {
        onRefresh?(enclosingScrollView)
    }
}
