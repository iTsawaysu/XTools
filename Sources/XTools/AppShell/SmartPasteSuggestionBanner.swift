import SwiftUI

/// Non-displacing smart-paste suggestion. Floats over the top of the workspace
/// instead of participating in page layout, so appearing and disappearing never
/// moves the tool page, its scroll ownership, or its controls.
struct SmartPasteSuggestionBanner: View {
    let suggestion: SmartPasteMonitor.Suggestion
    let onOpen: () -> Void
    let onDismiss: () -> Void

    /// Transient by design: the hint is a shortcut, never the only way to reach
    /// the tool (the sidebar and command palette stay the source of truth).
    private static let autoDismissDelay: TimeInterval = 12

    /// ToastCenter 同构的自动消失簿记：悬停进入时把剩余时长折算留存并停表，
    /// 移出后续走剩余时长（≤0 立即消失），保证横幅永远不会从指针下抽走。
    /// 建议变化由 RootView 的 .id(suggestion) 重建整个视图，onAppear 全量重置。
    @State private var dismissalTask: Task<Void, Never>?
    @State private var dismissalStartedAt: Date?
    @State private var dismissalRemaining: TimeInterval?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.system(size: ToolMetrics.IconSize.medium, weight: .medium))
                .foregroundStyle(ToolTheme.accent)
                .accessibilityHidden(true)

            Text(suggestion.message)
                .font(ToolTypography.bodyPlain)
                .foregroundStyle(ToolTheme.textPrimary)
                .lineLimit(1)

            Button(action: onOpen) {
                Text("打开 \(suggestion.toolTitle)")
            }
            .buttonStyle(IndexSmallButtonStyle())
            .accessibilityHint("切换到该工具")

            IndexIconButton(
                systemImage: "xmark",
                help: "忽略这个建议",
                action: onDismiss
            )
        }
        .padding(.leading, ToolMetrics.Spacing.md)
        .padding(.trailing, ToolMetrics.Spacing.sm)
        .padding(.vertical, ToolMetrics.Spacing.sm)
        .toolSurface(
            .floating,
            fallback: ToolTheme.popoverBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.modal, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.modal, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
        .toolShadow(ToolTheme.Shadow.floating)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(suggestion.message)，可以打开\(suggestion.toolTitle)")
        .onAppear {
            scheduleDismissal(after: Self.autoDismissDelay)
        }
        .onDisappear {
            dismissalTask?.cancel()
        }
        .onHover { hovering in
            if hovering {
                pauseDismissal()
            } else {
                resumeDismissal()
            }
        }
    }

    private func scheduleDismissal(after duration: TimeInterval) {
        dismissalTask?.cancel()
        dismissalRemaining = duration
        dismissalStartedAt = Date()
        dismissalTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    private func pauseDismissal() {
        guard let startedAt = dismissalStartedAt, let remaining = dismissalRemaining else {
            return
        }
        dismissalRemaining = max(0, remaining - Date().timeIntervalSince(startedAt))
        dismissalTask?.cancel()
        dismissalTask = nil
        dismissalStartedAt = nil
    }

    private func resumeDismissal() {
        // 只有暂停过才恢复（dismissalTask 非 nil 说明计时还在跑）。
        guard dismissalTask == nil, let remaining = dismissalRemaining else {
            return
        }
        guard remaining > 0 else {
            onDismiss()
            return
        }
        scheduleDismissal(after: remaining)
    }
}
