import AppKit
import SwiftUI

// MARK: - IndexOptionsMenu

/// One toolbar option inside `IndexOptionsMenu`. The binding stays with the
/// page's workspace model, so mutual exclusion (转义/去转义) and persistence
/// keep living at the call site.
struct IndexOptionsMenuOption {
    let id: String
    let title: String
    let help: String
    let isOn: Binding<Bool>
}

/// Toolbar-secondary options disclosure (prototype r2.2): a framed
/// 「处理选项 ▾」 trigger whose accent count digit only joins the row while
/// options are enabled, opening a compact single-line checkmark menu anchored
/// below its leading edge. The trigger rests on the workbench small-button
/// look (utility fill inside a hairline); hover, press, and the open state
/// shift to the shared quiet fills, and the accent color only marks the count
/// and the checkmarks so the secondary options never compete with the
/// workbench's primary action.
///
/// Rows toggle in place (the menu stays open for continuous selection);
/// 转义/去转义-style mutual exclusion stays at the call site via the bindings
/// it passes. Keyboard: the trigger opens natively, then Down/Up move a
/// visible highlight ring, Space toggles the highlighted row, and Escape
/// closes and hands focus back to the trigger — modelled on the command
/// palette's selection-index keyboard architecture, because programmatic
/// focus cannot be relied on for plain buttons. Dismissal paths: clicking
/// outside the menu (a window-local mouse monitor while open), Escape, and
/// re-clicking the trigger.
struct IndexOptionsMenu: View {
    let menuTitle: String
    var triggerTitle = "选项"
    let options: [IndexOptionsMenuOption]
    /// Option ids that render a hairline group divider above their row.
    var dividersBefore: Set<String> = []

    private enum TriggerFocusField {
        case trigger
    }

    @State private var isOpen = false
    @State private var highlightedRow: Int?
    @State private var dismissalBox = IndexOptionsMenuDismissalBox()
    @FocusState private var triggerFocus: TriggerFocusField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    fileprivate static let triggerHeight: CGFloat = 24

    var body: some View {
        trigger
            // Anchored to the trigger's leading edge: the count digit grows or
            // shrinks the trigger's trailing side, so a trailing anchor would
            // slide the open menu sideways on every toggle. The leading edge
            // is stable, which pins the panel in place.
            .overlay(alignment: .topLeading) {
                if isOpen {
                    menuPanel
                        .offset(y: Self.triggerHeight + 5)
                        .toolTransition(ToolMotion.Transition.anchoredDropdown, reduceMotion: reduceMotion)
                }
            }
            .toolAnimation(ToolMotion.Preset.settle, value: isOpen)
    }

    private var enabledOptions: [String] {
        options.filter { $0.isOn.wrappedValue }.map { $0.title }
    }

    private var enabledSummary: String {
        if enabledOptions.isEmpty {
            return "未启用任何处理选项"
        }
        return "已启用：\(enabledOptions.joined(separator: "、"))"
    }

    // MARK: Trigger

    private var trigger: some View {
        Button(action: toggleMenu) {
            HStack(spacing: 4) {
                Text(triggerTitle)

                // The digit only joins the row while options are enabled, so
                // the resting trigger keeps its label snug against the
                // chevron; monospacedDigit keeps 1↔2 from shifting. Toggling
                // an option eases the digit and the chevron instead of
                // popping them between frames.
                if !enabledOptions.isEmpty {
                    Text("\(enabledOptions.count)")
                        .font(ToolTypography.buttonSmall.monospacedDigit())
                        .foregroundStyle(ToolTheme.accent)
                        .transition(.opacity.combined(with: .offset(x: -2)))
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: ToolMetrics.IconSize.micro, weight: .semibold))
                    .foregroundStyle(ToolTheme.textSecondary)
                    .accessibilityHidden(true)
            }
            .toolAnimation(ToolMotion.Preset.settle, value: enabledOptions.count)
        }
        .buttonStyle(IndexOptionsMenuTriggerStyle(isOpen: isOpen))
        .focused($triggerFocus, equals: .trigger)
        .indexFocusRing(active: triggerFocus == .trigger, cornerRadius: ToolMetrics.CornerRadius.control)
        .overlay {
            IndexMenuArrowCursorLayer()
        }
        .help(enabledSummary)
        .accessibilityLabel(menuTitle)
        .accessibilityValue(enabledSummary)
    }

    // MARK: Menu panel

    private var menuPanel: some View {
        // No in-panel heading: the trigger carries the full 「处理选项」 name,
        // so the menu is just the option rows (prototype r2.2 compactness).
        VStack(alignment: .leading, spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                if dividersBefore.contains(options[index].id) {
                    Rectangle()
                        .fill(ToolTheme.strongBorder)
                        .frame(height: 0.5)
                        .padding(.vertical, 3)
                        .accessibilityHidden(true)
                }
                optionRow(index)
            }

            keyboardShortcutSurrogate
        }
        .padding(4)
        .frame(minWidth: 112, alignment: .leading)
        .background(
            ToolTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 1)
        }
        .toolShadow(ToolTheme.Shadow.floating)
        // Static row text installs an I-beam cursor rect that flashes before
        // hover-driven cursor fixes can react, so the source is overridden: a
        // transparent AppKit layer registers an arrow cursor rect over the
        // whole menu (hit-test transparent, clicks pass through). The hover
        // re-assert stays as a belt-and-suspenders fallback.
        .overlay {
            IndexMenuArrowCursorLayer()
        }
        .onHover { isHovering in
            if isHovering {
                NSCursor.arrow.set()
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { dismissalBox.panelFrame = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { dismissalBox.panelFrame = $0 }
            }
        }
        .onAppear {
            dismissalBox.dismiss = {
                isOpen = false
                highlightedRow = nil
                dismissalBox.lastOutsideDismissal = Date()
            }
            dismissalBox.install()
        }
        .onDisappear {
            dismissalBox.remove()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(menuTitle)
    }

    private func optionRow(_ index: Int) -> some View {
        let option = options[index]
        return Button {
            option.isOn.wrappedValue.toggle()
            highlightedRow = index
        } label: {
            HStack(spacing: 8) {
                // The checkmark slot stays reserved while off so the labels of
                // all three rows align on one column.
                Image(systemName: "checkmark")
                    .font(.system(size: ToolMetrics.IconSize.small, weight: .semibold))
                    .foregroundStyle(ToolTheme.accent)
                    .frame(width: 14)
                    .opacity(option.isOn.wrappedValue ? 1 : 0)
                    .toolAnimation(ToolMotion.Preset.controlFeedback, value: option.isOn.wrappedValue)

                Text(option.title)
                    .font(ToolTypography.compactBody)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(IndexOptionsMenuRowStyle(isHighlighted: highlightedRow == index))
        // Descriptions stay available to VoiceOver; the visual tooltip inside
        // the open menu reads as noise.
        .accessibilityHint(option.help)
        .accessibilityValue(option.isOn.wrappedValue ? "已开启" : "已关闭")
        .accessibilityAddTraits(option.isOn.wrappedValue ? .isSelected : [])
    }

    /// Hidden shortcut surrogates scoped to the open menu, mirroring the
    /// command palette's keyboard architecture: Escape closes and returns
    /// focus to the trigger, arrows move the highlight ring, Space toggles the
    /// highlighted row. They exist only while the menu is open, so nothing is
    /// intercepted otherwise.
    private var keyboardShortcutSurrogate: some View {
        Group {
            Button("关闭处理选项菜单") {
                closeMenu(restoringTriggerFocus: true)
            }
            .keyboardShortcut(.cancelAction)

            Button("下一个处理选项") {
                moveRowFocus(+1)
            }
            .keyboardShortcut(.downArrow, modifiers: [])

            Button("上一个处理选项") {
                moveRowFocus(-1)
            }
            .keyboardShortcut(.upArrow, modifiers: [])

            Button("切换当前处理选项") {
                toggleHighlightedRow()
            }
            .keyboardShortcut(.space, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: State transitions

    private func toggleMenu() {
        if isOpen {
            closeMenu(restoringTriggerFocus: false)
            return
        }
        // A press on the trigger reaches this action only after the mouse
        // monitor has already dismissed the open menu (mousedown precedes the
        // action); the grace period keeps that same press from reopening.
        if let lastOutsideDismissal = dismissalBox.lastOutsideDismissal,
           Date().timeIntervalSince(lastOutsideDismissal) < 0.3 {
            return
        }
        openMenu()
    }

    private func openMenu() {
        isOpen = true
        highlightedRow = 0
        // Hand the keyboard to the menu: the hidden Space surrogate owns
        // toggling while open, so the trigger must not re-activate on Space.
        triggerFocus = nil
    }

    private func closeMenu(restoringTriggerFocus: Bool) {
        isOpen = false
        highlightedRow = nil
        if restoringTriggerFocus {
            triggerFocus = .trigger
        }
    }

    private func moveRowFocus(_ delta: Int) {
        guard !options.isEmpty else { return }
        let current = highlightedRow ?? 0
        highlightedRow = min(max(current + delta, 0), options.count - 1)
    }

    private func toggleHighlightedRow() {
        guard let index = highlightedRow, options.indices.contains(index) else { return }
        options[index].isOn.wrappedValue.toggle()
    }
}

/// Outside-click dismissal shared by the menu lifetime. The monitor and the
/// window-resign observer live in one box so `onDisappear` always tears down
/// what `onAppear` installed; the panel frame is kept current by the menu's
/// background geometry reader so the hit test survives relayouts.
@MainActor
private final class IndexOptionsMenuDismissalBox {
    var panelFrame: CGRect = .zero
    var lastOutsideDismissal: Date?
    var dismiss: (() -> Void)?

    private var mouseMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    func install() {
        guard mouseMonitor == nil else { return }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handleMouse(event: event)
            return event
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss?()
            }
        }
    }

    func remove() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    private func handleMouse(event: NSEvent) {
        guard let dismiss else { return }
        // The event reports window coordinates (bottom-left origin); the panel
        // frame was captured in SwiftUI global space (top-left origin), so flip
        // it around the content height before the hit test.
        guard let window = event.window,
              let contentView = window.contentView else {
            return
        }
        let contentHeight = contentView.bounds.height
        let panelRect = CGRect(
            x: panelFrame.minX,
            y: contentHeight - panelFrame.maxY,
            width: panelFrame.width,
            height: panelFrame.height
        )
        // Clicks inside the menu keep it open for continuous selection; the
        // trigger click also passes through so its action toggle-closes.
        if panelRect.contains(event.locationInWindow) { return }
        dismiss()
    }
}

// MARK: - Styles

/// Toolbar-family trigger treatment: it rests on the framed small-button look
/// the workbench actions use (`IndexSmallButtonStyle(framed:)` — utility fill
/// inside a hairline) so the disclosure sits in the toolbar's control family.
/// Hover and press use the shared quiet fills; while the menu is open the
/// trigger switches to the app's engaged-option tint (`selectionFill` inside
/// `accentBorder` — the same language `IndexOptionSwitch` uses for on-state),
/// staying warm and light instead of the muddy neutral press fill.
private struct IndexOptionsMenuTriggerStyle: ButtonStyle {
    let isOpen: Bool

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, isOpen: isOpen)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let isOpen: Bool

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var hovering: Bool { isHovering && isEnabled }

        private var background: Color {
            if isOpen { return ToolTheme.selectionFill }
            if hovering || configuration.isPressed { return ToolTheme.activeFill }
            return ToolTheme.utilityBackground
        }

        private var border: Color {
            if isOpen { return ToolTheme.accentBorder }
            if hovering || configuration.isPressed { return ToolTheme.strongBorder }
            return ToolTheme.border
        }

        private var foreground: Color {
            if !isEnabled { return ToolTheme.textTertiary }
            if isOpen || configuration.isPressed { return ToolTheme.textPrimary }
            return hovering ? ToolTheme.textPrimary : ToolTheme.textSecondary
        }

        var body: some View {
            configuration.label
                .font(ToolTypography.buttonSmall)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 9)
                .frame(height: IndexOptionsMenu.triggerHeight)
                .background(
                    background,
                    in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                )
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

/// Menu row treatment: the whole row is the hit target, hover and press use
/// the shared quiet fills, and the enabled state is carried by the accent
/// checkmark instead of a selection block. Keyboard highlight renders as the
/// palette-style soft selection fill — a hard focus ring reads like an error
/// outline on a transient menu.
private struct IndexOptionsMenuRowStyle: ButtonStyle {
    let isHighlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, isHighlighted: isHighlighted)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let isHighlighted: Bool

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled

        private var hovering: Bool { isHovering && isEnabled }

        private var background: Color {
            if configuration.isPressed { return ToolTheme.activeFill }
            if isHighlighted { return ToolTheme.selectionFill }
            return hovering ? ToolTheme.hoverFill : Color.clear
        }

        var body: some View {
            configuration.label
                .background(
                    background,
                    in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                )
                .onHover { isHovering = $0 }
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: hovering)
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: configuration.isPressed)
        }
    }
}

// MARK: - Cursor

/// Transparent, hit-test-transparent AppKit layer that registers an arrow
/// cursor rect over its frame. SwiftUI static text installs its own I-beam
/// cursor rect, which flashes for a frame or two before any hover-driven
/// cursor fix can react; registering the arrow rect up front removes the
/// source instead of racing it (the shared I-beam helper's inverse problem).
private struct IndexMenuArrowCursorLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ArrowCursorRectView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ArrowCursorRectView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .arrow)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
