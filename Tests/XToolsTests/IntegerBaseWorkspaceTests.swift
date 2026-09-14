@testable import XTools
import XToolsCore
import Foundation
import Testing

struct IntegerBaseWorkspaceTests {
    @MainActor
    @Test func shortInputRendersExactlyOnceAndPublishesOneCoherentResult() {
        let counter = LockedCallCounter()
        let model = makeModel(
            synchronousDigitLimit: 128,
            renderer: { prepared in
                counter.increment()
                return IntegerBaseConverter.conversions(from: prepared)
            }
        )

        model.input = "255"

        #expect(counter.value == 1)
        #expect(model.conversions?.decimal == "255")
        #expect(model.conversions?.hex == "FF")
        #expect(model.error == nil)
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func inputAtSynchronousBoundaryRendersImmediately() {
        let counter = LockedCallCounter()
        let expected = IntegerBaseConverter.Conversions(
            binary: "sync",
            octal: "sync",
            decimal: "sync",
            hex: "sync"
        )
        let model = makeModel(
            synchronousDigitLimit: 128,
            renderer: { prepared in
                #expect(prepared.digitCount == 128)
                counter.increment()
                return expected
            }
        )

        model.input = String(repeating: "1", count: 128)

        #expect(counter.value == 1)
        #expect(model.conversions == expected)
        #expect(!model.isProcessing)
        #expect(model.error == nil)
    }

    @MainActor
    @Test func inputAboveSynchronousBoundaryUsesBackgroundExecution() async {
        let counter = LockedCallCounter()
        let expected = IntegerBaseConverter.Conversions(
            binary: "background",
            octal: "background",
            decimal: "background",
            hex: "background"
        )
        let model = makeModel(
            synchronousDigitLimit: 128,
            backgroundDebounce: .zero,
            backgroundRenderer: { prepared in
                #expect(prepared.digitCount == 129)
                counter.increment()
                return expected
            }
        )

        model.input = String(repeating: "1", count: 129)

        #expect(model.isProcessing)
        #expect(model.conversions == nil)
        await waitUntil { model.conversions == expected }

        #expect(counter.value == 1)
        #expect(!model.isProcessing)
        #expect(model.error == nil)
    }

    @MainActor
    @Test func maximumSupportedInputUsesBackgroundExecution() async {
        let counter = LockedCallCounter()
        let expected = IntegerBaseConverter.Conversions(
            binary: "maximum",
            octal: "maximum",
            decimal: "maximum",
            hex: "maximum"
        )
        let model = makeModel(
            synchronousDigitLimit: 128,
            backgroundDebounce: .zero,
            backgroundRenderer: { prepared in
                #expect(prepared.digitCount == IntegerBaseConverter.maximumInputDigitCount)
                counter.increment()
                return expected
            }
        )

        model.input = String(repeating: "1", count: IntegerBaseConverter.maximumInputDigitCount)

        #expect(model.isProcessing)
        await waitUntil { model.conversions == expected }

        #expect(counter.value == 1)
        #expect(!model.isProcessing)
        #expect(model.error == nil)
    }

    @MainActor
    @Test func longInputUsesBackgroundStateAndPublishesWhenCurrent() async {
        let model = makeModel(
            synchronousDigitLimit: 2,
            backgroundDebounce: .zero,
            backgroundRenderer: { prepared in
                await Task.yield()
                return IntegerBaseConverter.conversions(from: prepared)
            }
        )

        model.input = "255"

        #expect(model.isProcessing)
        #expect(model.conversions == nil)
        #expect(model.error == nil)

        await waitUntil { model.conversions?.decimal == "255" }

        #expect(!model.isProcessing)
        #expect(model.conversions?.hex == "FF")
        #expect(model.error == nil)
    }

    @MainActor
    @Test func staleBackgroundCompletionCannotReplaceNewerInput() async {
        let gate = IntegerBaseConversionGate()
        let model = makeModel(
            synchronousDigitLimit: 2,
            backgroundDebounce: .zero,
            backgroundRenderer: { prepared in
                await gate.wait(for: prepared.digitCount)
            }
        )

        model.input = "111"
        await gate.waitForRequest(digitCount: 3)

        model.input = "1111"
        await gate.waitForRequest(digitCount: 4)

        await gate.resume(
            digitCount: 3,
            with: .init(binary: "old", octal: "old", decimal: "old", hex: "old")
        )
        await Task.yield()

        #expect(model.isProcessing)
        #expect(model.conversions == nil)

        await gate.resume(
            digitCount: 4,
            with: .init(binary: "1111", octal: "17", decimal: "15", hex: "F")
        )
        await waitUntil { model.conversions?.decimal == "15" }

        #expect(!model.isProcessing)
        #expect(model.conversions?.hex == "F")
    }

    @MainActor
    @Test func clearInvalidatesPendingWorkAndRestoresEmptyState() async {
        let gate = IntegerBaseConversionGate()
        let model = makeModel(
            synchronousDigitLimit: 2,
            backgroundDebounce: .zero,
            backgroundRenderer: { prepared in
                await gate.wait(for: prepared.digitCount)
            }
        )

        model.input = "111"
        await gate.waitForRequest(digitCount: 3)

        model.clear()

        #expect(model.input.isEmpty)
        #expect(model.conversions == nil)
        #expect(model.error == nil)
        #expect(!model.isProcessing)

        await gate.resume(
            digitCount: 3,
            with: .init(binary: "old", octal: "old", decimal: "old", hex: "old")
        )
        await Task.yield()

        #expect(model.conversions == nil)
        #expect(!model.isProcessing)
    }

    @MainActor
    @Test func inputAboveMaximumFailsWithoutStartingBackgroundWork() async {
        let counter = LockedCallCounter()
        let model = makeModel(
            synchronousDigitLimit: 2,
            backgroundDebounce: .zero,
            backgroundRenderer: { prepared in
                counter.increment()
                return IntegerBaseConverter.conversions(from: prepared)
            }
        )

        model.input = String(repeating: "1", count: IntegerBaseConverter.maximumInputDigitCount + 1)
        await Task.yield()

        #expect(counter.value == 0)
        #expect(model.conversions == nil)
        #expect(!model.isProcessing)
        #expect(model.error == "输入数值最多支持 4096 位数字。")
    }

    @MainActor
    @Test func baseChangeInvalidatesPendingWorkAndRevalidatesCurrentInput() async {
        let gate = IntegerBaseConversionGate()
        let model = makeModel(
            synchronousDigitLimit: 2,
            backgroundDebounce: .zero,
            backgroundRenderer: { prepared in
                await gate.wait(for: prepared.digitCount)
            }
        )

        model.input = "111"
        await gate.waitForRequest(digitCount: 3)

        model.base = "2"
        await gate.waitForRequestCount(2, digitCount: 3)

        await gate.resumeFirst(
            digitCount: 3,
            with: .init(binary: "old", octal: "old", decimal: "old", hex: "old")
        )
        await Task.yield()
        #expect(model.conversions == nil)

        await gate.resumeFirst(
            digitCount: 3,
            with: .init(binary: "111", octal: "7", decimal: "7", hex: "7")
        )
        await waitUntil { model.conversions?.decimal == "7" }

        #expect(model.conversions?.binary == "111")
        #expect(model.error == nil)
    }

    @MainActor
    private func makeModel(
        synchronousDigitLimit: Int,
        backgroundDebounce: Duration = .milliseconds(180),
        renderer: @escaping IntegerBasePreparedRenderer = IntegerBaseConverter.conversions(from:),
        backgroundRenderer: IntegerBaseBackgroundRenderer? = nil
    ) -> IntegerBaseToolWorkspaceModel {
        let suiteName = "IntegerBaseWorkspaceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return IntegerBaseToolWorkspaceModel(
            preferences: ToolPreferenceStore(defaults: defaults),
            synchronousDigitLimit: synchronousDigitLimit,
            backgroundDebounce: backgroundDebounce,
            renderer: renderer,
            backgroundRenderer: backgroundRenderer
        )
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(20),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(condition())
    }
}

private final class LockedCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private actor IntegerBaseConversionGate {
    private var continuations: [Int: [CheckedContinuation<IntegerBaseConverter.Conversions, Never>]] = [:]
    private var requestCounts: [Int: Int] = [:]

    func wait(for digitCount: Int) async -> IntegerBaseConverter.Conversions {
        requestCounts[digitCount, default: 0] += 1
        return await withCheckedContinuation { continuation in
            continuations[digitCount, default: []].append(continuation)
        }
    }

    func waitForRequest(digitCount: Int) async {
        await waitForRequestCount(1, digitCount: digitCount)
    }

    func waitForRequestCount(_ expected: Int, digitCount: Int) async {
        while requestCounts[digitCount, default: 0] < expected {
            await Task.yield()
        }
    }

    func resume(
        digitCount: Int,
        with result: IntegerBaseConverter.Conversions
    ) {
        let pending = continuations.removeValue(forKey: digitCount) ?? []
        for continuation in pending {
            continuation.resume(returning: result)
        }
    }

    func resumeFirst(
        digitCount: Int,
        with result: IntegerBaseConverter.Conversions
    ) {
        guard var pending = continuations[digitCount], !pending.isEmpty else { return }
        let continuation = pending.removeFirst()
        continuations[digitCount] = pending
        continuation.resume(returning: result)
    }
}
