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
            trailingInset: 42
        )
        .overlay(alignment: .trailing) {
            IndexIconButton(
                systemImage: showsSecret ? "eye.slash" : "eye",
                help: showsSecret ? "隐藏\(secretNoun)" : "显示\(secretNoun)"
            ) {
                showsSecret.toggle()
            }
            .frame(width: 32, height: 32)
            .toolMotionIconSwap(id: showsSecret)
            .padding(.trailing, 5)
        }
        .accessibilityElement(children: .contain)
    }
}
