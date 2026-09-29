import XToolsCore
import SwiftUI

/// 「文本编码」Hub 的 URL 分段：经共享 IndexConverterPage 嵌入
/// （embedsPageShell: false，页面壳由 Hub 提供），workspace key 沿用
/// 合并前的 url-encoder-decoder。
struct IndexURLCoderSegment: View {
    var body: some View {
        IndexConverterPage(
            toolID: "url-encoder-decoder",
            embedsPageShell: false,
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
