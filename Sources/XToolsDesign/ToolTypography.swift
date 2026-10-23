import AppKit
import SwiftUI

/// Single source of truth for recurring tool-page typography.
///
/// macOS tool pages use one stable native point-size hierarchy. Centralized
/// semantic tokens keep page, panel, body, control, editor, and display text
/// consistent without a second app-level scaling system.
public enum ToolTypography {
    /// Compact V3 workbench hierarchy. Existing tool pages continue using the
    /// top-level tokens above and below this namespace.
    public enum Workbench {
        public static let title = Font.system(size: 20, weight: .semibold)
        public static let subtitle = Font.system(size: 13)
        public static let sectionTitle = Font.system(size: 13, weight: .semibold)
        public static let body = Font.system(size: 12.5)
        public static let caption = Font.system(size: 11)
        public static let input = Font.system(size: 12.5, design: .monospaced)
        public static let icon = Font.system(size: 14)
        public static let smallIcon = Font.system(size: 11)
        public static let chevron = Font.system(size: 10, weight: .medium)
    }

    // MARK: - Page Level

    public static let pageTitle = Font.system(size: 20, weight: .semibold)
    public static let pageSubtitle = Font.system(size: 12.5)

    // MARK: - Panel Level

    /// Quiet panel label: sans medium, sentence case (Clay Warmth — the
    /// terminal-style mono uppercase label is retired).
    public static let panelTitle = Font.system(size: 12.5, weight: .medium)

    // MARK: - Section Level

    public static let sectionTitle = Font.system(size: 14, weight: .semibold)
    /// Larger in-page section header (between page title and section title).
    public static let sectionHeader = Font.system(size: 15, weight: .semibold)

    // MARK: - Body & Labels

    /// Slightly larger body used by list rows (sidebar tools, palette rows).
    public static let bodyLarge = Font.system(size: 13)
    /// Group/section header rows in lists (sidebar groups, palette sections).
    public static let groupHeader = Font.system(size: 12, weight: .semibold)
    /// App copy and labels use the native system face. Code-like surfaces opt
    /// into `codeBody` explicitly so the shell never inherits a terminal look.
    public static let body = Font.system(size: 12.5)
    public static let codeBody = Font.system(size: 12.5, design: .monospaced)
    public static let bodyPlain = Font.system(size: 12.5)
    public static let bodyMedium = Font.system(size: 12.5, weight: .medium)
    public static let compactBody = Font.system(size: 12)
    public static let label = Font.system(size: 12, weight: .medium)
    public static let monoLabel = Font.system(size: 12, design: .monospaced)
    public static let caption = Font.system(size: 11)
    public static let monoCaption = Font.system(size: 11, design: .monospaced)
    public static let micro = Font.system(size: 10, weight: .medium)
    /// Field-label weight for labels attached to inputs and value rows.
    public static let fieldLabel = Font.system(size: 11, weight: .medium)
    /// Tiny monospaced tag (terminal tags, micro badges).
    public static let tagMicro = Font.system(size: 9.5, weight: .semibold, design: .monospaced)
    /// Keycap label for keyboard shortcuts (⌘↩, ⌘K) ensuring crisp glyph rendering.
    public static let keycap = Font.system(size: 11, weight: .medium)

    // MARK: - Markdown Preview (indexClay)

    /// Markdown prose baseline (13pt) and code block face for the rendered
    /// preview; heading sizes stay composed in MarkdownFontProperties so nested
    /// inline styles can merge over them.
    public static let markdownProse = Font.system(size: 13)
    public static let markdownCodeBlock = Font.system(size: 12, weight: .regular, design: .monospaced)

    // MARK: - Monospaced Values (semibold mono for codes & numeric badges)

    /// Semibold mono code badge (HTTP status codes, keycode chips).
    public static let monoValueSmall = Font.system(size: 12, weight: .semibold, design: .monospaced)
    /// Semibold mono row value where the value itself is the identity.
    public static let monoValueMedium = Font.system(size: 12.5, weight: .semibold, design: .monospaced)

    // MARK: - Brand

    /// Sidebar brand wordmark (mono semibold keeps the workbench identity).
    public static let brandMark = Font.system(size: 13, weight: .semibold, design: .monospaced)

    // MARK: - Display Values

    public static let valueMedium = Font.system(size: 18, design: .monospaced)
    public static let statValue = Font.system(size: 20, weight: .semibold, design: .monospaced)
    public static let heroValue = Font.system(size: 30, weight: .semibold, design: .monospaced)
    /// Rounded personality variant for "result as delight" surfaces (chronometer).
    public static let giantValueRounded = Font.system(size: 46, weight: .semibold, design: .rounded)
    /// Hero value with a selectable design (mono default, rounded delight).
    public static func heroValue(design: Font.Design) -> Font {
        Font.system(size: 30, weight: .semibold, design: design)
    }

    // MARK: - Button & Controls

    public static let buttonSmall = Font.system(size: 11, weight: .medium)

    public static func controlLabel(weight: Font.Weight) -> Font {
        .system(size: 12, weight: weight)
    }

    /// SF Symbol glyph font for chrome and rows. `size` must come from
    /// `ToolMetrics.IconSize`; weights collapse to regular / medium /
    /// semibold so icon weight cannot drift per page (design-foundation).
    public static func icon(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: - Numeric point-size mirrors
    //
    // Renderers that merge over point sizes (markdown inline pipeline) cannot
    // hold a composed `Font`. These mirrors keep their numeric hierarchies in
    // lockstep with the tokens above instead of re-spelling literals.

    public enum PointSize {
        public static let pageTitle: CGFloat = 20
        public static let sectionHeader: CGFloat = 15
        public static let sectionTitle: CGFloat = 14
        public static let markdownProse: CGFloat = 13
    }

    // MARK: - AppKit mirrors
    //
    // NSFont factories for AppKit-backed surfaces (collection headers, hover
    // layers). Keep sizes/weights in lockstep with the SwiftUI tokens above —
    // this is the only sanctioned place to construct raw NSFont point sizes.

    public enum AppKitMirror {
        public static func body() -> NSFont { .systemFont(ofSize: 12.5) }
        public static func bodyMedium() -> NSFont { .systemFont(ofSize: 12.5, weight: .medium) }
        public static func caption() -> NSFont { .systemFont(ofSize: 11) }
        /// Monospaced body twin of `codeBody` (12.5 regular) for AppKit-backed
        /// editors, gutters and read-only surfaces — the only sanctioned mono
        /// 12.5 construction.
        public static func codeBody() -> NSFont { .monospacedSystemFont(ofSize: 12.5, weight: .regular) }
    }
}
