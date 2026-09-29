import Foundation

/// One explicit authorization owns one session. Completed successes and failures
/// remain memoized within that scope: no retry loop, cache eviction/reload churn,
/// or cross-result sharing. The URL ceiling also bounds tasks and queued work.
public actor MarkdownRemoteImageSession {
    public nonisolated let id = UUID()
    private nonisolated let cancellation = WorkerCancellationToken()
    private let budget: MarkdownRemoteImageBudget
    private let loader: @Sendable (URL) async throws -> MarkdownRemoteImage
    private var jobs: [URL: Task<MarkdownRemoteImage, Error>] = [:]
    private var activeLoads = 0
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var decodedByteCount = 0

    public init(budget: MarkdownRemoteImageBudget = .init()) {
        self.budget = budget
        let service = MarkdownRemoteImageService(budget: budget)
        self.loader = { try await service.load($0) }
    }

    init(
        budget: MarkdownRemoteImageBudget = .init(),
        loader: @escaping @Sendable (URL) async throws -> MarkdownRemoteImage
    ) {
        self.budget = budget
        self.loader = loader
    }

    public nonisolated var isCancelled: Bool { cancellation.isCancelled }

    /// Revoke publication synchronously; cancellation of URLSession and queued
    /// work is drained on the actor without blocking the UI/responder thread.
    public nonisolated func cancel() {
        cancellation.cancel()
        Task { await invalidate() }
    }

    public func image(for url: URL) async throws -> MarkdownRemoteImage {
        try checkCancellation()
        let job: Task<MarkdownRemoteImage, Error>
        if let existing = jobs[url] {
            job = existing
        } else {
            guard jobs.count < budget.maximumURLs else { throw MarkdownRemoteImageError.scopeBudget }
            job = Task.detached(priority: .utility) { try await self.load(url) }
            jobs[url] = job
        }
        let image = try await job.value
        try checkCancellation()
        return image
    }

    func invalidate() {
        cancellation.cancel()
        let obsoleteJobs = jobs.values
        jobs.removeAll()
        decodedByteCount = 0
        for job in obsoleteJobs { job.cancel() }
        let obsoleteWaiters = waiters
        waiters.removeAll()
        for waiter in obsoleteWaiters { waiter.resume(throwing: CancellationError()) }
    }

    private func load(_ url: URL) async throws -> MarkdownRemoteImage {
        try await acquireSlot()
        defer { releaseSlot() }
        try checkCancellation()
        let image = try await loader(url)
        try checkCancellation()
        guard image.decodedByteCount > 0,
              image.decodedByteCount <= budget.imageDecodedByteLimit,
              image.decodedByteCount <= budget.scopeDecodedByteLimit - decodedByteCount else {
            throw MarkdownRemoteImageError.scopeBudget
        }
        decodedByteCount += image.decodedByteCount
        return image
    }

    private func acquireSlot() async throws {
        try checkCancellation()
        if activeLoads < budget.maximumConcurrentLoads {
            activeLoads += 1
        } else {
            try await withCheckedThrowingContinuation { waiters.append($0) }
        }
    }

    private func releaseSlot() {
        if !waiters.isEmpty, !isCancelled {
            waiters.removeFirst().resume()
        } else {
            activeLoads -= 1
        }
    }

    private func checkCancellation() throws {
        try Task.checkCancellation()
        if isCancelled { throw CancellationError() }
    }

    // Tests inspect bounded resource ownership, not timing-only performance.
    var resourceUsage: (urlCount: Int, decodedBytes: Int, active: Int, queued: Int) {
        (jobs.count, decodedByteCount, activeLoads, waiters.count)
    }
}
