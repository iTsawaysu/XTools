@testable import XTools
import CoreGraphics
import Testing

struct SidebarNavigationEntryProjectionTests {
    @Test func toolIdentityStaysStableAcrossFavoriteMigration() throws {
        let before = SidebarNavigationEntryProjection.entries(
            groups: [Self.group(section: .category(.development), items: [Self.alpha, Self.beta])],
            isSearchActive: false,
            isSectionExpanded: { _ in true }
        )
        let after = SidebarNavigationEntryProjection.entries(
            groups: [
                Self.group(section: .favorites, items: [Self.favoriteAlpha]),
                Self.group(section: .category(.development), items: [Self.beta])
            ],
            isSearchActive: false,
            isSectionExpanded: { _ in true }
        )

        let beforeID = try #require(before.first(where: { $0.toolID == .alpha })?.id)
        let afterID = try #require(after.first(where: { $0.toolID == .alpha })?.id)

        #expect(beforeID == "tool.alpha")
        #expect(afterID == beforeID)
        #expect(Set(after.map(\.id)).count == after.count)
    }

    @Test func collapsedAndExpandedSectionsKeepTheSameTrackIdentityDomain() {
        let group = Self.group(section: .category(.development), items: [Self.alpha, Self.beta])
        let collapsed = SidebarNavigationEntryProjection.entries(
            groups: [group],
            isSearchActive: false,
            isSectionExpanded: { _ in false }
        )
        let searching = SidebarNavigationEntryProjection.entries(
            groups: [group],
            isSearchActive: true,
            isSectionExpanded: { _ in false }
        )

        #expect(collapsed.map(\.id) == searching.map(\.id))
        #expect(collapsed.compactMap(\.toolID) == [.alpha, .beta])
        #expect(collapsed.disclosurePresentedHeights.allSatisfy { $0 == 0 })
        #expect(searching.compactMap(\.toolID) == [.alpha, .beta])
        #expect(searching.disclosurePresentedHeights.allSatisfy { $0 > 0 })
        #expect(collapsed.headerExpansionValues == [false])
        #expect(searching.headerExpansionValues == [true])
    }

    @Test func flatOrderPreservesHeaderRowAndGroupSpacing() {
        let entries = SidebarNavigationEntryProjection.entries(
            groups: [
                Self.group(section: .favorites, items: [Self.favoriteAlpha]),
                Self.group(section: .category(.development), items: [Self.beta])
            ],
            isSearchActive: false,
            isSectionExpanded: { $0 == .favorites }
        )

        #expect(entries.map(\.id) == [
            "header.favorites",
            "spacing.favorites.top",
            "tool.alpha",
            "spacing.favorites.bottom",
            "spacing.favorites.group",
            "header.category.development",
            "spacing.category.development.top",
            "tool.beta",
            "spacing.category.development.bottom"
        ])
        #expect(entries.compactMap(\.naturalSpacingHeight) == [
            SidebarMetrics.groupHeaderToItemsSpacing,
            SidebarMetrics.expandedGroupBottomPadding,
            SidebarMetrics.disclosureGroupSpacing,
            SidebarMetrics.groupHeaderToItemsSpacing,
            SidebarMetrics.expandedGroupBottomPadding
        ])
        #expect(entries.first(where: { $0.id == "tool.beta" })?.presentedHeight == 0)
    }

    @Test func toolHeightAndInterRowSpacingUseIndependentTracks() throws {
        let entries = SidebarNavigationEntryProjection.entries(
            groups: [Self.group(section: .category(.development), items: [Self.alpha, Self.beta])],
            isSearchActive: false,
            isSectionExpanded: { _ in true }
        )

        let toolEntries = entries.filter { $0.toolID != nil }
        let spacing = try #require(entries.first(where: {
            $0.id == "spacing.category.development.after.alpha"
        }))

        #expect(toolEntries.allSatisfy { $0.naturalHeight == SidebarMetrics.expandedRowHeight })
        #expect(toolEntries.allSatisfy { $0.presentedHeight == SidebarMetrics.expandedRowHeight })
        #expect(spacing.naturalHeight == SidebarMetrics.interRowSpacing)
        #expect(spacing.presentedHeight == SidebarMetrics.interRowSpacing)
    }

    private static var alpha: ToolNavigationItem {
        item(.alpha, isFavorite: false, section: .category(.development))
    }

    private static var favoriteAlpha: ToolNavigationItem {
        item(.alpha, isFavorite: true, section: .favorites)
    }

    private static var beta: ToolNavigationItem {
        item(.beta, isFavorite: false, section: .category(.development))
    }

    private static func group(
        section: ToolNavigationSection,
        items: [ToolNavigationItem]
    ) -> ToolNavigationGroup {
        ToolNavigationGroup(
            title: section == .favorites ? "收藏" : "Development",
            systemImage: section == .favorites ? "star.fill" : "hammer",
            section: section,
            items: items
        )
    }

    private static func item(
        _ id: ToolID,
        isFavorite: Bool,
        section: ToolNavigationSection
    ) -> ToolNavigationItem {
        ToolNavigationItem(
            id: id,
            title: id.rawValue,
            categoryID: .development,
            systemImage: "gear",
            isFavorite: isFavorite,
            section: section
        )
    }
}

private extension SidebarNavigationEntry {
    var toolID: ToolID? {
        guard case .item(let item, _) = content else { return nil }
        return item.id
    }

    var naturalSpacingHeight: CGFloat? {
        guard case .spacing = content else { return nil }
        return naturalHeight
    }
}

private extension Array where Element == SidebarNavigationEntry {
    var headerExpansionValues: [Bool] {
        compactMap { entry in
            guard case .header(_, let isExpanded) = entry.content else { return nil }
            return isExpanded
        }
    }

    /// Heights for tracks that collapse with disclosure (tools + group-local spacing),
    /// excluding always-visible headers and between-group spacing.
    var disclosurePresentedHeights: [CGFloat] {
        compactMap { entry in
            switch entry.content {
            case .header:
                return nil
            case .item:
                return entry.presentedHeight
            case .spacing:
                return entry.id.hasSuffix(".group") ? nil : entry.presentedHeight
            }
        }
    }
}

private extension ToolID {
    static let alpha = ToolID(rawValue: "alpha")
    static let beta = ToolID(rawValue: "beta")
}
