import AppKit
import SwiftUI

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
@MainActor
final class ToolToastCenter: ObservableObject {
    static let maxVisibleMessages = 4

    @Published private(set) var messages: [ToolToastMessage] = []

    private let announcer: any ToolAccessibilityAnnouncing
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]
    private var remainingDurations: [UUID: TimeInterval] = [:]
    private var startedAt: [UUID: Date] = [:]
    private var pausedIDs: Set<UUID> = []

    init(announcer: any ToolAccessibilityAnnouncing = ToolAccessibilityAnnouncer()) {
        self.announcer = announcer
    }

    func show(_ text: String, tone: ToolToastMessage.Tone = .success) {
        let message = ToolToastMessage(text: text, tone: tone)
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
        scheduleDismissal(for: message.id, after: tone.defaultToastDuration)
        announcer.announceStatus(message.accessibilityLabel)
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

            VStack(alignment: .trailing, spacing: 8) {
                ForEach(center.messages) { message in
                    ToolToastCard(message: message, center: center)
                        .toolTransition(ToolMotion.Transition.toastPanel, reduceMotion: reduceMotion)
                }
            }
            .frame(maxWidth: 360, alignment: .bottomTrailing)
            .padding(.bottom, 18)
            .padding(.trailing, 18)
            .animation(ToolMotion.animation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion), value: center.messages)
        }
    }
}

private struct ToolToastCard: View {
    let message: ToolToastMessage
    @ObservedObject var center: ToolToastCenter
    @State private var isCloseHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: message.tone.systemImage)
                .font(.system(size: ToolMetrics.IconSize.medium, weight: .semibold))
                .foregroundStyle(message.tone.tint)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
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
                    .font(.system(size: ToolMetrics.IconSize.micro, weight: .bold))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 320, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.modal, style: .continuous)
                .fill(message.tone.softFill)
        }
        .toolSurface(
            .floating,
            fallback: ToolTheme.popoverBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.modal, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.modal, style: .continuous)
                .strokeBorder(message.tone.tint.opacity(0.34), lineWidth: 0.5)
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
