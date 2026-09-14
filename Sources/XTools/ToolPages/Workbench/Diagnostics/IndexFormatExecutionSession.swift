import Combine
import XToolsCore
import Foundation

/// Serializes expensive formatter work off the main actor while keeping only the
/// latest debounced request pending. Formatters return a complete binding so a
/// stale or cancelled request can never partially update a workspace.
@MainActor
final class IndexFormatExecutionSession: ObservableObject {
    @Published private(set) var binding: FormatBinding
    @Published private(set) var isRunning = false

    private let execution: SupersedingExecutionSession

    init(binding: FormatBinding = FormatBinding()) {
        self.binding = binding
        // Latest-wins: superseded in-flight detached work is cancelled via the
        // cooperative token, and publish remains generation-gated so a late
        // completion can never overwrite a newer binding.
        self.execution = SupersedingExecutionSession(cancelInFlight: true)
    }

    func schedule<Snapshot: Sendable>(
        snapshot: Snapshot,
        delay: Duration = .milliseconds(200),
        operation: @escaping @Sendable (Snapshot) -> FormatBinding
    ) {
        let requestOperation: @Sendable (
            _ shouldCancel: @escaping @Sendable () -> Bool
        ) throws -> FormatBinding = { shouldCancel in
            if shouldCancel() {
                throw CancellationError()
            }
            return operation(snapshot)
        }

        isRunning = true
        execution.schedule(debounce: delay, operation: requestOperation) { [weak self] _, completedBinding in
            guard let self else { return }
            self.binding = completedBinding
            self.isRunning = false
        }
    }

    func invalidate(resetTo binding: FormatBinding = FormatBinding()) {
        self.binding = binding
        isRunning = false
        execution.invalidate()
    }
}
