import Foundation
import Testing
@testable import XToolsCore

struct AsyncWorkGateTests {
    @MainActor
    @Test func invalidateAdvancesTokenAndDropsStaleSchedule() async {
        let gate = AsyncWorkGate()
        let first = gate.token
        var published = 0

        gate.schedule(debounce: .milliseconds(50)) {
            published += 1
        }
        let second = gate.invalidate()
        #expect(second != first)
        #expect(!gate.isCurrent(first))
        #expect(gate.isCurrent(second))

        // Wait well past the cancelled debounce window without publishing.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(published == 0)
    }

    @MainActor
    @Test func schedulePublishesOnlyForCurrentToken() async throws {
        let gate = AsyncWorkGate()
        var values: [Int] = []

        gate.schedule(debounce: .milliseconds(40)) {
            values.append(1)
        }
        // Stay well under the debounce so the first schedule never fires.
        try? await Task.sleep(for: .milliseconds(5))
        _ = gate.invalidate()
        gate.schedule(debounce: .milliseconds(40)) {
            values.append(2)
        }

        try await waitUntil { values == [2] }
        #expect(values == [2])
    }

    @MainActor
    @Test func runDetachedDropsStaleResults() async throws {
        let gate = AsyncWorkGate()
        var published: [Int] = []

        gate.runDetached {
            try? await Task.sleep(for: .milliseconds(80))
            return 1
        } publish: { value in
            published.append(value)
        }
        _ = gate.invalidate()
        gate.runDetached {
            return 2
        } publish: { value in
            published.append(value)
        }

        try await waitUntil { published == [2] }
        #expect(published == [2])
    }

    @MainActor
    @Test func replacingRunDetachedCancelsDetachedOperation() async throws {
        let gate = AsyncWorkGate()
        let firstStarted = AsyncWorkSignal()
        let firstCancelled = AsyncWorkSignal()
        let releaseFirst = AsyncWorkSignal()
        var published: [Int] = []

        gate.runDetached {
            await firstStarted.signal()
            return await withTaskCancellationHandler {
                await releaseFirst.wait()
                return 1
            } onCancel: {
                Task { await firstCancelled.signal() }
            }
        } publish: { value in
            published.append(value)
        }

        await firstStarted.wait()
        gate.runDetached {
            2
        } publish: { value in
            published.append(value)
        }

        let cancellationWasForwarded = await firstCancelled.wait(timeout: .seconds(1))
        await releaseFirst.signal()
        #expect(cancellationWasForwarded)
        try await waitUntil { published == [2] }
        #expect(published == [2])
    }

    @MainActor
    @Test func completedReplacementCannotClearNewerScheduleHandle() async throws {
        let gate = AsyncWorkGate()
        let firstStarted = AsyncWorkSignal()
        let releaseFirst = AsyncWorkSignal()
        let firstCompleted = AsyncWorkSignal()
        let secondStarted = AsyncWorkSignal()
        let secondCancelled = AsyncWorkSignal()
        let releaseSecond = AsyncWorkSignal()
        let secondFinished = AsyncWorkSignal()
        var published: [Int] = []

        gate.schedule {
            await firstStarted.signal()
            await releaseFirst.wait()
            Task { @MainActor in
                await firstCompleted.signal()
            }
        }
        await firstStarted.wait()

        gate.schedule {
            await secondStarted.signal()
            await releaseSecond.wait()
            if Task.isCancelled {
                await secondCancelled.signal()
            } else {
                published.append(2)
            }
            await secondFinished.signal()
        }
        await secondStarted.wait()
        await releaseFirst.signal()

        // The barrier cannot run until the first task has returned through the
        // gate's synchronous completion bookkeeping on the main actor.
        await firstCompleted.wait()
        gate.invalidate()
        await releaseSecond.signal()
        await secondFinished.wait()

        #expect(await secondCancelled.isSignalledSnapshot())
        #expect(published.isEmpty)
    }

    @MainActor
    @Test func invalidateCancelsDetachedOperation() async {
        let gate = AsyncWorkGate()
        let started = AsyncWorkSignal()
        let cancelled = AsyncWorkSignal()
        let release = AsyncWorkSignal()

        gate.runDetached {
            await started.signal()
            return await withTaskCancellationHandler {
                await release.wait()
                return 1
            } onCancel: {
                Task { await cancelled.signal() }
            }
        } publish: { _ in
            Issue.record("Invalidated detached work must not publish")
        }

        await started.wait()
        gate.invalidate()
        let cancellationWasForwarded = await cancelled.wait(timeout: .seconds(1))
        await release.signal()
        #expect(cancellationWasForwarded)
    }

    @MainActor
    @Test func deinitCancelsDetachedOperation() async {
        var gate: AsyncWorkGate? = AsyncWorkGate()
        let started = AsyncWorkSignal()
        let cancelled = AsyncWorkSignal()
        let release = AsyncWorkSignal()

        gate?.runDetached {
            await started.signal()
            return await withTaskCancellationHandler {
                await release.wait()
                return 1
            } onCancel: {
                Task { await cancelled.signal() }
            }
        } publish: { _ in
            Issue.record("Detached work owned by a deallocated gate must not publish")
        }

        await started.wait()
        gate = nil
        let cancellationWasForwarded = await cancelled.wait(timeout: .seconds(1))
        await release.signal()
        #expect(cancellationWasForwarded)
    }

    @MainActor
    @Test func invalidatingBeforeDetachedRequestStartsDoesNotCallOperation() async {
        let gate = AsyncWorkGate()
        let calls = AsyncWorkCounter()

        gate.runDetached {
            await calls.increment()
            return 1
        } publish: { _ in
            Issue.record("Invalidated detached work must not publish")
        }
        gate.invalidate()

        // Give the enqueued outer task multiple opportunities to observe that
        // it was invalidated before creating its detached worker.
        for _ in 0..<4 {
            await Task.yield()
        }
        #expect(await calls.value == 0)
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(20),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                Issue.record("Timed out waiting for AsyncWorkGate state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor AsyncWorkSignal {
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !isSignalled else { return }
        isSignalled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    func wait() async {
        guard !isSignalled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func wait(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !isSignalled {
            guard clock.now < deadline else {
                return false
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    func isSignalledSnapshot() -> Bool {
        isSignalled
    }
}

private actor AsyncWorkCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

struct ImageInspectProbeContractTests {
    @Test func inspectTransparencyProbeMaxPixelLengthIsBounded() {
        #expect(ImageProcessor.inspectTransparencyProbeMaxPixelLength == 2_048)
        #expect(ImageProcessor.inspectTransparencyProbeMaxPixelLength > 0)
    }
}
