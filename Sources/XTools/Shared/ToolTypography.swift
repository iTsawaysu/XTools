import AppKit
import SwiftUI

/// Single source of truth for recurring tool-page typography.
///
/// macOS tool pages use one stable native point-size hierarchy. Centralized
/// semantic tokens keep page, panel, body, control, editor, and display text
/// consistent without a second app-level scaling system.
enum ToolTypography {
    /// Compact V3 workbench hierarchy. Existing tool pages continue using the
    /// top-level tokens above and below this namespace.
    enum Workbench {
        static let title = Font.system(size: 20, weight: .semibold)
        static let subtitle = Font.system(size: 13)
        static let sectionTitle = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 12.5)
        static let caption = Font.system(size: 11)
        static let input = Font.system(size: 12.5, design: .monospaced)
        static let icon = Font.system(size: 14)
        static let smallIcon = Font.system(size: 11)
        static let chevron = Font.system(size: 10, weight: .medium)
    }

    // MARK: - Page Level

    static let pageTitle = Font.system(size: 18, weight: .semibold)
    static let pageSubtitle = Font.system(size: 12.5)

    // MARK: - Panel Level

    /// Quiet panel label: sans medium, sentence case (Clay Warmth — the
    /// terminal-style mono uppercase label is retired).
    static let panelTitle = Font.system(size: 12.5, weight: .medium)
    /// Prominent panel header used by workbench-density panels (13pt semibold).
    static let panelTitleProminent = Font.system(size: 13, weight: .semibold)

    // MARK: - Section Level

    static let sectionTitle = Font.system(size: 14, weight: .semibold)
    /// Larger in-page section header (between page title and section title).
    static let sectionHeader = Font.system(size: 15, weight: .semibold)

    // MARK: - Body & Labels

    /// Slightly larger body used by list rows (sidebar tools, palette rows).
    static let bodyLarge = Font.system(size: 13)
    /// Group/section header rows in lists (sidebar groups, palette sections).
    static let groupHeader = Font.system(size: 12, weight: .semibold)
    /// App copy and labels use the native system face. Code-like surfaces opt
    /// into `codeBody` explicitly so the shell never inherits a terminal look.
    static let body = Font.system(size: 12.5)
    static let codeBody = Font.system(size: 12.5, design: .monospaced)
    static let bodyPlain = Font.system(size: 12.5)
    static let bodyMedium = Font.system(size: 12.5, weight: .medium)
    static let compactBody = Font.system(size: 12)
    static let label = Font.system(size: 12, weight: .medium)
    static let monoLabel = Font.system(size: 12, design: .monospaced)
    static let caption = Font.system(size: 11)
    static let monoCaption = Font.system(size: 11, design: .monospaced)
    static let micro = Font.system(size: 10, weight: .medium)
    /// Field-label weight for labels attached to inputs and value rows.
    static let fieldLabel = Font.system(size: 11, weight: .medium)
    /// Tiny monospaced tag (terminal tags, keyboard hints, micro badges).
    static let tagMicro = Font.system(size: 9.5, weight: .semibold, design: .monospaced)

    // MARK: - Monospaced Values (semibold mono for codes & numeric badges)

    /// Semibold mono code badge (HTTP status codes, keycode chips).
    static let monoValueSmall = Font.system(size: 12, weight: .semibold, design: .monospaced)
    /// Semibold mono row value where the value itself is the identity.
    static let monoValueMedium = Font.system(size: 12.5, weight: .semibold, design: .monospaced)

    // MARK: - Brand

    /// Sidebar brand wordmark (mono semibold keeps the workbench identity).
    static let brandMark = Font.system(size: 13, weight: .semibold, design: .monospaced)

    // MARK: - Display Values

    static let valueSmall = Font.system(size: 12, weight: .semibold)
    static let valueMedium = Font.system(size: 18, design: .monospaced)
    static let statValue = Font.system(size: 20, weight: .semibold, design: .monospaced)
    static let heroValue = Font.system(size: 30, weight: .semibold, design: .monospaced)
    static let giantValue = Font.system(size: 46, weight: .semibold, design: .monospaced)
    /// Rounded personality variant for "result as delight" surfaces (chronometer).
    static let giantValueRounded = Font.system(size: 46, weight: .semibold, design: .rounded)
    /// Hero value with a selectable design (mono default, rounded delight).
    static func heroValue(design: Font.Design) -> Font {
        Font.system(size: 30, weight: .semibold, design: design)
    }

    // MARK: - Button & Controls

    static let buttonSmall = Font.system(size: 11, weight: .medium)

    static func controlLabel(weight: Font.Weight) -> Font {
        .system(size: 12, weight: weight)
    }

    // MARK: - AppKit mirrors
    //
    // NSFont factories for AppKit-backed surfaces (collection headers, hover
    // layers). Keep sizes/weights in lockstep with the SwiftUI tokens above —
    // this is the only sanctioned place to construct raw NSFont point sizes.

    enum AppKitMirror {
        static func bodyMedium() -> NSFont { .systemFont(ofSize: 12.5, weight: .medium) }
        static func caption() -> NSFont { .systemFont(ofSize: 11) }
    }
}
