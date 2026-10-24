import AppKit
import SwiftUI

enum SidebarMetrics {
    /// 侧栏壳（品牌带 + 搜索框）几何。行级几何（行高/组头/间距/圆角）随
    /// 阶段③ 原生侧栏迁移交给系统 `List(.sidebar)`，自绘值（含 S14 的
    /// rowCornerRadius 7）已删除。
    /// Local brand band under the native unified toolbar. Kept as a content-area
    /// spacer (not fullSizeContentView overlay); 8pt under the 48pt toolbar so
    /// the brand + search slab reads as one header rather than a second titlebar.
    static let titlebarHeight: CGFloat = 40
    static let brandHorizontalPadding: CGFloat = 16
    static let searchHorizontalPadding: CGFloat = 12
    static let searchTopPadding: CGFloat = 0
    static let searchBottomPadding: CGFloat = 8
    static let searchSurfaceHeight: CGFloat = 32
    static let searchContentSpacing: CGFloat = 8
    static let searchLeadingPadding: CGFloat = 10
    static let searchTrailingPadding: CGFloat = 4
    static let searchIconWidth: CGFloat = 12
    static let searchClearButtonSize: CGFloat = 24
    static let searchLeadingContentInset: CGFloat = searchLeadingPadding + searchIconWidth + searchContentSpacing
    static let searchTrailingContentInset: CGFloat = searchTrailingPadding + searchClearButtonSize + searchContentSpacing
}
