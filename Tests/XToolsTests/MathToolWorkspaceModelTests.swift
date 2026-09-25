import Combine
import Foundation
import Testing
import XToolsCore
@testable import XTools

@MainActor
struct MathToolWorkspaceModelTests {
    @Test func shortInputPublishesImmediatelyAndLongInputRunsOffMainThread() async {
        let probe = MathBackgroundProbe()
        let workspace = MathToolWorkspaceModel(
            backgroundEvaluation: { input, shouldCancel in
                try probe.evaluate(input, shouldCancel: shouldCancel)
            },
            debounce: .zero,
            synchronousUTF8ByteLimit: 4
        )

        workspace.expression = "2+3"
        #expect(workspace.evaluation == .valid("5"))
        #expect(!workspace.isEvaluating)
        #expect(probe.callCount == 0)

        workspace.expression = "latest-long-input"
        #expect(workspace.evaluation == .empty)
        #expect(workspace.isEvaluating)
        #expect(await Self.wait(for: workspace, until: .valid("latest")))

        #expect(workspace.evaluation == .valid("latest"))
        #expect(!workspace.isEvaluating)
        #expect(!probe.ranOnMainThread)
    }

    @Test func newInputCancelsOldEvaluationAndClearInvalidatesPendingWork() async {
        let probe = MathBackgroundProbe()
        let workspace = MathToolWorkspaceModel(
            backgroundEvaluation: { input, shouldCancel in
                try probe.evaluate(input, shouldCancel: shouldCancel)
            },
            debounce: .zero,
            synchronousUTF8ByteLimit: 4
        )

        workspace.expression = "first-long-input"
        #expect(await Self.wait(for: probe.firstStarted))
        workspace.expression = "latest-long-input"
        #expect(await Self.wait(for: probe.firstCancelled))
        #expect(await Self.wait(for: workspace, until: .valid("latest")))
        #expect(workspace.evaluation == .valid("latest"))
        #expect(!workspace.isEvaluating)

        workspace.expression = "clear-long-input"
        #expect(await Self.wait(for: probe.clearStarted))
        workspace.clear()
        #expect(workspace.expression.isEmpty)
        #expect(workspace.evaluation == .empty)
        #expect(!workspace.isEvaluating)
        #expect(await Self.wait(for: probe.clearCancelled))
        #expect(workspace.evaluation == .empty)
        #expect(!probe.ranOnMainThread)
    }

    private static func wait(for semaphore: DispatchSemaphore) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: semaphore.wait(timeout: .now() + 5) == .success)
            }
        }
    }

    private static func wait(
        for workspace: MathToolWorkspaceModel,
        until expected: MathExpressionEvaluator.LiveEvaluation
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while clock.now < deadline {
            if workspace.evaluation == expected { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return workspace.evaluation == expected
    }
}

private final class MathBackgroundProbe: @unchecked Sendable {
    let firstStarted = DispatchSemaphore(value: 0)
    let firstCancelled = DispatchSemaphore(value: 0)
    let clearStarted = DispatchSemaphore(value: 0)
    let clearCancelled = DispatchSemaphore(value: 0)

    private let lock = NSLock()
    private var calls = 0
    private var calledOnMainThread = false

    var callCount: Int { lock.withLock { calls } }
    var ranOnMainThread: Bool { lock.withLock { calledOnMainThread } }

    func evaluate(
        _ expression: String,
        shouldCancel: @escaping @Sendable () -> Bool
    ) throws -> MathExpressionEvaluator.LiveEvaluation {
        lock.withLock {
            calls += 1
            calledOnMainThread = calledOnMainThread || Thread.isMainThread
        }

        if expression.hasPrefix("first") {
            firstStarted.signal()
            guard waitForCancellation(shouldCancel) else { throw CancellationError() }
            firstCancelled.signal()
            throw CancellationError()
        }
        if expression.hasPrefix("clear") {
            clearStarted.signal()
            guard waitForCancellation(shouldCancel) else { throw CancellationError() }
            clearCancelled.signal()
            throw CancellationError()
        }
        return .valid("latest")
    }

    private func waitForCancellation(_ shouldCancel: @Sendable () -> Bool) -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while clock.now < deadline {
            if shouldCancel() { return true }
            Thread.sleep(forTimeInterval: 0.001)
        }
        return shouldCancel()
    }
}
