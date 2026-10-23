import SwiftUI
import XToolsDesign

// MARK: - 统一按压反馈（design-foundation C2）

/// 全库唯一按压反馈实现：`ToolMotion.Scale.pressed`（0.97）缩放 +
/// `ToolTheme.Opacity.pressed`（0.88）压暗。Reduce Motion 分支只降透明度
/// 不缩放。此前按钮族的 0.98 纯缩放与壳层 0.97+0.88 两套参数在此收敛。
///
/// 动画由调用侧已有的 `toolAnimation(ToolMotion.Preset.controlFeedback,
/// value:)` 驱动；本 modifier 只负责几何/透明度状态本身。
struct IndexPressFeedback: ViewModifier {
    let isPressed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(!reduceMotion && isPressed ? ToolMotion.Scale.pressed : 1)
            .opacity(isPressed ? ToolTheme.Opacity.pressed : 1)
    }
}

extension View {
    /// 统一按压反馈（见 `IndexPressFeedback`）。
    func indexPressFeedback(_ isPressed: Bool) -> some View {
        modifier(IndexPressFeedback(isPressed: isPressed))
    }
}

// MARK: - 按压状态的环境下发

/// `IndexQuietChromeStyle(look: .labelOnly)` 不自绘观感，但自绘 label
/// （如顶栏 ⌘K 触发钮）仍需要按压态来切换自身底色。样式把
/// `configuration.isPressed` 通过环境下发，label 侧用
/// `@Environment(\.indexButtonIsPressed)` 读取，替代每个调用点保留一个
/// 私有 ButtonStyle。
private struct IndexButtonPressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var indexButtonIsPressed: Bool {
        get { self[IndexButtonPressedKey.self] }
        set { self[IndexButtonPressedKey.self] = newValue }
    }
}

// MARK: - 安静钮统一样式（design-foundation C1）

/// 安静钮统一样式：吸收此前 6 类同构的安静钮——IndexBareButtonStyle、
/// IndexOptionsMenuTriggerStyle/RowStyle、IndexOptionPressableButtonStyle、
/// SidebarChromeButtonStyle、QuietTitlebarButtonStyle、
/// CommandTriggerButtonStyle。共享 hover/press 核心收敛在本文件的
/// `IndexQuietChromeBody`：`isHovering && isEnabled` 门控 +
/// hoverFill/activeFill 安静底色 + controlFeedback 动画 + 统一按压反馈。
/// 字体/内边距/高度由调用点的 label 负责，本样式只拥有 chrome 反馈。
struct IndexQuietChromeStyle: ButtonStyle {
    /// 外形档位。
    enum Look: Sendable, Equatable {
        /// 完全无 chrome：仅提供命中语义，页面自绘 hover/按压观感
        /// （原 IndexBareButtonStyle——虚线选择器、锚点网格、行内开关）。
        case bare
        /// 静止透明；hover/press 铺共享安静底色 + 统一按压反馈
        /// （原 SidebarChromeButtonStyle、IndexOptionsMenuRowStyle）。
        case quiet
        /// 静止 utility 底 + hairline 描边；hover/press/展开态上色
        /// （原 IndexOptionsMenuTriggerStyle 工具栏触发器）。
        case framed
        /// 仅统一按压反馈，无任何底色（原 IndexOptionPressableButtonStyle）。
        case pressOnly
        /// 仅 controlFeedback 按压动画；观感完全由 label 自绘，按压态经
        /// `\indexButtonIsPressed` 环境下发（原 CommandTriggerButtonStyle）。
        case labelOnly
    }

    /// 前景墨色规则。
    enum Ink: Sendable, Equatable {
        /// 前景完全由 label 决定（菜单行、自绘 label）。
        case labelOwned
        /// hover/press 把墨色从 secondary 提到 primary；禁用降 tertiary；
        /// 展开态保持 primary（壳层方形钮/工具栏触发器）。
        case quiet
        /// 只有按压反馈：按下时前景闪 accent（标题栏收藏星标），静止 secondary。
        case pressAccent
    }

    var look: Look = .quiet
    var ink: Ink = .labelOwned
    /// framed 的展开/锚定态：selectionFill 底 + accentBorder 描边（菜单
    /// 打开时的触发器，与 IndexOptionSwitch 的 on 态同语言）。
    var isEngaged = false
    /// quiet 的键盘高亮行：selectionFill（下拉菜单方向键高亮）。
    var isKeyboardHighlighted = false
    var cornerRadius: CGFloat = ToolMetrics.CornerRadius.control

    init(
        look: Look = .quiet,
        ink: Ink = .labelOwned,
        isEngaged: Bool = false,
        isKeyboardHighlighted: Bool = false,
        cornerRadius: CGFloat = ToolMetrics.CornerRadius.control
    ) {
        self.look = look
        self.ink = ink
        self.isEngaged = isEngaged
        self.isKeyboardHighlighted = isKeyboardHighlighted
        self.cornerRadius = cornerRadius
    }

    func makeBody(configuration: Configuration) -> some View {
        IndexQuietChromeBody(configuration: configuration, style: self)
    }
}

/// 共享 hover/press 核心：一个实现承载此前 6 处复制体的同构逻辑。
private struct IndexQuietChromeBody: View {
    let configuration: ButtonStyle.Configuration
    let style: IndexQuietChromeStyle

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    private var hovering: Bool { isHovering && isEnabled }

    private var fill: Color {
        // 展开态（framed 触发器）优先于按压——菜单打开期间触发器保持
        // selectionFill 锚定（原 IndexOptionsMenuTriggerStyle 行为）；
        // 键盘高亮行（quiet 菜单行）按压时让位给 activeFill（原 RowStyle 行为）。
        if style.look == .framed, style.isEngaged { return ToolTheme.selectionFill }
        if configuration.isPressed { return ToolTheme.activeFill }
        if style.isKeyboardHighlighted { return ToolTheme.selectionFill }
        switch style.look {
        case .framed:
            return hovering ? ToolTheme.hoverFill : ToolTheme.utilityBackground
        case .quiet:
            // pressAccent（标题栏收藏星标这类）只有按压反馈，hover 保持透明。
            return hovering && style.ink != .pressAccent ? ToolTheme.hoverFill : Color.clear
        case .bare, .pressOnly, .labelOnly:
            return Color.clear
        }
    }

    private var border: Color {
        if style.isEngaged { return ToolTheme.accentBorder }
        if hovering || configuration.isPressed { return ToolTheme.strongBorder }
        return ToolTheme.border
    }

    private var foreground: Color? {
        switch style.ink {
        case .labelOwned:
            return nil
        case .quiet:
            if !isEnabled { return ToolTheme.textTertiary }
            if style.isEngaged || configuration.isPressed { return ToolTheme.textPrimary }
            return hovering ? ToolTheme.textPrimary : ToolTheme.textSecondary
        case .pressAccent:
            return configuration.isPressed ? ToolTheme.accent : ToolTheme.textSecondary
        }
    }

    @ViewBuilder
    var body: some View {
        switch style.look {
        case .bare:
            configuration.label

        case .labelOnly:
            configuration.label
                .environment(\.indexButtonIsPressed, configuration.isPressed)
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: configuration.isPressed)

        case .pressOnly:
            configuration.label
                .indexPressFeedback(configuration.isPressed)
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: configuration.isPressed)

        case .quiet, .framed:
            chromeBody
        }
    }

    private var chromeBody: some View {
        configuration.label
            .modifier(IndexConditionalInk(ink: foreground))
            .background(
                fill,
                in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            )
            .overlay {
                if style.look == .framed {
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
            .indexPressFeedback(configuration.isPressed)
            .onHover { isHovering = $0 }
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: hovering)
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: configuration.isPressed)
    }
}

/// 条件前景色：`.labelOwned` 时不干预 label 自带的前景。
private struct IndexConditionalInk: ViewModifier {
    let ink: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let ink {
            content.foregroundStyle(ink)
        } else {
            content
        }
    }
}
