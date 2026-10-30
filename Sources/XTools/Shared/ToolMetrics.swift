import Foundation

/// Single source of truth for spacing, corner radius, and breakpoints.
/// Eliminates magic numbers and ensures consistency across all UI components.
///
/// Usage:
///   .padding(ToolMetrics.Spacing.base)
///   .cornerRadius(ToolMetrics.CornerRadius.field)
enum ToolMetrics {
    /// Geometry for the approved V3 workbench. Shell and home components use
    /// these values instead of changing the shared tool-page scale.
    enum Workbench {
        static let mainMaxWidth: CGFloat = 980
        static let horizontalInset: CGFloat = 30
        static let topInset: CGFloat = 26
        static let sectionGap: CGFloat = 16
        static let searchHeroHeight: CGFloat = 48
        static let toolCardIconBox: CGFloat = 30
        static let toolCardHeight: CGFloat = 54
        static let categoryChipHeight: CGFloat = 36
        static let panelMinHeight: CGFloat = 176
    }

    // MARK: - Spacing (4x scale)

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let base: CGFloat = 16      // Default panel padding & spacing (v9 4pt grid)
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let page: CGFloat = 32      // Page horizontal/vertical padding

        // Shared panel geometry. Keeping these named prevents individual
        // workspaces from inventing slightly different header/content insets.
        static let panelInset: CGFloat = 16
        static let panelSection: CGFloat = 12
    }

    // MARK: - Corner Radius
    //
    // Clay Warmth ladder (Arc/Craft-grade softness): panels and modals are
    // generously rounded; controls and fields share one softer step. The ladder
    // is {6, 8, 10, 12} plus Capsule for pills.

    enum CornerRadius {
        static let panel: CGFloat = 10     // IndexPanel surfaces
        static let control: CGFloat = 8    // Small buttons, chips, segment items
        static let field: CGFloat = 8      // Input fields, large buttons, KV rows
        static let card: CGFloat = 12      // Resting dashboard/content cards
        static let modal: CGFloat = 12     // Floating surfaces: command palette, toasts, popovers, empty-state tiles
        static let keycap: CGFloat = 4      // Keyboard hint keycaps (near-square, Raycast-style)
        static let sidebarRow: CGFloat = 8 // Sidebar selection capsule and row chrome
        // pill: use Capsule() directly for fully rounded
        // Nested rule: inner radius = outer radius - padding (e.g. 8 - 2 = 6 for segment items)
        static let nestedControl: CGFloat = 6
    }

    /// v9 border widths. Status changes alter color, not width.
    enum BorderWidth {
        static let hairline: CGFloat = 0.5
        static let selection: CGFloat = 1
        static let focus: CGFloat = 1.5
    }

    // MARK: - Icon Size (SF Symbols rendered inside controls and chrome)

    enum IconSize {
        static let micro: CGFloat = 10     // chevrons, disclosure markers
        static let small: CGFloat = 12     // inline action icons
        static let medium: CGFloat = 13    // toolbar and panel-accessory icons
        static let large: CGFloat = 15     // rows, primary glyphs
        static let tool: CGFloat = 16      // tool identity icons (sidebar rows)
        static let display: CGFloat = 22   // empty-state / drop-zone hero glyphs
    }

    // MARK: - Control Height Ladder

    /// One height per role. Pages and shared controls must not invent other
    /// values for the same role; internal calendar cells and decorative
    /// chrome are not part of this ladder.
    enum ControlHeight {
        /// v9 canonical ladder: icon 24 / compact 28 / field 38 / bar 44.
        static let icon24: CGFloat = 24
        static let compact28: CGFloat = 28
        static let field38: CGFloat = 38
        static let bar44: CGFloat = 44
        /// Primary CTA exception; not part of the general ladder.
        static let cta32: CGFloat = 32

        // Deprecated aliases kept for P2a compatibility; P2b migrates call sites.
        static let compact = icon24
        static let small = compact28
        static let action = cta32
        static let field = field38
        static let row = bar44
    }

    // MARK: - Responsive Breakpoints

    enum Breakpoint {
        /// Collapse width for formatter tools (wider editors). Kept at or below
        /// the usable content width of the minimum window (960 window − 220
        /// sidebar ≈ 740) plus one column budget, so dual-pane formatters fold
        /// before their editors get crushed.
        static let pairCollapseFormatter: CGFloat = 860
        /// Collapse width for image-tool workspaces. Stays below the minimum
        /// window's content rail (960 − 250 sidebar ≈ 710) so the settings rail
        /// and its primary action never stack below the fold; narrow rails rely
        /// on per-control density fallbacks instead.
        static let pairCollapseImageTools: CGFloat = 660
    }

    // MARK: - Legacy Animation Duration

    /// Compatibility shim for older shared controls. New motion work should use
    /// `ToolMotion` so duration, curve, transition, and Reduce Motion behavior
    /// stay in one vocabulary.
    enum Animation {
        static let fast: TimeInterval = ToolMotion.Duration.micro
        static let base: TimeInterval = ToolMotion.Duration.quick
    }
}
