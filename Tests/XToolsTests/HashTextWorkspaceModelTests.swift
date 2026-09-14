@testable import XTools
import XToolsCore
import Foundation
import Testing

@MainActor
struct HashTextWorkspaceModelTests {
    @Test func smallInputRunsOffMainThreadAfterDebounce() async throws {
        let probe = HashDigestOperationProbe()
        let workspace = makeWorkspace(
            probe: probe,
            debounce: .milliseconds(10),
            realtimeUTF8ByteLimit: 64
        )

        workspace.input = "abc"
        #expect(workspace.isComputing)
        #expect(!workspace.usesExplicitComputation)

        try await Self.waitUntil {
            workspace.digests.first?.bytes == Array("abc".utf8) && !workspace.isComputing
        }

        #expect(!probe.ranOnMainThread)
        #expect(probe.maxConcurrent == 1)
    }

    @Test func inputAboveRealtimeLimitWaitsForExplicitComputation() async throws {
        let probe = HashDigestOperationProbe()
        let workspace = makeWorkspace(
            probe: probe,
            debounce: .milliseconds(10),
            realtimeUTF8ByteLimit: 4
        )

        workspace.input = "12345"
        try await Task.sleep(for: .milliseconds(150))

        #expect(workspace.usesExplicitComputation)
        #expect(!workspace.isComputing)
        #expect(workspace.digests.isEmpty)
        #expect(probe.startedInputs.isEmpty)

        workspace.computeExplicitly()
        #expect(workspace.isComputing)

        try await Self.waitUntil {
            workspace.digests.first?.bytes == Array("12345".utf8) && !workspace.isComputing
        }
        #expect(probe.startedInputs == ["12345"])
    }

    @Test func rapidChangesKeepOneActiveAndOneLatestPendingRequest() async throws {
        let probe = HashDigestOperationProbe(delays: [
            "first": 0.3,
            "latest": 0.5
        ])
        let workspace = makeWorkspace(
            probe: probe,
            debounce: .milliseconds(10),
            realtimeUTF8ByteLimit: 64
        )

        workspace.input = "first"
        try await Self.waitUntil { probe.startedInputs == ["first"] }

        workspace.input = "obsolete"
        workspace.input = "latest"
        try await Self.waitUntil { probe.startedInputs == ["first", "latest"] }

        #expect(workspace.digests.isEmpty)
        #expect(workspace.isComputing)

        try await Self.waitUntil {
            workspace.digests.first?.bytes == Array("latest".utf8) && !workspace.isComputing
        }

        #expect(probe.startedInputs == ["first", "latest"])
        #expect(probe.maxConcurrent == 1)
    }

    @Test func clearingCancelsWorkAndRejectsItsCompletion() async throws {
        let probe = HashDigestOperationProbe(delays: ["slow": 0.14])
        let workspace = makeWorkspace(
            probe: probe,
            debounce: .milliseconds(10),
            realtimeUTF8ByteLimit: 64
        )

        workspace.input = "seed"
        try await Self.waitUntil {
            workspace.digests.first?.bytes == Array("seed".utf8) && !workspace.isComputing
        }

        workspace.input = "slow"
        try await Self.waitUntil { probe.startedInputs.contains("slow") }

        workspace.input = ""
        #expect(workspace.digests.isEmpty)
        #expect(!workspace.isComputing)
        #expect(!workspace.usesExplicitComputation)

        try await Task.sleep(for: .milliseconds(400))
        #expect(workspace.digests.isEmpty)
        #expect(!workspace.isComputing)
        #expect(probe.maxConcurrent == 1)
    }

    @Test func realtimeBoundaryUsesMeasuredUTF8ByteLimit() async throws {
        let probe = HashDigestOperationProbe()
        let workspace = makeWorkspace(
            probe: probe,
            debounce: .milliseconds(10),
            realtimeUTF8ByteLimit: 4
        )

        workspace.input = "1234"
        try await Self.waitUntil { !workspace.digests.isEmpty && !workspace.isComputing }
        #expect(!workspace.usesExplicitComputation)

        workspace.input = "你好"
        try await Task.sleep(for: .milliseconds(150))
        #expect(workspace.usesExplicitComputation)
        #expect(workspace.digests.isEmpty)
        #expect(probe.startedInputs == ["1234"])
    }

    private func makeWorkspace(
        probe: HashDigestOperationProbe,
        debounce: Duration,
        realtimeUTF8ByteLimit: Int
    ) -> HashTextToolWorkspaceModel {
        HashTextToolWorkspaceModel(
            preferences: ToolPreferenceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            digestOperation: { bytes, shouldCancel in
                let input = String(decoding: bytes, as: UTF8.self)
                probe.begin(input)
                defer { probe.finish() }
                guard !shouldCancel() else { return nil }
                return [
                    HashDigestPipeline.DigestItem(
                        algorithm: .sha256,
                        bytes: bytes
                    )
                ]
            },
            debounce: debounce,
            realtimeUTF8ByteLimit: realtimeUTF8ByteLimit
        )
    }

    private static func waitUntil(
        timeout: Duration = .seconds(20),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                Issue.record("Timed out waiting for Hash workspace state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class HashDigestOperationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let delays: [String: TimeInterval]
    private var active = 0
    private var storedMaxConcurrent = 0
    private var storedStartedInputs: [String] = []
    private var storedRanOnMainThread = false

    init(delays: [String: TimeInterval] = [:]) {
        self.delays = delays
    }

    var maxConcurrent: Int {
        lock.withLock { storedMaxConcurrent }
    }

    var startedInputs: [String] {
        lock.withLock { storedStartedInputs }
    }

    var ranOnMainThread: Bool {
        lock.withLock { storedRanOnMainThread }
    }

    func begin(_ input: String) {
        lock.withLock {
            active += 1
            storedMaxConcurrent = max(storedMaxConcurrent, active)
            storedStartedInputs.append(input)
            storedRanOnMainThread = storedRanOnMainThread || Thread.isMainThread
        }
        if let delay = delays[input] {
            Thread.sleep(forTimeInterval: delay)
        }
    }

    func finish() {
        lock.withLock {
            active -= 1
        }
    }
}
