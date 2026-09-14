import AppKit
import SwiftUI

/// Native window toolbar content. The scene owns the toolbar chrome; this
/// value only projects the current shell state into stable toolbar slots.
struct WindowToolbarContent: ToolbarContent {
    let selectedTool: RegisteredTool?
    let isSidebarVisible: Bool
    let isFavorite: Bool
    let onToggleSidebar: () -> Void
    let onToggleFavorite: () -> Void
    let onCommandPalette: () -> Void
    let colorScheme: ColorScheme

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            SidebarToggleButton(
                isSidebarVisible: isSidebarVisible,
                action: onToggleSidebar,
                colorScheme: colorScheme
            )
        }

        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if selectedTool != nil {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: ToolMetrics.IconSize.medium, weight: .medium))
                        .frame(
                            width: WindowToolbarMetrics.iconButtonSize,
                            height: WindowToolbarMetrics.iconButtonSize
                        )
                        .toolMotionIconSwap(id: isFavorite)
                }
                .buttonStyle(QuietTitlebarButtonStyle())
                .environment(\.colorScheme, colorScheme)
                .foregroundStyle(isFavorite ? ToolTheme.accent : ToolTheme.textSecondary)
                .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }

            Button(action: onCommandPalette) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: ToolMetrics.IconSize.small, weight: .medium))

                    Text("跳转工具…")
                        .font(ToolTypography.compactBody)

                    Text("⌘K")
                        .font(ToolTypography.tagMicro)
                        .foregroundStyle(ToolTheme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay {
                            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
                        }
                }
                .frame(height: WindowToolbarMetrics.commandHeight)
                .padding(.horizontal, WindowToolbarMetrics.commandHorizontalPadding)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(CommandTriggerButtonStyle())
            .environment(\.colorScheme, colorScheme)
            .help("命令面板 (Command-K)")
            .accessibilityLabel("跳转工具")
            .accessibilityHint("打开命令面板，快捷键 Command-K")
        }
    }
}

private enum WindowToolbarMetrics {
    static let iconButtonSize: CGFloat = 28
    static let commandHeight: CGFloat = 30
    static let commandHorizontalPadding: CGFloat = 9
}

private struct SidebarToggleButton: View {
    let isSidebarVisible: Bool
    let action: () -> Void
    let colorScheme: ColorScheme

    @StateObject private var hoverState = HoverState()

    private var presentation: SidebarTogglePresentation {
        isSidebarVisible ? .hide : .show
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: ToolMetrics.IconSize.large, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .frame(
                    width: WindowToolbarMetrics.iconButtonSize,
                    height: WindowToolbarMetrics.iconButtonSize
                )
                .toolMotionIconSwap(id: isSidebarVisible)
        }
        .buttonStyle(SidebarChromeButtonStyle(isHovered: hoverState.isHovered))
        .environment(\.colorScheme, colorScheme)
        .help(presentation.help)
        .accessibilityLabel(presentation.title)
        .accessibilityHint(SidebarTogglePresentation.accessibilityHint)
        .accessibilityIdentifier("window.sidebar-toggle")
        .onHover { hoverState.isHovered = $0 }
    }
}
