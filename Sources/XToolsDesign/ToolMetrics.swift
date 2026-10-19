import Foundation

/// Single source of truth for spacing, corner radius, and breakpoints.
/// Eliminates magic numbers and ensures consistency across all UI components.
///
/// Usage:
///   .padding(ToolMetrics.Spacing.base)
///   .cornerRadius(ToolMetrics.CornerRadius.field)
public enum ToolMetrics {
    /// Geometry for the approved V3 workbench. Shell and home components use
    /// these values instead of changing the shared tool-page scale.
    public enum Workbench {
        public static let mainMaxWidth: CGFloat = 880
        public static let horizontalInset: CGFloat = 32
        public static let topInset: CGFloat = 38
        public static let shortcutRowHeight: CGFloat = 58
        public static let sectionGap: CGFloat = 32
        public static let compactCorner: CGFloat = 6
        public static let groupCorner: CGFloat = 8
    }

    // MARK: - Spacing (4x scale)

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let base: CGFloat = 14      // Default panel padding & spacing
        public static let lg: CGFloat = 16
        public static let page: CGFloat = 30      // Page horizontal/vertical padding

        // Shared panel geometry. Keeping these named prevents individual
        // workspaces from inventing slightly different header/content insets.
        public static let panelInset: CGFloat = 14
        public static let panelSection: CGFloat = 10
    }

    // MARK: - Corner Radius
    //
    // Clay Warmth ladder (Arc/Craft-grade softness): panels and modals are
    // generously rounded; controls and fields share one softer step. The ladder
    // is {6, 8, 10, 12} plus Capsule for pills.

    public enum CornerRadius {
        public static let panel: CGFloat = 10     // IndexPanel surfaces
        public static let control: CGFloat = 8    // Small buttons, chips, segment items
        public static let field: CGFloat = 8      // Input fields, large buttons, KV rows
        public static let card: CGFloat = 12      // Resting dashboard/content cards
        public static let modal: CGFloat = 12     // Floating surfaces: command palette, toasts, popovers, empty-state tiles
        public static let keycap: CGFloat = 4      // Keyboard hint keycaps (near-square, Raycast-style)
        // pill: use Capsule() directly for fully rounded
        // Nested rule: inner radius = outer radius - padding (e.g. 8 - 2 = 6 for segment items)
        public static let nestedControl: CGFloat = 6
    }

    // MARK: - Icon Size (SF Symbols rendered inside controls and chrome)

    public enum IconSize {
        public static let micro: CGFloat = 10     // chevrons, disclosure markers
        public static let small: CGFloat = 12     // inline action icons
        public static let medium: CGFloat = 13    // toolbar and panel-accessory icons
        public static let large: CGFloat = 15     // rows, primary glyphs
        public static let tool: CGFloat = 16      // tool identity icons (sidebar rows)
        public static let display: CGFloat = 22   // empty-state / drop-zone hero glyphs
    }

    // MARK: - Responsive Breakpoints

    public enum Breakpoint {
        /// Collapse width for formatter tools (wider editors). Kept at or below
        /// the usable content width of the minimum window (960 window − 220
        /// sidebar ≈ 740) plus one column budget, so dual-pane formatters fold
        /// before their editors get crushed.
        public static let pairCollapseFormatter: CGFloat = 860
    }

    // MARK: - Legacy Animation Duration

    /// Compatibility shim for older shared controls. New motion work should use
    /// `ToolMotion` so duration, curve, transition, and Reduce Motion behavior
    /// stay in one vocabulary.
    public enum Animation {
        public static let fast: TimeInterval = ToolMotion.Duration.micro
        public static let base: TimeInterval = ToolMotion.Duration.quick
    }
}
