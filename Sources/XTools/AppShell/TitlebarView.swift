import SwiftUI
import XToolsDesign

/// Native window toolbar content. The scene owns the toolbar chrome; this
/// value only projects the current shell state into stable toolbar slots.
struct WindowToolbarContent: ToolbarContent {
    let selectedTool: RegisteredTool?
    let isSidebarVisible: Bool
    let isFavorite: Bool
    /// 接收 presentation 模型**引用**（而非 RootViewModel 的计算属性）：
    /// `CommandPalettePresentationModel` 与 RootViewModel 刻意隔离——面板
    /// 开关不触发 RootView body 重估（rootBody=0 契约），所以工具栏内容
    /// 永远不会因面板开关而重建。压暗观察下沉到 `CommandTriggerLabel`
    /// 自身，只有按钮 label 随面板开关重估。
    let presentation: CommandPalettePresentationModel
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
                // Favorite toggle in native toolbar chrome. The star glyph and
                // active accent tint mirror `IndexFavoriteButton`; only the
                // chrome button style and 28pt toolbar size stay local because
                // this is AppKit toolbar chrome, not an in-page control.
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? IndexActionSymbol.favoriteFill : IndexActionSymbol.favorite)
                        .font(ToolTypography.icon(ToolMetrics.IconSize.medium, .medium))
                        .frame(
                            width: WindowToolbarMetrics.iconButtonSize,
                            height: WindowToolbarMetrics.iconButtonSize
                        )
                        .toolMotionIconSwap(id: isFavorite)
                }
                .buttonStyle(IndexQuietChromeStyle(ink: .pressAccent))
                .environment(\.colorScheme, colorScheme)
                .foregroundStyle(isFavorite ? ToolTheme.accent : ToolTheme.textSecondary)
                .help(isFavorite ? "取消收藏" : "加入收藏")
                .accessibilityLabel(isFavorite ? "取消收藏" : "加入收藏")
            }

            // label 自绘 chip 观感（底色/描边/按压态全部在 CommandTriggerLabel），
            // 按压态经 `\indexButtonIsPressed` 环境下发——压暗状态因此不经过
            // 工具栏内容重估就能更新（design-foundation C1：原私有
            // CommandTriggerButtonStyle 并入 IndexQuietChromeStyle(.labelOnly)）。
            Button(action: onCommandPalette) {
                CommandTriggerLabel(presentation: presentation)
            }
            .buttonStyle(IndexQuietChromeStyle(look: .labelOnly))
            .environment(\.colorScheme, colorScheme)
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

    private var presentation: SidebarTogglePresentation {
        isSidebarVisible ? .hide : .show
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(ToolTypography.icon(ToolMetrics.IconSize.large, .regular))
                .symbolRenderingMode(.monochrome)
                .frame(
                    width: WindowToolbarMetrics.iconButtonSize,
                    height: WindowToolbarMetrics.iconButtonSize
                )
                .toolMotionIconSwap(id: isSidebarVisible)
        }
        .buttonStyle(IndexQuietChromeStyle(ink: .quiet))
        .environment(\.colorScheme, colorScheme)
        .help(presentation.help)
        .accessibilityLabel(presentation.title)
        .accessibilityHint(SidebarTogglePresentation.accessibilityHint)
        .accessibilityIdentifier("window.sidebar-toggle")
    }
}

/// 顶栏 ⌘K 触发按钮的 label：内容与 chip 视觉（底色/描边/按压态）全部在这里，
/// 并**自行观察** `CommandPalettePresentationModel`。
///
/// 按钮住在原生工具栏（AppKit chrome 层），⌘K 的内容遮罩盖不住它——面板
/// 打开时把按钮自身压暗淡化（`presentation.shows` → opacity 0.4、去描边），
/// 视觉上与"被蒙层罩住"一致。观察放在本视图而非工具栏内容上：模型与
/// RootViewModel 刻意隔离（rootBody=0 契约），面板开关只重估这个 label，
/// App shell 不受牵连。按压态由安静钮统一样式
/// （`IndexQuietChromeStyle(look: .labelOnly)`）经环境注入。
struct CommandTriggerLabel: View {
    @ObservedObject var presentation: CommandPalettePresentationModel
    @Environment(\.indexButtonIsPressed) private var isPressed

    private var isDimmed: Bool { presentation.shows }

    var body: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(ToolTypography.icon(ToolMetrics.IconSize.small, .medium))

            Text("跳转工具…")
                .font(ToolTypography.compactBody)

            IndexKeycap(label: "⌘K")
        }
        .frame(height: WindowToolbarMetrics.commandHeight)
        .padding(.horizontal, WindowToolbarMetrics.commandHorizontalPadding)
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(isPressed && !isDimmed ? ToolTheme.textPrimary : ToolTheme.textSecondary)
        .background(
            isPressed && !isDimmed ? ToolTheme.activeFill : ToolTheme.commandTriggerChip,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
        )
        .overlay {
            if !isDimmed {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: 0.5)
            }
        }
        .opacity(isDimmed ? 0.4 : 1)
        .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isDimmed)
    }
}
