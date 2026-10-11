import AppKit
import SwiftUI
import Testing
@testable import XTools
import XToolsCore

@Suite(.serialized)
@MainActor
struct ToolPageStageModelTests {
    @Test func initialState() {
        let model = ToolPageStageModel()
        #expect(model.mounted.isEmpty)
        #expect(model.parked.isEmpty)
        #expect(model.displayed == nil)
        #expect(model.generation == 1)
        #expect(model.pendingArrivals.isEmpty)
    }

    @Test func swapImmediatelyClearsParkedAndSetsDisplayed() {
        let model = ToolPageStageModel()
        let key1 = ToolPageKey.tool(ToolID("tool1"))
        let key2 = ToolPageKey.tool(ToolID("tool2"))

        model.swapImmediately(to: key1)
        #expect(model.mounted == [key1])
        #expect(model.displayed == key1)
        #expect(model.parked.isEmpty)
        #expect(model.generation == 2)

        model.depart(key1)
        #expect(model.parked.contains(key1))

        model.swapImmediately(to: key2)
        #expect(model.mounted == [key2])
        #expect(model.displayed == key2)
        #expect(model.parked.isEmpty)
        #expect(!model.isParked(key1))
    }

    @Test func departureAndArrivalKeepAliveCycle() {
        let model = ToolPageStageModel()
        let key1 = ToolPageKey.tool(ToolID("tool1"))
        let key2 = ToolPageKey.tool(ToolID("tool2"))

        model.arrive(key1)
        #expect(model.mounted == [key1])
        #expect(model.displayed == key1)
        #expect(!model.isParked(key1))

        // Key1 departs
        model.depart(key1)
        #expect(model.displayed == nil)
        #expect(model.isParked(key1))
        #expect(model.mounted == [key1])

        // Key2 arrives
        model.arrive(key2)
        #expect(model.mounted.contains(key1))
        #expect(model.mounted.contains(key2))
        #expect(model.displayed == key2)
        #expect(model.isParked(key1))
        #expect(!model.isParked(key2))

        // Key1 revisited: the start pose survives until this generation is mounted.
        model.depart(key2)
        model.arrive(key1)
        #expect(model.pendingArrivals.contains(key1))
        model.finishArrival(key1, generation: model.generation)
        #expect(model.displayed == key1)
        #expect(!model.isParked(key1))
        #expect(!model.pendingArrivals.contains(key1))
        #expect(model.isParked(key2))
    }

    @Test func boundedLruEvictionEnforcesParkedCapacity() {
        let model = ToolPageStageModel()
        let key1 = ToolPageKey.tool(ToolID("tool1"))
        let key2 = ToolPageKey.tool(ToolID("tool2"))
        let key3 = ToolPageKey.tool(ToolID("tool3"))
        let key4 = ToolPageKey.tool(ToolID("tool4"))
        let key5 = ToolPageKey.tool(ToolID("tool5"))

        // Navigate 1 -> 2 -> 3 -> 4
        model.arrive(key1)
        model.depart(key1)

        model.arrive(key2)
        model.depart(key2)

        model.arrive(key3)
        model.depart(key3)

        // Currently parked: 1, 2, 3 (count = 3 == parkedCapacity)
        #expect(model.parked.count == 3)
        model.evictOverflow()
        #expect(model.parked.count == 3)

        // Key4 arrives and departs -> parked: 1, 2, 3, 4 (count = 4 > 3)
        model.arrive(key4)
        model.depart(key4)
        #expect(model.parked.count == 4)

        // Evict overflow -> oldest parked (key1) should be evicted
        model.evictOverflow()
        #expect(model.parked.count == ToolPageStageModel.parkedCapacity)
        #expect(!model.mounted.contains(key1))
        #expect(!model.isParked(key1))
        #expect(model.parked.contains(key2))
        #expect(model.parked.contains(key3))
        #expect(model.parked.contains(key4))

        // Navigate to 5 -> departs -> evict
        model.arrive(key5)
        model.depart(key5)
        model.evictOverflow()

        #expect(model.parked.count == ToolPageStageModel.parkedCapacity)
        #expect(!model.mounted.contains(key2)) // oldest (key2) evicted
        #expect(model.parked.contains(key3))
        #expect(model.parked.contains(key4))
        #expect(model.parked.contains(key5))
    }

    @Test func entryGenerationDrivesRevisitFocusInCoordinators() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let container = NSView(frame: window.contentLayoutRect)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 150, height: 100))
        let other = NSTextView(frame: NSRect(x: 160, y: 0, width: 150, height: 100))
        container.addSubview(textView)
        container.addSubview(other)
        window.contentView = container
        window.orderFront(nil)
        defer { window.close() }

        var text = ""
        var height: CGFloat = 100
        let undoableCoordinator = IndexUndoableTextView.Coordinator(
            text: Binding(get: { text }, set: { text = $0 }),
            measuredHeight: Binding(get: { height }, set: { height = $0 }),
            growsWithContent: false,
            inputPolicy: nil
        )
        let textKit2Coordinator = IndexTextKit2ViewportTextView.Coordinator(
            text: Binding(get: { text }, set: { text = $0 }), inputPolicy: nil
        )
        let focusActions: [(Int) -> Void] = [
            { undoableCoordinator.focus(textView, entryGeneration: $0) },
            { textKit2Coordinator.focus(textView, entryGeneration: $0) }
        ]
        for focus in focusActions {
            try #require(window.makeFirstResponder(other))
            focus(0)
            await drainFocusQueue()
            #expect(window.firstResponder === other)

            // Navigation away before queued focus executes must invalidate it.
            focus(2)
            focus(0)
            await drainFocusQueue()
            #expect(window.firstResponder === other)

            focus(3)
            await drainFocusQueue()
            #expect(window.firstResponder === textView)
            try #require(window.makeFirstResponder(other))
            focus(3)
            await drainFocusQueue()
            #expect(window.firstResponder === other)

            focus(4)
            await drainFocusQueue()
            #expect(window.firstResponder === textView)
            focus(0)
            await drainFocusQueue()
            #expect(window.firstResponder !== textView)
        }
    }

    @Test func singleLineEntryFocusCannotOutliveItsActiveGeneration() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let container = NSView(frame: window.contentLayoutRect)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 150, height: 24))
        let other = NSTextView(frame: NSRect(x: 0, y: 40, width: 150, height: 100))
        container.addSubview(field)
        container.addSubview(other)
        window.contentView = container
        window.orderFront(nil)
        defer { window.close() }
        let coordinator = IndexUndoableTextField.Coordinator(
            text: .constant(""), allowsCopy: true, selectAllOnFocus: false,
            onSubmit: nil, onEscape: nil, onFocusChange: nil
        )
        func focus(_ generation: Int) {
            coordinator.focus(field, entryGeneration: generation, entryTraceContext: nil, placeholder: "")
        }
        try #require(window.makeFirstResponder(other))
        focus(2)
        focus(0)
        await drainFocusQueue()
        #expect(window.firstResponder === other)
        coordinator.requestFocus(field, token: 1)
        await drainFocusQueue()
        #expect(window.firstResponder === other)
        focus(3)
        await drainFocusQueue()
        try #require(field.currentEditor() != nil)
        #expect(window.firstResponder === field.currentEditor())
        try #require(window.makeFirstResponder(other))
        focus(3)
        await drainFocusQueue()
        #expect(window.firstResponder === other)
        focus(4)
        await drainFocusQueue()
        #expect(window.firstResponder === field.currentEditor())
        focus(0)
        await drainFocusQueue()
        #expect(field.currentEditor() == nil)
    }

    @Test func staleArrivalCompletionCannotFinishTheLatestEntry() {
        let model = ToolPageStageModel()
        let a = ToolPageKey.tool(ToolID("a"))
        let b = ToolPageKey.tool(ToolID("b"))
        model.swapImmediately(to: a)
        model.depart(a)
        model.arrive(b)
        let oldGeneration = model.generation
        model.depart(b)
        model.arrive(a)
        model.depart(a)
        model.arrive(b)
        model.finishArrival(b, generation: oldGeneration)
        #expect(model.pendingArrivals.contains(b))
        model.finishArrival(b, generation: model.generation)
        #expect(model.pendingArrivals.isEmpty)
        model.swapImmediately(to: a)
        model.finishArrival(b, generation: oldGeneration)
        #expect(model.displayed == a)
        #expect(model.pendingArrivals.isEmpty)
    }

    private func drainFocusQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test func rapidSwitchingMaintainsInvariants() {
        let model = ToolPageStageModel()
        let keys = (0..<10).map { ToolPageKey.tool(ToolID(rawValue: "tool\($0)")) }

        for i in 0..<50 {
            let nextKey = keys[i % keys.count]
            if let current = model.displayed {
                model.depart(current)
            }
            model.arrive(nextKey)
            #expect(model.pendingArrivals.contains(nextKey))
            model.finishArrival(nextKey, generation: model.generation)
            model.evictOverflow()

            #expect(model.displayed == nextKey)
            #expect(model.parked.count <= ToolPageStageModel.parkedCapacity)
            #expect(!model.isParked(nextKey))
            #expect(!model.pendingArrivals.contains(nextKey))
            #expect(model.mounted.contains(nextKey))
            #expect(model.mounted.count == model.parked.count + 1)
        }
    }
}
