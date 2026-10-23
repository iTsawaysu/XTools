import AppKit
import SwiftUI
import XToolsDesign

enum IndexActionSymbol {
    static let clear = "xmark.circle"
    static let searchClear = "xmark.circle.fill"
    static let stop = "stop.fill"
    static let removeResource = "trash"
    static let reset = "arrow.counterclockwise"
    static let refresh = "arrow.clockwise"
    static let save = "square.and.arrow.down"
    static let copy = "doc.on.doc"
    static let favorite = "star"
    static let favoriteFill = "star.fill"
}

// MARK: - IndexButtonStyle

/// Conditional tooltip: applies `.help` only when a title exists — labeled
/// controls show their own title, so only icon-only slots carry a tooltip.
private struct IndexOptionalHelp: ViewModifier {
    let title: String?

    func body(content: Content) -> some View {
        if let title {
            content.help(title)
        } else {
            content
        }
    }
}

struct IndexButtonStyle: ButtonStyle {
    var primary = false
    /// 紧凑密度（design-foundation C2，吸收原 IndexSmallButtonStyle）：
    /// 高 `Control.small`（24）、水平内距 `Spacing.sm`、buttonSmall 字号、
    /// control 圆角；`done`/`framed` 为 compact 专属变体（成功回执/描边静止态）。
    var compact = false
    var done = false
    /// Framed secondary treatment (prototype v3 workbench actions): the button
    /// rests on `utilityBackground` inside a hairline instead of staying quiet
    /// on the page surface until hover.
    var framed = false

    init(primary: Bool = false, compact: Bool = false, done: Bool = false, framed: Bool = false) {
        self.primary = primary
        self.compact = compact
        self.done = done
        self.framed = framed
    }

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, primary: primary, compact: compact, done: done, framed: framed)
    }

    /// Extracted into a `View` so we can hold `@State` for hover — `ButtonStyle.Configuration`
    /// exposes `isPressed` but not hover. `@Environment(\.isEnabled)` gates the hover visual
    /// so disabled buttons don't light up.
    private struct StyleBody: View {
        let configuration: Configuration
        let primary: Bool
        let compact: Bool
        let done: Bool
        let framed: Bool

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var colorScheme

        private var hovering: Bool { isHovering && isEnabled }

        private var height: CGFloat { compact ? ToolMetrics.Control.small : ToolMetrics.Control.regular }
        private var horizontalPadding: CGFloat { compact ? ToolMetrics.Spacing.sm : ToolMetrics.Spacing.md }
        private var cornerRadius: CGFloat { compact ? ToolMetrics.CornerRadius.control : ToolMetrics.CornerRadius.field }
        private var font: Font { compact ? ToolTypography.buttonSmall : ToolTypography.bodyMedium }

        /// Compact 密度沿用原 IndexSmallButtonStyle 的紧凑文本（单行、
        /// 定宽不压缩）；regular 密度保持自然标题排版。
        @ViewBuilder
        private var labelContent: some View {
            if compact {
                configuration.label
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                configuration.label
            }
        }

        private var background: Color {
            if primary {
                if !isEnabled { return ToolTheme.accent.opacity(ToolTheme.Opacity.disabled(colorScheme)) }
                return (configuration.isPressed || hovering) ? ToolTheme.accentHover : ToolTheme.accent
            }
            if done { return ToolTheme.successSoft }
            if configuration.isPressed { return ToolTheme.activeFill }
            if hovering { return framed ? ToolTheme.activeFill : ToolTheme.hoverFill }
            // Quiet controls stay on the page surface until interaction. This
            // keeps action rows closer to Linear/Craft's low-noise grammar and
            // avoids a sea of bordered system buttons.
            return framed ? ToolTheme.utilityBackground : Color.clear
        }

        private var border: Color {
            if primary {
                return isEnabled ? ToolTheme.accent : ToolTheme.accent.opacity(ToolTheme.Opacity.disabled(colorScheme))
            }
            if done { return ToolTheme.successSoft }
            if hovering || configuration.isPressed { return ToolTheme.strongBorder }
            return framed ? ToolTheme.border : Color.clear
        }

        private var foreground: Color {
            if done { return ToolTheme.success }
            guard isEnabled else {
                if primary { return ToolTheme.onAccent.opacity(ToolTheme.Opacity.disabled(colorScheme)) }
                return compact ? ToolTheme.textTertiary.opacity(0.7) : ToolTheme.textTertiary
            }
            if primary { return ToolTheme.onAccent }
            return compact ? ToolTheme.textSecondary : ToolTheme.textPrimary
        }

        var body: some View {
            labelContent
                .font(font)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(foreground)
                .padding(.horizontal, horizontalPadding)
                .frame(height: height)
                .background(background, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .indexPressFeedback(configuration.isPressed)
                .onHover { isHovering = $0 }
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: hovering)
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: configuration.isPressed)
        }
    }
}

struct IndexIconActionButtonStyle: ButtonStyle {
    var isActive = false
    var activeTint: Color = ToolTheme.accent
    var tint: Color = ToolTheme.textSecondary
    var activeBackground: Color = ToolTheme.selectionFill

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(
            configuration: configuration,
            isActive: isActive,
            activeTint: activeTint,
            tint: tint,
            activeBackground: activeBackground
        )
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let isActive: Bool
        let activeTint: Color
        let tint: Color
        let activeBackground: Color

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var hovering: Bool { isHovering && isEnabled }

        // reduceMotion 仍用于下方 RM 事务门（禁用隐式动画）；按压几何/
        // 透明度反馈已由 `indexPressFeedback` 内部接管 RM 分支。

        private var foreground: Color {
            if isActive { return activeTint }
            return isEnabled ? tint : ToolTheme.textTertiary
        }

        private var background: Color {
            if configuration.isPressed && isEnabled { return ToolTheme.activeFill }
            if hovering { return ToolTheme.hoverFill }
            if isActive { return activeBackground }
            return Color.clear
        }

        var body: some View {
            configuration.label
                .font(ToolTypography.buttonSmall)
                .foregroundStyle(foreground)
                .frame(width: 24, height: 24)
                .background(background, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .indexPressFeedback(configuration.isPressed)
                .onHover { isHovering = $0 }
                .toolAnimation(
                    ToolMotion.Preset.controlFeedback,
                    value: [hovering, configuration.isPressed, isActive]
                )
                .transaction { transaction in
                    if reduceMotion { transaction.disablesAnimations = true }
                }
        }
    }
}

// MARK: - IndexPasteboard

enum IndexPasteboard {
    @discardableResult
    @MainActor
    static func copyString(_ string: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(string, forType: .string)
    }

    /// Data copy path for workflows that write raw `Data` (e.g. Base64 file
    /// output) rather than a `String`. Single pasteboard write entry so no
    /// page hand-rolls `NSPasteboard.general` directly.
    ///
    /// Deliberately non-isolated: `Base64FileWorkflowClient.PasteboardWriter`
    /// calls this from a `@Sendable (Data) -> Bool` closure, so it must not
    /// carry MainActor isolation. `NSPasteboard.general` writes are thread-safe.
    @discardableResult
    static func copyData(_ data: Data) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setData(data, forType: .string)
    }
}

// MARK: - IndexPrimaryActionButton

/// Primary action with an optional keycap hint (prototype v3 `⌘↩` chip).
/// The key equivalent itself stays at the call site so pages keep one place
/// to look for shortcut wiring.
struct IndexPrimaryActionButton: View {
    let title: String
    var hint: String? = nil
    var help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                Text(title)
                if let hint {
                    IndexKeyboardHintLabel(hint: hint)
                }
            }
            // Toolbar halves can run tight; the prototype action must keep its
            // label and shed width through the compressible diagnostic slot
            // instead of collapsing into an empty accent pill.
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(IndexButtonStyle(primary: true))
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Tiny keycap chip rendered inside primary actions.
private struct IndexKeyboardHintLabel: View {
    let hint: String

    var body: some View {
        IndexKeycap(label: hint, variant: .onAccent)
            .accessibilityHidden(true)
    }
}

struct IndexProgressMotionLabel<ID: Hashable>: View {
    let title: String
    let systemImage: String
    let isProcessing: Bool
    let id: ID

    var body: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Group {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
            }
            .frame(width: 14, height: 14)
            .toolMotionIconSwap(id: id)

            Text(title)
                .toolMotionTextSwap(id: id)
        }
    }
}

// MARK: - IndexFieldHeader

/// Field/pane header row: small secondary label on the leading side, trailing
/// quick actions (copy, segmented options, menus). Single home for the
/// `HStack { Text(label); Spacer; actions }` pattern so every pane header in
/// the app shares one type scale and color.
struct IndexFieldHeader<Accessory: View>: View {
    let title: String
    let accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Text(title)
                .font(ToolTypography.label)
                .foregroundStyle(ToolTheme.textSecondary)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            accessory
                .layoutPriority(2)
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

extension IndexFieldHeader where Accessory == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - IndexClearButton

struct IndexClearButton: View {
    let isDisabled: Bool
    var title = "清空"
    var iconOnly = false
    var showsIcon = true
    var framed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if iconOnly {
                Image(systemName: IndexActionSymbol.clear)
                    .font(ToolTypography.buttonSmall)
            } else if showsIcon {
                Label(title, systemImage: IndexActionSymbol.clear)
                    .font(ToolTypography.buttonSmall)
            } else {
                Text(title)
                    .font(ToolTypography.buttonSmall)
            }
        }
        .buttonStyle(IndexButtonStyle(compact: true, framed: framed))
        .disabled(isDisabled)
        // Icon-only slots have no visible title to fall back on.
        .modifier(IndexOptionalHelp(title: iconOnly ? title : nil))
        .accessibilityLabel(title)
    }
}

// MARK: - IndexIconButton

struct IndexIconButton: View {
    let systemImage: String
    let help: String
    /// `nil` models a momentary action. Passing a Boolean opts the control
    /// into toggle semantics for both styling and assistive technologies.
    var isActive: Bool? = nil
    var activeTint: Color = ToolTheme.accent
    var tint: Color = ToolTheme.textSecondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .toolMotionIconSwap(id: systemImage)
        }
        .buttonStyle(IndexIconActionButtonStyle(
            isActive: isActive ?? false,
            activeTint: activeTint,
            tint: tint
        ))
        .help(help)
        .accessibilityLabel(help)
        .modifier(IndexIconButtonActiveAccessibility(isActive: isActive))
    }
}

private struct IndexIconButtonActiveAccessibility: ViewModifier {
    let isActive: Bool?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let isActive {
            content
                .accessibilityAddTraits(isActive ? .isSelected : [])
                .accessibilityValue(isActive ? "已开启" : "已关闭")
        } else {
            content
        }
    }
}

