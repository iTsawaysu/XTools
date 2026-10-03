import Foundation

/// Sheet 面板请求的共享机制：同一会话同一时刻至多一个在途面板请求。
///
/// 每个请求登记唯一 requestID，任务体捕获该 ID 并在结束时回报：
/// `finish(id:)` 仅当 ID 仍是当前在途请求时清理并返回 true，过期完成
/// 静默丢弃（不覆盖更新的请求）；`cancel()` 先停任务再清理，重复调用
/// 无副作用。图片处理/批量转换/Favicon/文件类型检测四个会话共用。
struct PanelRequestBox {
    private(set) var task: Task<Void, Never>?
    private var activeRequestID: UUID?

    var hasActiveRequest: Bool { task != nil }

    /// 预登记请求并返回其 ID；任务体创建后经 `attach` 挂载。
    mutating func begin() -> UUID {
        let requestID = UUID()
        activeRequestID = requestID
        return requestID
    }

    /// 挂载已创建的任务（任务先建、查重后挂载的会话保留原顺序）。
    @discardableResult
    mutating func attach(_ task: Task<Void, Never>) -> Task<Void, Never> {
        self.task = task
        return task
    }

    /// 完成回报：仅当前在途请求的 ID 命中时清理并返回 true。
    @discardableResult
    mutating func finish(id: UUID) -> Bool {
        guard activeRequestID == id else { return false }
        activeRequestID = nil
        task = nil
        return true
    }

    /// 取消在途请求：先取消任务再清理。
    mutating func cancel() {
        activeRequestID = nil
        task?.cancel()
        task = nil
    }
}
