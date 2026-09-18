@testable import XTools
@testable import XToolsCore
import Foundation
import Testing

@MainActor
struct DiffWorkspaceTests {
    @Test func clearDuringRunSynchronouslyEmptiesEveryStateAndRejectsLateResult() async throws {
        let probe = DiffWorkspaceOperationProbe()
        let workspace = DiffToolWorkspaceModel(
            kind: .text,
            debounce: .zero,
            operation: { request, _ in
                probe.recordStart(request)
                while !Task.isCancelled {
                    Thread.sleep(forTimeInterval: 0.002)
                }
                probe.recordCancellation()
                throw CancellationError()
            }
        )
        workspace.left = "private-left"
        try await Self.waitUntil { probe.startedCount == 1 }

        workspace.clear()

        #expect(workspace.left.isEmpty)
        #expect(workspace.right.isEmpty)
        #expect(workspace.execution.binding == DiffExecutionBinding())
        #expect(!workspace.execution.isRunning)
        #expect(!workspace.hasAnyContent)
        try await Self.waitUntil { probe.cancellationCount == 1 }
        #expect(workspace.execution.binding == DiffExecutionBinding())
    }

    @Test func optionsTriggerReschedulingAndReflectInRequest() async throws {
        let probe = DiffWorkspaceOperationProbe()
        let workspace = DiffToolWorkspaceModel(
            kind: .text,
            debounce: .zero,
            operation: { request, _ in
                probe.recordStart(request)
                return DiffExecutionBinding()
            }
        )

        workspace.left = "abc"
        workspace.right = "ABC"
        try await Self.waitUntil { probe.startedCount >= 1 }

        workspace.ignoreCase = true
        try await Self.waitUntil {
            if case .text(let options) = probe.lastRequest?.kind {
                return options.ignoreCase && !options.ignoreWhitespace
            }
            return false
        }

        workspace.ignoreWhitespace = true
        try await Self.waitUntil {
            if case .text(let options) = probe.lastRequest?.kind {
                return options.ignoreCase && options.ignoreWhitespace
            }
            return false
        }

        workspace.clear()
        #expect(workspace.left.isEmpty)
        #expect(workspace.right.isEmpty)
        #expect(workspace.ignoreCase == true)
        #expect(workspace.ignoreWhitespace == true)
    }

    @Test func foldUnchangedIsPureProjectionAndDoesNotScheduleOperation() async throws {
        let probe = DiffWorkspaceOperationProbe()
        let workspace = DiffToolWorkspaceModel(
            kind: .json(labels: JSONDiffValidation.SideLabels(left: "L", right: "R")),
            debounce: .zero,
            operation: { request, _ in
                probe.recordStart(request)
                return DiffExecutionBinding()
            }
        )

        workspace.left = "{}"
        workspace.right = "{}"
        try await Self.waitUntil { !workspace.execution.isRunning && probe.startedCount >= 1 }
        let callCount = probe.startedCount

        workspace.foldUnchanged = true
        try await Task.sleep(for: .milliseconds(100))

        #expect(probe.startedCount == callCount)
        if case .json(_, let options) = probe.lastRequest?.kind {
            #expect(options.foldUnchanged == false)
        } else {
            Issue.record("Expected JSON request")
        }
    }

    private static func waitUntil(
        timeout: Duration = .seconds(20),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                Issue.record("Timed out waiting for diff workspace state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class DiffWorkspaceOperationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedStartedCount = 0
    private var storedCancellationCount = 0
    private var storedLastRequest: DiffExecutionRequest?

    var startedCount: Int {
        lock.withLock { storedStartedCount }
    }

    var cancellationCount: Int {
        lock.withLock { storedCancellationCount }
    }

    var lastRequest: DiffExecutionRequest? {
        lock.withLock { storedLastRequest }
    }

    func recordStart(_ request: DiffExecutionRequest) {
        lock.withLock {
            storedStartedCount += 1
            storedLastRequest = request
        }
    }

    func recordCancellation() {
        lock.withLock { storedCancellationCount += 1 }
    }
}
