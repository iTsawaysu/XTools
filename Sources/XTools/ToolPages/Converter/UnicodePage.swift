import XToolsCore
import SwiftUI

struct IndexUnicodePage: View {
    var body: some View {
        IndexConverterPage(
            toolID: "text-to-unicode",
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
