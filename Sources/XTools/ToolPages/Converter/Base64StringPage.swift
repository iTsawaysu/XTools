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
            errorMessage: { error in
                (error as? Base64Conversion.ConversionError)?.errorDescription
                    ?? "Base64 解码失败。"
            }
        ) { input, mode in
            mode == "enc" ? Base64Conversion.encode(input) : try Base64Conversion.decode(input)
        }
    }
}
