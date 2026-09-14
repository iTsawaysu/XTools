import CoreGraphics

struct SidebarNavigationEntry: Identifiable, Hashable {
    enum Content: Hashable {
        case header(ToolNavigationGroup, isExpanded: Bool)
        case item(ToolNavigationItem, section: ToolNavigationSection)
        case spacing
    }

    let id: String
    let groupID: String
    let content: Content
    let naturalHeight: CGFloat
    let presentedHeight: CGFloat
}

enum SidebarNavigationEntryProjection {
    static func entries(
        groups: [ToolNavigationGroup],
        isSearchActive: Bool,
        isSectionExpanded: (ToolNavigationSection) -> Bool
    ) -> [SidebarNavigationEntry] {
        var entries: [SidebarNavigationEntry] = []

        for (groupIndex, group) in groups.enumerated() {
            let isExpanded = isSearchActive || isSectionExpanded(group.section)
            entries.append(SidebarNavigationEntry(
                id: "header.\(group.id)",
                groupID: group.id,
                content: .header(group, isExpanded: isExpanded),
                naturalHeight: SidebarMetrics.groupHeaderHeight,
                presentedHeight: SidebarMetrics.groupHeaderHeight
            ))

            entries.append(SidebarNavigationEntry(
                id: "spacing.\(group.id).top",
                groupID: group.id,
                content: .spacing,
                naturalHeight: SidebarMetrics.groupHeaderToItemsSpacing,
                presentedHeight: isExpanded ? SidebarMetrics.groupHeaderToItemsSpacing : 0
            ))

            for (itemIndex, item) in group.items.enumerated() {
                entries.append(SidebarNavigationEntry(
                    id: "tool.\(item.id.rawValue)",
                    groupID: group.id,
                    content: .item(item, section: group.section),
                    naturalHeight: SidebarMetrics.expandedRowHeight,
                    presentedHeight: isExpanded ? SidebarMetrics.expandedRowHeight : 0
                ))

                if itemIndex < group.items.count - 1 {
                    entries.append(SidebarNavigationEntry(
                        id: "spacing.\(group.id).after.\(item.id.rawValue)",
                        groupID: group.id,
                        content: .spacing,
                        naturalHeight: SidebarMetrics.interRowSpacing,
                        presentedHeight: isExpanded ? SidebarMetrics.interRowSpacing : 0
                    ))
                }
            }

            entries.append(SidebarNavigationEntry(
                id: "spacing.\(group.id).bottom",
                groupID: group.id,
                content: .spacing,
                naturalHeight: SidebarMetrics.expandedGroupBottomPadding,
                presentedHeight: isExpanded ? SidebarMetrics.expandedGroupBottomPadding : 0
            ))

            if groupIndex < groups.index(before: groups.endIndex) {
                entries.append(SidebarNavigationEntry(
                    id: "spacing.\(group.id).group",
                    groupID: group.id,
                    content: .spacing,
                    naturalHeight: SidebarMetrics.disclosureGroupSpacing,
                    presentedHeight: SidebarMetrics.disclosureGroupSpacing
                ))
            }
        }

        return entries
    }
}
