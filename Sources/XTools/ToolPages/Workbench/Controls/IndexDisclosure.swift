import SwiftUI

// MARK: - IndexDisclosure

/// Shared expandable section in two forms:
/// - **carded** (default): full Clay Panel chrome — the only sanctioned
///   standalone disclosure surface (e.g. JWT local check).
/// - **inline** (`.inline()`): header-only row with rounded hover, for
///   collapsing a region *inside* an existing panel.
///
/// Pages must not hand-roll `.buttonStyle(.plain)` accordion headers.
struct IndexDisclosure<Content: View, Accessory: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    /// One-line hint shown only while collapsed (e.g. JWT's local-check summary).
    var collapsedSummary: String? = nil
    var isInline = false
    @ViewBuilder private var accessory: () -> Accessory
    @ViewBuilder private var content: () -> Content
    @State private var isHovering = false

    init(
        title: String,
        isExpanded: Binding<Bool>,
        collapsedSummary: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.collapsedSummary = collapsedSummary
        self.accessory = accessory
        self.content = content
    }

    /// Header-only form for regions nested inside an existing panel.
    func inline() -> IndexDisclosure {
        var copy = self
        copy.isInline = true
        return copy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ToolDisclosureBody(isExpanded: isExpanded) {
                content()
                    .padding(isInline ? ToolMetrics.Spacing.sm : ToolMetrics.Spacing.base)
            }
        }
        .modifier(IndexDisclosureContainer(isInline: isInline))
    }

    private var header: some View {
        Button {
            withToolAnimation(ToolMotion.Preset.accordion) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(isInline ? ToolTypography.bodyMedium : ToolTypography.panelTitle)
                    .foregroundStyle(isInline ? ToolTheme.textPrimary : ToolTheme.textSecondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .lineLimit(1)

                if !isExpanded, let collapsedSummary {
                    Text(collapsedSummary)
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                accessory()

                Image(systemName: "chevron.right")
                    .font(.system(size: ToolMetrics.IconSize.micro, weight: .semibold))
                    .foregroundStyle(ToolTheme.textTertiary)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, isInline ? 8 : 14)
            .frame(maxWidth: .infinity, minHeight: isInline ? 42 : 36, alignment: .leading)
            .background(
                isHovering ? ToolTheme.hoverFill : Color.clear,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withToolAnimation(ToolMotion.Preset.controlFeedback) { isHovering = hovering }
        }
        .accessibilityLabel(isExpanded ? "折叠\(title)" : "展开\(title)")
        .accessibilityValue(isExpanded ? "已展开" : "已收起\(collapsedSummary.map { "，\($0)" } ?? "")")
        .help(isExpanded ? "折叠\(title)" : "展开\(title)")
        .toolAnimation(ToolMotion.Preset.accordion, value: isExpanded)
    }
}

/// Container chrome: carded form paints the Clay Panel surface; inline form is
/// transparent so the owning panel shows through.
private struct IndexDisclosureContainer: ViewModifier {
    let isInline: Bool

    func body(content: Content) -> some View {
        if isInline {
            content
        } else {
            content
                .background(
                    ToolTheme.panelBackground,
                    in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                )
                .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                        .strokeBorder(ToolTheme.border, lineWidth: 0.5)
                }
                .toolShadow(ToolTheme.Shadow.panel)
        }
    }
}

extension IndexDisclosure where Accessory == EmptyView {
    init(
        title: String,
        isExpanded: Binding<Bool>,
        collapsedSummary: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            isExpanded: isExpanded,
            collapsedSummary: collapsedSummary,
            accessory: { EmptyView() },
            content: content
        )
    }
}
