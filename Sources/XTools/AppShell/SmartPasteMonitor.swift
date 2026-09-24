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
    struct Suggestion: Equatable {
        let kind: SmartPasteDetector.Kind
        let toolID: ToolID
        let toolTitle: String
        let message: String
    }

    private struct Route {
        let toolID: ToolID
        let message: String
    }

    /// Clipboard kind → owning tool. Tool identities live here (the app layer),
    /// while `SmartPasteDetector` stays UI- and registry-free.
    private static let routes: [SmartPasteDetector.Kind: Route] = [
        .json: Route(toolID: "json-formatter", message: "剪贴板里是 JSON"),
        .jwt: Route(toolID: "jwt-parser", message: "剪贴板里是 JWT"),
        .html: Route(toolID: "html-to-markdown", message: "剪贴板里是 HTML"),
        .xml: Route(toolID: "xml-formatter", message: "剪贴板里是 XML"),
        .cssColor: Route(toolID: "color-picker", message: "剪贴板里是 CSS 颜色"),
        .unixTimestamp: Route(toolID: "date-time-converter", message: "剪贴板里是 Unix 时间戳"),
        .urlEncoded: Route(toolID: "url-encoder-decoder", message: "剪贴板里是 URL 编码文本"),
        .dataURL: Route(toolID: "base64-file-converter", message: "剪贴板里是 Data URL"),
        .base64: Route(toolID: "base64-string", message: "剪贴板里是 Base64")
    ]

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
        suggestion = nil

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

        suggestion = Suggestion(
            kind: kind,
            toolID: tool.id,
            toolTitle: tool.title,
            message: route.message
        )
    }

    func dismiss() {
        dismissedChangeCount = inspectedChangeCount
        suggestion = nil
    }

    func noteSelectedTool(_ toolID: ToolID?) {
        currentToolID = toolID
        if suggestion?.toolID == toolID {
            suggestion = nil
        }
    }
}
