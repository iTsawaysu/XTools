import XToolsCore
import Foundation
import Testing

struct ChronometerStateTests {
    @Test func capabilitiesFollowInitialRunningAndPausedStateMatrix() {
        var state = ChronometerState()

        #expect(!state.isRunning)
        #expect(!state.hasElapsed)
        #expect(!state.canRecordLap)
        #expect(!state.canReset)

        state.start(at: 10)

        #expect(state.isRunning)
        #expect(state.hasElapsed)
        #expect(state.canRecordLap)
        #expect(!state.canReset)

        state.pause(at: 12)

        #expect(!state.isRunning)
        #expect(state.hasElapsed)
        #expect(!state.canRecordLap)
        #expect(state.canReset)
    }

    @Test func startPauseResumeAndElapsedUseSuppliedMonotonicTime() {
        var state = ChronometerState()

        #expect(state.elapsed(at: 10) == 0)
        state.start(at: 10)
        #expect(state.isRunning)
        #expect(state.elapsed(at: 12.5) == 2.5)

        state.pause(at: 13)
        #expect(!state.isRunning)
        #expect(state.elapsed(at: 20) == 3)

        state.start(at: 20)
        #expect(state.elapsed(at: 22) == 5)
    }

    @Test func lapsStoreIntervalAndSplitNewestFirst() {
        var state = ChronometerState()

        state.start(at: 10)

        let first = ChronometerLap(interval: 2.25, split: 2.25)
        let second = ChronometerLap(interval: 2.25, split: 4.5)
        #expect(state.recordLap(at: 12.25) == first)
        #expect(state.recordLap(at: 14.5) == second)
        #expect(state.laps == [second, first])
    }

    @Test func lapCannotRecordInInitialOrPausedState() {
        var state = ChronometerState()

        #expect(state.recordLap(at: 10) == nil)
        state.start(at: 10)
        state.pause(at: 12)

        #expect(state.recordLap(at: 20) == nil)
        #expect(state.laps.isEmpty)
    }

    @Test func lapAfterResumeExcludesPausedDurationFromIntervalAndSplit() {
        var state = ChronometerState()

        state.start(at: 10)
        #expect(state.recordLap(at: 12) == ChronometerLap(interval: 2, split: 2))
        state.pause(at: 13)
        state.start(at: 20)

        let resumedLap = ChronometerLap(interval: 3, split: 5)
        #expect(state.recordLap(at: 22) == resumedLap)
        #expect(state.laps.first == resumedLap)
    }

    @Test func resetClearsPausedElapsedAndTypedLaps() {
        var state = ChronometerState()

        state.start(at: 10)
        _ = state.recordLap(at: 12)
        state.pause(at: 13)
        #expect(state.canReset)

        state.reset()

        #expect(!state.isRunning)
        #expect(!state.hasElapsed)
        #expect(!state.canReset)
        #expect(state.elapsed(at: 20) == 0)
        #expect(state.laps.isEmpty)
    }

    @Test func backwardsNowInputDoesNotCreateNegativeElapsedTime() {
        var state = ChronometerState()

        state.start(at: 10)

        #expect(state.elapsed(at: 9) == 0)
        state.pause(at: 9)
        #expect(state.elapsed(at: 20) == 0)
    }
}
