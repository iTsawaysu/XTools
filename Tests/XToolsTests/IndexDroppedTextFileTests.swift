import AppKit
import Foundation
import Testing
@testable import XTools

@MainActor
struct IndexDroppedTextFileTests {
    @Test func newerDropRejectsLateRead() async throws {
        let (window, view) = makeEditor()
        let firstStarted = DropReadSignal()
        let releaseFirst = DropReadSignal()
        let firstReturned = DropReadSignal()
        let reader = IndexDroppedTextFile(view: view) { url in
            if url.lastPathComponent == "first" {
                await firstStarted.signal()
                await releaseFirst.wait()
                await firstReturned.signal()
            }
            return url.lastPathComponent
        }
        var published: [String] = []
        reader.start(url: URL(fileURLWithPath: "/first")) { published.append($0) }
        await firstStarted.wait()
        reader.start(url: URL(fileURLWithPath: "/second")) { published.append($0) }
        try await waitUntil { published == ["second"] }
        await releaseFirst.signal()
        await firstReturned.wait()
        try await Task.sleep(for: .milliseconds(30))
        #expect(published == ["second"])
        #expect(view.window === window)
    }

    @Test func editAndDetachRejectLateRead() async throws {
        for action in ["edit", "detach"] {
            let (window, view) = makeEditor()
            let started = DropReadSignal()
            let release = DropReadSignal()
            let returned = DropReadSignal()
            let reader = IndexDroppedTextFile(view: view) { _ in
                await started.signal()
                await release.wait()
                await returned.signal()
                return "stale"
            }
            view.sharedDroppedFile = reader
            var published: [String] = []
            reader.start(url: URL(fileURLWithPath: "/held")) { published.append($0) }
            await started.wait()
            if action == "edit" {
                view.string = "new edit"
                view.didChangeText()
            } else {
                window.contentView = NSView()
            }
            await release.signal()
            await returned.wait()
            try await Task.sleep(for: .milliseconds(30))
            #expect(published.isEmpty)
        }
    }

    private func makeEditor() -> (NSWindow, IndexCaretTextView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let view = IndexCaretTextView(frame: window.contentView!.bounds)
        window.contentView = view
        return (window, view)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for dropped file publication")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor DropReadSignal {
    private var signalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !signalled else { return }
        signalled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    func wait() async {
        guard !signalled else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
