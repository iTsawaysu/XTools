import SwiftUI

struct ToolSearchField: View {
    enum Size: Equatable {
        case regular38
        case hero48

        var height: CGFloat {
            switch self {
            case .regular38: return ToolMetrics.ControlHeight.field38
            case .hero48: return 48
            }
        }
    }

    @Binding var text: String
    let placeholder: String
    var size: Size = .regular38
    var autoFocus = false
    var clearTitle = "清空搜索"
    var onSubmit: (() -> Void)? = nil
    var onEscape: (() -> Void)? = nil

    var body: some View {
        IndexSearchInput(
            placeholder: placeholder,
            text: $text,
            height: size.height,
            autoFocus: autoFocus,
            clearTitle: clearTitle,
            onSubmit: onSubmit,
            onEscape: onEscape
        )
        .accessibilityLabel(placeholder)
    }
}
