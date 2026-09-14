import Foundation

@MainActor
public final class AsyncWorkGate {
    private var generation = 0
    private var task: Task<Void, Never>?

    public init() {}

    deinit {
        task?.cancel()
        task = nil
    }

    public var token: Int {
        generation
    }

    @discardableResult
    public func invalidate() -> Int {
        task?.cancel()
        task = nil
        generation &+= 1
        return generation
    }

    public func isCurrent(_ token: Int) -> Bool {
        generation == token
    }

    public func schedule(
        debounce: Duration = .zero,
        operation: @escaping @MainActor () async -> Void
    ) {
        let scheduledToken = generation
        task?.cancel()
        task = Task { [weak self] in
            do {
                if debounce > .zero {
                    try await Task.sleep(for: debounce)
                }
                try Task.checkCancellation()
                guard let self, self.isCurrent(scheduledToken) else { return }
                await operation()
                if self.isCurrent(scheduledToken) {
                    self.task = nil
                }
            } catch is CancellationError {
                // A newer invalidate/schedule owns replacement state.
            } catch {
                // Task.sleep only fails via cancellation.
            }
        }
    }

    /// Runs `operation` on a detached task, then publishes on the main actor only
    /// if `token` is still current.
    public func runDetached<Output: Sendable>(
        operation: @escaping @Sendable () async -> Output,
        publish: @escaping @MainActor (Output) -> Void
    ) {
        let scheduledToken = generation
        task?.cancel()
        task = Task { [weak self] in
            let output = await Task.detached(priority: .userInitiated) {
                await operation()
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isCurrent(scheduledToken), !Task.isCancelled else { return }
                self.task = nil
                publish(output)
            }
        }
    }
}
