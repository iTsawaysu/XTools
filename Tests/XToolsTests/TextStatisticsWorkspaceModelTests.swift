@testable import XTools
import XToolsCore
import Foundation
import Testing

@MainActor
struct TextStatisticsWorkspaceModelTests {
    @Test func analysisRunsOffMainThreadAfterDebounce() async throws {
        let probe = TextStatisticsAnalysisProbe()
        let workspace = TextStatisticsWorkspaceModel(
            analysisOperation: { input in
                probe.begin(input)
                defer { probe.finish(input) }
                return TextStatistics.analyze(input)
            },
            debounce: .milliseconds(10)
        )

        workspace.text = "Hi world\n你好！"
        #expect(workspace.isAnalyzing)

        try await Self.waitUntil {
            workspace.stats.characters == 12 && !workspace.isAnalyzing
        }

        #expect(!probe.ranOnMainThread)
        #expect(probe.maxConcurrent == 1)
    }

    @Test func rapidChangesCoalesceToLatestWithoutPublishingStaleResults() async throws {
        let probe = TextStatisticsAnalysisProbe(delays: [
            "first": 0.5,
            "latest": 0.6
        ])
        let workspace = TextStatisticsWorkspaceModel(
            analysisOperation: { input in
                probe.begin(input)
                defer { probe.finish(input) }
                return Self.syntheticStats(for: input)
            },
            debounce: .milliseconds(10)
        )

        workspace.text = "first"
        try await Self.waitUntil { probe.startedInputs == ["first"] }

        workspace.text = "obsolete"
        workspace.text = "latest"
        try await Self.waitUntil { probe.startedInputs == ["first", "latest"] }

        try await Self.waitUntil {
            workspace.stats.characters == "latest".count && !workspace.isAnalyzing
        }

        #expect(probe.startedInputs == ["first", "latest"])
        #expect(probe.maxConcurrent == 1)
    }

    @Test func clearingImmediatelyPublishesZeroAndRejectsRunningCompletion() async throws {
        let probe = TextStatisticsAnalysisProbe(delays: ["slow": 0.6])
        let workspace = TextStatisticsWorkspaceModel(
            analysisOperation: { input in
                probe.begin(input)
                defer { probe.finish(input) }
                return Self.syntheticStats(for: input)
            },
            debounce: .milliseconds(10)
        )

        workspace.text = "seed"
        try await Self.waitUntil {
            workspace.stats.characters == "seed".count && !workspace.isAnalyzing
        }

        workspace.text = "slow"
        try await Self.waitUntil { probe.startedInputs.contains("slow") }

        workspace.text = ""
        #expect(workspace.stats == .zero)
        #expect(!workspace.isAnalyzing)

        try await Task.sleep(for: .milliseconds(400))
        #expect(workspace.stats == .zero)
        #expect(!workspace.isAnalyzing)
        #expect(probe.maxConcurrent == 1)
    }

    @Test func repositoryRetainsTextAndCompletedStatsOnlyForCurrentAppSession() async throws {
        let suiteName = "TextStatisticsWorkspaceModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let repository = ToolWorkspaceRepository(defaults: defaults)
        let workspace = repository.model(for: TextStatisticsWorkspaceModel.key)
        workspace.text = "retained text"

        try await Self.waitUntil {
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

    private static func waitUntil(
        timeout: Duration = .seconds(20),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                Issue.record("Timed out waiting for text statistics workspace state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class TextStatisticsAnalysisProbe: @unchecked Sendable {
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

    func finish(_ input: String) {
        lock.withLock {
            active -= 1
        }
    }
}
