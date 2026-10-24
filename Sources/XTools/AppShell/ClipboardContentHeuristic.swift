import AppKit
import Foundation

/// Smart Detection 轻量版的剪贴板内容嗅探（阶段③ Batch D，design.md §7 /
/// PRD 需求 7）。与 `SmartPasteDetector`（建议横幅的通用检测器）并存：
/// 本类型只服务「为你建议」区，类别集是它的子集 + UUID（JSON / UUID /
/// Unix 时间戳 / Base64 / 颜色），判定序按 specificity 排列。
///
/// 隐私与成本边界（刻意保持，勿放宽）：
/// - 纯本地判定，无网络、无 IO；输入超界（32K 字符）直接不判。
/// - 建议状态只保留**类型判定结果**（Kind → 工具路由 + 文案），从不保留
///   内容本体、不落盘、不进持久化；预填文本只在用户显式点击建议的瞬间
///   经 `entryText()` 现读现投（投递载荷驻留内存、随选择变化作废）。
/// - 判定保守：整串（去首尾空白）形状匹配才算数，前缀混淆（如 UUID 后
///   拖尾巴、时间戳混字母）一律判否——错建议比没建议差。
public enum ClipboardContentHeuristic {
    public enum Kind: String, CaseIterable, Sendable {
        case json
        case uuid
        case unixTimestamp
        case base64
        case color
    }

    /// 检查输入上限（字符数）：与 SmartPasteDetector 同一量级，超界不判。
    public static let maxInspectedLength = 32 * 1024

    /// 有序判定：JSON → UUID → Unix 时间戳 → Base64 → 颜色。Base64 的
    /// 字符集最宽松所以靠后；同文本命中多个类别时取更具体的。
    public static func detect(_ raw: String) -> Kind? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isWithinCharacterLimit(text, limit: maxInspectedLength) else {
            return nil
        }
        if isJSONObjectOrArray(text) { return .json }
        if isUUID(text) { return .uuid }
        if isUnixTimestamp(text) { return .unixTimestamp }
        if isBase64(text) { return .base64 }
        if isColor(text) { return .color }
        return nil
    }

    public static func isWithinCharacterLimit(_ text: String, limit: Int) -> Bool {
        guard limit >= 0 else { return false }
        guard let boundary = text.index(
            text.startIndex,
            offsetBy: limit,
            limitedBy: text.endIndex
        ) else {
            return true
        }
        return boundary == text.endIndex
    }

    // MARK: - JSON（对象 / 数组）

    /// 形状前置（首尾括号配对）+ Foundation 可解析验证：避免对纯
    /// `{`/`[` 前缀的普通文本产生假阳性。
    private static func isJSONObjectOrArray(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[",
              let last = text.last, last == "}" || last == "]"
        else { return false }
        guard let data = text.data(using: .utf8) else { return false }
        // 不带 .fragmentsAllowed：顶层标量（"str"/42）本就解析失败，
        // 只认对象 / 数组顶层形态。
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    // MARK: - UUID

    /// 标准 8-4-4-4-12 十六进制连字形式（大小写均可）。
    private static let uuidPattern = try? NSRegularExpression(
        pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
    )

    private static func isUUID(_ text: String) -> Bool {
        guard let uuidPattern else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return uuidPattern.firstMatch(in: text, range: range) != nil
    }

    // MARK: - Unix 时间戳

    /// 10 位（秒，2001-2286 年量级）或 13 位（毫秒）纯数字整串。
    private static func isUnixTimestamp(_ text: String) -> Bool {
        // 纯数字整串校验（锚定整体），再按位数判定；避免 "1234567890a"
        // 这类前缀混淆被部分匹配放行。
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) else {
            return false
        }
        return text.count == 10 || text.count == 13
    }

    // MARK: - Base64

    private static let base64Alphabet = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    )

    /// ≥16 字符、仅标准字符集（padding `=` 只允许结尾）、长度 4 的倍数
    /// （padding 语义成立）、且 `Data(base64Encoded:)` 真的能解。
    /// 纯十六进制串（MD5/SHA 摘要形态）拒判：它们同时落在 Base64 字符集内
    /// 且常满足 4 倍长度，会误报「剪贴板中有 Base64」。
    private static func isBase64(_ text: String) -> Bool {
        guard text.count >= 16 else { return false }
        var body = Substring(text)
        var paddingCount = 0
        while body.hasSuffix("=") {
            body = body.dropLast()
            paddingCount += 1
        }
        guard paddingCount <= 2, !body.isEmpty,
              body.unicodeScalars.allSatisfy(base64Alphabet.contains)
        else { return false }
        guard (body.count + paddingCount) % 4 == 0 else { return false }
        if body.unicodeScalars.allSatisfy(hexDigits.contains) { return false }
        return Data(base64Encoded: text) != nil
    }

    // MARK: - 颜色

    /// `#RRGGBB`（6 位十六进制）与 `rgb()/rgba()/hsl()/hsla()` 函数形式；
    /// 函数体仅允许数字、小数点、逗号、百分号、空白。
    private static func isColor(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if lowercased.hasPrefix("#") {
            let digits = lowercased.dropFirst()
            guard digits.count == 6,
                  digits.unicodeScalars.allSatisfy({ hexDigits.contains($0) })
            else { return false }
            return true
        }
        let functions = ["rgb(", "rgba(", "hsl(", "hsla("]
        guard let function = functions.first(where: { lowercased.hasPrefix($0) }),
              lowercased.hasSuffix(")")
        else { return false }
        let body = lowercased.dropFirst(function.count).dropLast()
        guard !body.isEmpty else { return false }
        return body.unicodeScalars.allSatisfy { cssColorAllowed.contains($0) }
    }

    private static let hexDigits = CharacterSet(charactersIn: "0123456789abcdef")
    private static let cssColorAllowed = CharacterSet(charactersIn: "0123456789.,% ")
}

/// 「为你建议」的状态持有者（阶段③ Batch D）：App 激活时采样一次剪贴板，
/// 变化才重新判定；只保留类型判定与工具路由。工具身份（app 层关注点）与
/// 判定器（UI/registry 无关）分离，同 SmartPasteMonitor 的分层纪律。
@MainActor
final class ClipboardSuggestionModel: ObservableObject {
    struct Suggestion: Equatable, Hashable, Identifiable {
        let kind: ClipboardContentHeuristic.Kind
        let toolID: ToolID
        let toolTitle: String
        let systemImage: String
        /// 建议文案，如「剪贴板中有 JSON」（不含内容本体）。
        let message: String
        /// 分段 Hub 的深链分段（formatter: json；text-encoding: base64）。
        let segment: String?

        var id: String { kind.rawValue }
    }

    /// 判定类别 → 工具路由（五类；与 ClipboardContentHeuristic.Kind 一一对应）。
    private static let routes: [ClipboardContentHeuristic.Kind: (toolID: ToolID, segment: String?, message: String)] = [
        .json: ("formatter", "json", "剪贴板中有 JSON"),
        .uuid: ("generator", "uuid", "剪贴板中有 UUID"),
        .unixTimestamp: ("date-time-converter", nil, "剪贴板中有 Unix 时间戳"),
        .base64: ("text-encoding", "base64", "剪贴板中有 Base64"),
        .color: ("color-picker", nil, "剪贴板中有 CSS 颜色"),
    ]

    /// 检测字节上限：每次读入按 UTF-8 界定（八字节/字符远高于字符级上限
    /// 可能接受的任何输入）。
    private static let maxInspectedBytes = ClipboardContentHeuristic.maxInspectedLength * 8

    @Published private(set) var suggestion: Suggestion?

    private var inspectedChangeCount = -1

    /// App 激活/回前台时重采样；changeCount 未变直接跳过。检测后立即丢弃
    /// 文本本体（建议只存类型判定）。
    func refresh(registry: ToolRegistry, pasteboard: NSPasteboard = .general) {
        let changeCount = pasteboard.changeCount
        guard changeCount != inspectedChangeCount else { return }
        inspectedChangeCount = changeCount

        // 任何新内容都作废旧建议（旧建议描述的是旧剪贴板）。
        suggestion = nil

        guard let data = pasteboard.data(forType: .string),
              !data.isEmpty,
              data.count <= Self.maxInspectedBytes,
              let text = String(data: data, encoding: .utf8),
              let kind = ClipboardContentHeuristic.detect(text),
              let route = Self.routes[kind],
              let tool = registry.tool(for: route.toolID)
        else { return }

        suggestion = Suggestion(
            kind: kind,
            toolID: tool.id,
            toolTitle: tool.title,
            systemImage: tool.systemImage,
            message: route.message,
            segment: route.segment
        )
    }

    /// 用户显式点击建议的瞬间现读剪贴板文本（预填投递专用）；此刻内容
    /// 才进入内存投递载荷，建议状态本身始终不含内容。
    func entryText(pasteboard: NSPasteboard = .general) -> String? {
        guard let data = pasteboard.data(forType: .string),
              !data.isEmpty,
              data.count <= Self.maxInspectedBytes,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty,
              ClipboardContentHeuristic.isWithinCharacterLimit(text, limit: ClipboardContentHeuristic.maxInspectedLength)
        else { return nil }
        return text
    }
}
