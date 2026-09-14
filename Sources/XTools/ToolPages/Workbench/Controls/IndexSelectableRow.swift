import SwiftUI

// MARK: - IndexSelectableRow

/// The shared interactive row: one grammar for list rows, option cells, and
/// inline choices.
///
/// State contract (app-wide):
/// - hover → `hoverFill`
/// - selected (mouse or programmatic) → `selectionFill` + `selectionStroke`
/// - keyboard focus (Tab) → focus ring (`ToolTheme.focusRing`, 1.5pt) on top;
///   Return activates via `.onSubmit`.
///
/// Pages must not hand-roll `.buttonStyle(.plain)` + `onHover` rows.
struct IndexSelectableRow<Content: View>: View {
    var isSelected = false
    var cornerRadius: CGFloat = ToolMetrics.CornerRadius.control
    var isFocused = false
    let action: () -> Void
    @ViewBuilder private let content: () -> Content
    @State private var isHovering = false

    init(
        isSelected: Bool = false,
        cornerRadius: CGFloat = ToolMetrics.CornerRadius.control,
        isFocused: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
        self.isFocused = isFocused
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withToolAnimation(ToolMotion.Preset.controlFeedback) { isHovering = hovering }
        }
        .background(
            isSelected ? ToolTheme.selectionFill : isHovering ? ToolTheme.hoverFill : Color.clear,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            if isSelected || isHovering {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? ToolTheme.selectionStroke : ToolTheme.border,
                        lineWidth: isSelected ? 1 : 0.5
                    )
            }
        }
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ToolTheme.focusRing, lineWidth: 1.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onSubmit(action)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Focusable

extension View {
    /// Adds the shared keyboard-focus ring around any view. Pairs with
    /// `IndexSelectableRow(isFocused:)` for rows that own their own button.
    func indexFocusRing(active: Bool, cornerRadius: CGFloat = ToolMetrics.CornerRadius.control) -> some View {
        overlay {
            if active {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(ToolTheme.focusRing, lineWidth: 1.5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
