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

struct RegexResultSummary: View {
    let stats: [(String, String)]

    private let compactColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                    metric(label: stat.0, value: stat.1)

                    if index < stats.count - 1 {
                        Divider()
                            .frame(height: 16)
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
        .padding(.horizontal, 10)
        .padding(.vertical, ToolMetrics.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .indexSurface(.field, fill: ToolTheme.editorBackground, border: ToolTheme.border)
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

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(matches.enumerated()), id: \.offset) { index, match in
                RegexMatchCard(
                    ordinal: index + 1,
                    match: match,
                    valueMotion: valueMotion
                )
            }
        }
    }
}

private struct RegexMatchCard: View {
    let ordinal: Int
    let match: RegexMatcher.Match
    let valueMotion: IndexValueMotionPolicy

    var body: some View {
        IndexSurfaceRow(horizontalPadding: 12, verticalPadding: 11) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("匹配 #\(ordinal)")
                        .font(ToolTypography.bodyMedium)
                        .foregroundStyle(ToolTheme.accentHover)

                    Spacer(minLength: 8)

                    Text("范围 [\(match.index), \(match.end))")
                        .font(ToolTypography.monoLabel)
                        .foregroundStyle(ToolTheme.textSecondary)
                        .textSelection(.enabled)
                }

                RegexMatchValue(match.value, valueMotion: valueMotion)

                if !match.captures.isEmpty {
                    Divider()
                    RegexCaptureList(title: "捕获", captures: match.captures, tone: ToolTheme.textSecondary)
                }

                if !match.groups.isEmpty {
                    Divider()
                    RegexCaptureList(title: "命名组", captures: match.groups, tone: ToolTheme.success)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("匹配 \(ordinal)，范围 \(match.index) 到 \(match.end)")
    }
}

private struct RegexMatchValue: View {
    let value: String
    let valueMotion: IndexValueMotionPolicy

    init(_ value: String, valueMotion: IndexValueMotionPolicy = .immediate) {
        self.value = value
        self.valueMotion = valueMotion
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
            .foregroundStyle(ToolTheme.textPrimary)
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
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(ToolTypography.micro)
                .foregroundStyle(tone)
                .textCase(.uppercase)

            ForEach(Array(captures.enumerated()), id: \.offset) { _, capture in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(capture.name)
                            .font(ToolTypography.monoLabel)
                            .foregroundStyle(tone)
                            .lineLimit(1)

                        Text("[\(capture.start), \(capture.end))")
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textSecondary)

                        Spacer(minLength: 0)
                    }

                    RegexMatchValue(capture.value)
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(tone.opacity(0.45))
                        .frame(width: 2)
                }
            }
        }
    }
}
