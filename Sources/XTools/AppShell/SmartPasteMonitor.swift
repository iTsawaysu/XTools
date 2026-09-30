import AppKit
import Foundation
import XToolsCore

/// Window-scoped clipboard observer behind the shell's smart-paste suggestion.
///
/// Privacy and cost rules (deliberate, please keep):
/// - Samples the pasteboard only when the app becomes active and the pasteboard
///   actually changed since the last sample — never polls in the background.
/// - Reads only the string representation, bounded by
///   `SmartPasteDetector.maxInspectedLength`.
/// - A dismissal sticks to that clipboard generation, so the same content never
///   re-suggests. Copying again re-arms it.
/// - Never suggests the tool the user is already looking at.
@MainActor
final class SmartPasteMonitor: ObservableObject {
    struct Suggestion: Hashable {
        let kind: SmartPasteDetector.Kind
        let toolID: ToolID
        let toolTitle: String
        let message: String
        /// 目标工具自带分段时的深链分段（formatter: json/xml；text-encoding: url/base64）。
        let hubSegment: String?
    }

    private struct Route {
        let toolID: ToolID
        let message: String
        /// 目标工具自带分段时的深链分段（formatter: json/xml；text-encoding: url/base64）。
        /// var + 默认值使其留在 memberwise init 的可选参数里。
        var hubSegment: String? = nil
    }

    /// Clipboard kind → owning tool. Tool identities live here (the app layer),
    /// while `SmartPasteDetector` stays UI- and registry-free.
    private static let routes: [SmartPasteDetector.Kind: Route] = [
        .json: Route(toolID: "formatter", message: "剪贴板里是 JSON", hubSegment: "json"),
        .jwt: Route(toolID: "jwt-parser", message: "剪贴板里是 JWT"),
        .html: Route(toolID: "html-to-markdown", message: "剪贴板里是 HTML"),
        .xml: Route(toolID: "formatter", message: "剪贴板里是 XML", hubSegment: "xml"),
        .cssColor: Route(toolID: "color-picker", message: "剪贴板里是 CSS 颜色"),
        .unixTimestamp: Route(toolID: "date-time-converter", message: "剪贴板里是 Unix 时间戳"),
        .urlEncoded: Route(toolID: "text-encoding", message: "剪贴板里是 URL 编码文本", hubSegment: "url"),
        .dataURL: Route(toolID: "base64-file-converter", message: "剪贴板里是 Data URL"),
        .base64: Route(toolID: "text-encoding", message: "剪贴板里是 Base64", hubSegment: "base64")
    ]

    /// 每次突变都包在 applyToolMotion（panelReveal 事务）里，横幅的进出场
    /// 因此落在动画事务内（ToastCenter 同构）；Reduce Motion 时自动直执行。
    @Published private(set) var suggestion: Suggestion?

    private var inspectedChangeCount = -1
    private var dismissedChangeCount = -1
    private var currentToolID: ToolID?

    /// NSPasteboard is main-thread-only and has no bounded read, so a huge
    /// clipboard still pays the fetch itself; this bound only skips building
    /// the String. Eight UTF-8 bytes per character is far above anything the
    /// character-level inspection limit can ever accept.
    private static let maxInspectedBytes = SmartPasteDetector.maxInspectedLength * 8

    static func isWithinInspectionLimit(
        _ text: String,
        limit: Int = SmartPasteDetector.maxInspectedLength
    ) -> Bool {
        SmartPasteDetector.isWithinCharacterLimit(text, limit: limit)
    }

    /// Re-samples the pasteboard when it changed since the last sample.
    func refresh(registry: ToolRegistry, pasteboard: NSPasteboard = .general) {
        let changeCount = pasteboard.changeCount
        guard changeCount != inspectedChangeCount else { return }
        inspectedChangeCount = changeCount

        // Any new content invalidates the previous suggestion, including content
        // that does not classify — the old hint is about the old clipboard.
        applyToolMotion { suggestion = nil }

        guard changeCount != dismissedChangeCount else { return }
        guard let data = pasteboard.data(forType: .string),
              !data.isEmpty,
              data.count <= Self.maxInspectedBytes,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty,
              Self.isWithinInspectionLimit(text),
              let kind = SmartPasteDetector.detect(text),
              let route = Self.routes[kind],
              let tool = registry.tool(for: route.toolID),
              tool.id != currentToolID
        else {
            return
        }

        applyToolMotion {
            suggestion = Suggestion(
                kind: kind,
                toolID: tool.id,
                toolTitle: tool.title,
                message: route.message,
                hubSegment: route.hubSegment
            )
        }
    }

    func dismiss() {
        dismissedChangeCount = inspectedChangeCount
        applyToolMotion { suggestion = nil }
    }

    func noteSelectedTool(_ toolID: ToolID?) {
        currentToolID = toolID
        if suggestion?.toolID == toolID {
            applyToolMotion { suggestion = nil }
        }
    }
}

/// SmartPaste 深链的一次性分段提示：横幅点击时写入目标工具与分段，经
/// environmentObject 注入，目标 Hub 出现时校验 toolID 后消费并清空（工具
/// 已打开再点建议时经 onChange 立即生效），「格式化」「文本编码」等
/// 分段式 Hub 共用。
@MainActor
final class HubSegmentEntryHint: ObservableObject {
    struct Request: Equatable {
        let toolID: ToolID
        let segment: String
    }

    @Published var request: Request?
}
