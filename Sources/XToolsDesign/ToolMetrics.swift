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
        /// Fixed height of every paper's head row. One value for all shells so
        /// paper identities align across tools (audit H-02).
        public static let paperHeadHeight: CGFloat = 44
        /// Fixed paper inset on all four sides (audit H-02 / rules §2.2).
        public static let paperInset: CGFloat = 14
        /// Maximum readable width for tool-paper content on very wide windows.
        /// Above this the paper stops growing and centres (audit W-04).
        public static let paperMaxWidth: CGFloat = 1080
    }

    // MARK: - Spacing
    //
    // 11-step ladder (design-foundation, 2026-10): 1, 2, 4, 6, 8, 10, 12,
    // 14, 16, 20, 24. Retired neighbours snap by proximity: 3/5→4, 7/9→8,
    // 11/13→12, 15/18→16, 26/30/32→24, 1.5/2.5→2 (equidistant takes the
    // lower step). Pages must not spell these numbers; `spacing: 0` stays
    // legal for explicitly tight stacks.

    public enum Spacing {
        public static let hair: CGFloat = 1
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let fine: CGFloat = 6
        public static let sm: CGFloat = 8
        public static let compact: CGFloat = 10
        public static let md: CGFloat = 12
        public static let base: CGFloat = 14      // Default panel padding & spacing
        public static let lg: CGFloat = 16
        public static let xxl: CGFloat = 20
        public static let xxxl: CGFloat = 24

        // Shared panel geometry. Keeping these named prevents individual
        // workspaces from inventing slightly different header/content insets.
        public static let panelInset: CGFloat = 14
        public static let panelSection: CGFloat = 10
        /// 0.5pt hairline. Pages must not spell the literal themselves.
        public static let hairline: CGFloat = 0.5
        /// Reading measure for a single centered form field (watermark text,
        /// short input strips) inside a paper.
        public static let compactFormMaxWidth: CGFloat = 360
    }

    // MARK: - Corner Radius
    //
    // Clay Warmth ladder (Arc/Craft-grade softness): panels and modals are
    // generously rounded; controls and fields share one softer step. The ladder
    // is {4, 6, 8, 10} plus Capsule for pills.

    /// Four fixed steps (rules §3.2): paper 10 · editor/input 8 · small
    /// control 8 · keycap 4. `card`/`modal` are legacy aliases that resolve
    /// to the same four steps so old call sites cannot reintroduce a fifth
    /// or sixth visual radius (audit C-04).
    public enum CornerRadius {
        public static let panel: CGFloat = 10     // Paper surfaces
        public static let control: CGFloat = 8    // Small buttons, chips, segment items
        public static let field: CGFloat = 8      // Input fields, large buttons, KV rows
        public static let card: CGFloat = panel   // Legacy alias → paper step
        public static let modal: CGFloat = panel  // Legacy alias → paper step
        public static let keycap: CGFloat = 4     // Keyboard hint keycaps
        // pill: use Capsule() directly for fully rounded
        /// Nested rule: inner radius = outer radius - padding (8 − 2 = 6).
        public static let nestedControl: CGFloat = 6
    }

    // MARK: - Control Size (fixed square/row dimensions used by chrome)

    /// Fixed control dimensions. Pages must not spell these numbers; the
    /// values cover the app's icon buttons, chips, rows and thumbnails.
    public enum Control {
        public static let tiny: CGFloat = 16
        public static let mini: CGFloat = 20
        public static let small: CGFloat = 24
        public static let medium: CGFloat = 28
        public static let regular: CGFloat = 32
        public static let large: CGFloat = 38
        public static let thumb: CGFloat = 44
        public static let badge: CGFloat = 18
        public static let swatch: CGFloat = 48
        public static let row: CGFloat = 36
        public static let strip: CGFloat = 92
        /// Regular option-group control height — the IndexSegmentedControl
        /// "regular" step (design.md §3.4). Switch tracks and option rows in
        /// the same group align on this value; the compact 22 step stays
        /// density-local to the segmented control.
        public static let segmentItem: CGFloat = 26
        /// Label column for "label + value" rows (chmod, Basic Auth, math).
        public static let labelColumn: CGFloat = 70
        /// Number field / slider column widths used by option groups.
        public static let slider: CGFloat = 100
        public static let colorWell: CGFloat = 180
        public static let valueColumn: CGFloat = 88
        public static let thumbnail: CGFloat = 64
        public static let preview: CGFloat = 132
        public static let calendar: CGFloat = 280
        public static let modeSegment: CGFloat = 110
        public static let modeSegmentHeight: CGFloat = 38
        public static let dot: CGFloat = 5
        public static let separator: CGFloat = 2
        public static let swatchTiny: CGFloat = 8
        public static let textMicroWidth: CGFloat = 18
        public static let labelInset: CGFloat = 13
        /// Minimum widths for the long-text action cluster on text conversion
        /// pages (mode picker, password field).
        public static let actionMinWidth: CGFloat = 76
        public static let fieldMinWidth: CGFloat = 160
        public static let passwordIdealWidth: CGFloat = 220
        public static let passwordMaxWidth: CGFloat = 280
        /// Reading measures for long-form / list content inside papers.
        public static let readingWide: CGFloat = 620
        public static let readingMedium: CGFloat = 360
        public static let readingNarrow: CGFloat = 320
        public static let textSmallWidth: CGFloat = 44
        public static let textWideWidth: CGFloat = 300
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

    // MARK: - Window

    /// 主窗口几何单源：XToolsApp（Scene 层 window frame）与 RootView（内容
    /// 层 frame）双处引用同一常量，防止两处 min 尺寸漂移（阶段③ 治理速赢）。
    public enum Window {
        public static let minimumWidth: CGFloat = 960
        public static let minimumHeight: CGFloat = 640
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
