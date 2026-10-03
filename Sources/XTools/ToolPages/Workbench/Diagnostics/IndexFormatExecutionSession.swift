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
    @Published private(set) var diagnosticMarker: IndexTextAreaDiagnosticMarker?

    private let execution: SupersedingExecutionSession

    var hasResult: Bool {
        Self.hasResult(binding)
    }

    var hasStaleResult: Bool {
        hasResult && !isOutputFresh
    }

    var diagnostic: FormatDiagnostic? {
        binding.diagnostic
    }

    /// 格式化页共享的清除可用性判定：输出或错误/警告诊断任一非空即有可
    /// 清除内容（行级 diagnostic 不构成可清除内容，与各页既有表达式一致）。
    var hasClearableContent: Bool {
        !binding.output.isEmpty || binding.error != nil || binding.warning != nil
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
        sourceText: String? = nil,
        delay: Duration = .milliseconds(200),
        cooperativeCancellation: Bool = false,
        operation: @escaping @Sendable (Snapshot) -> FormatBinding
    ) {
        let requestOperation: @Sendable (
            _ shouldCancel: @escaping @Sendable () -> Bool
        ) throws -> (FormatBinding, IndexTextAreaDiagnosticMarker?) = { shouldCancel in
            if shouldCancel() {
                throw CancellationError()
            }
            let binding = cooperativeCancellation
                ? StructuredTextExecution.withCancellation(shouldCancel) { operation(snapshot) }
                : operation(snapshot)
            if shouldCancel() { throw CancellationError() }
            let marker = sourceText.flatMap { source in
                binding.diagnostic.flatMap { IndexTextAreaDiagnosticMarker(diagnostic: $0, sourceText: source) }
            }
            return (binding, marker)
        }

        isRunning = true
        isOutputFresh = false
        diagnosticMarker = nil
        execution.schedule(debounce: delay, operation: requestOperation) { [weak self] _, result in
            guard let self else { return }
            self.binding = result.0
            self.diagnosticMarker = result.1
            self.isRunning = false
            self.isOutputFresh = true
        }
    }

    /// Invalidates in-flight work when its source changes while preserving the
    /// last result as a visibly stale reference until the next run completes.
    func sourceDidChange() {
        diagnosticMarker = nil
        isRunning = false
        isOutputFresh = !hasResult
        execution.invalidate()
    }

    func invalidate(resetTo binding: FormatBinding = FormatBinding()) {
        diagnosticMarker = nil
        self.binding = binding
        isRunning = false
        isOutputFresh = true
        execution.invalidate()
    }

    private static func hasResult(_ binding: FormatBinding) -> Bool {
        !binding.output.isEmpty || binding.error != nil || binding.warning != nil || binding.diagnostic != nil
    }
}
