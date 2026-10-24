@testable import XTools
import AppKit
import Foundation
import Testing

/// Smart Detection 轻量版（阶段③ Batch D，design.md §7）：
/// `ClipboardContentHeuristic` 五类有序判定（含负例与前缀混淆），
/// `ClipboardSuggestionModel` 的类型判定路由与「不存内容」边界。
@MainActor
struct ClipboardContentHeuristicTests {
    // MARK: - JSON

    @Test func jsonObjectsAndArraysAreDetected() {
        #expect(ClipboardContentHeuristic.detect(#"{"name":"x","n":1}"#) == .json)
        #expect(ClipboardContentHeuristic.detect(#"[1,2,3]"#) == .json)
        #expect(ClipboardContentHeuristic.detect("  {\n  \"a\": true\n}  ") == .json)
        #expect(ClipboardContentHeuristic.detect("{\"nested\":{\"deep\":[1,\"s\"]}}") == .json)
    }

    @Test func jsonRejectsFragmentsAndBrokenShapes() {
        // 顶层标量（无 fragmentsAllowed 语义）不是对象/数组。
        #expect(ClipboardContentHeuristic.detect("\"just a string\"") == nil)
        #expect(ClipboardContentHeuristic.detect("42") == nil)
        // 前缀混淆：括号开头但解析失败。
        #expect(ClipboardContentHeuristic.detect("{\"a\":") == nil)
        #expect(ClipboardContentHeuristic.detect("{broken}") == nil)
        #expect(ClipboardContentHeuristic.detect("[1,2,") == nil)
    }

    // MARK: - UUID

    @Test func uuidVariantsAreDetected() {
        #expect(ClipboardContentHeuristic.detect("550e8400-e29b-41d4-a716-446655440000") == .uuid)
        #expect(ClipboardContentHeuristic.detect("550E8400-E29B-41D4-A716-446655440000") == .uuid)
    }

    @Test func uuidRejectsPrefixConfusion() {
        // 拖尾巴的 UUID 不算（保守：整串形状匹配）。
        #expect(ClipboardContentHeuristic.detect("550e8400-e29b-41d4-a716-446655440000xyz") == nil)
        // 无连字的 32 位 hex 串不判为 UUID（它恰好是可解的 Base64,属
        // Base64 判定的合法命中——UUID 判定只认连字形态）。
        #expect(ClipboardContentHeuristic.detect("550e8400e29b41a4a716446655440000") != .uuid)
        #expect(ClipboardContentHeuristic.detect("zz50e8400-e29b-41d4-a716-446655440000") == nil)
    }

    // MARK: - Unix 时间戳

    @Test func unixTimestampsAreDetected() {
        #expect(ClipboardContentHeuristic.detect("1761288000") == .unixTimestamp) // 10 位秒
        #expect(ClipboardContentHeuristic.detect("1761288000123") == .unixTimestamp) // 13 位毫秒
    }

    @Test func unixTimestampRejectsPrefixConfusion() {
        #expect(ClipboardContentHeuristic.detect("1234567890a") == nil)
        #expect(ClipboardContentHeuristic.detect("12345678901") == nil) // 11 位
        #expect(ClipboardContentHeuristic.detect("123456789") == nil) // 9 位
        #expect(ClipboardContentHeuristic.detect("1234-567890") == nil)
    }

    // MARK: - Base64

    @Test func base64PayloadsAreDetected() {
        // 16 字符（4 的倍数）恰好可达下限，且可解。
        #expect(ClipboardContentHeuristic.detect("SGVsbG8gV29ybGQh") == .base64)
        #expect(ClipboardContentHeuristic.detect("SGVsbG8gV29ybGQ=") == .base64)
        #expect(ClipboardContentHeuristic.detect("QUJDREVGQUJDREVGQUJDREVG") == .base64)
    }

    @Test func base64RejectsShortAndUndecodableInputs() {
        #expect(ClipboardContentHeuristic.detect("SGVsbG8=") == nil) // < 16
        // 长度不满足 4 的倍数（无 padding 余 2 / padding 超限）。
        #expect(ClipboardContentHeuristic.detect("SGVsbG8sIHdvcmxkIQ") == nil)
        #expect(ClipboardContentHeuristic.detect("SGVsbG8sIHdvcmxkIQ===") == nil)
        // 字符集外。
        #expect(ClipboardContentHeuristic.detect("SGVs!G8sIHdvcmxkIQ==") == nil)
        // padding 位置错误（中段等号）。
        #expect(ClipboardContentHeuristic.detect("SG=sbG8sIHdvcmxkIQ==") == nil)
        // 普通长英文句子：可编码字符集内但不满足 4 倍数或解码失败。
        #expect(ClipboardContentHeuristic.detect("absolutely plain long text here") == nil)
    }

    // MARK: - 颜色

    @Test func colorsAreDetected() {
        #expect(ClipboardContentHeuristic.detect("#FF8800") == .color)
        #expect(ClipboardContentHeuristic.detect("#ff8800") == .color)
        #expect(ClipboardContentHeuristic.detect("rgb(255, 136, 0)") == .color)
        #expect(ClipboardContentHeuristic.detect("rgba(255, 136, 0, 0.5)") == .color)
        #expect(ClipboardContentHeuristic.detect("hsl(32, 100%, 50%)") == .color)
        #expect(ClipboardContentHeuristic.detect("hsla(32, 100%, 50%, 1)") == .color)
    }

    @Test func colorsRejectShortHexAndJunkBodies() {
        #expect(ClipboardContentHeuristic.detect("#FF880") == nil) // 5 位
        #expect(ClipboardContentHeuristic.detect("#FF88 00") == nil)
        #expect(ClipboardContentHeuristic.detect("rgb()") == nil)
        #expect(ClipboardContentHeuristic.detect("rgb(zug zug)") == nil)
        #expect(ClipboardContentHeuristic.detect("red") == nil) // 颜色名不做判定
    }

    // MARK: - 有序性与兜底负例

    @Test func orderedDetectionPrefersMoreSpecificKinds() {
        // UUID 是合法 Base64 字符集外的连字形态；JSON 优先于一切。
        let payload = #"{"v":"550e8400-e29b-41d4-a716-446655440000"}"#
        #expect(ClipboardContentHeuristic.detect(payload) == .json)
    }

    @Test func emptyAndPlainTextProduceNothing() {
        #expect(ClipboardContentHeuristic.detect("") == nil)
        #expect(ClipboardContentHeuristic.detect("   \n\t ") == nil)
        #expect(ClipboardContentHeuristic.detect("hello world, this is a plain sentence") == nil)
        #expect(ClipboardContentHeuristic.detect(String(repeating: "x", count: 33 * 1024)) == nil) // 超界
    }

    // MARK: - ClipboardSuggestionModel（路由 + 隐私边界）

    private func pasteboardWith(_ text: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("ClipboardContentHeuristicTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard
    }

    @Test func suggestionRoutesFiveKindsToTools() throws {
        let cases: [(String, ClipboardContentHeuristic.Kind, ToolID, String?)] = [
            (#"{"a":1}"#, .json, "formatter", "json"),
            ("550e8400-e29b-41d4-a716-446655440000", .uuid, "generator", "uuid"),
            ("1761288000", .unixTimestamp, "date-time-converter", nil),
            ("SGVsbG8sIHdvcmxkIQ==", .base64, "text-encoding", "base64"),
            ("#FF8800", .color, "color-picker", nil),
        ]
        for (text, kind, toolID, segment) in cases {
            let model = ClipboardSuggestionModel()
            let pasteboard = pasteboardWith(text)
            defer { pasteboard.releaseGlobally() }
            model.refresh(registry: .default, pasteboard: pasteboard)

            let suggestion = try #require(model.suggestion)
            #expect(suggestion.kind == kind)
            #expect(suggestion.toolID == toolID)
            #expect(suggestion.segment == segment)
            #expect(!suggestion.message.contains(text), "建议文案不得包含剪贴板内容本体")
        }
    }

    @Test func suggestionSurvivesOnlyUntilContentChangesAndNeverStoresContent() {
        let model = ClipboardSuggestionModel()
        let pasteboard = pasteboardWith("1761288000")
        defer { pasteboard.releaseGlobally() }
        model.refresh(registry: .default, pasteboard: pasteboard)
        #expect(model.suggestion != nil)

        // 换成不可判定内容：旧建议作废。
        pasteboard.clearContents()
        pasteboard.setString("plain words", forType: .string)
        model.refresh(registry: .default, pasteboard: pasteboard)
        #expect(model.suggestion == nil)

        // 未变化的剪贴板（changeCount 不变）不重采样。
        model.refresh(registry: .default, pasteboard: pasteboard)
        #expect(model.suggestion == nil)
    }

    @Test func entryTextReadsContentOnlyAtExplicitOpenTime() {
        let model = ClipboardSuggestionModel()
        let pasteboard = pasteboardWith("1761288000")
        defer { pasteboard.releaseGlobally() }
        model.refresh(registry: .default, pasteboard: pasteboard)

        #expect(model.entryText(pasteboard: pasteboard) == "1761288000")

        pasteboard.clearContents()
        pasteboard.setString(
            String(repeating: "a", count: ClipboardContentHeuristic.maxInspectedLength + 1),
            forType: .string
        )
        #expect(model.entryText(pasteboard: pasteboard) == nil, "超界内容不投递")
    }
}
