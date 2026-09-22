import AppKit
import XToolsCore
import SwiftUI

enum IndexValueMotionPolicy: Equatable {
    case textSwap
    case immediate
}

func indexGeneratedResultValueMotion(index: Int, limit: Int) -> IndexValueMotionPolicy {
    index >= 0 && index < limit ? .textSwap : .immediate
}

private extension View {
    @ViewBuilder
    func indexValueMotion<ID: Hashable>(
        _ policy: IndexValueMotionPolicy,
        id: ID
    ) -> some View {
        switch policy {
        case .textSwap:
            toolMotionTextSwap(id: id)
        case .immediate:
            self
        }
    }
}

// MARK: - IndexKV

struct IndexKVRow: View {
    let key: String
    let value: String
    var keyWidth: CGFloat = 130
    var color: Color? = nil
    var copyable: Bool = false
    var valueLineBreakMode: NSLineBreakMode? = nil
    var valueMotion: IndexValueMotionPolicy = .immediate

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(ToolTypography.monoLabel)
                .foregroundStyle(color ?? ToolTheme.textSecondary)
                .frame(width: keyWidth, alignment: .leading)
            valueText
                .font(ToolTypography.monoLabel)
                .foregroundStyle(ToolTheme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .indexValueMotion(valueMotion, id: value)
            if copyable {
                IndexCopyButton(text: value, title: "")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(ToolTheme.panelBackground)
    }

    @ViewBuilder
    private var valueText: some View {
        if let valueLineBreakMode {
            Text(indexWrappingAttributedText(value, lineBreakMode: valueLineBreakMode))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(value)
        }
    }
}

struct IndexKVSurface<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(ToolTheme.border)
            .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: 0.5)
            }
    }
}

struct IndexKV: View {
    let rows: [(String, String, Color?)]
    var emptyText = IndexEmptyStateCopy.autoShow("文本")
    var copyable = true
    var valueLineBreakMode: NSLineBreakMode? = .byCharWrapping
    var valueMotion: IndexValueMotionPolicy = .textSwap

    var body: some View {
        IndexKVSurface {
            VStack(spacing: 1) {
                if rows.isEmpty {
                    Text(emptyText)
                        .font(ToolTypography.bodyPlain)
                        .foregroundStyle(ToolTheme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
                        .background(ToolTheme.panelBackground)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        IndexKVRow(
                            key: row.0,
                            value: row.1,
                            color: row.2,
                            copyable: copyable,
                            valueLineBreakMode: valueLineBreakMode,
                            valueMotion: valueMotion
                        )
                    }
                }
            }
        }
    }
}

struct IndexScrollableKVRow: Identifiable {
    let id: String
    let key: String
    let value: String
    let color: Color?
}

struct IndexScrollableKV: View {
    let rows: [IndexScrollableKVRow]
    var emptyText = IndexEmptyStateCopy.autoShow("文本")
    var copyable = true
    var valueLineBreakMode: NSLineBreakMode? = .byCharWrapping
    var valueMotion: IndexValueMotionPolicy = .textSwap

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presenceUpdateID: [String] {
        rows.flatMap { [$0.id, $0.key, $0.value, String(reflecting: $0.color)] }
    }

    var body: some View {
        IndexScrollableResultPresence(
            value: rows.isEmpty ? nil : rows,
            updateID: presenceUpdateID
        ) { snapshot, animatesRowInsertion in
            resultSurface(snapshot, animatesRowInsertion: animatesRowInsertion)
        } empty: {
            IndexKV(
                rows: [],
                emptyText: emptyText,
                copyable: copyable,
                valueLineBreakMode: valueLineBreakMode,
                valueMotion: valueMotion
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func resultSurface(
        _ snapshot: [IndexScrollableKVRow],
        animatesRowInsertion: Bool
    ) -> some View {
        let surface = IndexKVSurface {
            VStack(spacing: 1) {
                ForEach(snapshot) { row in
                    IndexKVRow(
                        key: row.key,
                        value: row.value,
                        color: row.color,
                        copyable: copyable,
                        valueLineBreakMode: valueLineBreakMode,
                        valueMotion: valueMotion
                    )
                    .toolTransition(
                        animatesRowInsertion ? ToolMotion.Transition.topRowInsertion : .identity,
                        reduceMotion: reduceMotion
                    )
                }
            }
        }
        .frame(minHeight: 70, alignment: .top)

        if animatesRowInsertion {
            surface
                .toolAnimation(ToolMotion.Preset.orderedContent, value: snapshot.map(\.id))
        } else {
            surface
        }
    }
}

struct IndexShortResultKV: View {
    let rows: [(String, String, Color?)]
    var emptyText = IndexEmptyStateCopy.autoShow("文本")
    var copyable = true
    var valueLineBreakMode: NSLineBreakMode = .byCharWrapping
    var workspaceSemantic: IndexWorkspaceSemantic = .naturalHeightShortResultPanel
    var valueMotion: IndexValueMotionPolicy = .textSwap

    private var presenceUpdateID: [String] {
        rows.flatMap { [$0.0, $0.1, String(reflecting: $0.2)] }
    }

    var body: some View {
        IndexWorkspaceResultSurface(workspaceSemantic: workspaceSemantic) {
            IndexResultPresence(
                value: rows.isEmpty ? nil : rows,
                updateID: presenceUpdateID
            ) { snapshot in
                IndexKV(
                    rows: snapshot,
                    emptyText: emptyText,
                    copyable: copyable,
                    valueLineBreakMode: valueLineBreakMode,
                    valueMotion: valueMotion
                )
            } empty: {
                IndexKV(
                    rows: [],
                    emptyText: emptyText,
                    copyable: copyable,
                    valueLineBreakMode: valueLineBreakMode,
                    valueMotion: valueMotion
                )
            }
        }
    }
}

// MARK: - IndexSurfaceRow

struct IndexSurfaceRow<Content: View>: View {
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 8
    private let content: Content

    init(
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: 0.5)
            }
    }
}

struct IndexResultCardItem: Identifiable {
    let id: String
    let label: String
    let value: String
    var badgeText: String?
    var badgeTone: IndexBadgeTone = .neutral
    var copyHelp = "复制此项"

    init(
        id: String,
        label: String,
        value: String,
        badgeText: String? = nil,
        badgeTone: IndexBadgeTone = .neutral,
        copyHelp: String = "复制此项"
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.badgeText = badgeText
        self.badgeTone = badgeTone
        self.copyHelp = copyHelp
    }
}

struct IndexDerivedResultCardList: View {
    let items: [IndexResultCardItem]
    var emptyText = IndexEmptyStateCopy.autoShow("内容")

    var body: some View {
        IndexShortResultCardList(items: items, emptyText: emptyText)
    }
}

struct IndexShortResultCardList: View {
    let items: [IndexResultCardItem]
    var emptyText = IndexEmptyStateCopy.autoShow("内容")
    var workspaceSemantic: IndexWorkspaceSemantic = .naturalHeightShortResultPanel

    private var presenceUpdateID: [String] {
        items.flatMap { item in
            [
                item.id,
                item.label,
                item.value,
                item.badgeText ?? "",
                String(reflecting: item.badgeTone),
                item.copyHelp
            ]
        }
    }

    var body: some View {
        IndexWorkspaceResultSurface(workspaceSemantic: workspaceSemantic) {
            IndexResultPresence(
                value: items.isEmpty ? nil : items,
                updateID: presenceUpdateID
            ) { snapshot in
                IndexResultCardStack(items: snapshot, revealsItems: false)
                    .padding(8)
            } empty: {
                IndexResultCardEmptyState(emptyText: emptyText)
            }
        }
    }
}

private struct IndexResultCardStack: View {
    let items: [IndexResultCardItem]
    var revealsItems = true
    var valueMotionLimit = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var revealSignature: String {
        if items.isEmpty {
            return "empty"
        }

        return items.prefix(8).map(\.id).joined(separator: "|")
    }

    private var stack: some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                IndexResultCard(
                    item: item,
                    valueMotion: indexGeneratedResultValueMotion(index: index, limit: valueMotionLimit)
                )
                    .toolTransition(revealsItems && index < 8 ? ToolMotion.Transition.diagnostic : .identity, reduceMotion: reduceMotion)
            }
        }
    }

    @ViewBuilder
    var body: some View {
        if revealsItems {
            stack
                .toolAnimation(ToolMotion.Preset.panelReveal, value: revealSignature)
        } else {
            stack
        }
    }
}

private struct IndexResultCardEmptyState: View {
    let emptyText: String

    var body: some View {
        VStack(spacing: 6) {
            Text(emptyText)
                .font(ToolTypography.bodyPlain)
                .foregroundStyle(ToolTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
        .padding(.horizontal, 12)
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
    }
}

private struct IndexResultCard: View {
    let item: IndexResultCardItem
    let valueMotion: IndexValueMotionPolicy

    var body: some View {
        IndexSurfaceRow(horizontalPadding: 12, verticalPadding: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.label)
                        .font(ToolTypography.micro)
                        .foregroundStyle(ToolTheme.textTertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if let badgeText = item.badgeText {
                        IndexBadge(badgeText, tone: item.badgeTone)
                    }

                    Spacer(minLength: 8)

                    IndexCopyButton(text: item.value, title: item.copyHelp, iconOnly: true)
                }

                valueText
            }
        }
    }

    private var valueText: some View {
        Text(indexWrappingAttributedText(item.value, lineBreakMode: .byCharWrapping))
            .font(ToolTypography.monoLabel)
            .foregroundStyle(ToolTheme.textPrimary)
            .textSelection(.enabled)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .indexValueMotion(valueMotion, id: item.value)
    }
}

struct IndexWorkspaceDiagnostic: View {
    let text: String?
    var tone: ToolFeedbackTone = .error
    var maxWidth: CGFloat = 460
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let text, !text.isEmpty {
            Label(text, systemImage: tone.systemImage)
                .font(ToolTypography.label)
                .foregroundStyle(tone.tint)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                            .fill(ToolTheme.panelBackground)
                        RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                            .fill(tone.softFill)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                        .strokeBorder(tone.tint.opacity(0.45), lineWidth: 0.5)
                }
                .toolShadow(ToolTheme.Shadow.floating)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: maxWidth, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)
                .allowsHitTesting(false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(tone.accessibilityPrefix)：\(text)")
        }
    }
}

struct IndexDiagnosticStatusButton: View {
    let payload: IndexWorkspaceDiagnosticPayload
    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            Image(systemName: payload.tone.systemImage)
                .font(.system(size: ToolMetrics.IconSize.medium, weight: .semibold))
                .foregroundStyle(payload.tone.tint)
                .frame(width: 24, height: 24)
                .background(payload.tone.softFill, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                        .strokeBorder(payload.tone.tint.opacity(0.45), lineWidth: 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(payload.text)
        .accessibilityLabel("\(payload.tone.accessibilityPrefix)：\(payload.text)")
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: payload.tone.systemImage)
                    .font(.system(size: ToolMetrics.IconSize.large, weight: .semibold))
                    .foregroundStyle(payload.tone.tint)
                    .accessibilityHidden(true)

                Text(payload.text)
                    .font(ToolTypography.label)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: min(payload.maxWidth, 360), alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(payload.tone.accessibilityPrefix)：\(payload.text)")
        }
    }
}

struct IndexDiagnosticStatusSlot: View {
    let payload: IndexWorkspaceDiagnosticPayload?

    var body: some View {
        Group {
            if let payload {
                IndexDiagnosticStatusButton(payload: payload)
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 24, height: 24)
    }
}

struct IndexPanelWorkspaceDiagnostic: View {
    let payload: IndexWorkspaceDiagnosticPayload?

    var body: some View {
        Group {
            if let payload {
                IndexDiagnosticStatusButton(payload: payload)
            } else {
                Color.clear
            }
        }
        .frame(width: 31, height: 24)
    }
}

struct IndexWorkspaceDiagnosticRegion<Content: View>: View {
    let text: String?
    var tone: ToolFeedbackTone = .error
    var maxWidth: CGFloat = 460
    private let content: Content

    init(
        _ text: String?,
        tone: ToolFeedbackTone = .error,
        maxWidth: CGFloat = 460,
        spacing: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        self.text = text
        self.tone = tone
        self.maxWidth = maxWidth
        self.content = content()
    }

    private var visibleText: String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .preference(key: IndexWorkspaceDiagnosticPreferenceKey.self, value: diagnosticPayload)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .toolAnimation(ToolMotion.Preset.diagnostic, value: text)
    }

    private var diagnosticPayload: IndexWorkspaceDiagnosticPayload? {
        guard let visibleText else { return nil }
        return IndexWorkspaceDiagnosticPayload(text: visibleText, tone: tone, maxWidth: maxWidth)
    }
}

struct IndexWorkspaceDiagnosticPayload: Equatable {
    let text: String
    let tone: ToolFeedbackTone
    let maxWidth: CGFloat
}

struct IndexWorkspaceDiagnosticPresentationState: Equatable {
    private(set) var current: IndexWorkspaceDiagnosticPayload?

    mutating func update(
        to next: IndexWorkspaceDiagnosticPayload?
    ) -> IndexWorkspaceDiagnosticPayload? {
        let previous = current
        current = next

        guard let next else { return nil }
        guard let previous else { return next }
        guard next.tone.workspaceDiagnosticPriority > previous.tone.workspaceDiagnosticPriority else {
            return nil
        }
        return next
    }
}

struct IndexWorkspaceDiagnosticPreferenceKey: PreferenceKey {
    static let defaultValue: IndexWorkspaceDiagnosticPayload? = nil

    static func reduce(
        value: inout IndexWorkspaceDiagnosticPayload?,
        nextValue: () -> IndexWorkspaceDiagnosticPayload?
    ) {
        guard let candidate = nextValue() else { return }
        guard let current = value else {
            value = candidate
            return
        }

        if candidate.tone.workspaceDiagnosticPriority > current.tone.workspaceDiagnosticPriority {
            value = candidate
        }
    }
}

extension View {
    func indexWorkspaceDiagnostic(
        _ text: String?,
        tone: ToolFeedbackTone = .error,
        maxWidth: CGFloat = 460
    ) -> some View {
        IndexWorkspaceDiagnosticRegion(text, tone: tone, maxWidth: maxWidth) {
            self
        }
    }

    func indexWorkspaceDiagnosticOverlay(
        _ text: String?,
        tone: ToolFeedbackTone = .error,
        alignment: Alignment = .topTrailing,
        maxWidth: CGFloat = 460
    ) -> some View {
        overlay(alignment: alignment) {
            IndexWorkspaceDiagnostic(text: text, tone: tone, maxWidth: maxWidth)
        }
        .toolAnimation(ToolMotion.Preset.diagnostic, value: text)
    }
}

// MARK: - IndexStatGrid

/// Statistics display grid
struct IndexStatGrid: View {
    let stats: [(String, String)]
    var valueMotion: IndexValueMotionPolicy = .textSwap

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                VStack(alignment: .leading, spacing: 3) {
                    Text(stat.1)
                        .font(ToolTypography.statValue)
                        .foregroundStyle(ToolTheme.accentHover)
                        .indexValueMotion(valueMotion, id: stat.1)
                    Text(stat.0)
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textSecondary)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ToolTheme.panelBackground)
            }
        }
        .background(ToolTheme.border)
        .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
    }
}
