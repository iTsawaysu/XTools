import SwiftUI

/// Non-displacing smart-paste suggestion. Floats over the top of the workspace
/// instead of participating in page layout, so appearing and disappearing never
/// moves the tool page, its scroll ownership, or its controls.
struct SmartPasteSuggestionBanner: View {
    let suggestion: SmartPasteMonitor.Suggestion
    let onOpen: () -> Void
    let onDismiss: () -> Void

    /// Transient by design: the hint is a shortcut, never the only way to reach
    /// the tool (the sidebar and command palette stay the source of truth).
    private static let autoDismissDelay: Duration = .seconds(12)

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.system(size: ToolMetrics.IconSize.medium, weight: .medium))
                .foregroundStyle(ToolTheme.accent)
                .accessibilityHidden(true)

            Text(suggestion.message)
                .font(ToolTypography.bodyPlain)
                .foregroundStyle(ToolTheme.textPrimary)
                .lineLimit(1)

            Button(action: onOpen) {
                Text("打开 \(suggestion.toolTitle)")
            }
            .buttonStyle(IndexSmallButtonStyle())
            .accessibilityHint("切换到该工具")

            IndexIconButton(
                systemImage: "xmark",
                help: "忽略这个建议",
                action: onDismiss
            )
        }
        .padding(.leading, ToolMetrics.Spacing.md)
        .padding(.trailing, ToolMetrics.Spacing.sm)
        .padding(.vertical, ToolMetrics.Spacing.sm)
        .toolSurface(
            .floating,
            fallback: ToolTheme.popoverBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.modal, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.modal, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
        .toolShadow(ToolTheme.Shadow.floating)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(suggestion.message)，可以打开\(suggestion.toolTitle)")
        .task(id: suggestion.toolID) {
            do {
                try await Task.sleep(for: Self.autoDismissDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }
}
