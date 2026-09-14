import XToolsCore
import Foundation
import Testing

@Suite("SupersedingDetachedWorker")
struct SupersedingDetachedWorkerTests {
    @Test
    func publishesLatestGenerationResult() async {
        let worker = SupersedingDetachedWorker(cancelInFlight: true)
        let box = ResultBox<String>()

        await worker.submit(
            generation: 1,
            operation: { _ in "first" },
            completion: { generation, output in
                await box.set("\(generation):\(output)")
            }
        )

        #expect(await box.value == "1:first")
    }

    @Test
    func dropsSupersededInFlightWhenCancelEnabled() async {
        let worker = SupersedingDetachedWorker(cancelInFlight: true)
        let box = ResultBox<String>()
        let started = Expectation()

        async let first: Void = worker.submit(
            generation: 1,
            operation: { shouldCancel in
                Task { await started.fulfill() }
                while !shouldCancel() {
                    Thread.sleep(forTimeInterval: 0.005)
                }
                throw CancellationError()
            },
            completion: { _, _ in
                await box.set("stale")
            }
        )

        await started.wait()
        await worker.invalidate(before: 2)

        await worker.submit(
            generation: 2,
            operation: { _ in "current" },
            completion: { generation, output in
                await box.set("\(generation):\(output)")
            }
        )

        await first
        #expect(await box.value == "2:current")
    }

    @Test
    func cancelInFlightFalseKeepsRunningWorkButDropsPublish() async {
        let worker = SupersedingDetachedWorker(cancelInFlight: false)
        let box = ResultBox<String>()
        let entered = Expectation()
        let released = Expectation()

        async let running: Void = worker.submit(
            generation: 1,
            operation: { _ in
                Task { await entered.fulfill() }
                // Spin until release is signaled via a shared lock flag.
                while !released.isFulfilledSnapshot() {
                    Thread.sleep(forTimeInterval: 0.005)
                }
                return "late"
            },
            completion: { _, output in
                await box.set(output)
            }
        )

        await entered.wait()
        await worker.invalidate(before: 2)
        await released.fulfill()
        await running

        #expect(await box.value == nil)
    }

    @Test
    func mapsCancellationErrorToSkippedCompletion() async {
        let worker = SupersedingDetachedWorker(cancelInFlight: true)
        let box = ResultBox<String>()

        await worker.submit(
            generation: 1,
            operation: { _ in
                throw CancellationError()
            },
            completion: { _, output in
                await box.set(output)
            }
        )

        #expect(await box.value == nil)
    }
}

private actor ResultBox<Value: Sendable> {
    private(set) var value: Value?

    func set(_ value: Value) {
        self.value = value
    }
}

private final class Expectation: @unchecked Sendable {
    private let lock = NSLock()
    private var isFulfilled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func fulfill() async {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            isFulfilled = true
            let pending = self.waiters
            self.waiters = []
            return pending
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    func wait() async {
        let shouldWait: Bool = lock.withLock {
            if isFulfilled { return false }
            return true
        }
        guard shouldWait else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.withLock {
                if isFulfilled {
                    continuation.resume()
                } else {
                    waiters.append(continuation)
                }
            }
        }
    }

    func isFulfilledSnapshot() -> Bool {
        lock.withLock { isFulfilled }
    }
}
