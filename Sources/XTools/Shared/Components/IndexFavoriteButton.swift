import SwiftUI
import XToolsDesign

/// Shared favorite toggle (F 收藏归位): every favorite affordance renders the
/// same star glyph, accent active tint, hover/press feedback and accessibility
/// copy, so "收藏" reads identically app-wide instead of three hand-rolled
/// buttons. A favorite is a selection — the active tint is always accent,
/// never a warning tone.
struct IndexFavoriteButton: View {
    /// `regular` = 24×24 icon action (in-page rows, e.g. Timezone).
    /// `compact` = 10pt glyph in a 24×24 hit region (dense sidebar rows where
    /// the star sits flush and the surrounding row owns the reveal behavior).
    enum Density {
        case regular
        case compact
    }

    let isFavorite: Bool
    let density: Density
    var help: String? = nil
    let action: () -> Void

    init(
        isFavorite: Bool,
        density: Density = .regular,
        help: String? = nil,
        action: @escaping () -> Void
    ) {
        self.isFavorite = isFavorite
        self.density = density
        self.help = help
        self.action = action
    }

    private var label: String {
        isFavorite ? "取消收藏" : "加入收藏"
    }

    private var resolvedHelp: String {
        help ?? label
    }

    var body: some View {
        switch density {
        case .regular:
            regularBody
        case .compact:
            compactBody
        }
    }

    /// Full icon-action button: 24×24 hit, shared icon-action hover/press,
    /// accent active tint, star glyph swap.
    private var regularBody: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? IndexActionSymbol.favoriteFill : IndexActionSymbol.favorite)
                .toolMotionIconSwap(id: isFavorite)
        }
        .buttonStyle(IndexIconActionButtonStyle(
            isActive: isFavorite,
            activeTint: ToolTheme.accent,
            tint: ToolTheme.textSecondary,
            activeBackground: ToolTheme.selectionFill
        ))
        .help(resolvedHelp)
        .accessibilityLabel(resolvedHelp)
        .accessibilityValue(isFavorite ? "已收藏" : "")
    }

    /// Dense variant for sidebar rows: the glyph stays at 10pt so the star
    /// reads as a quiet row affordance, while the hit region stays 24×24 for
    /// pointer/keyboard reach. Reveal-on-hover stays at the call site.
    private var compactBody: some View {
        Button(action: action) {
            Image(systemName: isFavorite ? IndexActionSymbol.favoriteFill : IndexActionSymbol.favorite)
                .font(.system(size: ToolMetrics.IconSize.micro))
                .foregroundStyle(isFavorite ? ToolTheme.accent : ToolTheme.textSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .toolMotionIconSwap(id: isFavorite)
        }
        .toolInteractionFeedback()
        .help(resolvedHelp)
        .accessibilityLabel(resolvedHelp)
        .accessibilityValue(isFavorite ? "已收藏" : "")
    }
}
