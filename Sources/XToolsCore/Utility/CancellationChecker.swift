import Foundation

/// 通用计算任务取消检查器。
/// 提供线程安全、轻量的阶段性取消断言，解耦特定领域的跨模块引用。
public struct CancellationChecker: Sendable {
    private let shouldCancel: (@Sendable () -> Bool)?

    public init(shouldCancel: (@Sendable () -> Bool)? = nil) {
        self.shouldCancel = shouldCancel
    }

    public static let disabled = CancellationChecker()

    public func check() throws {
        if shouldCancel?() == true {
            throw CancellationError()
        }
    }
}

/// 兼容别名：原 DiffCancellationChecker 迁移为通用 CancellationChecker
public typealias DiffCancellationChecker = CancellationChecker
