import AppKit
import SwiftUI
import Testing
@testable import XTools
import XToolsCore

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

        // Key1 revisited
        model.stageArrivalStart(key1)
        #expect(model.pendingArrivals.contains(key1))

        model.depart(key2)
        model.arrive(key1)
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

    @Test func entryGenerationDrivesRevisitFocusInCoordinators() {
        let textView = NSTextView()
        var text = ""
        var height: CGFloat = 100
        let undoableCoordinator = IndexUndoableTextView.Coordinator(
            text: Binding(get: { text }, set: { text = $0 }),
            measuredHeight: Binding(get: { height }, set: { height = $0 }),
            growsWithContent: false,
            inputPolicy: nil
        )

        // Parked page (entryGeneration == 0) ignores focus
        undoableCoordinator.focus(textView, entryGeneration: 0)

        // Page arrival (generation == 2) triggers focus
        undoableCoordinator.focus(textView, entryGeneration: 2)

        // Redundant updateNSView calls in same generation do not re-trigger
        undoableCoordinator.focus(textView, entryGeneration: 2)

        // Revisit in next generation (generation == 3) triggers focus again
        undoableCoordinator.focus(textView, entryGeneration: 3)

        let textKit2Coordinator = IndexTextKit2ViewportTextView.Coordinator(
            text: Binding(get: { text }, set: { text = $0 }),
            inputPolicy: nil
        )
        textKit2Coordinator.focus(textView, entryGeneration: 0)
        textKit2Coordinator.focus(textView, entryGeneration: 2)
        textKit2Coordinator.focus(textView, entryGeneration: 2)
        textKit2Coordinator.focus(textView, entryGeneration: 3)
    }

    @Test func rapidSwitchingMaintainsInvariants() {
        let model = ToolPageStageModel()
        let keys = (0..<10).map { ToolPageKey.tool(ToolID(rawValue: "tool\($0)")) }

        for i in 0..<50 {
            let nextKey = keys[i % keys.count]
            if let current = model.displayed {
                model.depart(current)
            }
            if model.isParked(nextKey) {
                model.stageArrivalStart(nextKey)
            }
            model.arrive(nextKey)
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
