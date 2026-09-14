import XToolsCore
import SwiftUI

struct IndexURLCoderPage: View {
    var body: some View {
        IndexConverterPage(
            toolID: "url-encoder-decoder",
            title: "URL 编解码",
            subtitle: "对路径片段、查询参数值等 URL 组件进行百分号编码与解码。",
            modes: [
                IndexConverterMode(id: "enc", label: "编码"),
                IndexConverterMode(id: "dec", label: "解码")
            ],
            placeholder: "输入路径片段或查询参数值",
            backfillsOutputOnModeChange: true,
            errorMessage: { error in
                (error as? URLPercentCoding.CodingError)?.errorDescription
                    ?? "URL 解码失败。"
            }
        ) { input, mode in
            if mode == "enc" {
                return URLPercentCoding.encodeComponent(input)
            }

            return try URLPercentCoding.decode(input)
        }
    }
}
