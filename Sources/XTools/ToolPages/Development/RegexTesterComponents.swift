import SwiftUI
import XToolsCore
import XToolsDesign

// MARK: - Match Details

struct RegexMatchList: View {
    let matches: [RegexMatcher.Match]
    var valueMotion: IndexValueMotionPolicy = .immediate
    /// 当前在正文中定位的匹配（0 起）；再次点击同一行取消定位。
    var selectedIndex: Int? = nil
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        LazyVStack(spacing: ToolMetrics.Spacing.sm) {
            ForEach(Array(matches.enumerated()), id: \.offset) { index, match in
                RegexMatchRow(
                    ordinal: index + 1,
                    match: match,
                    valueMotion: valueMotion,
                    isSelected: selectedIndex == index,
                    onSelect: onSelect
                )
            }
        }
    }
}

/// 单匹配紧凑行：序号 + 值 + 范围同行，捕获组缩进跟随并按组序分色
/// （与正文高亮同一调色板）；点击行在正文中定位该匹配。
private struct RegexMatchRow: View {
    let ordinal: Int
    let match: RegexMatcher.Match
    let valueMotion: IndexValueMotionPolicy
    var isSelected = false
    var onSelect: ((Int) -> Void)? = nil

    @State private var isHovered = false

    private var showsInteraction: Bool { onSelect != nil }

    var body: some View {
        Button {
            onSelect?(ordinal - 1)
        } label: {
            content
                .padding(.horizontal, ToolMetrics.Spacing.compact)
                .padding(.vertical, ToolMetrics.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    rowFill,
                    in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                        .strokeBorder(isSelected ? ToolTheme.accent.opacity(0.55) : .clear, lineWidth: 1)
                }
        }
        .buttonStyle(IndexBareButtonStyle())
        .onHover { hovered in
            guard showsInteraction else { return }
            isHovered = hovered
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("匹配 \(ordinal)，范围 \(match.displayRange.start) 到 \(match.displayRange.end)") + Text(match.displayRange.unitSuffix))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: ToolMetrics.Spacing.sm) {
                Text("#\(ordinal)")
                    .font(ToolTypography.monoLabel)
                    .foregroundStyle(isSelected ? ToolTheme.accentHover : ToolTheme.textSecondary)

                RegexMatchValue(match.value, valueMotion: valueMotion)

                Text(match.displayRange.label)
                    .font(ToolTypography.monoCaption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .textSelection(.enabled)
            }

            if !match.captures.isEmpty {
                RegexCaptureList(title: "捕获", captures: match.captures, tint: IndexTextAreaHighlightPalette.captureForeground)
            }

            if !match.groups.isEmpty {
                RegexCaptureList(title: "命名组", captures: match.groups, tint: IndexTextAreaHighlightPalette.captureForeground)
            }
        }
    }

    private var rowFill: Color {
        if isSelected { return ToolTheme.selectionFill }
        if isHovered && showsInteraction { return ToolTheme.hoverFill }
        return .clear
    }
}

private struct RegexMatchValue: View {
    let value: String
    let valueMotion: IndexValueMotionPolicy
    var color: Color? = nil

    init(_ value: String, valueMotion: IndexValueMotionPolicy = .immediate, color: Color? = nil) {
        self.value = value
        self.valueMotion = valueMotion
        self.color = color
    }

    @ViewBuilder
    var body: some View {
        switch valueMotion {
        case .textSwap:
            valueText.toolMotionTextSwap(id: value)
        case .immediate:
            valueText
        }
    }

    private var valueText: some View {
        Text(indexWrappingAttributedText(value, lineBreakMode: .byCharWrapping))
            .font(ToolTypography.monoLabel)
            .foregroundStyle(color ?? ToolTheme.textPrimary)
            .textSelection(.enabled)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RegexCaptureList: View {
    let title: String
    let captures: [RegexMatcher.Capture]
    var tint: (Int) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.snug) {
            Text(title)
                .font(ToolTypography.micro)
                .foregroundStyle(ToolTheme.textTertiary)
                .textCase(.uppercase)

            ForEach(Array(captures.enumerated()), id: \.offset) { index, capture in
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: ToolMetrics.Spacing.sm) {
                        Text(capture.name)
                            .font(ToolTypography.monoLabel)
                            .foregroundStyle(tint(index))
                            .lineLimit(1)

                        Text(capture.displayRange.label)
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textSecondary)

                        Spacer(minLength: 0)
                    }

                    RegexMatchValue(capture.value, color: tint(index))
                }
                .padding(.leading, ToolMetrics.Spacing.compact)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(tint(index).opacity(0.45))
                        .frame(width: ToolMetrics.Control.separator)
                }
            }
        }
    }
}
