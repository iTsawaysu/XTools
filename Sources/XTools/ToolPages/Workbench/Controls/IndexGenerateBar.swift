import SwiftUI

// MARK: - IndexGenerateBar

/// Standard generator accessory bar: "重新生成" refresh action plus
/// "全部复制" bulk copy. One component for every generator family page
/// (UUID / password / token / random values).
struct IndexGenerateBar: View {
    var copyText: String
    var copyTitle = "全部复制"
    let regenerate: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: regenerate) {
                Label("重新生成", systemImage: IndexActionSymbol.refresh)
                    .font(ToolTypography.buttonSmall)
            }
            .buttonStyle(IndexSmallButtonStyle())
            .help("重新生成")

            IndexCopyButton(text: copyText, title: copyTitle)
        }
    }
}
