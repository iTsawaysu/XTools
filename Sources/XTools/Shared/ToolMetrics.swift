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
        static let mainMaxWidth: CGFloat = 880
        static let horizontalInset: CGFloat = 32
        static let topInset: CGFloat = 38
        static let inputHeight: CGFloat = 82
        static let resultMaxHeight: CGFloat = 180
        static let shortcutRowHeight: CGFloat = 58
        static let sectionGap: CGFloat = 32
        static let compactCorner: CGFloat = 6
        static let groupCorner: CGFloat = 8
    }

    // MARK: - Spacing (4x scale)

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let base: CGFloat = 14      // Default panel padding & spacing
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 26
        static let page: CGFloat = 30      // Page horizontal/vertical padding

        // Shared panel geometry. Keeping these named prevents individual
        // workspaces from inventing slightly different header/content insets.
        static let panelInset: CGFloat = 14
        static let panelSection: CGFloat = 10
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
        // pill: use Capsule() directly for fully rounded
        // Nested rule: inner radius = outer radius - padding (e.g. 8 - 2 = 6 for segment items)
        static let nestedControl: CGFloat = 6
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

    // MARK: - Responsive Breakpoints

    enum Breakpoint {
        /// Default collapse width for IndexPairLayout (simple I/O pairs)
        static let pairCollapseDefault: CGFloat = 720

        /// Collapse width for formatter tools (wider editors). Kept at or below
        /// the usable content width of the minimum window (960 window − 220
        /// sidebar ≈ 740) plus one column budget, so dual-pane formatters fold
        /// before their editors get crushed.
        static let pairCollapseFormatter: CGFloat = 860

        /// Minimum content width per column before folding (guideline)
        static let minColumnWidth: CGFloat = 360
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
