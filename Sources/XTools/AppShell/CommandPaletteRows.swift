import SwiftUI

/// Raycast/Linear-style section header: left-aligned group label with the
/// section's row count, aligned to the row icon column.
struct CommandPaletteSectionTitle: View {
    let text: String
    let count: Int?

    init(_ text: String, count: Int? = nil) {
        self.text = text
        self.count = count
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(ToolTypography.groupHeader)
                .foregroundStyle(ToolTheme.textTertiary)
            if let count {
                Text(count.formatted())
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 3)
        .accessibilityElement(children: .combine)
    }
}

/// Raycast-style bottom hints: the palette's keyboard grammar at a glance.
/// Bottom hints: the palette's keyboard grammar at a glance. The return
/// label follows the ACTIVE row's real action — tools jump, commands run —
/// so the hint never describes a behavior the current selection doesn't have.
struct CommandPaletteHintsBar: View {
    /// ↩ 对当前选中行的实际语义（工具＝跳转，命令＝执行）。
    let returnLabel: String

    var body: some View {
        VStack(spacing: 0) {
            ToolDivider()
            HStack(spacing: 12) {
                Self.hint(key: "↑↓", label: "浏览")
                Self.hint(key: "↩", label: returnLabel)
                Spacer()
                Self.hint(key: "esc", label: "关闭")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
    }

    private static func hint(key: String, label: String) -> some View {
        HStack(spacing: 5) {
            IndexKeycap(label: key)
            Text(label)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// v3 continuity flight: per-row launch icon anchors, keyed by row id so
/// RootView can resolve the takeoff point when a row activates.
struct PaletteRowIconAnchorsKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct CommandPaletteRow: View {
    let id: String
    let title: String
    var highlightRanges: [Range<String.Index>] = []
    let subtitle: String?
    var subtitleHighlightRanges: [Range<String.Index>] = []
    let systemImage: String
    var isActive: Bool = false
    var isKeyboardActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: ToolMetrics.IconSize.tool, weight: .regular))
                    .foregroundStyle(isActive ? ToolTheme.accentHover : ToolTheme.textSecondary)
                    // The shared solid-chip bed (Keycap recipe) carries the
                    // resting icon; the active row swaps to the accent tint.
                    .frame(width: 24, height: 24)
                    .background(
                        isActive ? ToolTheme.accentSoft : ToolTheme.chipBed,
                        in: RoundedRectangle(
                            cornerRadius: ToolMetrics.CornerRadius.nestedControl,
                            style: .continuous
                        )
                    )
                    .anchorPreference(key: PaletteRowIconAnchorsKey.self, value: .bounds) {
                        [id: $0]
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.accentHighlighted(
                        title,
                        baseColor: ToolTheme.textPrimary,
                        highlightRanges: highlightRanges
                    ))
                        .font(ToolTypography.bodyLarge)
                        .lineLimit(1)

                    if let subtitle {
                        Text(Self.accentHighlighted(
                            subtitle,
                            baseColor: ToolTheme.textTertiary,
                            highlightRanges: subtitleHighlightRanges
                        ))
                            .font(ToolTypography.caption)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isActive {
                    Text("↩")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
            // Selection fill/stroke live in the floating highlight layer
            // (`CommandPaletteSelectionHighlightLayer`); the row keeps only
            // the keyboard focus ring.
            .overlay {
                if isKeyboardActive {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                        .strokeBorder(ToolTheme.focusRing, lineWidth: 1.5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .toolInteractionFeedback()
    }

    /// Accent-paints the engine's matched ranges over a base color. Title
    /// and subtitle ranges arrive prebuilt with the snapshot (one engine
    /// pass per query, shared with ranking), so rendering never re-runs
    /// matching and keyword/pinyin-only hits simply paint nothing.
    static func accentHighlighted(
        _ text: String,
        baseColor: Color,
        highlightRanges: [Range<String.Index>]
    ) -> AttributedString {
        guard !highlightRanges.isEmpty else {
            var plain = AttributedString(text)
            plain.foregroundColor = baseColor
            return plain
        }

        var attributed = AttributedString()
        var cursor = text.startIndex
        for range in highlightRanges {
            if cursor < range.lowerBound {
                var segment = AttributedString(String(text[cursor..<range.lowerBound]))
                segment.foregroundColor = baseColor
                attributed += segment
            }
            var matched = AttributedString(String(text[range]))
            matched.foregroundColor = ToolTheme.accentHover
            attributed += matched
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            var tail = AttributedString(String(text[cursor...]))
            tail.foregroundColor = baseColor
            attributed += tail
        }
        return attributed
    }
}
