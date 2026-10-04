import Foundation

/// Sheet 面板请求的共享机制：同一会话同一时刻至多一个在途面板请求。
///
/// 每个请求登记唯一 requestID，任务体捕获该 ID 并在结束时回报：
/// `finish(id:)` 仅当 ID 仍是当前在途请求时清理并返回 true，过期完成
/// 静默丢弃（不覆盖更新的请求）；`cancel()` 先停任务再清理，重复调用
/// 无副作用。图片处理/批量转换/Favicon/文件类型检测四个会话共用。
struct PanelRequestBox {
    private final class State: @unchecked Sendable {
        var task: Task<Void, Never>?
        var activeRequestID: UUID?
    }

    private let state = State()

    var task: Task<Void, Never>? {
        state.task
    }

    var hasActiveRequest: Bool { state.task != nil }

    /// 预登记请求并返回其 ID；任务体创建后经 `attach` 挂载。
    @discardableResult
    mutating func begin() -> UUID {
        let requestID = UUID()
        state.activeRequestID = requestID
        return requestID
    }

    /// 挂载已创建的任务（任务先建、查重后挂载的会话保留原顺序）。
    @discardableResult
    mutating func attach(_ task: Task<Void, Never>) -> Task<Void, Never> {
        state.task = task
        return task
    }

    /// 完成回报：仅当前在途请求的 ID 命中时清理并返回 true。
    @discardableResult
    mutating func finish(id: UUID) -> Bool {
        guard state.activeRequestID == id else { return false }
        state.activeRequestID = nil
        state.task = nil
        return true
    }

    /// 取消在途请求：先取消任务再清理。
    mutating func cancel() {
        state.activeRequestID = nil
        state.task?.cancel()
        state.task = nil
    }

    /// 统一执行面板请求并映射结果或错误，避免各会话重复样板代码。
    @discardableResult
    @MainActor
    mutating func request<Result>(
        _ action: @escaping @MainActor () async throws -> Result?,
        onSuccess: @escaping @MainActor (Result) -> Void,
        onError: (@MainActor (String) -> Void)? = nil
    ) -> Task<Void, Never> {
        if let existing = state.task {
            return existing
        }
        let requestID = begin()
        let state = self.state
        let task = Task { @MainActor [weak state] in
            guard let state else { return }
            do {
                guard let result = try await action() else {
                    if state.activeRequestID == requestID {
                        state.activeRequestID = nil
                        state.task = nil
                    }
                    return
                }
                guard !Task.isCancelled, state.activeRequestID == requestID else { return }
                state.activeRequestID = nil
                state.task = nil
                onSuccess(result)
            } catch is CancellationError {
                if state.activeRequestID == requestID {
                    state.activeRequestID = nil
                    state.task = nil
                }
            } catch {
                guard state.activeRequestID == requestID else { return }
                state.activeRequestID = nil
                state.task = nil
                onError?(FileInputPanelFailure.diagnosticMessage(for: error))
            }
        }
        return attach(task)
    }
}
