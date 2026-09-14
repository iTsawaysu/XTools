@testable import XTools
import Testing

struct ResultPresenceStateTests {
    @Test func completionUsesActionSpecificDurationsAndExitIsShorter() {
        let appearance = IndexResultPresenceCompletion.appearance(generation: 1)
        let exit = IndexResultPresenceCompletion.exit(generation: 2)

        #expect(appearance.duration == ToolMotion.ResultPresence.appearanceDuration)
        #expect(exit.duration == ToolMotion.ResultPresence.exitDuration)
        #expect(exit.duration < appearance.duration)
    }

    @Test func initialEmptyMountsWithoutStartingAPresentationLifecycle() {
        let state = IndexResultPresenceState<String>(initialValue: nil)

        #expect(state.phase == .empty)
        #expect(state.snapshot == nil)
        #expect(state.generation == 0)
    }

    @Test func initialResultMountsPresentedWithoutAppearanceLifecycle() {
        let state = IndexResultPresenceState(initialValue: "seed")

        #expect(state.phase == .presented)
        #expect(state.snapshot == "seed")
        #expect(state.generation == 0)
    }

    @Test func firstDelayedResultCanSettleImmediatelyWithoutDisablingLaterAppearance() {
        var state = IndexResultPresenceState<String>(initialValue: nil)

        #expect(
            state.update(
                to: "automatic-seed",
                reduceMotion: false,
                firstAppearance: .immediate
            ) == .settle
        )
        #expect(state.phase == .presented)
        #expect(state.snapshot == "automatic-seed")
        #expect(state.generation == 1)

        #expect(
            state.update(
                to: nil,
                reduceMotion: false,
                firstAppearance: .immediate
            ) == .exit(generation: 2)
        )
        let exitFinished = state.finish(.exit(generation: 2))
        #expect(exitFinished)

        #expect(
            state.update(
                to: "explicit-regeneration",
                reduceMotion: false,
                firstAppearance: .immediate
            ) == .appear(generation: 3, fadesIn: true)
        )
        #expect(state.phase == .appearing)
        #expect(state.snapshot == "explicit-regeneration")
    }

    @Test func generatedResultValueMotionStopsAfterTheFirstEightSlots() {
        #expect(indexGeneratedResultValueMotion(index: 0, limit: 8) == .textSwap)
        #expect(indexGeneratedResultValueMotion(index: 7, limit: 8) == .textSwap)
        #expect(indexGeneratedResultValueMotion(index: 8, limit: 8) == .immediate)
        #expect(indexGeneratedResultValueMotion(index: 49, limit: 8) == .immediate)
        #expect(indexGeneratedResultValueMotion(index: 0, limit: 0) == .immediate)
    }

    @Test func exitRetainsSnapshotUntilTheMatchingCompletion() {
        var state = IndexResultPresenceState(initialValue: "result")

        #expect(state.update(to: nil, reduceMotion: false) == .exit(generation: 1))
        #expect(state.phase == .exiting)
        #expect(state.snapshot == "result")

        let staleCompletionAccepted = state.finish(.exit(generation: 0))
        #expect(!staleCompletionAccepted)
        #expect(state.phase == .exiting)
        #expect(state.snapshot == "result")

        let matchingCompletionAccepted = state.finish(.exit(generation: 1))
        #expect(matchingCompletionAccepted)
        #expect(state.phase == .empty)
        #expect(state.snapshot == nil)
    }

    @Test func reversingAnExitInvalidatesItsFinalizerAndKeepsTheNewResult() {
        var state = IndexResultPresenceState(initialValue: "old")

        #expect(state.update(to: nil, reduceMotion: false) == .exit(generation: 1))
        #expect(state.update(to: "new", reduceMotion: false) == .appear(generation: 2, fadesIn: false))
        #expect(state.phase == .appearing)
        #expect(state.snapshot == "new")

        let staleExitAccepted = state.finish(.exit(generation: 1))
        #expect(!staleExitAccepted)
        #expect(state.phase == .appearing)
        #expect(state.snapshot == "new")

        let matchingAppearanceAccepted = state.finish(.appearance(generation: 2))
        #expect(matchingAppearanceAccepted)
        #expect(state.phase == .presented)
        #expect(state.snapshot == "new")
    }

    @Test func clearingDuringAppearanceInvalidatesTheAppearanceFinalizer() {
        var state = IndexResultPresenceState<String>(initialValue: nil)

        #expect(state.update(to: "result", reduceMotion: false) == .appear(generation: 1, fadesIn: true))
        #expect(state.update(to: nil, reduceMotion: false) == .exit(generation: 2))
        #expect(state.phase == .exiting)
        #expect(state.snapshot == "result")

        let staleAppearanceAccepted = state.finish(.appearance(generation: 1))
        #expect(!staleAppearanceAccepted)
        #expect(state.phase == .exiting)

        let matchingExitAccepted = state.finish(.exit(generation: 2))
        #expect(matchingExitAccepted)
        #expect(state.phase == .empty)
        #expect(state.snapshot == nil)
    }

    @Test func nonemptyUpdatesStayPresentedWithoutRestartingPresenceMotion() {
        var state = IndexResultPresenceState(initialValue: "first")

        #expect(state.update(to: "second", reduceMotion: false) == .update)
        #expect(state.phase == .presented)
        #expect(state.snapshot == "second")
        #expect(state.generation == 0)
    }

    @Test func reduceMotionSettlesImmediatelyAndCancelsPendingPresentation() {
        var state = IndexResultPresenceState<String>(initialValue: nil)

        #expect(state.update(to: "result", reduceMotion: true) == .settle)
        #expect(state.phase == .presented)
        #expect(state.snapshot == "result")
        #expect(state.generation == 1)

        #expect(state.update(to: nil, reduceMotion: true) == .settle)
        #expect(state.phase == .empty)
        #expect(state.snapshot == nil)
        #expect(state.generation == 2)
    }
}
