import AppKit
import Foundation
import Testing
@testable import XTools

@MainActor
struct IndexDroppedTextFileTests {
    @Test func typedRejectionsAreVisibleWithoutPublishingReplacementText() async throws {
        for rejection in [IndexDroppedTextRejection.tooLarge, .invalidEncoding, .unreadable, .notRegularFile] {
            let (window, view) = makeEditor()
            view.string = "existing draft"
            let reader = IndexDroppedTextFile(view: view, outcomeReader: { _ in .rejected(rejection) })
            reader.start(url: URL(fileURLWithPath: "/fixture")) { view.string = $0 }
            try await waitUntil { reader.rejection != nil }
            #expect(reader.rejection == rejection)
            #expect(view.string == "existing draft")
            #expect(view.window === window)
            reader.dismissRejection()
            #expect(reader.rejection == nil)
        }
    }

    @Test func typedCancellationKeepsDraftAndDiagnosticQuiet() async throws {
        let (window, view) = makeEditor()
        view.string = "existing draft"
        let returned = DropReadSignal()
        let reader = IndexDroppedTextFile(view: view, outcomeReader: { _ in
            await returned.signal()
            return .cancelled
        })
        reader.start(url: URL(fileURLWithPath: "/fixture")) { view.string = $0 }
        await returned.wait()
        try await Task.sleep(for: .milliseconds(30))
        #expect(reader.rejection == nil)
        #expect(view.string == "existing draft")
        #expect(view.window === window)
    }

    @Test func realBoundedReaderDistinguishesOversizedAndInvalidTextFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("XToolsImportRegression-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oversized = directory.appendingPathComponent("oversized.txt")
        #expect(FileManager.default.createFile(atPath: oversized.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(IndexDroppedTextRejection.maximumBytes + 1))
        try handle.close()
        if case .rejected(let rejection) = IndexCaretTextView.readDroppedOutcome(from: oversized) {
            #expect(rejection == .tooLarge)
        } else { Issue.record("Expected bounded file rejection") }
        let malformed = directory.appendingPathComponent("malformed.txt")
        try Data([0xC3]).write(to: malformed)
        if case .rejected(let rejection) = IndexCaretTextView.readDroppedOutcome(from: malformed) {
            #expect(rejection == .invalidEncoding)
        } else { Issue.record("Expected text encoding rejection") }
        #expect(IndexCaretTextView.decodeDroppedContent(Data([0xFF, 0xFE, 0x61, 0x00, 0xFF])) == nil)
    }

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

}

private typealias DropReadSignal = TestAsyncSignal
