import SwiftUI

@MainActor
struct DashboardView: View {
    private struct Shortcut: Identifiable {
        let id: ToolID
        let detail: String
    }

    private struct RecentItem: Identifiable {
        let recent: DashboardRecentTool
        let tool: RegisteredTool

        var id: ToolID { tool.id }
    }

    private static let shortcuts: [Shortcut] = [
        Shortcut(id: "formatter", detail: "JSON · XML · YAML · SQL"),
        Shortcut(id: "base64-string", detail: "编码与解码文本"),
        Shortcut(id: "url-encoder-decoder", detail: "处理百分号编码"),
        Shortcut(id: "regex-tester", detail: "验证文本匹配"),
        Shortcut(id: "date-time-converter", detail: "转换日期与时间"),
        Shortcut(id: "color-picker", detail: "查看常用颜色格式")
    ]

    @ObservedObject private var store: DashboardStore
    private let registry: ToolRegistry
    private let onSelectTool: (ToolID) -> Void

    init(
        store: DashboardStore,
        registry: ToolRegistry,
        onSelectTool: @escaping (ToolID) -> Void = { _ in }
    ) {
        self.store = store
        self.registry = registry
        self.onSelectTool = onSelectTool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageHeader
                statsSection

                ToolWorkspaceHost(key: HomeContentSession.key) { session, observed in
                    HomeContentWorkbench(session: session, input: observed.input)
                }
                .padding(.top, ToolMetrics.Workbench.sectionGap)

                shortcutSection.padding(.top, ToolMetrics.Workbench.sectionGap)
                recentSection.padding(.top, ToolMetrics.Workbench.sectionGap)
            }
            .frame(maxWidth: ToolMetrics.Workbench.mainMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, ToolMetrics.Workbench.horizontalInset)
            .padding(.top, ToolMetrics.Workbench.topInset)
            .padding(.bottom, 30)
        }
        .background(ToolTheme.Workbench.canvas)
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("工作台")
                    .font(ToolTypography.Workbench.title)
                    .foregroundStyle(ToolTheme.Workbench.textPrimary)
                Text("\(greetingText) · 粘贴一段内容，或直接打开常用工具。")
                    .font(ToolTypography.Workbench.subtitle)
                    .foregroundStyle(ToolTheme.Workbench.textSecondary)
            }

            Spacer(minLength: 12)

            DashboardTrendStrip(days: store.sevenDayTrend)

            Label("内容只在当前页面处理", systemImage: "lock")
                .font(ToolTypography.Workbench.caption)
                .foregroundStyle(ToolTheme.Workbench.textFaint)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.bottom, 24)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "早安，开发者"
        case 11..<13: return "午安，开发者"
        case 13..<18: return "下午好，开发者"
        case 18..<24: return "晚上好，开发者"
        default: return "夜深了，开发者"
        }
    }

    /// Instrument strip: three monospaced counters that roll up on first
    /// appearance. Backed by the already-persisted `DashboardStore` activity
    /// (total launches / 7-day window) plus the live registry size.
    private var statsSection: some View {
        HStack(alignment: .top, spacing: 44) {
            DashboardStat(
                caption: "累计启动",
                value: store.totalLaunches
            )
            DashboardStat(
                caption: "近 7 日",
                value: store.sevenDayTrend.reduce(0) { $0 + $1.launchCount }
            )
            DashboardStat(
                caption: "收录工具",
                value: registry.categoryGroups().reduce(0) { $0 + $1.tools.count }
            )
        }
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkbenchSectionHeader(title: "快捷工具", detail: "常用本地工具")

            VStack(spacing: 0) {
                shortcutRow(Array(Self.shortcuts.prefix(3)))
                Rectangle().fill(ToolTheme.Workbench.border).frame(height: 1)
                shortcutRow(Array(Self.shortcuts.dropFirst(3)))
            }
            .background(
                ToolTheme.Workbench.surface,
                in: RoundedRectangle(cornerRadius: ToolMetrics.Workbench.groupCorner, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.Workbench.groupCorner, style: .continuous)
                    .strokeBorder(ToolTheme.Workbench.border, lineWidth: 1)
            }
            .clipShape(
                RoundedRectangle(cornerRadius: ToolMetrics.Workbench.groupCorner, style: .continuous)
            )
        }
    }

    private func shortcutRow(_ shortcuts: [Shortcut]) -> some View {
        HStack(spacing: 0) {
            ForEach(shortcuts.indices, id: \.self) { index in
                let shortcut = shortcuts[index]
                if let tool = registry.tool(for: shortcut.id) {
                    WorkbenchShortcutButton(
                        tool: tool,
                        detail: shortcut.detail,
                        action: { onSelectTool(tool.id) }
                    )
                    .frame(maxWidth: .infinity)

                    if index < shortcuts.count - 1 {
                        Rectangle()
                            .fill(ToolTheme.Workbench.border)
                            .frame(width: 1, height: ToolMetrics.Workbench.shortcutRowHeight)
                    }
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkbenchSectionHeader(title: "最近打开", detail: "本机使用记录")

            if recentTools.isEmpty {
                Text("打开工具后会显示在这里。")
                    .font(ToolTypography.Workbench.body)
                    .foregroundStyle(ToolTheme.Workbench.textSecondary)
                    .frame(minHeight: 34, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    ForEach(recentTools) { item in
                        WorkbenchRecentButton(
                            tool: item.tool,
                            lastOpenedAt: item.recent.lastOpenedAt,
                            action: { onSelectTool(item.tool.id) }
                        )
                    }
                }
                .frame(minHeight: 34, alignment: .leading)
            }
        }
    }

    private var recentTools: [RecentItem] {
        let knownToolIDs = Set(
            registry.categoryGroups().flatMap { group in group.tools.map(\.id) }
        )
        return store.recentTools(knownToolIDs: knownToolIDs)
            .prefix(3)
            .compactMap { recent in
                registry.tool(for: recent.toolID).map {
                    RecentItem(recent: recent, tool: $0)
                }
            }
    }
}

private struct WorkbenchSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(ToolTypography.Workbench.sectionTitle)
                .foregroundStyle(ToolTheme.Workbench.textPrimary)
            Spacer()
            Text(detail)
                .font(ToolTypography.Workbench.caption)
                .foregroundStyle(ToolTheme.Workbench.textFaint)
        }
    }
}

/// One dashboard counter. The value rolls from zero on first appearance
/// (macOS 14+ digit roll; older systems and Reduce Motion show the final
/// number), giving the workspace an instrument-panel arrival beat.
/// Wave 2 trend strip (prototype c7): seven launch-count bars spring-grow
/// from the baseline one beat apart; today's bar carries the accent. Growth
/// spring and stagger live in `ToolMotion` (`TrendBars` / `Duration.stagger`).
private struct DashboardTrendStrip: View {
    let days: [DashboardActivityDay]

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maxValue: Int {
        max(1, days.map(\.launchCount).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("近 7 日趋势")
                .font(ToolTypography.monoCaption)
                .foregroundStyle(ToolTheme.Workbench.textFaint)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    let isToday = index == days.count - 1
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.trendBar, style: .continuous)
                        .fill(isToday ? AnyShapeStyle(ToolTheme.accent) : AnyShapeStyle(ToolTheme.textTertiary))
                        .opacity(isToday ? 1 : 0.5)
                        .frame(width: 9, height: barHeight(day))
                        .scaleEffect(y: hasAppeared ? 1 : 0.001, anchor: .bottom)
                        .animation(
                            reduceMotion
                                ? nil
                                : ToolMotion.TrendBars.growth.delay(Double(index) * ToolMotion.Duration.stagger),
                            value: hasAppeared
                        )
                }
            }
            .frame(height: 46, alignment: .bottom)
            HStack(spacing: 6) {
                ForEach(days) { day in
                    Text(Self.weekdayLabel(day.date))
                        .font(ToolTypography.monoCaption)
                        .foregroundStyle(ToolTheme.Workbench.textFaint)
                        .frame(width: 9)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("近 7 日趋势:" + days
            .map { "\(Self.weekdayLabel($0.date)) \( $0.launchCount) 次" }
            .joined(separator: "，"))
        .onAppear {
            hasAppeared = true
        }
    }

    private func barHeight(_ day: DashboardActivityDay) -> CGFloat {
        8 + CGFloat(day.launchCount) / CGFloat(maxValue) * 38
    }

    private static func weekdayLabel(_ date: Date) -> String {
        let index = Calendar.current.component(.weekday, from: date)
        return Calendar.current.veryShortWeekdaySymbols[index - 1]
    }
}

private struct DashboardStat: View {    let caption: String
    let value: Int

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayedValue: Int {
        hasAppeared ? value : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(ToolTypography.monoCaption)
                .foregroundStyle(ToolTheme.Workbench.textFaint)
            Text("\(displayedValue)")
                .font(ToolTypography.statValue)
                .foregroundStyle(ToolTheme.Workbench.textPrimary)
                .toolNumericTransition(value: displayedValue)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption) \(value)")
        .onAppear {
            hasAppeared = true
        }
    }
}

private struct WorkbenchShortcutButton: View {
    let tool: RegisteredTool
    let detail: String
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: tool.systemImage)
                    .font(ToolTypography.Workbench.icon)
                    .foregroundStyle(ToolTheme.Workbench.textSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title)
                        .font(ToolTypography.Workbench.body.weight(.semibold))
                        .foregroundStyle(ToolTheme.Workbench.textPrimary)
                    Text(detail)
                        .font(ToolTypography.Workbench.caption)
                        .foregroundStyle(ToolTheme.Workbench.textSecondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(ToolTypography.Workbench.chevron)
                    .foregroundStyle(ToolTheme.Workbench.textFaint)
            }
            .padding(.horizontal, 13)
            .frame(height: ToolMetrics.Workbench.shortcutRowHeight)
            .contentShape(Rectangle())
            .background(isHovering ? ToolTheme.Workbench.surfaceSecondary : Color.clear)
        }
        .buttonStyle(IndexBareButtonStyle())
        .focused($isFocused)
        .indexFocusRing(active: isFocused, cornerRadius: ToolMetrics.Workbench.compactCorner)
        .onHover { isHovering = $0 }
        .help("打开\(tool.title)")
        .accessibilityLabel("打开\(tool.title)")
        .accessibilityIdentifier("dashboard.shortcut.\(tool.id.rawValue)")
    }
}

private struct WorkbenchRecentButton: View {
    let tool: RegisteredTool
    let lastOpenedAt: Date
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tool.systemImage).font(ToolTypography.Workbench.smallIcon)
                Text(tool.title).lineLimit(1)
                Text(relativeTimeText)
                    .foregroundStyle(ToolTheme.Workbench.textFaint)
                    .lineLimit(1)
            }
            .font(ToolTypography.Workbench.caption)
            .foregroundStyle(ToolTheme.Workbench.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                isHovering ? ToolTheme.Workbench.surfaceSecondary : ToolTheme.Workbench.surface,
                in: RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous)
                    .strokeBorder(ToolTheme.Workbench.border, lineWidth: 1)
            }
            .contentShape(
                RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous)
            )
        }
        .buttonStyle(IndexBareButtonStyle())
        .focused($isFocused)
        .indexFocusRing(active: isFocused, cornerRadius: ToolMetrics.Workbench.compactCorner)
        .onHover { isHovering = $0 }
        .help("打开\(tool.title) · \(fullTimestamp)")
        .accessibilityLabel("打开\(tool.title)，\(lastOpenedAt.formatted(date: .abbreviated, time: .shortened))")
        .accessibilityIdentifier("dashboard.recent.\(tool.id.rawValue)")
    }

    private var relativeTimeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastOpenedAt, relativeTo: Date())
    }

    private var fullTimestamp: String {
        lastOpenedAt.formatted(date: .complete, time: .standard)
    }

}
