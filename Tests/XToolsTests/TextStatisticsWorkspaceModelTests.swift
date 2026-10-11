@testable import XTools
import XToolsCore
import Foundation
import Combine
import Testing

@MainActor
struct TextStatisticsWorkspaceModelTests {
    @Test func analysisRunsOffMainThreadAfterDebounce() async throws {
        let probe = TextStatisticsAnalysisProbe()
        let workspace = TextStatisticsWorkspaceModel(
            analysisOperation: { input, _ in
                probe.begin(input)
                defer { probe.finish(input) }
                return TextStatistics.analyze(input)
            },
            debounce: .milliseconds(10)
        )

        workspace.text = "Hi world\n你好！"
        #expect(workspace.isAnalyzing)

        try await waitUntil {
            workspace.stats.characters == 12 && !workspace.isAnalyzing
        }

        #expect(!probe.ranOnMainThread)
        #expect(probe.maxConcurrent == 1)
    }

    @Test func rapidChangesCoalesceToLatestWithoutPublishingStaleResults() async throws {
        let probe = TextStatisticsAnalysisProbe(heldInputs: ["first", "latest"])
        defer { probe.release("first"); probe.release("latest") }
        let workspace = TextStatisticsWorkspaceModel(
            analysisOperation: { input, _ in
                probe.begin(input)
                defer { probe.finish(input) }
                return Self.syntheticStats(for: input)
            },
            debounce: .milliseconds(10)
        )
        let observation = workspace.$stats.sink { probe.recordPublication($0.characters) }
        defer { observation.cancel() }

        workspace.text = "first"
        try await waitUntil { probe.startedInputs == ["first"] }

        workspace.text = "obsolete"
        workspace.text = "latest"
        probe.release("first")
        try await waitUntil { probe.startedInputs == ["first", "latest"] }
        #expect(probe.finishedInputs == ["first"])
        #expect(probe.publishedCharacters == [0])
        #expect(workspace.isAnalyzing)
        probe.release("latest")

        try await waitUntil {
            workspace.stats.characters == "latest".count && !workspace.isAnalyzing
        }

        #expect(probe.startedInputs == ["first", "latest"])
        #expect(probe.publishedCharacters == [0, "latest".count])
        #expect(probe.maxConcurrent == 1)
    }

    @Test func clearingImmediatelyPublishesZeroAndRejectsRunningCompletion() async throws {
        let probe = TextStatisticsAnalysisProbe(heldInputs: ["slow"])
        defer { probe.release("slow") }
        let workspace = TextStatisticsWorkspaceModel(
            analysisOperation: { input, _ in
                probe.begin(input)
                defer { probe.finish(input) }
                return Self.syntheticStats(for: input)
            },
            debounce: .milliseconds(10)
        )
        let observation = workspace.$stats.sink { probe.recordPublication($0.characters) }
        defer { observation.cancel() }

        workspace.text = "seed"
        try await waitUntil {
            workspace.stats.characters == "seed".count && !workspace.isAnalyzing
        }

        workspace.text = "slow"
        try await waitUntil { probe.startedInputs.contains("slow") }

        workspace.text = ""
        #expect(workspace.stats == .zero)
        #expect(!workspace.isAnalyzing)

        probe.release("slow")
        try await waitUntil { probe.finishedInputs.contains("slow") }
        // The operation has really returned; allow its queued completion to run.
        try await Task.sleep(for: .milliseconds(30))
        #expect(workspace.stats == .zero)
        #expect(probe.publishedCharacters == [0, "seed".count, 0])
        #expect(!workspace.isAnalyzing)
        #expect(probe.maxConcurrent == 1)
    }

    @Test func supersedingCancelsActiveAnalysisBeforePublishingLatest() async throws {
        let probe = TextStatisticsAnalysisProbe()
        let workspace = TextStatisticsWorkspaceModel(
            analysisOperation: { input, shouldCancel in
                probe.begin(input)
                defer { probe.finish(input) }
                if input == "first" {
                    while !shouldCancel() { Thread.sleep(forTimeInterval: 0.002) }
                    probe.markCancelled(input)
                    throw CancellationError()
                }
                return Self.syntheticStats(for: input)
            },
            debounce: .milliseconds(10)
        )

        workspace.text = "first"
        try await waitUntil { probe.startedInputs == ["first"] }
        workspace.text = "latest"
        try await waitUntil {
            probe.cancelledInputs == ["first"]
                && workspace.stats.characters == "latest".count
                && !workspace.isAnalyzing
        }

        #expect(probe.startedInputs == ["first", "latest"])
        #expect(probe.maxConcurrent == 1)
    }

    @Test func releasingWorkspaceCancelsActiveAnalysis() async throws {
        let probe = TextStatisticsAnalysisProbe()
        var workspace: TextStatisticsWorkspaceModel? = TextStatisticsWorkspaceModel(
            analysisOperation: { input, shouldCancel in
                probe.begin(input)
                defer { probe.finish(input) }
                while !shouldCancel() { Thread.sleep(forTimeInterval: 0.002) }
                probe.markCancelled(input)
                throw CancellationError()
            },
            debounce: .milliseconds(10)
        )

        workspace?.text = "held"
        try await waitUntil { probe.startedInputs == ["held"] }
        workspace = nil
        try await waitUntil { probe.cancelledInputs == ["held"] }
        #expect(probe.maxConcurrent == 1)
    }

    @Test func repositoryRetainsTextAndCompletedStatsOnlyForCurrentAppSession() async throws {
        let suiteName = "TextStatisticsWorkspaceModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let repository = ToolWorkspaceRepository(defaults: defaults)
        let workspace = repository.model(for: TextStatisticsWorkspaceModel.key)
        workspace.text = "retained text"

        try await waitUntil {
            workspace.stats.characters == "retained text".count && !workspace.isAnalyzing
        }

        let returned = repository.model(for: TextStatisticsWorkspaceModel.key)
        #expect(returned === workspace)
        #expect(returned.text == "retained text")
        #expect(returned.stats.characters == "retained text".count)

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
            .model(for: TextStatisticsWorkspaceModel.key)
        #expect(relaunched !== workspace)
        #expect(relaunched.text.isEmpty)
        #expect(relaunched.stats == .zero)
        #expect(!relaunched.isAnalyzing)
    }

    nonisolated private static func syntheticStats(
        for input: String
    ) -> TextStatistics.Stats {
        TextStatistics.Stats(
            characters: input.count,
            nonWhitespaceCharacters: input.filter { !$0.isWhitespace }.count,
            words: input.isEmpty ? 0 : 1,
            lines: input.isEmpty ? 0 : 1,
            sentences: input.isEmpty ? 0 : 1,
            bytes: input.utf8.count
        )
    }
}

private final class TextStatisticsAnalysisProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let heldInputs: [String: DispatchSemaphore]
    private var active = 0
    private var storedMaxConcurrent = 0
    private var storedStartedInputs: [String] = []
    private var storedFinishedInputs: [String] = []
    private var storedPublishedCharacters: [Int] = []
    private var storedCancelledInputs: [String] = []
    private var storedRanOnMainThread = false

    init(heldInputs: [String] = []) {
        self.heldInputs = Dictionary(uniqueKeysWithValues: heldInputs.map { ($0, DispatchSemaphore(value: 0)) })
    }

    var maxConcurrent: Int {
        lock.withLock { storedMaxConcurrent }
    }

    var startedInputs: [String] {
        lock.withLock { storedStartedInputs }
    }

    var cancelledInputs: [String] {
        lock.withLock { storedCancelledInputs }
    }

    var finishedInputs: [String] { lock.withLock { storedFinishedInputs } }
    var publishedCharacters: [Int] { lock.withLock { storedPublishedCharacters } }

    func recordPublication(_ characters: Int) {
        lock.withLock { storedPublishedCharacters.append(characters) }
    }

    func release(_ input: String) { heldInputs[input]?.signal() }

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
        if let gate = heldInputs[input], gate.wait(timeout: .now() + 20) == .timedOut {
            Issue.record("Timed out waiting to release analysis for \(input)")
        }
    }

    func finish(_ input: String) {
        lock.withLock {
            active -= 1
            storedFinishedInputs.append(input)
        }
    }

    func markCancelled(_ input: String) {
        lock.withLock { storedCancelledInputs.append(input) }
    }
}
