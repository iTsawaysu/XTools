import AppKit
import SwiftUI

/// Joined `− value +` quantity stepper (prototype v3 parameter rows).
///
/// A bounded numeric param with single-step buttons: value reads in mono at
/// the center, decrements/increments clamp into `range`, and every step
/// reports through the same `value` binding so retained-preference changes
/// stay observable via `onChange`. Native `Stepper` and `IndexNumberInput`
/// typing stay out of the way — this control is pointer/AX step-only.
struct IndexStepperInput: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var decrementHelp = "减少"
    var incrementHelp = "增加"

    var body: some View {
        HStack(spacing: 0) {
            stepButton(
                symbol: "minus",
                help: decrementHelp,
                isDisabled: value <= range.lowerBound
            ) { step(-1) }

            Text("\(value)")
                .font(ToolTypography.codeBody)
                .monospacedDigit()
                .foregroundStyle(ToolTheme.textPrimary)
                .frame(width: 28)
                .accessibilityValue(Text("\(value)"))

            stepButton(
                symbol: "plus",
                help: incrementHelp,
                isDisabled: value >= range.upperBound
            ) { step(1) }
        }
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func stepButton(
        symbol: String,
        help: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        StepButton(symbol: symbol, help: help, isDisabled: isDisabled, action: action)
    }

    private func step(_ direction: Int) {
        let next = min(max(value + direction, range.lowerBound), range.upperBound)
        guard next != value else { return }
        value = next
    }

    private struct StepButton: View {
        let symbol: String
        let help: String
        let isDisabled: Bool
        let action: () -> Void

        @State private var isHovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var background: Color {
            if isDisabled { return Color.clear }
            if isHovering { return ToolTheme.hoverFill }
            return Color.clear
        }

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(ToolTypography.label)
                    .foregroundStyle(isDisabled ? ToolTheme.textTertiary : ToolTheme.textSecondary)
                    .frame(width: 24, height: 26)
                    .background(background, in: Rectangle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(IndexBareButtonStyle())
            .disabled(isDisabled)
            .help(help)
            .accessibilityLabel(help)
            .onHover { hovering in
                guard !isDisabled else { return }
                isHovering = hovering
            }
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: isHovering)
        }
    }
}
