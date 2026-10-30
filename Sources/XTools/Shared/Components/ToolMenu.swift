import SwiftUI

struct ToolMenuItem<Item: Hashable>: Identifiable {
    let id: Item
    let title: String
    var systemImage: String? = nil
    var isEnabled = true
}

struct ToolMenu<Item: Hashable>: View {
    enum Presentation: Equatable {
        case popover
        case picker
    }

    let triggerTitle: String
    let items: [ToolMenuItem<Item>]
    var selection: Binding<Item>? = nil
    var presentation: Presentation = .popover
    var onSelect: ((Item) -> Void)? = nil

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    private var resolvedTitle: String {
        guard let selection,
              let selected = items.first(where: { $0.id == selection.wrappedValue })
        else { return triggerTitle }
        return selected.title
    }

    private var hovering: Bool { isHovering && isEnabled }

    private var height: CGFloat {
        presentation == .picker
            ? ToolMetrics.ControlHeight.field38
            : ToolMetrics.ControlHeight.compact28
    }

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button {
                    selection?.wrappedValue = item.id
                    onSelect?(item.id)
                } label: {
                    if item.id == selection?.wrappedValue {
                        Label(item.title, systemImage: item.systemImage ?? "checkmark")
                    } else if let systemImage = item.systemImage {
                        Label(item.title, systemImage: systemImage)
                    } else {
                        Text(item.title)
                    }
                }
                .disabled(!item.isEnabled)
            }
        } label: {
            HStack(spacing: 6) {
                Text(resolvedTitle)
                    .font(presentation == .picker ? ToolTypography.body : ToolTypography.buttonSmall)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: ToolMetrics.IconSize.micro, weight: .medium))
                    .foregroundStyle(ToolTheme.textTertiary)
            }
            .foregroundStyle(ToolTheme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: height)
            .background(
                (isHovering && isEnabled) ? ToolTheme.hoverFill : ToolTheme.utilityBackground,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: ToolMetrics.BorderWidth.hairline)
            }
            .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovering = $0 }
        .toolAnimation(hovering ? ToolMotion.Preset.hoverIn : ToolMotion.Preset.hoverOut, value: hovering)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(resolvedTitle)
    }
}
