import SwiftUI

// MARK: - IndexSecureInput

/// Mono text field with an eye reveal-toggle for secrets (JWT secret, Basic
/// Auth password). The only sanctioned secure-input surface: while hidden the
/// text is masked and not selectable-copyable; the reveal button is the single
/// affordance that flips both.
struct IndexSecureInput: View {
    var placeholder: String
    @Binding var text: String
    @Binding var showsSecret: Bool
    /// Noun used in help/accessibility copy, e.g. "Secret" or "密码".
    var secretNoun: String = "密码"

    var body: some View {
        IndexTextInput(
            placeholder: placeholder,
            text: $text,
            secure: !showsSecret,
            allowsCopy: showsSecret,
            trailingInset: 36
        )
        .overlay(alignment: .trailing) {
            Button {
                showsSecret.toggle()
            } label: {
                Image(systemName: showsSecret ? "eye.slash" : "eye")
                    .font(.system(size: ToolMetrics.IconSize.medium, weight: .regular))
                    .foregroundStyle(showsSecret ? ToolTheme.accent : ToolTheme.textSecondary)
                    .toolMotionIconSwap(id: showsSecret)
            }
            .buttonStyle(ToolIconActionButtonStyle(isActive: showsSecret))
            .indexTooltip(showsSecret ? "隐藏\(secretNoun)" : "显示\(secretNoun)")
            .accessibilityLabel(showsSecret ? "隐藏\(secretNoun)" : "显示\(secretNoun)")
            .arrowCursorOnHover()
            .padding(.trailing, 6)
        }
        .accessibilityElement(children: .contain)
    }
}
