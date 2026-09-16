import AppKit
import SwiftUI

/// Single source of truth for the app's visual language.
///
/// Palette = **Clay Terminal** — the Ink Terminal Pro layout (see `SPEC.md` §7)
/// re-skinned onto Anthropic / Claude's warm clay-orange brand accent. Dark is
/// the reference; the dark surface ladder is anchored on the user-chosen
/// `#151517` workspace tone (warmer + lighter than the old near-black). Light is
/// derived by intent into a matching warm-neutral set, not a naive invert, and
/// is verified in-app.
///
/// Existing semantic token *names* are kept so all 36 tools restyle by value;
/// SPEC §7.1's suggested names are noted in comments for cross-reference.
enum ToolTheme {
    /// V3 workbench aliases. The home layout has its own geometry, while its
    /// color language deliberately remains inside the established app theme.
    enum Workbench {
        static let canvas = workspaceBackground
        static let surface = panelBackground
        static let surfaceSecondary = utilityBackground

        static let textPrimary = ToolTheme.textPrimary
        static let textSecondary = ToolTheme.textSecondary
        static let textFaint = ToolTheme.textTertiary

        static let border = ToolTheme.border
        static let action = ToolTheme.accent
        static let onAction = ToolTheme.onAccent
        static let danger = ToolTheme.error
        static let dangerBackground = ToolTheme.errorSoft
    }

    // MARK: - Accent (Claude 黏土橙)

    static let accent = dynamicColor(light: 0xC15F3C, dark: 0xD97757)          // §7.1 accent · Clay
    static let accentHover = dynamicColor(light: 0xA84F30, dark: 0xE38A6D)
    static let accentDim = dynamicColor(light: 0xA84F30, dark: 0xBE6346)       // §7.1 accentDim
    static let accentSoft = dynamicColor(light: 0xC15F3C, dark: 0xD97757, alpha: 0.10, darkAlpha: 0.12)  // §7.1 accentSoft
    static let accentBorder = dynamicColor(light: 0xC15F3C, dark: 0xD97757, alpha: 0.34, darkAlpha: 0.36) // §7.1 accentBorder
    /// Foreground that sits *on top of* an accent fill (status mode block, brand mark).
    /// Light accent is mid-dark → white text reads; dark accent is bright → deep-brown text reads.
    static let onAccent = dynamicColor(light: 0xFFF8F2, dark: 0x1A0F0A)        // §7.1 onAccent

    // MARK: - Surfaces (暖近黑底层级，锚定 #151517)
    //
    // Clay Warmth 层级（figure-ground）：浅色 = 暖灰底 + 白卡片；深色 = 亮度阶梯
    // （editor 最沉 < workspace < panel < utility/popover）。

    static let windowBackground = dynamicColor(light: 0xE8E4DC, dark: 0x0E0F11)     // §7.1 surfaceWindow
    static let workspaceBackground = dynamicColor(light: 0xF4F1EB, dark: 0x151517)  // §7.1 surfaceWorkspace ← 用户指定
    static let sidebarBackground = dynamicColor(light: 0xEAE6DE, dark: 0x121214)    // §7.1 surfaceSidebar
    static let sidebarHeaderBackground = sidebarBackground
    static let contentBackground = workspaceBackground
    static let panelBackground = dynamicColor(light: 0xFDFCFA, dark: 0x1E1E22)      // §7.1 surfacePanel
    static let utilityBackground = dynamicColor(light: 0xF5F2EC, dark: 0x242429)    // §7.1 surfacePanel2
    static let editorBackground = dynamicColor(light: 0xF5F2EC, dark: 0x0F0F11)     // §7.1 surfaceField
    static let elevatedBackground = dynamicColor(light: 0xFDFCFA, dark: 0x242429)
    static let popoverBackground = dynamicColor(light: 0xFDFCFA, dark: 0x242429, alpha: 0.96, darkAlpha: 0.97)

    // MARK: - Text (暖白 / 次要 / 弱)

    static let textPrimary = dynamicColor(light: 0x2A2520, dark: 0xE4E2DC)     // §7.1 textPrimary · 暖白
    static let textSecondary = dynamicColor(light: 0x6B645C, dark: 0x8A847C)   // §7.1 textSecondary
    static let textTertiary = dynamicColor(light: 0x9A938A, dark: 0x6E6862)    // §7.1 textTertiary(深色提亮以满足对比度)

    // MARK: - Lines & fills

    static let border = dynamicColor(light: 0x000000, dark: 0xFFFFFF, alpha: 0.08, darkAlpha: 0.07)        // §7.1 border
    static let strongBorder = dynamicColor(light: 0x000000, dark: 0xFFFFFF, alpha: 0.13, darkAlpha: 0.11)  // §7.1 border2
    static let hoverFill = dynamicColor(light: 0x000000, dark: 0xFFFFFF, alpha: 0.045, darkAlpha: 0.045)   // §7.1 hover
    static let activeFill = dynamicColor(light: 0x000000, dark: 0xFFFFFF, alpha: 0.07, darkAlpha: 0.07)
    static let selectionFill = dynamicColor(light: 0xC15F3C, dark: 0xD97757, alpha: 0.10, darkAlpha: 0.12)     // §7.1 selection
    static let selectionStroke = dynamicColor(light: 0xC15F3C, dark: 0xD97757, alpha: 0.22, darkAlpha: 0.30)   // §7.1 selectionBorder
    static let focusRing = dynamicColor(light: 0xC15F3C, dark: 0xD97757, alpha: 0.30, darkAlpha: 0.50)
    static let subtleShadow = dynamicColor(light: 0x1A140E, dark: 0x000000, alpha: 0.18, darkAlpha: 0.55)
    static let panelShadow = dynamicColor(light: 0x1A140E, dark: 0x000000, alpha: 0.05, darkAlpha: 0.32)
    /// Persistent cards sit one step above the workspace. Keep the lift
    /// visible but restrained so cards never read as floating dialogs.
    static let cardShadow = dynamicColor(light: 0x1A140E, dark: 0x000000, alpha: 0.075, darkAlpha: 0.38)

    // MARK: - Shadow recipes（层级语言：面板几乎无影靠色差，浮层与模态分层）

    /// A shadow recipe pairs a tint with radius/offset so every elevation
    /// level renders identically app-wide (`.toolShadow(...)`).
    struct ShadowRecipe {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }

    enum Shadow {
        /// Resting panels: separation comes from the surface ladder, not shadow.
        static let panel = ShadowRecipe(color: panelShadow, radius: 1, y: 1)
        /// Resting content cards: a low, short lift distinct from panels and
        /// substantially quieter than floating/modal surfaces.
        static let card = ShadowRecipe(color: cardShadow, radius: 5, y: 2)
        /// Floating feedback surfaces (toast / banner / diagnostic HUD).
        static let floating = ShadowRecipe(color: subtleShadow, radius: 12, y: 6)
        /// Modal layers (command palette, large popovers) — Arc-style depth.
        static let modal = ShadowRecipe(color: subtleShadow, radius: 24, y: 12)
    }

    // MARK: - Status (红黄绿灯 / 状态)

    static let info = accent
    static let success = dynamicColor(light: 0x4F7A4F, dark: 0x8FBC8F)   // §7.1 statusGreen · 柔橄榄绿
    static let warning = dynamicColor(light: 0xB58105, dark: 0xD8B156)   // §7.1 statusAmber
    static let error = dynamicColor(light: 0xC4362E, dark: 0xE5635C)     // §7.1 statusRed
    static let successSoft = dynamicColor(light: 0x4F7A4F, dark: 0x8FBC8F, alpha: 0.12, darkAlpha: 0.14)
    static let warningSoft = dynamicColor(light: 0xB58105, dark: 0xD8B156, alpha: 0.11, darkAlpha: 0.13)
    static let errorSoft = dynamicColor(light: 0xC4362E, dark: 0xE5635C, alpha: 0.11, darkAlpha: 0.13)

    // MARK: - Diff 行内片段强调(三层差异标记的片段层,比 soft 强一档)

    static let successFragment = dynamicColor(light: 0x4F7A4F, dark: 0x8FBC8F, alpha: 0.27, darkAlpha: 0.30)
    static let errorFragment = dynamicColor(light: 0xC4362E, dark: 0xE5635C, alpha: 0.25, darkAlpha: 0.30)

    // MARK: - Category identity gradients（135°，Clay 派生的低饱和暖色对）

    /// Arc Spaces 式分类身份徽章用。亮度/饱和度保持同档，仅色相微移，
    /// 与 Clay 橙和谐共处而不是各自争艳。
    static func categoryGradient(_ id: ToolCategoryID) -> LinearGradient {
        let (from, to) = Self.categoryGradientStops(id)
        return LinearGradient(
            colors: [Self.dynamicColor(light: from.0, dark: from.1),
                     Self.dynamicColor(light: to.0, dark: to.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func categoryGradientStops(_ id: ToolCategoryID) -> ((UInt32, UInt32), (UInt32, UInt32)) {
        switch id.rawValue {
        case "converter": return ((0xD97757, 0xE0875F), (0xE0A15E, 0xE7B268))   // 橙→金
        case "crypto": return ((0xD97757, 0xE0875F), (0xC96E8E, 0xD0819B))     // 橙→玫瑰
        case "development": return ((0xD97757, 0xE0875F), (0x9E6B4F, 0xA97B5C)) // 橙→赭
        case "web": return ((0xD97757, 0xE0875F), (0x8FA3B8, 0x9BB0C3))        // 橙→雾蓝
        case "text": return ((0xD97757, 0xE0875F), (0xC9B08A, 0xD2BC9A))       // 橙→砂
        case "image": return ((0xD97757, 0xE0875F), (0xA87BA0, 0xB489AC))      // 橙→藕紫
        case "time": return ((0xD97757, 0xE0875F), (0x7FA5A0, 0x8DB2AD))       // 橙→青瓷
        case "utility": return ((0xD97757, 0xE0875F), (0xA3B08A, 0xAFBC96))    // 橙→苔绿
        default: return ((0xD97757, 0xE0875F), (0x9A938A, 0xA6A097))           // 橙→暖灰
        }
    }

    // MARK: - Syntax highlight (§7.2 — 暖中性主调 + 柔蓝做唯一冷 pop)

    static let synKey = dynamicColor(light: 0x8A6D4A, dark: 0xD8C4B0)    // key：暖米
    static let synString = dynamicColor(light: 0x4F7A4F, dark: 0x8FBC8F) // string：柔橄榄绿
    static let synNumber = dynamicColor(light: 0x2563A8, dark: 0x6FB8E0) // number：柔蓝（避让橙 accent）
    static let synBool = dynamicColor(light: 0x9A6B3A, dark: 0xC99A6B)   // bool/null：暖棕
    static let synPunctuation = dynamicColor(light: 0x9A938A, dark: 0x5A554F) // 标点：暖灰压暗

    enum SynNSColor {
        static let key = dynamicNSColor(light: 0x8A6D4A, dark: 0xD8C4B0)
        static let string = dynamicNSColor(light: 0x4F7A4F, dark: 0x8FBC8F)
        static let number = dynamicNSColor(light: 0x2563A8, dark: 0x6FB8E0)
        static let bool = dynamicNSColor(light: 0x9A6B3A, dark: 0xC99A6B)
        static let punctuation = dynamicNSColor(light: 0x9A938A, dark: 0x5A554F)
        static let textPrimary = dynamicNSColor(light: 0x2A2520, dark: 0xE4E2DC)
        static let textSecondary = dynamicNSColor(light: 0x6B645C, dark: 0x8A847C)
    }

    static func dynamicNSColor(
        light: UInt32,
        dark: UInt32,
        alpha: CGFloat = 1,
        darkAlpha: CGFloat? = nil
    ) -> NSColor {
        NSColor(
            name: nil,
            dynamicProvider: { appearance in
                if appearance.isDarkMode {
                    return .toolHex(dark, alpha: darkAlpha ?? alpha)
                }

                return .toolHex(light, alpha: alpha)
            }
        )
    }

    private static func dynamicColor(
        light: UInt32,
        dark: UInt32,
        alpha: CGFloat = 1,
        darkAlpha: CGFloat? = nil
    ) -> Color {
        Color(nsColor: dynamicNSColor(light: light, dark: dark, alpha: alpha, darkAlpha: darkAlpha))
    }
}

private extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private extension NSColor {
    static func toolHex(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension View {
    /// Applies a `ToolTheme.Shadow` recipe so elevation renders identically
    /// app-wide instead of per-view radius/offset improvisation.
    func toolShadow(_ recipe: ToolTheme.ShadowRecipe) -> some View {
        shadow(color: recipe.color, radius: recipe.radius, y: recipe.y)
    }
}
