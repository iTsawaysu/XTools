import Combine
import XToolsCore
import Foundation

typealias TextStatisticsAnalysisOperation = @Sendable (
    _ input: String
) -> TextStatistics.Stats

private actor TextStatisticsAnalysisWorker {
    private struct Request: Sendable {
        let input: String
        let generation: Int
        let completion: @Sendable (
            _ generation: Int,
            _ stats: TextStatistics.Stats
        ) async -> Void
    }

    private let operation: TextStatisticsAnalysisOperation
    private var pending: Request?
    private var isDraining = false
    private var minimumGeneration = 0

    init(operation: @escaping TextStatisticsAnalysisOperation) {
        self.operation = operation
    }

    func invalidate(before generation: Int) {
        minimumGeneration = max(minimumGeneration, generation)
        if let pending, pending.generation < minimumGeneration {
            self.pending = nil
        }
    }

    func submit(
        input: String,
        generation: Int,
        completion: @escaping @Sendable (
            _ generation: Int,
            _ stats: TextStatistics.Stats
        ) async -> Void
    ) async {
        guard generation >= minimumGeneration else { return }

        pending = Request(
            input: input,
            generation: generation,
            completion: completion
        )
        guard !isDraining else { return }

        isDraining = true
        await drain()
    }

    private func drain() async {
        while let request = pending {
            pending = nil
            let operation = self.operation
            let input = request.input
            let stats = await Task.detached(priority: .userInitiated) {
                operation(input)
            }.value

            guard request.generation >= minimumGeneration else { continue }
            await request.completion(request.generation, stats)
        }

        isDraining = false
    }
}

@MainActor
final class TextStatisticsWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<TextStatisticsWorkspaceModel>(toolID: "text-statistics") { _ in
        TextStatisticsWorkspaceModel()
    }

    @Published var text = "" {
        didSet {
            guard text != oldValue else { return }
            scheduleAnalysis()
        }
    }

    @Published private(set) var stats = TextStatistics.Stats.zero
    @Published private(set) var isAnalyzing = false

    private let worker: TextStatisticsAnalysisWorker
    private let debounce: Duration
    private let workGate = AsyncWorkGate()

    convenience init() {
        self.init(
            analysisOperation: TextStatisticsWorkspaceModel.defaultAnalysis,
            debounce: .milliseconds(120)
        )
    }

    init(
        analysisOperation: @escaping TextStatisticsAnalysisOperation,
        debounce: Duration
    ) {
        worker = TextStatisticsAnalysisWorker(operation: analysisOperation)
        self.debounce = debounce
    }

    private func scheduleAnalysis() {
        let token = workGate.invalidate()
        let input = text
        let worker = worker
        let minimumGeneration = input.isEmpty ? token &+ 1 : token

        Task {
            await worker.invalidate(before: minimumGeneration)
        }

        guard !input.isEmpty else {
            stats = .zero
            isAnalyzing = false
            return
        }

        isAnalyzing = true
        workGate.schedule(debounce: debounce) { [weak self] in
            guard let self, self.workGate.isCurrent(token) else { return }
            await worker.submit(
                input: input,
                generation: token
            ) { [weak self] completedGeneration, completedStats in
                await self?.receive(
                    completedStats,
                    generation: completedGeneration
                )
            }
        }
    }

    private func receive(
        _ completedStats: TextStatistics.Stats,
        generation completedGeneration: Int
    ) {
        guard workGate.isCurrent(completedGeneration), !text.isEmpty else { return }
        stats = completedStats
        isAnalyzing = false
    }

    nonisolated private static func defaultAnalysis(
        _ input: String
    ) -> TextStatistics.Stats {
        TextStatistics.analyze(input)
    }
}
