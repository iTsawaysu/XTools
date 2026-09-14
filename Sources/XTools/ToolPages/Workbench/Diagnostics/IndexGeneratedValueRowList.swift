import AppKit
import SwiftUI

/// One generated value slot (prototype v3 result rows).
///
/// `id` is the slot identity (`slot-\(offset)`) and never derives from the
/// value, so regenerating keeps row order stable while values change.
struct IndexGeneratedValueRow: Identifiable {
    let id: String
    let value: String
    var copyHelp: String = "复制此项"
}

/// Flat generated-value row list (prototype v3 UUID results).
///
/// A bounded mono row list: per-row index, the value, and a hover-revealed
/// copy action; clicking anywhere else in the row copies the value. Bumping
/// `motionGeneration` remounts the rows so each one replays the staggered
/// pop-in (30ms per row for the first rows, matching the generated-list
/// motion cap) without changing slot identity. Reduce Motion skips both the
/// stagger and the pop.
struct IndexGeneratedValueRowList: View {
    let rows: [IndexGeneratedValueRow]
    var emptyText = IndexEmptyStateCopy.noResults
    var motionGeneration = 0
    /// Long values (tokens, passwords) wrap within the row instead of
    /// truncating mid-value; rows grow and keep their 44pt minimum.
    var wrapsValues = false

    /// Rows past this index join the stagger instantly (shared motion cap).
    private let staggerRowLimit = 8
    private let staggerStep: TimeInterval = 0.03

    var body: some View {
        Group {
            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(replayRows) { replayRow in
                            IndexGeneratedValueRowView(
                                row: replayRow.row,
                                index: replayRow.index,
                                wrapsValue: wrapsValues,
                                staggerDelay: staggerDelay(for: replayRow.index)
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Generation-scoped replay identity: slot semantics stay intact, the
    /// generation prefix only exists so regeneration remounts rows and
    /// replays the pop-in stagger.
    private var replayRows: [ReplayRow] {
        rows.enumerated().map { index, row in
            ReplayRow(id: "\(motionGeneration)-\(row.id)", row: row, index: index)
        }
    }

    private struct ReplayRow: Identifiable {
        let id: String
        let row: IndexGeneratedValueRow
        let index: Int
    }

    private var emptyState: some View {
        Text(emptyText)
            .font(ToolTypography.bodyPlain)
            .foregroundStyle(ToolTheme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
            .padding(.horizontal, 12)
    }

    private func staggerDelay(for index: Int) -> TimeInterval {
        Double(min(index, staggerRowLimit)) * staggerStep
    }
}

private struct IndexGeneratedValueRowView: View {
    let row: IndexGeneratedValueRow
    let index: Int
    var wrapsValue = false
    let staggerDelay: TimeInterval

    @State private var isHovering = false
    @State private var isRevealed = false
    @State private var feedback = IndexEphemeralActionFeedbackState()
    @Environment(\.toolToastCenter) private var toastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsActions: Bool {
        isHovering || feedback.isPresented
    }

    var body: some View {
        Button(action: copyValue) {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(ToolTypography.monoCaption)
                    .monospacedDigit()
                    .foregroundStyle(ToolTheme.textTertiary)
                    .frame(width: 18, alignment: .trailing)

                Text(row.value)
                    .font(ToolTypography.codeBody)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .lineLimit(wrapsValue ? nil : 1)
                    .truncationMode(wrapsValue ? .tail : .middle)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: wrapsValue)
                    .frame(maxWidth: .infinity, alignment: .leading)

                IndexCopyButton(text: row.value, title: row.copyHelp, iconOnly: true)
                    .opacity(showsActions ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(IndexBareButtonStyle())
        .background(isHovering ? ToolTheme.hoverFill : Color.clear)
        .onHover { isHovering = $0 }
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isHovering)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: 0.5)
        }
        .opacity(isRevealed ? 1 : 0)
        .scaleEffect(isRevealed ? 1 : 0.96, anchor: .top)
        .offset(y: isRevealed ? 0 : 2)
        .animation(
            ToolMotion.animation(
                ToolMotion.Curve.smoothOut(duration: ToolMotion.Duration.fast).delay(staggerDelay),
                reduceMotion: reduceMotion
            ),
            value: isRevealed
        )
        .accessibilityHint(row.copyHelp)
        .task(id: row.id) {
            replayAppearance()
        }
        .task(id: feedback.generation) {
            let generation = feedback.generation
            guard feedback.isPresented else { return }

            do {
                try await Task.sleep(for: IndexEphemeralActionFeedbackState.holdDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            feedback.finish(generation: generation)
        }
    }

    /// Rows mount hidden and pop in one frame later; the per-row animation
    /// delay above produces the stagger. Reduce Motion settles instantly.
    private func replayAppearance() {
        guard !reduceMotion else {
            withTransaction(ToolMotion.disabledTransaction) {
                isRevealed = true
            }
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled else { return }
            isRevealed = true
        }
    }

    private func copyValue() {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(row.value, forType: .string) else {
            toastCenter?.show("剪贴板写入失败。", tone: .error)
            return
        }
        toastCenter?.show(ToolFeedbackCopy.copied, tone: .success)
        feedback.trigger()
    }
}
