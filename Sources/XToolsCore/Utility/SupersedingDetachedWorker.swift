import Foundation

/// Thread-safe lower bound on generations allowed to run or publish.
public final class GenerationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var minimumGeneration = 0

    public init() {}

    public func invalidate(before generation: Int) {
        lock.withLock {
            minimumGeneration = max(minimumGeneration, generation)
        }
    }

    public func allows(_ generation: Int) -> Bool {
        lock.withLock { generation >= minimumGeneration }
    }
}

/// Cooperative cancel flag for long-running detached work.
public final class WorkerCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    public func cancel() {
        lock.withLock { cancelled = true }
    }
}

public actor SupersedingDetachedWorker {
    private struct Request: Sendable {
        let generation: Int
        let operation: @Sendable (_ shouldCancel: @escaping @Sendable () -> Bool) throws -> any Sendable
        let completion: @Sendable (_ generation: Int, _ output: any Sendable) async -> Void
    }

    public let generationGate: GenerationGate
    public let cancelInFlight: Bool

    private var pending: Request?
    private var activeTask: Task<any Sendable, Error>?
    private var activeGeneration: Int?
    private var activeToken: WorkerCancellationToken?
    private var isDraining = false
    private var minimumGeneration = 0

    public init(
        cancelInFlight: Bool = true,
        generationGate: GenerationGate = GenerationGate()
    ) {
        self.cancelInFlight = cancelInFlight
        self.generationGate = generationGate
    }

    public func invalidate(before generation: Int) {
        generationGate.invalidate(before: generation)
        minimumGeneration = max(minimumGeneration, generation)

        if let pending, pending.generation < minimumGeneration {
            self.pending = nil
        }
        if cancelInFlight,
           let activeGeneration,
           activeGeneration < minimumGeneration {
            activeToken?.cancel()
            activeTask?.cancel()
        }
    }

    /// Submits work for `generation`. Newer submits replace pending work.
    ///
    /// `operation` may throw `CancellationError` (or check `shouldCancel`) to
    /// skip completion. Domain failures that should publish a binding must be
    /// caught inside `operation` by the caller.
    public func submit<Output: Sendable>(
        generation: Int,
        operation: @escaping @Sendable (
            _ shouldCancel: @escaping @Sendable () -> Bool
        ) throws -> Output,
        completion: @escaping @Sendable (_ generation: Int, _ output: Output) async -> Void
    ) async {
        guard generation >= minimumGeneration,
              generationGate.allows(generation) else { return }

        pending = Request(
            generation: generation,
            operation: { shouldCancel in
                try operation(shouldCancel)
            },
            completion: { completedGeneration, output in
                guard let typed = output as? Output else { return }
                await completion(completedGeneration, typed)
            }
        )
        guard !isDraining else { return }

        isDraining = true
        await drain()
    }

    private func drain() async {
        while let request = pending {
            pending = nil

            guard request.generation >= minimumGeneration,
                  generationGate.allows(request.generation) else { continue }

            let token = WorkerCancellationToken()
            let task = Task.detached(priority: .userInitiated) { () throws -> any Sendable in
                try request.operation {
                    token.isCancelled || Task.isCancelled
                }
            }
            activeTask = task
            activeGeneration = request.generation
            activeToken = token

            let output: any Sendable
            do {
                output = try await task.value
            } catch is CancellationError {
                clearActiveTask(for: request.generation)
                continue
            } catch {
                clearActiveTask(for: request.generation)
                continue
            }
            clearActiveTask(for: request.generation)

            guard request.generation >= minimumGeneration,
                  generationGate.allows(request.generation) else { continue }
            await request.completion(request.generation, output)
        }

        isDraining = false
    }

    private func clearActiveTask(for generation: Int) {
        guard activeGeneration == generation else { return }
        activeTask = nil
        activeGeneration = nil
        activeToken = nil
    }
}
