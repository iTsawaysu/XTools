import AppKit
import SwiftUI
import XToolsDesign

// MARK: - App-level toast center

/// A transient message shown by the window-level toast, mirroring the toast in
/// the design reference (a checkmark or warning glyph plus a short message).
struct ToolToastMessage: Identifiable, Equatable {
    typealias Tone = ToolFeedbackTone

    let id = UUID()
    let text: String
    var tone: Tone = .success

    var accessibilityLabel: String {
        "\(tone.accessibilityPrefix)：\(text)"
    }
}

@MainActor
protocol ToolAccessibilityAnnouncing {
    func announceStatus(_ text: String)
}

@MainActor
struct ToolAccessibilityAnnouncer: ToolAccessibilityAnnouncing {
    func announceStatus(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }
}

/// Window-scoped toast queue. Injected into the environment at the shell so any
/// tool can surface copy/paste/clear feedback through one consistent surface.
///
/// Toast/HUD 双通道（阶段③ C4，design.md §5 / PRD 决策 10）：`show` 时刻做
/// 呈现判定——宿主窗口 isKeyWindow 且应用激活 → 现状 Toast 队列；窗口非 key
/// 或应用未激活 → 同 payload 降级右下 HUD（`ToolHUDHost`，单条、无边框、
/// 固定 2s 自动隐藏、无动作钮）。判定只发生在入队时刻，通道不随窗口状态
/// 迁移；无障碍播报两条通道同文案（不新建文案体系）。
@MainActor
final class ToolToastCenter: ObservableObject {
    static let maxVisibleMessages = 4
    /// HUD 降级通道的固定自动隐藏时长（design.md §5）。
    static let hudAutoHideDuration: Duration = .seconds(2)

    @Published private(set) var messages: [ToolToastMessage] = []
    /// HUD 降级通道当前 payload（同 `ToolToastMessage` 结构，单条顶替）。
    @Published private(set) var hudMessage: ToolToastMessage?

    private let announcer: any ToolAccessibilityAnnouncing
    /// 呈现判定注入点（测试用）；缺省按宿主窗口 key 态 + 应用激活态判定。
    private let isHUDPresentationOverride: (@MainActor () -> Bool)?
    /// 宿主窗口（ToolToastWindowBinder 注入）；未绑定时不参与判定。
    fileprivate weak var window: NSWindow?
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]
    private var hudDismissTask: Task<Void, Never>?
    private var remainingDurations: [UUID: TimeInterval] = [:]
    private var startedAt: [UUID: Date] = [:]
    private var pausedIDs: Set<UUID> = []

    init(
        announcer: any ToolAccessibilityAnnouncing = ToolAccessibilityAnnouncer(),
        isHUDPresentation: (@MainActor () -> Bool)? = nil
    ) {
        self.announcer = announcer
        self.isHUDPresentationOverride = isHUDPresentation
    }

    func show(_ text: String, tone: ToolToastMessage.Tone = .success) {
        let message = ToolToastMessage(text: text, tone: tone)
        if self.presentsAsHUD() {
            presentHUD(message)
        } else {
            presentToast(message)
        }
        announcer.announceStatus(message.accessibilityLabel)
    }

    /// 呈现判定（design.md §5）：宿主窗口非 key 或应用未激活（macOS 侧以
    /// `NSApp.isActive` 表达 activationState == .active）→ HUD 降级。
    /// 无窗口绑定时按应用激活态兜底；测试可经 init 注入固定判定。
    private func presentsAsHUD() -> Bool {
        if let isHUDPresentationOverride {
            return isHUDPresentationOverride()
        }
        if let window {
            return !window.isKeyWindow || !NSApp.isActive
        }
        return !NSApp.isActive
    }

    /// 现状 Toast 队列（前台 key 窗口通道，语义不变）。
    private func presentToast(_ message: ToolToastMessage) {
        var removedIDs: [UUID] = []

        applyToolMotion {
            messages.append(message)
            if messages.count > Self.maxVisibleMessages {
                let overflow = messages.count - Self.maxVisibleMessages
                removedIDs = messages.prefix(overflow).map(\.id)
                messages.removeFirst(overflow)
            }
        }

        removedIDs.forEach(cleanupMessage)
        scheduleDismissal(for: message.id, after: message.tone.defaultToastDuration)
    }

    /// HUD 降级通道：单条槽位，新 payload 顶替旧条并重置自动隐藏；
    /// 无 hover/动作交互（动作仅 Toast 支持）。
    private func presentHUD(_ message: ToolToastMessage) {
        applyToolMotion { hudMessage = message }
        hudDismissTask?.cancel()
        hudDismissTask = Task { @MainActor in
            try? await Task.sleep(for: Self.hudAutoHideDuration)
            guard !Task.isCancelled else { return }
            applyToolMotion { hudMessage = nil }
        }
    }

    func dismiss(_ id: UUID) {
        cleanupMessage(id)
        applyToolMotion {
            messages.removeAll { $0.id == id }
        }
    }

    func pauseDismissal(for id: UUID) {
        guard messages.contains(where: { $0.id == id }),
              !pausedIDs.contains(id) else {
            return
        }

        pausedIDs.insert(id)
        if let started = startedAt[id], let remaining = remainingDurations[id] {
            remainingDurations[id] = max(0, remaining - Date().timeIntervalSince(started))
        }
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        startedAt[id] = nil
    }

    func resumeDismissal(for id: UUID) {
        guard pausedIDs.remove(id) != nil,
              messages.contains(where: { $0.id == id }) else {
            return
        }

        let remaining = remainingDurations[id] ?? message(for: id)?.tone.defaultToastDuration ?? ToolFeedbackTone.info.defaultToastDuration
        guard remaining > 0 else {
            dismiss(id)
            return
        }

        scheduleDismissal(for: id, after: remaining)
    }

    private func scheduleDismissal(for id: UUID, after duration: TimeInterval) {
        dismissTasks[id]?.cancel()
        remainingDurations[id] = duration
        startedAt[id] = Date()
        dismissTasks[id] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            dismiss(id)
        }
    }

    private func cleanupMessage(_ id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        remainingDurations[id] = nil
        startedAt[id] = nil
        pausedIDs.remove(id)
    }

    private func message(for id: UUID) -> ToolToastMessage? {
        messages.first { $0.id == id }
    }
}

private struct ToolToastCenterKey: EnvironmentKey {
    static let defaultValue: ToolToastCenter? = nil
}

extension EnvironmentValues {
    var toolToastCenter: ToolToastCenter? {
        get { self[ToolToastCenterKey.self] }
        set { self[ToolToastCenterKey.self] = newValue }
    }
}

/// The window-level toast view, anchored bottom-trailing in a bounded stack.
struct ToolToastHost: View {
    @ObservedObject var center: ToolToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .allowsHitTesting(false)

            VStack(alignment: .trailing, spacing: ToolMetrics.Spacing.sm) {
                ForEach(center.messages) { message in
                    ToolToastCard(message: message, center: center)
                        .toolTransition(ToolMotion.Transition.toastPanel, reduceMotion: reduceMotion)
                }
            }
            .frame(maxWidth: 360, alignment: .bottomTrailing)
            .padding(.bottom, ToolMetrics.Spacing.lg)
            .padding(.trailing, ToolMetrics.Spacing.lg)
            .animation(ToolMotion.animation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion), value: center.messages)
        }
    }
}

private struct ToolToastCard: View {
    let message: ToolToastMessage
    @ObservedObject var center: ToolToastCenter
    @State private var isCloseHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: ToolMetrics.Spacing.compact) {
            Image(systemName: message.tone.systemImage)
                .font(ToolTypography.icon(ToolMetrics.IconSize.medium, .semibold))
                .foregroundStyle(message.tone.tint)
                .frame(width: 16, height: 16)
                .padding(.top, ToolMetrics.Spacing.hair)
                .accessibilityHidden(true)

            Text(message.text)
                .font(ToolTypography.label)
                .foregroundStyle(ToolTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(message.accessibilityLabel)

            Button {
                center.dismiss(message.id)
            } label: {
                Image(systemName: "xmark")
                    .font(ToolTypography.icon(ToolMetrics.IconSize.micro, .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .toolInteractionFeedback()
            .foregroundStyle(ToolTheme.textSecondary)
            .background(
                isCloseHovered ? ToolTheme.hoverFill : Color.clear,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
            .onHover { isCloseHovered = $0 }
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: isCloseHovered)
            .help("关闭提示")
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, ToolMetrics.Spacing.md)
        .padding(.vertical, ToolMetrics.Spacing.compact)
        .frame(width: 320, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.modal, style: .continuous)
                .fill(message.tone.softFill)
        }
        // Opaque surface — the transient system material flashes a bright
        // placeholder frame on appear/disappear (the "white block"), exactly
        // like the palette before it went opaque.
        .indexSurface(
            .modal,
            fill: ToolTheme.popoverBackground,
            border: .clear,
            borderWidth: 0
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.modal, style: .continuous)
                .strokeBorder(message.tone.borderTint, lineWidth: 0.5)
        }
        .toolShadow(ToolTheme.Shadow.floating)
        .onHover { hovering in
            if hovering {
                center.pauseDismissal(for: message.id)
            } else {
                center.resumeDismissal(for: message.id)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - HUD 降级通道（阶段③ C4，design.md §5）

/// 把宿主实际 `NSWindow` 交给 toast center（呈现判定的输入）。与
/// `WindowAppearanceOwner` / `FileInputPanelWindowBinder` 同一
/// `viewDidMoveToWindow` 绑定模式，挂 RootView background 层。
struct ToolToastWindowBinder: NSViewRepresentable {
    let center: ToolToastCenter

    func makeNSView(context: Context) -> NSView {
        BinderView(center: center)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? BinderView)?.center = center
    }

    @MainActor
    private final class BinderView: NSView {
        weak var center: ToolToastCenter?

        init(center: ToolToastCenter) {
            self.center = center
            super.init(frame: .zero)
            isHidden = true
            setContentHuggingPriority(.required, for: .horizontal)
            setContentHuggingPriority(.required, for: .vertical)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            center?.window = window
        }
    }
}

/// 窗口非 key / 应用未激活时的降级呈现（C4 双通道）：右下系统风浮层，
/// 只展示 title/tone、无边框、无动作钮（动作仅 Toast 支持）；自动隐藏
/// 由 center 的 2s 固定时长驱动。走阶段①组件：opaque `indexSurface(.modal)`
/// + `toolShadow(.floating)`，与 Toast 卡同宽（320）同节奏（toastPanel 过渡）。
struct ToolHUDHost: View {
    @ObservedObject var center: ToolToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .allowsHitTesting(false)

            if let message = center.hudMessage {
                ToolHUDCard(message: message)
                    .toolTransition(ToolMotion.Transition.toastPanel, reduceMotion: reduceMotion)
                    .padding(.bottom, ToolMetrics.Spacing.lg)
                    .padding(.trailing, ToolMetrics.Spacing.lg)
            }
        }
        .animation(
            ToolMotion.animation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion),
            value: center.hudMessage
        )
    }
}

private struct ToolHUDCard: View {
    let message: ToolToastMessage

    var body: some View {
        HStack(alignment: .top, spacing: ToolMetrics.Spacing.compact) {
            Image(systemName: message.tone.systemImage)
                .font(ToolTypography.icon(ToolMetrics.IconSize.medium, .semibold))
                .foregroundStyle(message.tone.tint)
                .frame(width: 16, height: 16)
                .padding(.top, ToolMetrics.Spacing.hair)
                .accessibilityHidden(true)

            Text(message.text)
                .font(ToolTypography.label)
                .foregroundStyle(ToolTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(message.accessibilityLabel)
        }
        .padding(.horizontal, ToolMetrics.Spacing.md)
        .padding(.vertical, ToolMetrics.Spacing.compact)
        .frame(width: 320, alignment: .leading)
        // Opaque surface，无边框（与 Toast 卡的唯一视觉差：无 tone 描边、
        // 无关闭钮）——transient 系统材质的亮框闪烁与 palette 同根。
        .indexSurface(
            .modal,
            fill: ToolTheme.popoverBackground,
            border: .clear,
            borderWidth: 0
        )
        .toolShadow(ToolTheme.Shadow.floating)
        .accessibilityElement(children: .contain)
    }
}
