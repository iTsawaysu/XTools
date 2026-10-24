import AppKit
import XToolsCore
import SwiftUI
import XToolsDesign

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
        HStack(alignment: .top, spacing: ToolMetrics.Spacing.md) {
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
        .padding(.horizontal, ToolMetrics.Spacing.md)
        .padding(.vertical, ToolMetrics.Spacing.sm)
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
            .background(ToolTheme.panelBackground)
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
            VStack(spacing: 0) {
                if rows.isEmpty {
                    // 空态唯一入口（design-foundation C4）：内联空文案行归一
                    // 到 IndexEmptyState（output 密度），保持 70 最小高度语义。
                    IndexEmptyState(title: emptyText, density: .output)
                        .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
                        .background(ToolTheme.panelBackground)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        IndexKVRow(
                            key: row.0,
                            value: row.1,
                            color: row.2,
                            copyable: copyable,
                            valueLineBreakMode: valueLineBreakMode,
                            valueMotion: valueMotion
                        )
                        if index < rows.count - 1 {
                            // 0.5pt hairline 分隔（与侧栏/工作台行一致），
                            // 取代原先 1px strongBorder 底缝——深色宽缝在
                            // 暖纸上读成"每行独立卡片"，观感突兀。
                            Rectangle()
                                .fill(ToolTheme.border)
                                .frame(height: ToolMetrics.Spacing.hairline)
                        }
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
        IndexResultPresence(
            value: rows.isEmpty ? nil : rows,
            updateID: presenceUpdateID,
            scrollable: true
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
            VStack(spacing: 0) {
                ForEach(Array(snapshot.enumerated()), id: \.element.id) { index, row in
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
                    if index < snapshot.count - 1 {
                        Rectangle()
                            .fill(ToolTheme.border)
                            .frame(height: ToolMetrics.Spacing.hairline)
                    }
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
    /// Rows that are themselves clickable opt into a hover wash. Passive rows
    /// keep the resting surface so a static information list does not look
    /// interactive (audit I-06).
    var isInteractive = false
    private let content: Content

    @State private var isHovering = false

    init(
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 8,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(
                        isHovering && isInteractive ? ToolTheme.strongBorder : ToolTheme.border,
                        lineWidth: 0.5
                    )
            }
            .background {
                // hover 通道 opacity 插值（design-foundation D2）：固定渲染
                // 圆角色片，只在交互态 hover 时升至 1。
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .fill(ToolTheme.hoverFill)
                    .opacity(isInteractive && isHovering ? 1 : 0)
            }
            .onHover { hovering in
                guard isInteractive else { return }
                isHovering = hovering
            }
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: isHovering)
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
                    .padding(ToolMetrics.Spacing.sm)
            } empty: {
                IndexEmptyState(
                    title: emptyText,
                    systemImage: nil,
                    message: nil,
                    density: .output
                )
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
        LazyVStack(spacing: ToolMetrics.Spacing.sm) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                IndexResultCard(
                    item: item,
                    valueMotion: indexGeneratedResultValueMotion(index: index, limit: valueMotionLimit)
                )
                    // 诊断卡入场并入 contentReveal 0.24（design-foundation D1：
                    // 原 diagnostic 0.15 与结果出现 0.24 同屏节奏不齐）。
                    .toolTransition(revealsItems && index < 8 ? ToolMotion.Transition.modeContent : .identity, reduceMotion: reduceMotion)
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

private struct IndexResultCard: View {
    let item: IndexResultCardItem
    let valueMotion: IndexValueMotionPolicy

    var body: some View {
        IndexSurfaceRow(horizontalPadding: 12, verticalPadding: 8) {
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.fine) {
                HStack(spacing: ToolMetrics.Spacing.sm) {
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
                .padding(.horizontal, ToolMetrics.Spacing.md)
                .padding(.vertical, ToolMetrics.Spacing.sm)
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
                        .strokeBorder(tone.borderTint, lineWidth: 0.5)
                }
                .toolShadow(ToolTheme.Shadow.floating)
                .padding(.horizontal, ToolMetrics.Spacing.compact)
                .padding(.vertical, ToolMetrics.Spacing.sm)
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
                .font(ToolTypography.icon(ToolMetrics.IconSize.medium, .semibold))
                .foregroundStyle(payload.tone.tint)
                .frame(width: 24, height: 24)
                .background(payload.tone.softFill, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                        .strokeBorder(payload.tone.borderTint, lineWidth: 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(payload.text)
        .accessibilityLabel("\(payload.tone.accessibilityPrefix)：\(payload.text)")
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            HStack(alignment: .top, spacing: ToolMetrics.Spacing.sm) {
                Image(systemName: payload.tone.systemImage)
                    .font(ToolTypography.icon(ToolMetrics.IconSize.large, .semibold))
                    .foregroundStyle(payload.tone.tint)
                    .accessibilityHidden(true)

                Text(payload.text)
                    .font(ToolTypography.label)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ToolMetrics.Spacing.md)
            .frame(maxWidth: min(payload.maxWidth, 360), alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(payload.tone.accessibilityPrefix)：\(payload.text)")
        }
    }
}

struct IndexWorkspaceDiagnosticRegion<Content: View>: View {
    let text: String?
    var tone: ToolFeedbackTone = .error
    var maxWidth: CGFloat = 460
    var detail: FormatDiagnostic? = nil
    var isLocatable = false
    private let content: Content

    init(
        _ text: String?,
        tone: ToolFeedbackTone = .error,
        maxWidth: CGFloat = 460,
        detail: FormatDiagnostic? = nil,
        isLocatable: Bool = false,
        spacing: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        self.text = text
        self.tone = tone
        self.maxWidth = maxWidth
        self.detail = detail
        self.isLocatable = isLocatable
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
        return IndexWorkspaceDiagnosticPayload(
            text: visibleText,
            tone: tone,
            maxWidth: maxWidth,
            detail: detail,
            isLocatable: isLocatable
        )
    }
}

/// 壳层「定位」请求（page-rollout B2）：WorkbenchSurface 的诊断 banner 点
/// 「定位」时递增本值并经环境下发；声明了源标记的输入编辑器把它当作
/// `diagnosticNavigationToken` 消费（一次性请求，0 = 仅描边不跳转）。
private struct WorkbenchDiagnosticLocateRequestKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// 当前定位请求 token（壳层 banner「定位」驱动；无 banner 时恒 0）。
    var workbenchDiagnosticLocateRequest: Int {
        get { self[WorkbenchDiagnosticLocateRequestKey.self] }
        set { self[WorkbenchDiagnosticLocateRequestKey.self] = newValue }
    }
}

/// 纸顶诊断槽的单轨载荷。`detail`/`isLocatable` 是 page-rollout Batch B 的
/// 扩展：格式化族的诊断带 `FormatDiagnostic`（banner「详情」popover 的有界
/// 细节）与可定位标记——这两项能力原属 IndexFormatWorkbench 参数轨，迁
/// preference 单轨后随载荷透传，避免 spec「details open in a bounded
/// popover / explicit navigation」合同降级。定位动作本身不带闭包（payload
/// 须保持 Sendable）：「定位」钮由壳持有一个一次性 token 经
/// `workbenchDiagnosticLocateRequest` 环境下发，页面的源标记编辑器以它为
/// navigationToken 消费（page-rollout B2）。
struct IndexWorkspaceDiagnosticPayload: Equatable {
    let text: String
    let tone: ToolFeedbackTone
    let maxWidth: CGFloat
    var detail: FormatDiagnostic? = nil
    var isLocatable: Bool = false
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
        guard next != previous else { return nil }
        guard next.tone.workspaceDiagnosticPriority >= previous.tone.workspaceDiagnosticPriority else {
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
        maxWidth: CGFloat = 460,
        detail: FormatDiagnostic? = nil,
        isLocatable: Bool = false
    ) -> some View {
        IndexWorkspaceDiagnosticRegion(text, tone: tone, maxWidth: maxWidth, detail: detail, isLocatable: isLocatable) {
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
        HStack(spacing: ToolMetrics.Spacing.hair) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xs) {
                    Text(stat.1)
                        .font(ToolTypography.statValue)
                        .foregroundStyle(ToolTheme.accentHover)
                        .indexValueMotion(valueMotion, id: stat.1)
                    Text(stat.0)
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textSecondary)
                }
                .padding(.horizontal, ToolMetrics.Spacing.lg)
                .padding(.vertical, ToolMetrics.Spacing.md)
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
