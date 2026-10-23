import AppKit
import SwiftUI
import XToolsDesign

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
    @Environment(\.toolPageEntryGeneration) private var entryGeneration

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
            .onChange(of: entryGeneration) { generation in
                guard generation == 0 else { return }
                dismissalBox.remove()
                triggerFocus = nil
                closeMenu(restoringTriggerFocus: false)
            }
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
            HStack(spacing: ToolMetrics.Spacing.xs) {
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
                        .toolTransition(ToolMotion.Transition.labelCountSwap, reduceMotion: reduceMotion)
                }

                Image(systemName: "chevron.down")
                    .font(ToolTypography.icon(ToolMetrics.IconSize.micro, .semibold))
                    .foregroundStyle(ToolTheme.textSecondary)
                    .accessibilityHidden(true)
            }
            .font(ToolTypography.buttonSmall)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, ToolMetrics.Spacing.sm)
            .frame(height: Self.triggerHeight)
            .toolAnimation(ToolMotion.Preset.settle, value: enabledOptions.count)
        }
        .buttonStyle(IndexQuietChromeStyle(look: .framed, ink: .quiet, isEngaged: isOpen))
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
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xxs) {
            ForEach(options.indices, id: \.self) { index in
                if dividersBefore.contains(options[index].id) {
                    Rectangle()
                        .fill(ToolTheme.strongBorder)
                        .frame(height: ToolMetrics.Spacing.hairline)
                        .padding(.vertical, ToolMetrics.Spacing.xs)
                        .accessibilityHidden(true)
                }
                optionRow(index)
            }

            keyboardShortcutSurrogate
        }
        .padding(ToolMetrics.Spacing.xs)
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
        // whole menu (hit-test transparent, clicks pass through). The
        // hover-enter assert stays as a belt-and-suspenders fallback.
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
            guard entryGeneration > 0 else { return }
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
            HStack(spacing: ToolMetrics.Spacing.sm) {
                // The checkmark slot stays reserved while off so the labels of
                // all three rows align on one column.
                Image(systemName: "checkmark")
                    .font(ToolTypography.icon(ToolMetrics.IconSize.small, .semibold))
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
            .padding(.horizontal, ToolMetrics.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(IndexQuietChromeStyle(
            isKeyboardHighlighted: highlightedRow == index,
            cornerRadius: ToolMetrics.CornerRadius.nestedControl
        ))
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
            .keyboardShortcut(entryGeneration > 0 ? .cancelAction : nil)

            Button("下一个处理选项") {
                moveRowFocus(+1)
            }
            .keyboardShortcut(entryGeneration > 0 ? KeyboardShortcut(.downArrow, modifiers: []) : nil)

            Button("上一个处理选项") {
                moveRowFocus(-1)
            }
            .keyboardShortcut(entryGeneration > 0 ? KeyboardShortcut(.upArrow, modifiers: []) : nil)

            Button("切换当前处理选项") {
                toggleHighlightedRow()
            }
            .keyboardShortcut(entryGeneration > 0 ? KeyboardShortcut(.space, modifiers: []) : nil)
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
        guard entryGeneration > 0 else { return }
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
//
// 触发器与菜单行的 hover/press 样式已并入共享安静钮家族
// （design-foundation C1）：
// - 触发器：`IndexQuietChromeStyle(look: .framed, ink: .quiet, isEngaged:)`
//   ——静止 utility 底 + hairline，hover/press 共享安静底色，菜单打开时
//   切到 selectionFill + accentBorder（与 IndexOptionSwitch 的 on 态同语言）。
// - 菜单行：`IndexQuietChromeStyle(isKeyboardHighlighted:, cornerRadius:
//   nestedControl)` ——整行命中，hover/press 共享安静底色，键盘高亮是
//   palette 式软选中填充；启用态由 accent 勾选承担而非选中色块。

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
