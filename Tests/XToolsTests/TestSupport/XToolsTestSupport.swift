import Foundation
import Testing

public struct TestTimeoutError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String = "Timed out waiting for condition") {
        self.message = message
    }
    public var description: String { message }
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(20),
    interval: Duration = .milliseconds(10),
    _ condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now >= deadline {
            throw TestTimeoutError()
        }
        try await Task.sleep(for: interval)
    }
}

@MainActor
func waitUntilAssert(
    timeout: Duration = .seconds(20),
    condition: @escaping @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(condition())
}

actor TestAsyncGate<Input: Sendable, Output: Sendable> {
    private var openedOutput: Output?
    private var continuations: [CheckedContinuation<Output, Never>] = []
    private var recordedInputs: [Input] = []

    func awaitGate(input: Input) async -> Output {
        recordedInputs.append(input)
        if let output = openedOutput {
            return output
        }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open(with output: Output) {
        openedOutput = output
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: output)
        }
    }

    var inputs: [Input] {
        recordedInputs
    }

    var requestCount: Int {
        recordedInputs.count
    }

    func waitForRequests(count: Int, timeout: Duration = .seconds(20)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while recordedInputs.count < count, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

actor TestKeyedAsyncGate<Key: Hashable & Sendable, Value: Sendable> {
    private var continuations: [Key: [CheckedContinuation<Value, Never>]] = [:]
    private var requestCounts: [Key: Int] = [:]

    func awaitGate(_ key: Key) async -> Value {
        requestCounts[key, default: 0] += 1
        return await withCheckedContinuation { continuation in
            continuations[key, default: []].append(continuation)
        }
    }

    func execute(_ key: Key) async -> Value {
        await awaitGate(key)
    }

    func wait(for key: Key) async -> Value {
        await awaitGate(key)
    }

    func waitForRequest(_ key: Key, timeout: Duration = .seconds(20)) async {
        await waitForRequestCount(1, key: key, timeout: timeout)
    }

    func waitForRequest(digitCount: Key, timeout: Duration = .seconds(20)) async {
        await waitForRequestCount(1, key: digitCount, timeout: timeout)
    }

    func waitForRequestCount(_ expected: Int, key: Key, timeout: Duration = .seconds(20)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while requestCounts[key, default: 0] < expected, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        if requestCounts[key, default: 0] < expected {
            Issue.record("Timed out waiting for request count \(expected) with key: \(key)")
        }
    }

    func waitForRequestCount(_ expected: Int, digitCount: Key, timeout: Duration = .seconds(20)) async {
        await waitForRequestCount(expected, key: digitCount, timeout: timeout)
    }

    func resume(_ key: Key, with value: Value) {
        let pending = continuations.removeValue(forKey: key) ?? []
        for continuation in pending {
            continuation.resume(returning: value)
        }
    }

    func resume(for key: Key, with value: Value) {
        resume(key, with: value)
    }

    func resume(digitCount: Key, with value: Value) {
        resume(digitCount, with: value)
    }

    func resumeFirst(_ key: Key, with value: Value) {
        guard var pending = continuations[key], !pending.isEmpty else { return }
        let continuation = pending.removeFirst()
        continuations[key] = pending
        continuation.resume(returning: value)
    }

    func resumeFirst(digitCount: Key, with value: Value) {
        resumeFirst(digitCount, with: value)
    }
}

actor TestAsyncSignal {
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard !isSignalled else { return }
        isSignalled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    func wait() async {
        guard !isSignalled else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func wait(timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !isSignalled {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    func isSignalledSnapshot() -> Bool {
        isSignalled
    }
}

final class TestLockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    init(initialValue: Int = 0) {
        self._count = initialValue
    }

    @discardableResult
    func increment() -> Int {
        lock.withLock {
            _count += 1
            return _count
        }
    }

    func incrementAndRead() -> Int {
        increment()
    }

    var count: Int {
        get {
            lock.withLock { _count }
        }
        set {
            lock.withLock { _count = newValue }
        }
    }

    var value: Int {
        count
    }
}
