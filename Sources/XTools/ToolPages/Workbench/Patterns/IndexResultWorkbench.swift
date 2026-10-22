import SwiftUI
import XToolsDesign

/// Single-result workbench for tools without an input: one paper, a header
/// with the actions, and the result surface filling the rest.
struct IndexResultWorkbench<Controls: View, Content: View>: View {
    let title: String
    private let controls: Controls
    private let content: Content

    init(
        title: String,
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.controls = controls()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                Text(title)
                    .font(ToolTypography.panelTitle)
                    .foregroundStyle(ToolTheme.textPrimary)
                Spacer(minLength: ToolMetrics.Spacing.sm)
                controls
            }
            .padding(.horizontal, ToolMetrics.Spacing.md)
            .frame(height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ToolTheme.border)
                    .frame(height: 0.5)
            }

            content
                .padding(.horizontal, ToolMetrics.Spacing.md)
                .padding(.bottom, ToolMetrics.Spacing.md)
                .padding(.top, ToolMetrics.Spacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(
            ToolTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
