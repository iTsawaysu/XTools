@testable import XTools
@testable import XToolsCore
import Foundation
import Testing

@MainActor
struct IndexFormatExecutionSessionTests {
    @Test func emptySessionIsFreshAndNeverReportsAStaleResult() {
        let session = IndexFormatExecutionSession()

        #expect(!session.hasResult)
        #expect(session.isOutputFresh)
        #expect(!session.hasStaleResult)

        session.sourceDidChange()
        #expect(session.isOutputFresh)
        #expect(!session.hasStaleResult)
    }

    @Test func freshnessTracksRunningCompletionAndSourceChanges() async throws {
        let session = IndexFormatExecutionSession(binding: FormatBinding(output: "previous"))
        #expect(session.isOutputFresh)

        session.schedule(snapshot: "next", delay: .milliseconds(20)) { snapshot in
            FormatBinding(output: snapshot)
        }
        #expect(session.isRunning)
        #expect(!session.isOutputFresh)
        #expect(session.binding.output == "previous")

        try await Self.waitUntil { session.binding.output == "next" && !session.isRunning }
        #expect(session.isOutputFresh)

        session.sourceDidChange()
        #expect(!session.isRunning)
        #expect(!session.isOutputFresh)
        #expect(session.hasStaleResult)
        #expect(session.binding.output == "next", "Source edits retain the last result as an explicitly stale reference")
    }

    @Test func sourceChangeRejectsLateCompletionWithoutDiscardingLastResult() async throws {
        let probe = FormatOperationProbe(delays: ["slow": 0.14])
        let session = IndexFormatExecutionSession(binding: FormatBinding(output: "previous"))

        session.schedule(snapshot: "slow", delay: .zero) { snapshot in
            probe.begin(snapshot)
            defer { probe.finish() }
            return FormatBinding(output: snapshot)
        }
        try await Self.waitUntil { probe.startedInputs == ["slow"] }

        session.sourceDidChange()
        try await Task.sleep(for: .milliseconds(400))

        #expect(session.binding.output == "previous")
        #expect(!session.isRunning)
        #expect(!session.isOutputFresh)
    }

    @Test func operationRunsOffMainActorAndPublishesItsBinding() async throws {
        let session = IndexFormatExecutionSession()

        session.schedule(snapshot: "json", delay: .milliseconds(10)) { snapshot in
            FormatBinding(output: "background:\(snapshot):\(!Thread.isMainThread)")
        }

        try await Self.waitUntil { session.binding.output == "background:json:true" && !session.isRunning }
    }

    @Test func debounceCoalescesRapidInputBeforeStartingWork() async throws {
        let probe = FormatOperationProbe()
        let session = IndexFormatExecutionSession()

        session.schedule(snapshot: "first", delay: .milliseconds(40)) { snapshot in
            probe.recordStart(snapshot)
            return FormatBinding(output: snapshot)
        }
        session.schedule(snapshot: "latest", delay: .milliseconds(40)) { snapshot in
            probe.recordStart(snapshot)
            return FormatBinding(output: snapshot)
        }

        try await Self.waitUntil { session.binding.output == "latest" && !session.isRunning }
        #expect(probe.startedInputs == ["latest"])
    }

    @Test func rapidChangesKeepOneActiveAndOneLatestPendingRequest() async throws {
        let probe = FormatOperationProbe(delays: ["first": 0.12, "latest": 0.01])
        let session = IndexFormatExecutionSession()

        session.schedule(snapshot: "first", delay: .milliseconds(10)) { snapshot in
            probe.begin(snapshot)
            defer { probe.finish() }
            return FormatBinding(output: snapshot)
        }
        try await Self.waitUntil { probe.startedInputs == ["first"] }

        session.schedule(snapshot: "obsolete", delay: .milliseconds(10)) { snapshot in
            probe.begin(snapshot)
            defer { probe.finish() }
            return FormatBinding(output: snapshot)
        }
        session.schedule(snapshot: "latest", delay: .milliseconds(10)) { snapshot in
            probe.begin(snapshot)
            defer { probe.finish() }
            return FormatBinding(output: snapshot)
        }

        try await Self.waitUntil { session.binding.output == "latest" && !session.isRunning }
        #expect(probe.startedInputs == ["first", "latest"])
        #expect(probe.maxConcurrent == 1)
    }

    @Test func newerScheduledGenerationDropsWorkerPendingBeforeDebounce() async throws {
        let probe = FormatOperationProbe()
        let releaseFirst = DispatchSemaphore(value: 0)
        let session = IndexFormatExecutionSession()

        session.schedule(snapshot: "first", delay: .zero) { snapshot in
            probe.begin(snapshot)
            defer { probe.finish() }
            if snapshot == "first" {
                // Keep the active worker deterministic while the obsolete request
                // is queued and the latest debounce is scheduled.
                releaseFirst.wait()
            }
            return FormatBinding(output: snapshot)
        }
        try await Self.waitUntil { probe.startedInputs == ["first"] }

        session.schedule(snapshot: "obsolete", delay: .zero) { snapshot in
            probe.begin(snapshot)
            defer { probe.finish() }
            return FormatBinding(output: snapshot)
        }
        try await Task.sleep(for: .milliseconds(50))

        session.schedule(snapshot: "latest", delay: .milliseconds(200)) { snapshot in
            probe.begin(snapshot)
            defer { probe.finish() }
            return FormatBinding(output: snapshot)
        }
        releaseFirst.signal()

        try await Self.waitUntil { session.binding.output == "latest" && !session.isRunning }
        #expect(probe.startedInputs == ["first", "latest"])
    }

    @Test func invalidateClearsBindingAndRejectsLateCompletion() async throws {
        let probe = FormatOperationProbe(delays: ["slow": 0.14])
        let session = IndexFormatExecutionSession()

        session.schedule(snapshot: "slow", delay: .milliseconds(10)) { snapshot in
            probe.begin(snapshot)
            defer { probe.finish() }
            return FormatBinding(output: snapshot)
        }
        try await Self.waitUntil { probe.startedInputs == ["slow"] }

        session.invalidate(resetTo: FormatBinding(output: "cleared"))
        #expect(session.binding.output == "cleared")
        #expect(!session.isRunning)

        try await Task.sleep(for: .milliseconds(400))
        #expect(session.binding.output == "cleared")
        #expect(!session.isRunning)
    }

    @Test func fiveStructuredFormatterOperationsRunOffMainActor() async throws {
        let cases: [(String, String, @Sendable (String) -> FormatBinding)] = [
            ("JSON", #"{"a":1}"#, { input in
                FormatRunner.run(input) {
                    try JSONFormatting.format($0, sortKeys: false, indentWidth: 2)
                }
                .binding(text: { $0 })
            }),
            ("SQL", "select * from users", { input in
                FormatRunner.run(input) {
                    try SQLFormatting.format($0)
                }
                .binding(text: { $0 })
            }),
            ("XML", "<root><item/></root>", { input in
                FormatRunner.run(input) {
                    try XMLFormatting.format($0)
                }
                .binding(text: { $0 })
            }),
            ("YAML", "key: value", { input in
                FormatRunner.run(input, produce: YAMLPrettifier.formatValidated)
                    .binding(text: { $0 })
            }),
            ("Docker", "docker run nginx", { input in
                let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
                do {
                    let result = try DockerRunToDockerComposeService.convert(trimmed)
                    return FormatBinding(output: result.yaml)
                } catch {
                    return FormatBinding(error: "failed")
                }
            })
        ]

        let session = IndexFormatExecutionSession()
        for (name, input, operation) in cases {
            session.invalidate()
            session.schedule(snapshot: input, delay: .zero) { input in
                let binding = operation(input)
                return Thread.isMainThread
                    ? FormatBinding(error: "\(name) ran on the main actor")
                    : binding
            }
            try await Self.waitUntil { !session.isRunning }
            #expect(session.binding.error == nil, "\(name) formatter should complete off-main")
            #expect(!session.binding.output.isEmpty, "\(name) formatter should publish output")
        }
    }

    @Test func largeFormatterOperationLeavesMainActorAvailable() async throws {
        let session = IndexFormatExecutionSession()
        let input = "[" + String(repeating: "{\"value\":1},", count: 30_000).dropLast() + "]"
        var mainActorProbeCount = 0

        session.schedule(snapshot: input, delay: .zero) { snapshot in
            FormatRunner.run(snapshot) {
                try JSONFormatting.format($0, sortKeys: false, indentWidth: 2)
            }
            .binding(text: { $0 })
        }

        while session.binding.output.isEmpty && session.isRunning {
            mainActorProbeCount += 1
            await Task.yield()
        }

        try await Self.waitUntil { !session.isRunning }
        #expect(!session.binding.output.isEmpty)
        #expect(mainActorProbeCount > 0)
    }

    @Test func operationReceivesAnImmutableOptionSnapshot() async throws {
        struct Snapshot: Sendable {
            let input: String
            let mode: String
            let indent: Int
        }

        let session = IndexFormatExecutionSession()
        var input = "before"
        var mode = "format"
        var indent = 2
        let snapshot = Snapshot(input: input, mode: mode, indent: indent)

        session.schedule(snapshot: snapshot, delay: .zero) { snapshot in
            FormatBinding(output: "\(snapshot.mode):\(snapshot.indent):\(snapshot.input)")
        }
        input = "after"
        mode = "minify"
        indent = 4

        try await Self.waitUntil { session.binding.output == "format:2:before" && !session.isRunning }
    }

    private static func waitUntil(
        timeout: Duration = .seconds(20),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                Issue.record("Timed out waiting for format execution session state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class FormatOperationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let delays: [String: TimeInterval]
    private var active = 0
    private var storedMaxConcurrent = 0
    private var storedStartedInputs: [String] = []

    init(delays: [String: TimeInterval] = [:]) {
        self.delays = delays
    }

    var startedInputs: [String] {
        lock.withLock { storedStartedInputs }
    }

    var maxConcurrent: Int {
        lock.withLock { storedMaxConcurrent }
    }

    func recordStart(_ input: String) {
        lock.withLock { storedStartedInputs.append(input) }
    }

    func begin(_ input: String) {
        lock.withLock {
            storedStartedInputs.append(input)
            active += 1
            storedMaxConcurrent = max(storedMaxConcurrent, active)
        }
        if let delay = delays[input] {
            Thread.sleep(forTimeInterval: delay)
        }
    }

    func finish() {
        lock.withLock { active -= 1 }
    }
}
