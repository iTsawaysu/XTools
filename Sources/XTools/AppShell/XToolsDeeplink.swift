import Foundation

/// `xtools://tool/<id>?segment=<s>&input=<text>` 深链（阶段③ Batch D，
/// design.md §8）。解析为纯值；容错语义：
/// - scheme/host 不符、路径缺工具 id → 整体忽略（nil）。
/// - 工具 id 在注册表不存在 → 消费端忽略（保持当前选择不动）。
/// - segment 非法 → 由目标 Hub 的分段枚举校验丢弃（既有
///   HubSegmentEntryHint 消费语义）。
/// - input 空 / 缺失 → 仅打开工具不预填；input 走 SmartPaste 通道
///   （WorkbenchEntryPayload）预填目标工具首位输入。
struct XToolsDeeplink: Equatable {
    static let scheme = "xtools"
    static let toolHost = "tool"

    let toolID: ToolID
    let segment: String?
    let input: String?

    static func parse(_ url: URL) -> XToolsDeeplink? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == toolHost
        else { return nil }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard let rawToolID = pathComponents.first,
              !rawToolID.isEmpty
        else { return nil }
        // 工具 id 不做注册表校验（消费端 openSuggestionTarget 兜底忽略），
        // 这里只收敛出 ToolID 值。
        let toolID = ToolID(rawValue: rawToolID)

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        let segment = queryItems.first { $0.name == "segment" }?
            .value.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let input = queryItems.first { $0.name == "input" }?.value
            .flatMap { $0.isEmpty ? nil : $0 }

        return XToolsDeeplink(toolID: toolID, segment: segment, input: input)
    }
}

/// 深链消费去重（阶段③ Batch D）：SwiftUI `.onOpenURL` 会把同一 URL 事件
/// 递给每个已挂载窗口的 handler——多窗口下必须保证一次 URL 只被消费一次。
/// 第一个 claim 的窗口消费；同帧内重复 claim 同一 URL 一律拒绝。URL 事件
/// 间隔超过去重窗口的重复 URL（用户再次触发同一链接）照常生效。
@MainActor
final class XToolsDeeplinkConsumer {
    static let shared = XToolsDeeplinkConsumer()

    /// 同一 URL 的去重窗口（秒）：SwiftUI 对同一事件的多窗口分发发生在
    /// 同一 runloop 邻域内，取一个足够覆盖该邻域、又远小于人工重复触发的值。
    static let deduplicationWindow: TimeInterval = 0.05

    private var lastClaimedURL: URL?
    private var lastClaimedAt: TimeInterval = 0

    func claim(_ url: URL, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        // 被拒绝的重复 claim 不刷新窗口锚点：去重窗口固定从消费时刻起算，
        // 多窗口同帧分发无论多少个 handler 都挡得住，窗口外的再次触发
        // （用户重新打开同一链接）不被滑动窗口吞掉。
        if url == lastClaimedURL, now - lastClaimedAt < Self.deduplicationWindow {
            return false
        }
        lastClaimedURL = url
        lastClaimedAt = now
        return true
    }
}
