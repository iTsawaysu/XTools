import Combine
import XToolsCore
import Foundation

enum DiffExecutionResultState: Equatable {
    case empty
    case running
    case stale
    case current
}

@MainActor
/// Cooperative cancellation of long LCS work survives session deallocation.
final class DiffExecutionSession: ObservableObject {
    @Published private(set) var binding: DiffExecutionBinding
    @Published private(set) var isRunning = false
    @Published private(set) var resultState: DiffExecutionResultState

    var isDisplayingStaleResult: Bool {
        resultState == .stale
    }

    private let execution: SupersedingExecutionSession

    init(binding: DiffExecutionBinding = DiffExecutionBinding()) {
        self.binding = binding
        self.resultState = binding == DiffExecutionBinding() ? .empty : .current
        // Latest-wins: newer diffs cancel superseded in-flight LCS work; the
        // core keeps publish generation-gated so a late completion can never
        // overwrite a newer binding.
        self.execution = SupersedingExecutionSession(cancelInFlight: true)
    }

    func schedule(
        request: DiffExecutionRequest,
        delay: Duration = .milliseconds(200),
        operation: @escaping DiffExecutionOperation = DiffExecution.project
    ) {
        let requestOperation: @Sendable (
            _ shouldCancel: @escaping @Sendable () -> Bool
        ) throws -> DiffExecutionBinding = { shouldCancel in
            do {
                return try operation(request, shouldCancel)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return DiffExecution.failureBinding()
            }
        }

        isRunning = true
        resultState = resultState == .current || resultState == .stale ? .stale : .running
        execution.schedule(debounce: delay, operation: requestOperation) { [weak self] _, completedBinding in
            guard let self else { return }
            self.binding = completedBinding
            self.isRunning = false
            self.resultState = .current
        }
    }

    func invalidate(resetTo binding: DiffExecutionBinding = DiffExecutionBinding()) {
        self.binding = binding
        isRunning = false
        resultState = binding == DiffExecutionBinding() ? .empty : .current
        execution.invalidate()
    }

    /// Compatibility alias for existing call sites and tests.
    nonisolated static func defaultOperation(
        _ request: DiffExecutionRequest,
        shouldCancel: @escaping @Sendable () -> Bool
    ) throws -> DiffExecutionBinding {
        try DiffExecution.project(request, shouldCancel: shouldCancel)
    }
}
