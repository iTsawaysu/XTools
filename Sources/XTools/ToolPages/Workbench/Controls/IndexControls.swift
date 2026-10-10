import AppKit
import SwiftUI

enum IndexActionSymbol {
    static let clear = "xmark.circle"
    static let searchClear = "xmark.circle.fill"
    static let stop = "stop.fill"
    static let removeResource = "trash"
    static let reset = "arrow.counterclockwise"
    static let refresh = "arrow.clockwise"
    static let save = "square.and.arrow.down"
    static let copy = "doc.on.doc"
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

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, primary: primary)
    }

    /// Extracted into a `View` so we can hold `@State` for hover — `ButtonStyle.Configuration`
    /// exposes `isPressed` but not hover. `@Environment(\.isEnabled)` gates the hover visual
    /// so disabled buttons don't light up.
    private struct StyleBody: View {
        let configuration: Configuration
        let primary: Bool

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var hovering: Bool { isHovering && isEnabled }

        private var background: Color {
            if primary {
                return (configuration.isPressed || hovering) ? ToolTheme.accentHover : ToolTheme.accent
            }
            if configuration.isPressed { return ToolTheme.activeFill }
            // Quiet controls stay on the page surface until interaction. This
            // keeps action rows closer to Linear/Craft's low-noise grammar and
            // avoids a sea of bordered system buttons.
            return hovering ? ToolTheme.hoverFill : Color.clear
        }

        var body: some View {
            configuration.label
                .font(ToolTypography.bodyMedium)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(primary ? ToolTheme.onAccent : ToolTheme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(background, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                        .strokeBorder(primary ? ToolTheme.accent : (hovering ? ToolTheme.strongBorder : Color.clear), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
                .scaleEffect(!reduceMotion && configuration.isPressed ? ToolMotion.Scale.modal : 1)
                .onHover { isHovering = $0 }
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: hovering)
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: configuration.isPressed)
        }
    }
}

// MARK: - IndexSmallButtonStyle

struct IndexSmallButtonStyle: ButtonStyle {
    var done = false
    /// Framed secondary treatment (prototype v3 workbench actions): the button
    /// rests on `utilityBackground` inside a hairline instead of staying quiet
    /// on the page surface until hover.
    var framed = false

    init(done: Bool = false, framed: Bool = false) {
        self.done = done
        self.framed = framed
    }

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, done: done, framed: framed)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let done: Bool
        let framed: Bool

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var hovering: Bool { isHovering && isEnabled }

        private var background: Color {
            if done { return ToolTheme.successSoft }
            if configuration.isPressed { return ToolTheme.activeFill }
            if hovering { return framed ? ToolTheme.activeFill : ToolTheme.hoverFill }
            return framed ? ToolTheme.utilityBackground : Color.clear
        }

        private var border: Color {
            if done { return ToolTheme.successSoft }
            if hovering || configuration.isPressed { return ToolTheme.strongBorder }
            return framed ? ToolTheme.border : Color.clear
        }

        var body: some View {
            configuration.label
                .font(ToolTypography.buttonSmall)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(done ? ToolTheme.success : ToolTheme.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(background, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .scaleEffect(!reduceMotion && configuration.isPressed ? ToolMotion.Scale.pressed : 1)
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
                .scaleEffect(configuration.isPressed ? ToolMotion.Scale.pressed : 1)
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
            HStack(spacing: 7) {
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
        HStack(spacing: 7) {
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
        HStack(spacing: 8) {
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
        .buttonStyle(IndexSmallButtonStyle(framed: framed))
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

