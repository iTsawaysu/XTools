import SwiftUI
import XToolsCore

// MARK: - Result Status

struct RegexResultStatus: View {
    let text: String
    var tone: IndexBadgeTone = .neutral

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(tone.tint)
                .frame(width: 6, height: 6)

            Text(text)
                .font(ToolTypography.compactBody)
                .foregroundStyle(tone.tint)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - Compact Summary

/// 静态统计行：不再占据独立盒面，与状态行同行呈现；零值统计由页面侧过滤。
struct RegexResultSummary: View {
    let stats: [(String, String)]

    private let compactColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                    metric(label: stat.0, value: stat.1)

                    if index < stats.count - 1 {
                        Text("·")
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textTertiary)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 8) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    metric(label: stat.0, value: stat.1)
                }
            }
        }
        // 不设 maxWidth 贪心帧：让外层 HStack 的 Spacer 把统计推到与范围列同一右缘。
    }

    private func metric(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(ToolTypography.monoLabel)
                .foregroundStyle(ToolTheme.accentHover)

            Text(label)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)：\(value)")
    }
}

// MARK: - Match Details

struct RegexMatchList: View {
    let matches: [RegexMatcher.Match]
    var valueMotion: IndexValueMotionPolicy = .immediate
    /// 当前在正文中定位的匹配（0 起）；再次点击同一行取消定位。
    var selectedIndex: Int? = nil
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        LazyVStack(spacing: 8) {
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
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
        .accessibilityLabel("匹配 \(ordinal)，范围 \(match.index) 到 \(match.end)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("#\(ordinal)")
                    .font(ToolTypography.monoLabel)
                    .foregroundStyle(isSelected ? ToolTheme.accentHover : ToolTheme.textSecondary)

                RegexMatchValue(match.value, valueMotion: valueMotion)

                Text("[\(match.index), \(match.end))")
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
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(ToolTypography.micro)
                .foregroundStyle(ToolTheme.textTertiary)
                .textCase(.uppercase)

            ForEach(Array(captures.enumerated()), id: \.offset) { index, capture in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(capture.name)
                            .font(ToolTypography.monoLabel)
                            .foregroundStyle(tint(index))
                            .lineLimit(1)

                        Text("[\(capture.start), \(capture.end))")
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textSecondary)

                        Spacer(minLength: 0)
                    }

                    RegexMatchValue(capture.value, color: tint(index))
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(tint(index).opacity(0.45))
                        .frame(width: 2)
                }
            }
        }
    }
}
