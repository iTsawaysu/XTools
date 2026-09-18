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
    @Published private(set) var isOutputFresh: Bool

    private let execution: SupersedingExecutionSession

    var hasResult: Bool {
        Self.hasResult(binding)
    }

    var hasStaleResult: Bool {
        hasResult && !isOutputFresh
    }

    init(binding: FormatBinding = FormatBinding()) {
        self.binding = binding
        self.isOutputFresh = true
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
        isOutputFresh = false
        execution.schedule(debounce: delay, operation: requestOperation) { [weak self] _, completedBinding in
            guard let self else { return }
            self.binding = completedBinding
            self.isRunning = false
            self.isOutputFresh = true
        }
    }

    /// Invalidates in-flight work when its source changes while preserving the
    /// last result as a visibly stale reference until the next run completes.
    func sourceDidChange() {
        isRunning = false
        isOutputFresh = !hasResult
        execution.invalidate()
    }

    func invalidate(resetTo binding: FormatBinding = FormatBinding()) {
        self.binding = binding
        isRunning = false
        isOutputFresh = true
        execution.invalidate()
    }

    private static func hasResult(_ binding: FormatBinding) -> Bool {
        !binding.output.isEmpty || binding.error != nil || binding.warning != nil
    }
}
