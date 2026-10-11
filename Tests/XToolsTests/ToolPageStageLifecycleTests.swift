import AppKit
import SwiftUI
import Testing
@testable import XTools
import XToolsCore

@Suite(.serialized)
@MainActor
struct ToolPageStageLifecycleTests {
    private func waitForActive(_ key: String, recorder: StageTestRecorder) async throws {
        do {
            try await waitUntil(timeout: .seconds(3)) { recorder.activeKey == key }
        } catch {
            Issue.record("Stage expected active \(key); actual \(recorder.activeKey ?? "nil"); created \(recorder.creationCount); events \(recorder.events)")
            throw error
        }
    }

    @Test func parkedPageRetainsStateUntilLruEviction() async throws {
        try #require(!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                     "This lifecycle case requires the retained-page motion path")
        let selection = StageTestSelection()
        let recorder = StageTestRecorder()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: StageTestHost(
            selection: selection, recorder: recorder
        ))
        window.orderFront(nil)
        defer { window.close() }

        try await waitForActive("a", recorder: recorder)
        try await Task.sleep(for: .milliseconds(450))
        let original = try #require(recorder.latestIdentity["a"])

        recorder.activeKey = nil
        selection.key = "b"
        try await waitForActive("b", recorder: recorder)
        try await Task.sleep(for: .milliseconds(450))
        recorder.activeKey = nil
        selection.key = "a"
        try await waitForActive("a", recorder: recorder)
        try await Task.sleep(for: .milliseconds(450))

        #expect(recorder.latestIdentity["a"] == original,
                "A → B → A must reuse the parked page's StateObject")
        #expect(recorder.creationCount["a"] == 1)
        #expect(recorder.creationCount["b"] == 1)

        // Exceed the three parked-page slots, then prove this oracle can
        // distinguish a genuine eviction from an ordinary retained revisit.
        for key in ["b", "c", "d", "e"] {
            recorder.activeKey = nil
            selection.key = key
            try await waitForActive(key, recorder: recorder)
            try await Task.sleep(for: .milliseconds(450))
        }
        recorder.activeKey = nil
        selection.key = "a"
        try await waitForActive("a", recorder: recorder)
        try await Task.sleep(for: .milliseconds(450))
        #expect(recorder.latestIdentity["a"] != original)
    }

    @Test func rapidReversalKeepsBothPageIdentitiesAndLatestSelection() async throws {
        try #require(!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let selection = StageTestSelection()
        let recorder = StageTestRecorder()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: StageTestHost(selection: selection, recorder: recorder))
        window.orderFront(nil)
        defer { window.close() }
        try await waitForActive("a", recorder: recorder)
        let original = try #require(recorder.latestIdentity["a"])
        for key in ["b", "a", "b", "a", "b", "a"] {
            recorder.activeKey = nil
            selection.key = key
            try await waitForActive(key, recorder: recorder)
        }
        // This delay only lets stale navigation work surface; it is not a frame oracle.
        try await Task.sleep(for: .milliseconds(450))
        #expect(recorder.activeKey == "a")
        #expect(recorder.latestIdentity["a"] == original)
        #expect(recorder.creationCount["a"] == 1)
        #expect(recorder.creationCount["b"] == 1)
    }

    @Test func parkedKeyCaptureReleasesFocusAndRejectsLateRequests() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let container = NSView(frame: window.contentLayoutRect)
        let capture = KeyCaptureNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 152))
        let other = StageTestResponder(frame: NSRect(x: 170, y: 0, width: 100, height: 30))
        var listening = false
        var events = 0
        capture.isListening = Binding(get: { listening }, set: { listening = $0 })
        capture.onEvent = { _ in events += 1 }
        container.addSubview(capture)
        container.addSubview(other)
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        capture.setActive(true)
        try #require(window.makeFirstResponder(capture))
        #expect(listening)
        capture.requestInitialFocus(token: 1)
        capture.setActive(false)
        #expect(!listening)
        #expect(window.firstResponder !== capture)
        #expect(!capture.acceptsFirstResponder)
        #expect(!capture.accessibilityPerformPress())
        try #require(window.makeFirstResponder(other))
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "a",
            charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        ))
        capture.keyDown(with: event)
        capture.flagsChanged(with: event)
        capture.requestInitialFocus(token: 2)
        // Pass both bounded retry deadlines from the departed request.
        try await Task.sleep(for: .milliseconds(350))
        #expect(window.firstResponder === other)
        #expect(events == 0)
        capture.setActive(true)
        #expect(capture.accessibilityPerformPress())
        #expect(listening)
        capture.keyDown(with: event)
        #expect(events == 1)
    }

    @Test func diffShortcutsUseRealArrowCharactersAndOnlyTheActiveHost() throws {
        let host = IndexEditableDiffScrollHostView()
        var directions: [Bool] = []
        host.onNavigateDifference = { directions.append($0) }
        func key(_ characters: String, modifiers: NSEvent.ModifierFlags = [.option, .command]) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0
            ))
        }
        #expect(host.performKeyEquivalent(with: try key("\u{F701}")))
        #expect(host.performKeyEquivalent(with: try key("\u{F700}")))
        #expect(directions == [true, false])
        #expect(!host.performKeyEquivalent(with: try key("63233")))
        #expect(!host.performKeyEquivalent(with: try key("\u{F701}", modifiers: .command)))
        host.isPageActive = false
        #expect(!host.performKeyEquivalent(with: try key("\u{F701}")))
        #expect(!host.performKeyEquivalent(with: try key("\u{F700}")))
        #expect(directions == [true, false])
    }

    @Test func retainedFormatWorkbenchShortcutsFollowTheActivePage() async throws {
        let selection = StageTestSelection()
        let recorder = StageTestRecorder()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: StageShortcutTestHost(selection: selection, recorder: recorder))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let commandReturn = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))
        for key in ["a", "b", "a", "b"] {
            selection.key = key
            try await waitForActive(key, recorder: recorder)
            window.contentView?.layoutSubtreeIfNeeded()
            let previous = recorder.actionCount
            #expect(window.performKeyEquivalent(with: commandReturn))
            #expect(recorder.actionCount[key, default: 0] == previous[key, default: 0] + 1)
            let hidden = key == "a" ? "b" : "a"
            #expect(recorder.actionCount[hidden, default: 0] == previous[hidden, default: 0])
        }
    }
}

@MainActor
private final class StageTestResponder: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
private final class StageTestSelection: ObservableObject {
    @Published var key = "a"
}

@MainActor
private final class StageTestRecorder {
    var activeKey: String?
    var latestIdentity: [String: UUID] = [:]
    var creationCount: [String: Int] = [:]
    var actionCount: [String: Int] = [:]
    var events: [String] = []
}

@MainActor
private struct StageShortcutTestHost: View {
    @ObservedObject var selection: StageTestSelection
    let recorder: StageTestRecorder

    var body: some View {
        ToolPageStage(target: .tool(ToolID(rawValue: selection.key))) { key in
            if case .tool(let id) = key.payload {
                StageShortcutTestPage(key: id.rawValue, recorder: recorder)
            }
        }
    }
}

@MainActor
private struct StageShortcutTestPage: View {
    let key: String
    let recorder: StageTestRecorder
    @Environment(\.toolPageEntryGeneration) private var generation

    var body: some View {
        IndexFormatWorkbench<EmptyView, EmptyView, EmptyView>(
            inputTitle: key, outputTitle: "Output", input: .constant("input"), output: "",
            autoFocus: false,
            onFormat: { recorder.actionCount[key, default: 0] += 1 },
            onClear: {}, leadingControl: { EmptyView() }
        )
        .onAppear { recordActivity(generation: generation) }
        .onChange(of: generation) { _, newValue in
            recorder.events.append("\(key): changed \(newValue), captured \(generation)")
            recordActivity(generation: newValue)
        }
    }

    private func recordActivity(generation: Int) {
        recorder.events.append("\(key): generation \(generation)")
        if generation > 0 { recorder.activeKey = key }
    }
}

@MainActor
private final class StageTestIdentity: ObservableObject {
    let id = UUID()

    init(key: String, recorder: StageTestRecorder) {
        recorder.creationCount[key, default: 0] += 1
    }
}

@MainActor
private struct StageTestHost: View {
    @ObservedObject var selection: StageTestSelection
    let recorder: StageTestRecorder

    var body: some View {
        ToolPageStage(target: .tool(ToolID(rawValue: selection.key))) { pageKey in
            if case .tool(let id) = pageKey.payload {
                StageTestPage(key: id.rawValue, recorder: recorder)
            }
        }
    }
}

@MainActor
private struct StageTestPage: View {
    let key: String
    let recorder: StageTestRecorder
    @StateObject private var identity: StageTestIdentity
    @Environment(\.toolPageEntryGeneration) private var generation

    init(key: String, recorder: StageTestRecorder) {
        self.key = key
        self.recorder = recorder
        _identity = StateObject(wrappedValue: StageTestIdentity(key: key, recorder: recorder))
    }

    var body: some View {
        Text("\(key): \(identity.id)")
            .onAppear { recordActivePage(generation: generation) }
            .onChange(of: generation) { _, newValue in
                recorder.events.append("\(key): changed \(newValue), captured \(generation)")
                recordActivePage(generation: newValue)
            }
    }

    private func recordActivePage(generation: Int) {
        recorder.events.append("\(key): generation \(generation)")
        guard generation > 0 else { return }
        recorder.latestIdentity[key] = identity.id
        recorder.activeKey = key
    }
}
