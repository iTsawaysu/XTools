import Combine
import XToolsCore
import Foundation

@MainActor
/// Cooperative cancellation of long LCS work survives session deallocation.
final class DiffExecutionSession: ObservableObject {
    @Published private(set) var binding: DiffExecutionBinding
    @Published private(set) var isRunning = false

    var isDisplayingStaleResult: Bool {
        isRunning && binding != DiffExecutionBinding()
    }

    private let execution: SupersedingExecutionSession

    init(binding: DiffExecutionBinding = DiffExecutionBinding()) {
        self.binding = binding
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
        ) throws -> DiffExecutionBinding = { _ in
            do {
                return try operation(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return DiffExecution.failureBinding()
            }
        }

        isRunning = true
        execution.schedule(debounce: delay, operation: requestOperation) { [weak self] _, completedBinding in
            guard let self else { return }
            self.binding = completedBinding
            self.isRunning = false
        }
    }

    func invalidate(resetTo binding: DiffExecutionBinding = DiffExecutionBinding()) {
        self.binding = binding
        isRunning = false
        execution.invalidate()
    }

    /// Compatibility alias for existing call sites and tests.
    nonisolated static func defaultOperation(
        _ request: DiffExecutionRequest
    ) throws -> DiffExecutionBinding {
        try DiffExecution.project(request)
    }
}
