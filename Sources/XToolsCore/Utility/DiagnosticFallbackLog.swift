import Foundation
import os

/// 诊断兜底路径的底层错误留档。
///
/// 各工作台/会话的最后一个 catch 分支展示给用户的是稳定兜底文案，底层
/// 错误在此之前完全丢失——真触发时（新增错误类型漏配 errorDescription、
/// 预期之外的异常路径）无从归因。这里把兜底错误写入统一分类的 os_log，
/// 可在 Console.app 按 subsystem + "diagnostics-fallback" 检索。
///
/// 隐私：动态错误内容保持 os_log 默认脱敏（<private>），用户输入不会
/// 进日志；仅代码位置与错误类型名按 public 记录（纯代码标识）。
public enum DiagnosticFallbackLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "XTools",
        category: "diagnostics-fallback"
    )

    /// 在兜底 catch 中留档底层错误。`context` 用稳定的代码位置标识
    /// （如 "FormatRunner.run"），便于检索时定位来源。
    public static func record(_ error: Error, context: StaticString) {
        logger.error(
            "Fallback at \(context, privacy: .public): \(String(describing: type(of: error)), privacy: .public) — \(error.localizedDescription)"
        )
    }
}
