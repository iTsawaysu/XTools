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
/// Existing semantic token *names* are kept so all 34 tools restyle by value;
/// SPEC §7.1's suggested names are noted in comments for cross-reference.
///
/// ## Stroke-width semantics (design-foundation)
///
/// Border weights carry meaning by width — pick the role, not a number:
/// - `0.5` (`ToolMetrics.Spacing.hairline`): surface-part hairlines —
///   panels, KV surfaces, badges, cards, resting inputs.
/// - `1`: interactive control borders — button family, segmented tracks,
///   menu triggers, input resting edges that belong to a control.
/// - `1.5`: keyboard focus rings only (`IndexFocusRing` / focused inputs).
/// Tone-colored hairlines use the `*Border` tokens (shared 0.32/0.38 alpha
/// pair), never per-caller `tint.opacity(...)` values.
public enum ToolTheme {
    /// V3 workbench aliases. The home layout has its own geometry, while its
    /// color language deliberately remains inside the established app theme.
    public enum Workbench {
        public static let canvas = workspaceBackground
        public static let surface = panelBackground
        public static let surfaceSecondary = utilityBackground

        public static let textPrimary = ToolTheme.textPrimary
        public static let textSecondary = ToolTheme.textSecondary
        public static let textFaint = ToolTheme.textTertiary

        public static let border = ToolTheme.border
        public static let action = ToolTheme.accent
    }

    // MARK: - Accent (Claude 黏土橙)

    public static let accent = dynamicColor(light: 0xB5532F, dark: 0xD97757)          // §7.1 accent · Clay
    public static let accentHover = dynamicColor(light: 0x9F4927, dark: 0xE38A6D)
    public static let accentSoft = dynamicColor(light: 0xB5532F, dark: 0xD97757, alpha: 0.10, darkAlpha: 0.12)  // §7.1 accentSoft
    public static let accentBorder = dynamicColor(light: 0xB5532F, dark: 0xD97757, alpha: 0.34, darkAlpha: 0.36) // §7.1 accentBorder
    /// Foreground that sits *on top of* an accent fill (status mode block, brand mark).
    /// Light accent is mid-dark → white text reads; dark accent is bright → deep-brown text reads.
    public static let onAccent = dynamicColor(light: 0xFFF8F2, dark: 0x1A0F0A)        // §7.1 onAccent

    // MARK: - Surfaces (v5 暖中性阶梯，锚定陶土橙)
    //
    // v5：色相不变（clay accent），把中性色从冷灰改成暖炭/暖纸，并拉开
    // editor < workspace < panel < utility 的明度差；表面靠色阶分层，
    // 不引入玻璃、噪点或渐变材质。
    // 浅色 = 暖纸底 + 近白卡片；深色 = 暖炭阶梯。

    public static let windowBackground = dynamicColor(light: 0xE7E0D4, dark: 0x0D0B09)     // §7.1 surfaceWindow
    public static let workspaceBackground = dynamicColor(light: 0xF6F1E7, dark: 0x191510)  // §7.1 surfaceWorkspace
    public static let sidebarBackground = dynamicColor(light: 0xEDE6D9, dark: 0x110E0B)    // §7.1 surfaceSidebar
    public static let panelBackground = dynamicColor(light: 0xFCF8EF, dark: 0x2F2820)      // §7.1 surfacePanel
    public static let utilityBackground = dynamicColor(light: 0xFFFFFF, dark: 0x38302A)    // §7.1 surfacePanel2
    public static let editorBackground = dynamicColor(light: 0xEFE7D8, dark: 0x0B0908)     // §7.1 surfaceField
    /// 顶栏 ⌘K 触发按钮的 chip 底。浅色比 `editorBackground` 深一档：统一键帽
    /// `IndexKeycap` 的白色顶面落在过浅的 chip 上会白对白糊成一团，需要约 8%
    /// 明度差才能读出 figure-ground 层次（见 `Keycap` 注释的实测锚）；深色沿用
    /// editorBackground 的近黑——亮灰键帽在近黑上已有足够分离。
    public static let commandTriggerChip = dynamicColor(light: 0xEDE6D9, dark: 0x0B0908)
    public static let elevatedBackground = dynamicColor(light: 0xFFFFFF, dark: 0x38302A)
    public static let popoverBackground = dynamicColor(light: 0xFFFFFF, dark: 0x38302A, alpha: 0.97, darkAlpha: 0.98)

    // MARK: - Text (暖白 / 次要 / 弱)

    public static let textPrimary = dynamicColor(light: 0x2B241C, dark: 0xEDE6DC)     // §7.1 textPrimary · 暖白
    public static let textSecondary = dynamicColor(light: 0x5F5548, dark: 0xB0A698)   // §7.1 textSecondary
    public static let textTertiary = dynamicColor(light: 0x6F6455, dark: 0xA59B8E)    // §7.1 textTertiary（编辑面 ≥4.5:1）

    // MARK: - Lines & fills

    public static let border = dynamicColor(light: 0x3A2A1B, dark: 0xFFE7D2, alpha: 0.09, darkAlpha: 0.075)        // §7.1 border
    public static let strongBorder = dynamicColor(light: 0x3A2A1B, dark: 0xFFE7D2, alpha: 0.14, darkAlpha: 0.115)  // §7.1 border2
    public static let hoverFill = dynamicColor(light: 0x3A2A1B, dark: 0xFFE7D2, alpha: 0.05, darkAlpha: 0.05)      // §7.1 hover
    public static let activeFill = dynamicColor(light: 0x3A2A1B, dark: 0xFFE7D2, alpha: 0.075, darkAlpha: 0.075)
    public static let selectionFill = dynamicColor(light: 0xB5532F, dark: 0xD97757, alpha: 0.10, darkAlpha: 0.12)     // §7.1 selection
    public static let selectionStroke = dynamicColor(light: 0xB5532F, dark: 0xD97757, alpha: 0.22, darkAlpha: 0.30)   // §7.1 selectionBorder
    public static let focusRing = dynamicColor(light: 0xB5532F, dark: 0xD97757, alpha: 0.30, darkAlpha: 0.50)
    public static let subtleShadow = dynamicColor(light: 0x1A140E, dark: 0x000000, alpha: 0.18, darkAlpha: 0.55)
    public static let panelShadow = dynamicColor(light: 0x1A140E, dark: 0x000000, alpha: 0.05, darkAlpha: 0.32)
    /// Persistent cards sit one step above the workspace. Keep the lift
    /// visible but restrained so cards never read as floating dialogs.
    public static let cardShadow = dynamicColor(light: 0x1A140E, dark: 0x000000, alpha: 0.075, darkAlpha: 0.38)
    /// Wave 2 card-lift pane hover: resting depth (prototype --pane-shadow).
    public static let paneHoverShadowResting = dynamicColor(light: 0x1A140E, dark: 0x000000, alpha: 0.05, darkAlpha: 0.18)
    /// Wave 2 card-lift pane hover: lifted depth (prototype --pane-shadow-hov).
    public static let paneHoverShadowLifted = dynamicColor(light: 0x1A140E, dark: 0x000000, alpha: 0.12, darkAlpha: 0.34)

    // MARK: - Keycap（统一键帽配方 · 实心色片）
    //
    // 全 App 键帽的唯一视觉来源（`IndexKeycap`）。配方刻意归零装饰：
    // 一块比所在表面深（浅色）/亮（深色）一档的实心色片 + 干净硬边界 +
    // 近黑（浅）/暖白（深）字形，无渐变、无边线、无描边、无投影——
    // 质感全部来自色片与表面的明度差（参考实测：浅色床 #E6E6E6 落在
    // #FCFCFC 面板上，约 8% 明度差，边缘 1px 直切无任何过渡线）。

    /// 行内图标色片的静息底（Raycast 式图标底座），半透明不抢内容。
    public static let chipBed = dynamicColor(light: 0x000000, dark: 0xFFFFFF, alpha: 0.07, darkAlpha: 0.10)

    public enum Keycap {
        /// 键帽床：浅色＝黑 7%、深色＝白 10%，叠在所在表面上形成约一档明度差
        /// （ADR-0024 实测配方）。单层实心，无渐变/侧壁。
        public static let surface = dynamicColor(light: 0x000000, dark: 0xFFFFFF, alpha: 0.07, darkAlpha: 0.10)
        /// onAccent 变体（实心 accent 主按钮内）：onAccent 同色系床。
        public static let onAccentSurface = dynamicColor(light: 0xFFF8F2, dark: 0x2A1D15, alpha: 0.95, darkAlpha: 0.95)
        /// The keycap has its own surface; its glyph must contrast with that surface.
        public static let onAccentForeground = dynamicColor(light: 0x1A0F0A, dark: 0xFFF8F2)
    }

    // MARK: - Shadow recipes（层级语言：面板几乎无影靠色差，浮层与模态分层）

    /// A shadow recipe pairs a tint with radius/offset so every elevation
    /// level renders identically app-wide (`.toolShadow(...)`).
    public struct ShadowRecipe: Sendable {
        public let color: Color
        public let radius: CGFloat
        public let y: CGFloat

        public init(color: Color, radius: CGFloat, y: CGFloat) {
            self.color = color
            self.radius = radius
            self.y = y
        }
    }

    public enum Shadow {
        /// Resting panels: separation comes from the surface ladder, not shadow.
        public static let panel = ShadowRecipe(color: panelShadow, radius: 1, y: 1)
        /// Wave 2 card-lift pane hover depth pair (timing lives in
        /// `ToolMotion.PaneHover`): resting → lifted is the hover transition.
        /// Lift values stay restrained per review feedback.
        public static let paneHoverResting = ShadowRecipe(color: paneHoverShadowResting, radius: 6, y: 2)
        public static let paneHoverLifted = ShadowRecipe(color: paneHoverShadowLifted, radius: 20, y: 6)
        /// Resting content cards: a low, short lift distinct from panels and
        /// substantially quieter than floating/modal surfaces.
        public static let card = ShadowRecipe(color: cardShadow, radius: 5, y: 2)
        /// Floating feedback surfaces (toast / banner / diagnostic HUD).
        public static let floating = ShadowRecipe(color: subtleShadow, radius: 12, y: 6)
        /// Modal layers (command palette, large popovers) — Arc-style depth.
        public static let modal = ShadowRecipe(color: subtleShadow, radius: 24, y: 12)
    }

    // MARK: - Status (红黄绿灯 / 状态)

    public static let info = accent
    public static let success = dynamicColor(light: 0x4F7A4F, dark: 0x8FBC8F)   // §7.1 statusGreen · 柔橄榄绿
    public static let warning = dynamicColor(light: 0xB58105, dark: 0xD8B156)   // §7.1 statusAmber
    public static let error = dynamicColor(light: 0xC4362E, dark: 0xE5635C)     // §7.1 statusRed
    public static let successSoft = dynamicColor(light: 0x4F7A4F, dark: 0x8FBC8F, alpha: 0.12, darkAlpha: 0.14)
    public static let warningSoft = dynamicColor(light: 0xB58105, dark: 0xD8B156, alpha: 0.11, darkAlpha: 0.13)
    public static let errorSoft = dynamicColor(light: 0xC4362E, dark: 0xE5635C, alpha: 0.11, darkAlpha: 0.13)

    // MARK: - Tone borders（语义色 hairline 描边 · design-foundation）
    //
    // 同一用途「tone 色细描边」（badge / toast / 诊断轮廓 / 分组条）此前在
    // 调用侧自造 0.25–0.7 七种透明度；现在统一为一对 darkAlpha（light 0.32 /
    // dark 0.38），跟随 `accentBorder` 的双模式先例，0.5pt hairline 权重下
    // 浅纸与暖炭读感一致。

    public static let infoBorder = dynamicColor(light: 0xB5532F, dark: 0xD97757, alpha: 0.32, darkAlpha: 0.38)
    public static let successBorder = dynamicColor(light: 0x4F7A4F, dark: 0x8FBC8F, alpha: 0.32, darkAlpha: 0.38)
    public static let warningBorder = dynamicColor(light: 0xB58105, dark: 0xD8B156, alpha: 0.32, darkAlpha: 0.38)
    public static let errorBorder = dynamicColor(light: 0xC4362E, dark: 0xE5635C, alpha: 0.32, darkAlpha: 0.38)

    // MARK: - Opacity（外观感知的共享透明度）

    /// `.opacity()` 常量本身不跟随外观；共享 chrome 的透明度语义在此收口，
    /// 命名必须表达用途，调用侧不再拼写裸值。
    public enum Opacity {
        /// 禁用/弱化态的整体压暗：浅色纸面降到 0.40，深色暖炭保留 0.45 的
        /// 存在感。覆盖此前按钮族 0.40/0.35/0.55 等自造值。
        public static let disabledLight: CGFloat = 0.40
        public static let disabledDark: CGFloat = 0.45

        public static func disabled(_ scheme: ColorScheme) -> CGFloat {
            scheme == .dark ? disabledDark : disabledLight
        }

        /// 统一按压透明度（design-foundation C2）：与 `ToolMotion.Scale.pressed`
        /// 0.97 配对，Reduce Motion 下只降透明度不缩放。全库按压反馈单套参数。
        public static let pressed: Double = 0.88
    }

    // MARK: - Diff 行内片段强调(三层差异标记的片段层,比 soft 强一档)

    public static let successFragment = dynamicColor(light: 0x4F7A4F, dark: 0x8FBC8F, alpha: 0.27, darkAlpha: 0.30)
    public static let errorFragment = dynamicColor(light: 0xC4362E, dark: 0xE5635C, alpha: 0.25, darkAlpha: 0.30)

    // MARK: - Category identity gradients（135°，Clay 派生的低饱和暖色对）

    /// Arc Spaces 式分类身份徽章用。亮度/饱和度保持同档，仅色相微移，
    /// 与 Clay 橙和谐共处而不是各自争艳。
    // MARK: - Syntax highlight (§7.2 — 暖中性主调 + 柔蓝做唯一冷 pop)

    public static let synKey = dynamicColor(light: 0x8A6D4A, dark: 0xD8C4B0)    // key：暖米
    public static let synString = dynamicColor(light: 0x4F7A4F, dark: 0x8FBC8F) // string：柔橄榄绿
    public static let synNumber = dynamicColor(light: 0x2563A8, dark: 0x6FB8E0) // number：柔蓝（避让橙 accent）
    public static let synBool = dynamicColor(light: 0x9A6B3A, dark: 0xC99A6B)   // bool/null：暖棕
    public static let synPunctuation = dynamicColor(light: 0x9A938A, dark: 0x5A554F) // 标点：暖灰压暗

    public enum SynNSColor {
        public static let key = dynamicNSColor(light: 0x8A6D4A, dark: 0xD8C4B0)
        public static let string = dynamicNSColor(light: 0x4F7A4F, dark: 0x8FBC8F)
        public static let number = dynamicNSColor(light: 0x2563A8, dark: 0x6FB8E0)
        public static let bool = dynamicNSColor(light: 0x9A6B3A, dark: 0xC99A6B)
        public static let punctuation = dynamicNSColor(light: 0x9A938A, dark: 0x5A554F)
        public static let textPrimary = dynamicNSColor(light: 0x2A2520, dark: 0xE4E2DC)
        public static let textSecondary = dynamicNSColor(light: 0x6B645C, dark: 0x8A847C)
    }

    /// AppKit twin of the sidebar selection tokens for the flat navigation
    /// renderer's sliding indicator (see `SidebarSelectionIndicatorView`).
    /// Same values as `selectionFill` / `accent`; SwiftUI `Color` tokens cannot
    /// be wrapped back into appearance-tracking `NSColor` without duplicating
    /// the provider, mirroring the SynNSColor convention above.
    public enum SelectionNSColor {
        public static let fill = dynamicNSColor(light: 0xB5532F, dark: 0xD97757, alpha: 0.10, darkAlpha: 0.12)
        public static let rail = dynamicNSColor(light: 0xB5532F, dark: 0xD97757)
    }

    /// AppKit token for the sidebar's permanent thin scroll knob (see
    /// `SidebarScrollIndicatorView`). Translucent ink matching the native
    /// overlay knob sampled on the sidebar surface (~50% black over beige).
    public enum ScrollbarNSColor {
        public static let sidebarKnob = dynamicNSColor(
            light: 0x000000,
            dark: 0xFFFFFF,
            alpha: 0.5,
            darkAlpha: 0.4
        )
    }

    public static func dynamicNSColor(
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

public extension View {
    /// Applies a `ToolTheme.Shadow` recipe so elevation renders identically
    /// app-wide instead of per-view radius/offset improvisation.
    func toolShadow(_ recipe: ToolTheme.ShadowRecipe) -> some View {
        shadow(color: recipe.color, radius: recipe.radius, y: recipe.y)
    }

    /// Casts a shadow from an opaque rounded shape placed *behind* the view
    /// instead of compositing the shadow out of the content itself. Panes
    /// that host native AppKit editors need this: their gutter hairlines are
    /// drawn at subpixel width inside `NSView.draw`, and a content-level
    /// shadow flattens the subtree into the shadow layer, dropping those
    /// hairlines. The backing shape is fully covered by the pane above it,
    /// so only the shadow is visible.
    func toolShadowBehind(
        _ recipe: ToolTheme.ShadowRecipe,
        cornerRadius: CGFloat,
        surface: Color = ToolTheme.panelBackground
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(surface)
                .shadow(color: recipe.color, radius: recipe.radius, y: recipe.y)
        }
    }
}
