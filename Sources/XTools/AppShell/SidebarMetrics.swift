import AppKit
import SwiftUI

enum SidebarMetrics {
    /// Local brand band under the native unified toolbar. Kept as a content-area
    /// spacer (not fullSizeContentView overlay); slightly under 48pt so the
    /// brand + search slab reads as one header rather than a second titlebar.
    static let titlebarHeight: CGFloat = 40
    static let brandHorizontalPadding: CGFloat = 16
    static let searchHorizontalPadding: CGFloat = 12
    static let searchTopPadding: CGFloat = 0
    static let searchBottomPadding: CGFloat = 8
    static let disclosureGroupSpacing: CGFloat = 5
    static let expandedGroupBottomPadding: CGFloat = 4
    static let groupHeaderHeight: CGFloat = 30
    static let groupHeaderToItemsSpacing: CGFloat = 3
    static let expandedRowHeight: CGFloat = 32
    static let interRowSpacing: CGFloat = 1
    static let iconSize: CGFloat = 16
    static let toolRowHorizontalPadding: CGFloat = 9
    static let toolRowHierarchyIndent: CGFloat = 16
    static let rowCornerRadius: CGFloat = 7
    static let searchSurfaceHeight: CGFloat = 32
    static let searchContentSpacing: CGFloat = 8
    static let searchLeadingPadding: CGFloat = 10
    static let searchTrailingPadding: CGFloat = 4
    static let searchIconWidth: CGFloat = 12
    static let searchClearButtonSize: CGFloat = 24
    static let searchLeadingContentInset: CGFloat = searchLeadingPadding + searchIconWidth + searchContentSpacing
    static let searchTrailingContentInset: CGFloat = searchTrailingPadding + searchClearButtonSize + searchContentSpacing
}
