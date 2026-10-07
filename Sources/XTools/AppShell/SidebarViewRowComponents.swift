import AppKit
import SwiftUI

struct SidebarGroupHeader: View {
    let title: String
    let systemImage: String
    let isFavorites: Bool
    let section: ToolNavigationSection
    let isExpanded: Bool
    var isActiveSection: Bool = false
    let isSearchActive: Bool
    let reduceMotion: Bool
    let action: () -> Void

    @StateObject private var hoverState = SidebarHoverState()

    private var foreground: Color {
        if isActiveSection {
            return ToolTheme.textPrimary
        }
        if hoverState.isHovered || isExpanded {
            return ToolTheme.textSecondary
        }
        return ToolTheme.textTertiary
    }

    private var iconForeground: Color {
        if isFavorites {
            return isActiveSection || hoverState.isHovered ? ToolTheme.accent : ToolTheme.accent.opacity(0.85)
        }
        return foreground
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: ToolMetrics.IconSize.micro, weight: .bold))
                    .foregroundStyle(foreground)
                    .frame(width: 10, height: 12)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Image(systemName: systemImage)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: ToolMetrics.IconSize.medium, weight: .medium))
                    .foregroundStyle(iconForeground)
                    .frame(width: SidebarMetrics.iconSize, height: SidebarMetrics.iconSize)

                Text(title)
                    .font(ToolTypography.groupHeader)
                    .fontWeight(isActiveSection ? .medium : .regular)
                    .tracking(0.2)
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                // Arc Spaces 式分类身份点：低饱和渐变，仅非收藏分组。
                if !isFavorites, case .category(let categoryID) = section {
                    Circle()
                        .fill(ToolTheme.categoryGradient(categoryID))
                        .frame(width: 7, height: 7)
                        .opacity(isActiveSection ? 1.0 : (isExpanded ? 0.95 : 0.55))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: SidebarMetrics.groupHeaderHeight)
            .background(
                backgroundFill,
                in: RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isExpanded ? "已展开" : "已收起")
        .onHover { hoverState.isHovered = $0 }
        // Search / Reduce Motion land immediately; otherwise share accordion timing
        // with the AppKit track owner (ADR-0015) via ToolMotion.animation.
        .animation(
            ToolMotion.animation(
                ToolMotion.Preset.accordion,
                reduceMotion: reduceMotion || isSearchActive
            ),
            value: isExpanded
        )
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: hoverState.isHovered)
    }

    private var accessibilityLabel: String {
        if isSearchActive {
            return "搜索时保持展开\(title)"
        }
        return "\(isExpanded ? "折叠" : "展开")\(title)"
    }

    private var backgroundFill: Color {
        if hoverState.isHovered {
            return ToolTheme.hoverFill
        }
        return .clear
    }
}

struct BrandMark: View {
    var body: some View {
        // Terminal prompt glyph. Solid accent, no glow (Ink Terminal Pro avoids
        // the Linear-style purple gradient + bloom — SPEC §7, anti-slop).
        Image(systemName: "chevron.right")
            .font(.system(size: ToolMetrics.IconSize.small, weight: .bold))
            .foregroundStyle(ToolTheme.onAccent)
            .frame(width: 22, height: 22)
            .background(ToolTheme.accent, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
    }
}

struct SidebarFooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @StateObject private var hoverState = SidebarHoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: ToolMetrics.IconSize.medium, weight: .regular))
                    .frame(width: 15)

                Text(title)
                    .font(ToolTypography.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(hoverState.isHovered ? ToolTheme.textPrimary : ToolTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                hoverState.isHovered ? ToolTheme.hoverFill : Color.clear,
                in: RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .toolInteractionFeedback()
        .onHover { hoverState.isHovered = $0 }
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: hoverState.isHovered)
    }
}

struct SidebarToolRow: View {
    let toolID: ToolID
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isInActiveSection: Bool
    let isFavorite: Bool
    @ObservedObject var hoverState: SidebarNavigationTrackHoverState
    let onToggleFavorite: () -> Void
    let action: () -> Void

    private var shouldHighlight: Bool {
        isSelected && isInActiveSection
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: ToolMetrics.IconSize.large, weight: .regular))
                        .foregroundStyle(shouldHighlight ? ToolTheme.accentHover : ToolTheme.textSecondary)
                        .frame(width: 18, height: SidebarMetrics.iconSize)

                    Text(title)
                        .font(ToolTypography.bodyLarge)
                        .fontWeight(shouldHighlight ? .medium : .regular)
                        .foregroundStyle(shouldHighlight ? ToolTheme.textPrimary : ToolTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .padding(.leading, SidebarMetrics.toolRowHorizontalPadding + SidebarMetrics.toolRowHierarchyIndent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: SidebarMetrics.expandedRowHeight)
            }
            .buttonStyle(.plain)
            // The navigation control owns every point up to the reserved
            // favorite slot.  Without an explicit frame SwiftUI may size the
            // Button to its label's ideal width, leaving the trailing blank
            // area inert even though the row itself is full width.
            .frame(maxWidth: .infinity, alignment: .leading)
            .toolInteractionFeedback()
            .contentShape(Rectangle())
            .accessibilityLabel(title)
            .accessibilityValue(shouldHighlight ? "已选择" : "")

            // Favorite toggle: keep the favorite action as a sibling of the tool button. Nested
            // SwiftUI Buttons have ambiguous event and accessibility behavior.
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: ToolMetrics.IconSize.micro))
                    .foregroundStyle(isFavorite ? ToolTheme.accent : ToolTheme.textSecondary)
                    .frame(width: 14, height: 14)
                    .toolMotionIconSwap(id: isFavorite)
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .toolInteractionFeedback()
            .accessibilityIdentifier("sidebar.favorite.\(toolID.rawValue)")
            .help(isFavorite ? "取消收藏" : "加入收藏")
            .accessibilityLabel(isFavorite ? "取消收藏\(title)" : "收藏\(title)")
            .opacity(isFavorite || hoverState.isHovered ? 1 : 0)
            .allowsHitTesting(isFavorite || hoverState.isHovered)
            .accessibilityHidden(!(isFavorite || hoverState.isHovered))
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: isFavorite || hoverState.isHovered)
            .padding(.trailing, SidebarMetrics.toolRowHorizontalPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: SidebarMetrics.expandedRowHeight)
        // Selection chrome (the selection-level pill + accent rail) is owned
        // by the flat renderer's sliding indicator
        // (SidebarSelectionIndicatorView); the row keeps only its text/icon
        // color states, which flip instantly while the indicator springs
        // between rows.
        .background(rowBackground, in: RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous))
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: hoverState.isHovered)
        .contextMenu {
            Button(isFavorite ? "取消收藏" : "加入收藏", action: onToggleFavorite)
        }
    }

    private var rowBackground: Color {
        hoverState.isHovered ? ToolTheme.hoverFill : .clear
    }
}

@MainActor
private final class SidebarHoverState: ObservableObject {
    @Published var isHovered = false
}
