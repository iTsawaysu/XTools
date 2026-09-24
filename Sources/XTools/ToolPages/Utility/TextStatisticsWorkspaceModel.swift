import Combine
import XToolsCore
import Foundation

typealias TextStatisticsAnalysisOperation = @Sendable (
    _ input: String,
    _ shouldCancel: @escaping @Sendable () -> Bool
) throws -> TextStatistics.Stats

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

    private let execution = SupersedingExecutionSession(cancelInFlight: true)
    private let analysisOperation: TextStatisticsAnalysisOperation
    private let debounce: Duration

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
        self.analysisOperation = analysisOperation
        self.debounce = debounce
    }

    private func scheduleAnalysis() {
        let input = text
        guard !input.isEmpty else {
            execution.invalidate()
            stats = .zero
            isAnalyzing = false
            return
        }

        isAnalyzing = true
        let analysisOperation = analysisOperation
        execution.schedule(debounce: debounce, operation: { shouldCancel in
            try analysisOperation(input, shouldCancel)
        }) { [weak self] _, completedStats in
            guard let self, !self.text.isEmpty else { return }
            self.stats = completedStats
            self.isAnalyzing = false
        }
    }

    nonisolated private static func defaultAnalysis(
        _ input: String,
        shouldCancel: @escaping @Sendable () -> Bool
    ) throws -> TextStatistics.Stats {
        try TextStatistics.analyze(input, shouldCancel: shouldCancel)
    }
}
