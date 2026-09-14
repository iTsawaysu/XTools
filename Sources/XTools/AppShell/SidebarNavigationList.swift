import AppKit
import SwiftUI

@MainActor
final class SidebarNavigationTrackHoverState: ObservableObject {
    @Published private(set) var isHovered = false

    func setHovered(_ isHovered: Bool) {
        guard self.isHovered != isHovered else { return }
        self.isHovered = isHovered
    }
}

struct SidebarNavigationListConfiguration {
    let entries: [SidebarNavigationEntry]
    let selectedToolID: ToolID?
    let selectedSection: ToolNavigationSection?
    let favoriteOrder: [ToolID]
    let isSearchActive: Bool
    let reduceMotion: Bool
    let colorScheme: ColorScheme
    let onSelectTool: (ToolID) -> Void
    let onToggleFavorite: (ToolID) -> Void
    let onToggleSection: (ToolNavigationSection) -> Void
    var onToggleSectionExclusive: ((ToolNavigationSection) -> Void)? = nil
}

struct SidebarNavigationTrackRoot: View {
    let entry: SidebarNavigationEntry
    let selectedToolID: ToolID?
    let selectedSection: ToolNavigationSection?
    let isSearchActive: Bool
    let interaction: SidebarNavigationTrackInteraction
    @ObservedObject var hoverState: SidebarNavigationTrackHoverState
    let colorScheme: ColorScheme
    let reduceMotion: Bool
    let onSelectTool: (ToolID) -> Void
    let onToggleFavorite: (ToolID) -> Void
    let onToggleSection: (ToolNavigationSection) -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: entry.naturalHeight, alignment: .top)
            .allowsHitTesting(interaction.isInteractionEnabled)
            .disabled(!interaction.areControlsEnabled)
            .accessibilityHidden(interaction.isAccessibilityHidden)
            .environment(\.colorScheme, colorScheme)
            .tint(ToolTheme.accent)
            .transaction { transaction in
                if reduceMotion {
                    transaction.disablesAnimations = true
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.content {
        case .header(let group, let isExpanded):
            SidebarGroupHeader(
                title: group.title,
                systemImage: group.systemImage,
                isFavorites: group.section == .favorites,
                section: group.section,
                isExpanded: isExpanded,
                isSearchActive: isSearchActive,
                reduceMotion: reduceMotion,
                action: { onToggleSection(group.section) }
            )
            .accessibilityIdentifier("sidebar.group.\(group.id)")

        case .item(let item, let section):
            SidebarToolRow(
                toolID: item.id,
                title: item.title,
                systemImage: item.systemImage,
                isSelected: selectedToolID == item.id,
                isInActiveSection: selectedSection == section,
                isFavorite: item.isFavorite,
                hoverState: hoverState,
                onToggleFavorite: { onToggleFavorite(item.id) },
                action: { onSelectTool(item.id) }
            )
            .accessibilityIdentifier("sidebar.tool.\(item.id.rawValue)")

        case .spacing:
            Color.clear
                .accessibilityHidden(true)
        }
    }
}
