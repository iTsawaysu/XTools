import XToolsCore
import SwiftUI

struct IndexBase64StringPage: View {
    var body: some View {
        IndexConverterPage(
            toolID: "base64-string",
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
