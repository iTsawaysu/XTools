import XToolsCore
import SwiftUI

/// 「文本编码」Hub 的 Base64 分段：经共享 IndexConverterPage 嵌入
/// （embedsPageShell: false，页面壳由 Hub 提供），workspace key 沿用
/// 合并前的 base64-string。
struct IndexBase64StringSegment: View {
    var body: some View {
        IndexConverterPage(
            toolID: "base64-string",
            embedsPageShell: false,
            title: "Base64 字符串",
            subtitle: "在纯文本与 Base64 之间互转，支持 UTF-8。",
            modes: [
                IndexConverterMode(id: "enc", label: "编码"),
                IndexConverterMode(id: "dec", label: "解码")
            ],
            initialMode: "dec",
            placeholder: "在此粘贴文本或 Base64…",
            backfillsOutputOnModeChange: true,
            // 编码方向空格是有效字符（严格空判定）；解码方向纯空白视为
            // 空态，否则用户清空内容残留空白时会看到「不是有效的 Base64」。
            isEmptyInputForMode: { input, mode in
                mode == "enc"
                    ? input.isEmpty
                    : input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            },
            errorMessage: { error in
                (error as? Base64Conversion.ConversionError)?.errorDescription
                    ?? "Base64 解码失败。"
            }
        ) { input, mode in
            mode == "enc" ? Base64Conversion.encode(input) : try Base64Conversion.decode(input)
        }
    }
}
