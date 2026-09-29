import XToolsCore
import SwiftUI

/// 「文本编码」Hub 的 Unicode 分段：经共享 IndexConverterPage 嵌入
/// （embedsPageShell: false，页面壳由 Hub 提供），workspace key 沿用
/// 合并前的 text-to-unicode。
struct IndexUnicodeSegment: View {
    var body: some View {
        IndexConverterPage(
            toolID: "text-to-unicode",
            embedsPageShell: false,
            title: "Unicode 转换",
            subtitle: "文本与 Unicode 转义序列互转。",
            modes: [
                IndexConverterMode(id: "enc", label: "文本→Unicode"),
                IndexConverterMode(id: "dec", label: "Unicode→文本")
            ],
            placeholder: "输入文本或 \\u 转义…",
            backfillsOutputOnModeChange: true,
            errorMessage: { error in
                (error as? UnicodeEscaping.DecodingError)?.errorDescription
                    ?? "Unicode 转义解码失败。"
            }
        ) { input, mode in
            if mode == "enc" {
                return UnicodeEscaping.encode(input)
            }
            return try UnicodeEscaping.decodeValidated(input)
        }
    }
}
