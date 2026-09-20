import AppKit
import SwiftUI
import XToolsCore

// MARK: - 顶栏诊断通栏横幅 (Top Banner)

struct IndexDiagnosticBanner: View {
    let diagnostic: FormatDiagnostic?
    let message: String
    var tone: ToolFeedbackTone = .error
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        diagnostic: FormatDiagnostic?,
        message: String,
        tone: ToolFeedbackTone = .error
    ) {
        self.diagnostic = diagnostic
        self.message = message
        self.tone = tone
    }

    private var hasSuggestion: Bool {
        guard let suggestion = diagnostic?.suggestion else { return false }
        return !suggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var fullCopyPayload: String {
        var lines: [String] = []
        let title = diagnostic?.formatName.isEmpty == false ? "\(diagnostic!.formatName) 格式化" : "提示"
        lines.append("【\(title)】\(tone.accessibilityPrefix): \(message)")
        if let line = diagnostic?.line {
            let col = diagnostic?.column != nil ? ", 列 \(diagnostic!.column!)" : ""
            lines.append("位置: 第 \(line) 行\(col)")
        }
        if let suggestion = diagnostic?.suggestion, !suggestion.isEmpty {
            lines.append("修复建议: \(suggestion)")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: tone.systemImage)
                    .font(.system(size: ToolMetrics.IconSize.medium, weight: .semibold))
                    .foregroundStyle(tone.tint)
                    .accessibilityHidden(true)

                if let line = diagnostic?.line {
                    HStack(spacing: 3) {
                        Text("行 \(line)")
                        if let column = diagnostic?.column {
                            Text(":\(column)")
                        }
                    }
                    .font(ToolTypography.monoLabel)
                    .foregroundStyle(tone.tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tone.tint.opacity(0.12), in: Capsule())
                }

                Text(message)
                    .font(ToolTypography.label)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .lineLimit(isExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    if hasSuggestion {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(isExpanded ? "收起建议" : "修复建议")
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: ToolMetrics.IconSize.micro, weight: .semibold))
                            }
                            .font(ToolTypography.caption)
                            .foregroundStyle(tone.tint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tone.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(isExpanded ? "收起建议" : "查看针对该问题的智能修复建议")
                    }

                    IndexCopyButton(
                        text: fullCopyPayload,
                        title: "复制",
                        showsIcon: false,
                        framed: true
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            if isExpanded, let suggestion = diagnostic?.suggestion {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: ToolMetrics.IconSize.small))
                        .foregroundStyle(ToolTheme.warning)
                        .padding(.top, 1)
                    Text(suggestion)
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textPrimary)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(9)
                .background(ToolTheme.warningSoft.opacity(0.65), in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 9)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.softFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(tone.tint.opacity(0.25)).frame(height: 0.5)
        }
    }
}
