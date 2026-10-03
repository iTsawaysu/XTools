import Foundation
import os

public enum HTMLReadabilityScriptResource {
    public static let version = "0.6.0"

    public enum ResourceError: Error, Equatable, Sendable {
        case missing
        case unreadable
    }

    /// 成功结果的进程级缓存：脚本约几十 KB，而每次 URL 正文提取都要执行它，
    /// 不必每次转换都从 bundle 重读。只缓存成功——读取失败（打包异常等）
    /// 保持可重试语义。锁保护的不可变容器满足 Swift 6 严格并发。
    private static let cachedScript = OSAllocatedUnfairLock<String?>(initialState: nil)

    public static func load() throws -> String {
        if let cached = cachedScript.withLock({ $0 }) {
            return cached
        }
        let script = try readFromBundle()
        cachedScript.withLock { $0 = script }
        return script
    }

    private static func readFromBundle() throws -> String {
        guard let url = Bundle.module.url(
            forResource: "Readability-\(version)",
            withExtension: "js"
        ) else {
            throw ResourceError.missing
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ResourceError.unreadable
        }
    }
}
