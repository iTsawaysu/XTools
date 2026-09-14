import Foundation

/// Deep module: the latest-wins execution lifecycle shared by tool sessions.
///
/// `schedule` accepts a domain operation plus a publish mapping; this module
/// alone owns debounce, generation bumping, cooperative cancellation, and
/// stale-publish rejection. Sessions compose their snapshots and diagnostics
/// on top instead of re-deriving the race logic per workstream.
@MainActor
public final class SupersedingExecutionSession {
    private let generationGate: GenerationGate
    private let worker: SupersedingDetachedWorker
    private var schedulingTask: Task<Void, Never>?
    public private(set) var generation = 0

    public init(cancelInFlight: Bool = true) {
        let generationGate = GenerationGate()
        self.generationGate = generationGate
        self.worker = SupersedingDetachedWorker(
            cancelInFlight: cancelInFlight,
            generationGate: generationGate
        )
    }

    deinit {
        schedulingTask?.cancel()
        generationGate.invalidate(before: Int.max)
        let worker = worker
        Task {
            await worker.invalidate(before: Int.max)
        }
    }

    public func isCurrent(_ generation: Int) -> Bool {
        self.generation == generation
    }

    /// Starts a new latest-wins run. `operation` executes after `debounce` off
    /// the main actor and can observe `shouldCancel` for cooperative abort;
    /// `publish` fires on the main actor only when the run is still the newest.
    public func schedule<Output: Sendable>(
        debounce: Duration = .zero,
        operation: @escaping @Sendable (
            _ shouldCancel: @escaping @Sendable () -> Bool
        ) throws -> Output,
        publish: @escaping @MainActor (_ generation: Int, _ output: Output) -> Void
    ) {
        schedulingTask?.cancel()
        schedulingTask = nil
        generation &+= 1

        let currentGeneration = generation
        generationGate.invalidate(before: currentGeneration)
        let worker = self.worker

        schedulingTask = Task { [weak self] in
            await worker.invalidate(before: currentGeneration)

            do {
                if debounce > .zero {
                    try await Task.sleep(for: debounce)
                }
                try Task.checkCancellation()
                guard self?.generation == currentGeneration else { return }

                await worker.submit(
                    generation: currentGeneration,
                    operation: operation,
                    completion: { [weak self] completedGeneration, output in
                        guard let self else { return }
                        await MainActor.run {
                            guard self.generation == completedGeneration else { return }
                            self.schedulingTask = nil
                            publish(completedGeneration, output)
                        }
                    }
                )
            } catch is CancellationError {
                // A newer schedule or invalidate owns the replacement state.
            } catch {
                // Task.sleep only fails through cancellation.
            }
        }
    }

    /// Sync cancellation: further scheduled work and stale publishes are dead.
    public func invalidate() {
        schedulingTask?.cancel()
        schedulingTask = nil
        generation &+= 1
        generationGate.invalidate(before: generation)

        let currentGeneration = generation
        let worker = self.worker
        Task {
            await worker.invalidate(before: currentGeneration)
        }
    }
}
