import Foundation

/// Sheet 面板请求的共享机制：同一会话同一时刻至多一个在途面板请求。
///
/// 只有当前请求可以交回结果，取消后的回调由请求 ID 拦截。
@MainActor
final class PanelRequestBox {
    private(set) var task: Task<Void, Never>?
    private var activeRequestID: UUID?

    var hasActiveRequest: Bool { task != nil }

    private func finish(id: UUID) -> Bool {
        guard activeRequestID == id else { return false }
        activeRequestID = nil
        task = nil
        return true
    }

    func cancel() {
        activeRequestID = nil
        task?.cancel()
        task = nil
    }

    @discardableResult
    func request<Result>(
        _ action: @escaping @MainActor () async throws -> Result?,
        onSuccess: @escaping @MainActor (Result) -> Void,
        onError: (@MainActor (String) -> Void)? = nil
    ) -> Task<Void, Never> {
        if let existing = task {
            return existing
        }
        let requestID = UUID()
        activeRequestID = requestID
        let task = Task { @MainActor [weak self] in
            do {
                try Task.checkCancellation()
                let result = try await action()
                guard self?.finish(id: requestID) == true, !Task.isCancelled, let result else { return }
                onSuccess(result)
            } catch is CancellationError {
                _ = self?.finish(id: requestID)
            } catch {
                guard self?.finish(id: requestID) == true, !Task.isCancelled else { return }
                onError?(FileInputPanelFailure.diagnosticMessage(for: error))
            }
        }
        self.task = task
        return task
    }

    deinit {
        task?.cancel()
    }
}
