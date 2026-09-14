@testable import XTools
@testable import XToolsCore
import Foundation
import Testing

@MainActor
struct DiffExecutionSessionTests {
    @Test func operationRunsOffMainActorAndPublishesOneCompleteBinding() async throws {
        let session = DiffExecutionSession()
        let request = DiffExecutionRequest(kind: .text, left: "old", right: "new")

        session.schedule(request: request, delay: .milliseconds(10)) { request in
            DiffExecutionBinding(
                rows: [],
                error: Thread.isMainThread ? "main" : "\(request.left)->\(request.right)"
            )
        }

        try await Self.waitUntil {
            session.binding.error == "old->new" && !session.isRunning
        }
    }

    @Test func debounceCoalescesRapidRequestsBeforeWorkStarts() async throws {
        let probe = DiffOperationProbe()
        let session = DiffExecutionSession()

        session.schedule(request: .text("first"), delay: .milliseconds(40)) { request in
            probe.recordStart(request.left)
            return DiffExecutionBinding(error: request.left)
        }
        session.schedule(request: .text("latest"), delay: .milliseconds(40)) { request in
            probe.recordStart(request.left)
            return DiffExecutionBinding(error: request.left)
        }

        try await Self.waitUntil {
            session.binding.error == "latest" && !session.isRunning
        }
        #expect(probe.startedInputs == ["latest"])
    }

    @Test func activeWorkIsCancelledAndOnlyLatestPendingRequestRuns() async throws {
        let probe = DiffOperationProbe()
        let session = DiffExecutionSession()

        session.schedule(request: .text("first"), delay: .zero) { request in
            probe.begin(request.left)
            defer { probe.finish() }
            while !Task.isCancelled {
                Thread.sleep(forTimeInterval: 0.002)
            }
            probe.recordCancellation(request.left)
            throw CancellationError()
        }
        try await Self.waitUntil { probe.startedInputs == ["first"] }

        session.schedule(request: .text("obsolete"), delay: .milliseconds(10)) { request in
            probe.begin(request.left)
            defer { probe.finish() }
            return DiffExecutionBinding(error: request.left)
        }
        session.schedule(request: .text("latest"), delay: .milliseconds(10)) { request in
            probe.begin(request.left)
            defer { probe.finish() }
            return DiffExecutionBinding(error: request.left)
        }

        try await Self.waitUntil {
            session.binding.error == "latest" && !session.isRunning
        }
        #expect(probe.startedInputs == ["first", "latest"])
        #expect(probe.maxConcurrent == 1)
        #expect(probe.cancelledInputs.contains("first"))
    }

    @Test func cooperativeActiveOperationObservesCancellation() async throws {
        let probe = DiffOperationProbe()
        let session = DiffExecutionSession()

        session.schedule(request: .text("slow"), delay: .zero) { request in
            probe.recordStart(request.left)
            while !Task.isCancelled {
                Thread.sleep(forTimeInterval: 0.002)
            }
            probe.recordCancellation(request.left)
            throw CancellationError()
        }
        try await Self.waitUntil { probe.startedInputs == ["slow"] }

        session.schedule(request: .text("latest"), delay: .zero) { request in
            DiffExecutionBinding(error: request.left)
        }

        try await Self.waitUntil {
            session.binding.error == "latest" && !session.isRunning
        }
        #expect(probe.cancelledInputs == ["slow"])
    }

    @Test func staleSuccessAndFailureCannotReplaceLatestBinding() async throws {
        let session = DiffExecutionSession()
        let probe = DiffOperationProbe(delays: ["success": 0.12, "failure": 0.12])

        session.schedule(request: .text("success"), delay: .zero) { request in
            probe.sleepIgnoringCancellation(request.left)
            return DiffExecutionBinding(error: "stale-success")
        }
        try await Self.waitUntil { probe.startedInputs == ["success"] }
        session.schedule(request: .text("current"), delay: .zero) { _ in
            DiffExecutionBinding(error: "current")
        }
        try await Self.waitUntil {
            session.binding.error == "current" && !session.isRunning
        }

        session.schedule(request: .text("failure"), delay: .zero) { request in
            probe.sleepIgnoringCancellation(request.left)
            throw DiffOperationProbe.Failure.expected
        }
        try await Self.waitUntil { probe.startedInputs.contains("failure") }
        session.schedule(request: .text("new-current"), delay: .zero) { _ in
            DiffExecutionBinding(error: "new-current")
        }
        try await Self.waitUntil {
            session.binding.error == "new-current" && !session.isRunning
        }

        #expect(session.binding.error == "new-current")
    }

    @Test func invalidateClearsStateAndRejectsLateCompletion() async throws {
        let probe = DiffOperationProbe(delays: ["slow": 0.12])
        let session = DiffExecutionSession(
            binding: DiffExecutionBinding(error: "existing")
        )

        session.schedule(request: .text("slow"), delay: .zero) { request in
            probe.sleepIgnoringCancellation(request.left)
            return DiffExecutionBinding(error: "late")
        }
        try await Self.waitUntil { probe.startedInputs == ["slow"] }

        session.invalidate()
        #expect(session.binding == DiffExecutionBinding())
        #expect(!session.isRunning)

        try await Task.sleep(for: .milliseconds(400))
        #expect(session.binding == DiffExecutionBinding())
        #expect(!session.isRunning)
    }

    @Test func operationReceivesImmutableRequestSnapshot() async throws {
        let session = DiffExecutionSession()
        var left = "before-left"
        var right = "before-right"
        let request = DiffExecutionRequest(kind: .text, left: left, right: right)

        session.schedule(request: request, delay: .milliseconds(20)) { request in
            DiffExecutionBinding(error: "\(request.left)|\(request.right)")
        }
        left = "after-left"
        right = "after-right"

        try await Self.waitUntil {
            session.binding.error == "before-left|before-right" && !session.isRunning
        }
    }

    @Test func deallocationCancelsActiveOperation() async throws {
        let probe = DiffOperationProbe()
        var session: DiffExecutionSession? = DiffExecutionSession()
        weak let weakSession = session

        session?.schedule(request: .text("owned"), delay: .zero) { request in
            probe.recordStart(request.left)
            while !Task.isCancelled {
                Thread.sleep(forTimeInterval: 0.002)
            }
            probe.recordCancellation(request.left)
            throw CancellationError()
        }
        try await Self.waitUntil { probe.startedInputs == ["owned"] }

        session = nil

        try await Self.waitUntil {
            weakSession == nil && probe.cancelledInputs == ["owned"]
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
                Issue.record("Timed out waiting for diff execution session state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private extension DiffExecutionRequest {
    static func text(_ value: String) -> Self {
        Self(kind: .text, left: value, right: "right")
    }
}

private final class DiffOperationProbe: @unchecked Sendable {
    enum Failure: Error {
        case expected
    }

    private let lock = NSLock()
    private let delays: [String: TimeInterval]
    private var active = 0
    private var storedMaxConcurrent = 0
    private var storedStartedInputs: [String] = []
    private var storedCancelledInputs: [String] = []

    init(delays: [String: TimeInterval] = [:]) {
        self.delays = delays
    }

    var startedInputs: [String] {
        lock.withLock { storedStartedInputs }
    }

    var cancelledInputs: [String] {
        lock.withLock { storedCancelledInputs }
    }

    var maxConcurrent: Int {
        lock.withLock { storedMaxConcurrent }
    }

    func recordStart(_ input: String) {
        lock.withLock { storedStartedInputs.append(input) }
    }

    func recordCancellation(_ input: String) {
        lock.withLock { storedCancelledInputs.append(input) }
    }

    func begin(_ input: String) {
        lock.withLock {
            storedStartedInputs.append(input)
            active += 1
            storedMaxConcurrent = max(storedMaxConcurrent, active)
        }
        if let delay = delays[input] {
            let deadline = Date().addingTimeInterval(delay)
            while Date() < deadline {
                if Task.isCancelled {
                    recordCancellation(input)
                    return
                }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
    }

    func sleepIgnoringCancellation(_ input: String) {
        recordStart(input)
        if let delay = delays[input] {
            Thread.sleep(forTimeInterval: delay)
        }
    }

    func finish() {
        lock.withLock { active -= 1 }
    }
}
