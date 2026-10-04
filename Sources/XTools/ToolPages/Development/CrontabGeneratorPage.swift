import SwiftUI
import XToolsCore

@MainActor
final class CrontabToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<CrontabToolWorkspaceModel>(toolID: "crontab-generator") { _ in
        CrontabToolWorkspaceModel()
    }

    @Published var expression = "*/5 * * * *"
    @Published var error: String?
    @Published var nextRuns: [Date] = []
    /// 本次计算 nextRuns 的时间基准；相对时间（如「5 分钟后」）据此换算。
    @Published var generatedAt: Date?
    @Published var previewTimeZoneIdentifier: String?
    let debouncer = IndexDebouncer()

    var hasAnyContent: Bool {
        !expression.isEmpty || error != nil || !nextRuns.isEmpty
    }

    func clear() {
        debouncer.cancel()
        expression = ""
        error = nil
        nextRuns = []
        generatedAt = nil
        previewTimeZoneIdentifier = nil
    }
}

struct IndexCrontabPage: View {
    var body: some View {
        ToolWorkspaceHost(key: CrontabToolWorkspaceModel.key) { workspace, _ in
            IndexCrontabWorkspaceContent(workspace: workspace)
        }
    }
}

/// 两面板结构：表达式与预设同板，解析摘要、逐字段说明与下次运行同板。
/// 摘要（Core 的 expressionSummary）先给答案，逐字段行退居参考细节。
private struct IndexCrontabWorkspaceContent: View {
    @ObservedObject var workspace: CrontabToolWorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let presets = [
        ("每分钟", "* * * * *"), ("每10分钟", "*/10 * * * *"), ("每小时", "0 * * * *"),
        ("每6小时", "0 */6 * * *"), ("每30分钟", "*/30 * * * *"), ("每天", "0 0 * * *"),
        ("每天两次", "0 0,12 * * *"), ("工作日9点", "0 9 * * 1-5"), ("周末午夜", "0 0 * * 6,0"),
        ("每周", "0 0 * * 0"), ("每周一8点", "0 8 * * 1"), ("每月1号", "0 0 1 * *"),
        ("每季度", "0 0 1 */3 *"), ("每年", "0 0 1 1 *")
    ]

    var body: some View {
        IndexPage("Crontab 生成", subtitle: "用预设拼出 cron 表达式并给出说明。", workspaceSemantic: .naturalHeightShortResultPanel) {
            IndexPanel("Cron 表达式") {
                VStack(alignment: .leading, spacing: 14) {
                    IndexTextInput(placeholder: "*/5 * * * *", text: $workspace.expression, height: 44, alignment: .center)
                        .font(ToolTypography.valueMedium)
                        .onChange(of: workspace.expression) { _ in
                            workspace.debouncer.schedule(IndexDebouncer.keystrokeDebounce) { validate() }
                        }
                        .indexWorkspaceDiagnostic(workspace.error)

                    if let fields = CronScheduler.fieldExplanations(workspace.expression) {
                        fieldSegmentBar(fields)
                    }

                    Text("预设")
                        .font(ToolTypography.micro)
                        .foregroundStyle(ToolTheme.textTertiary)

                    IndexFlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(presets, id: \.0) { preset in
                            let isActive = preset.1 == workspace.expression.trimmingCharacters(in: .whitespacesAndNewlines)
                            IndexBadge(preset.0, isSelected: isActive, help: preset.1) {
                                workspace.expression = preset.1
                                validate()
                            }
                        }
                    }
                }
            } accessory: {
                HStack(spacing: 8) {
                    IndexClearButton(
                        isDisabled: !workspace.hasAnyContent,
                        title: "清空 Cron 表达式",
                        iconOnly: true,
                        action: workspace.clear
                    )
                    IndexCopyButton(text: workspace.expression.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            IndexPanel("解析结果") {
                VStack(alignment: .leading, spacing: 12) {
                    if let summary = CronScheduler.expressionSummary(workspace.expression) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "clock")
                                .font(ToolTypography.body)
                                .foregroundStyle(ToolTheme.accentHover)
                            Text(summary)
                                .font(ToolTypography.sectionTitle)
                                .foregroundStyle(ToolTheme.accentHover)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                    }

                    if let dayNote = CronScheduler.dayMatchingExplanation(workspace.expression) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(ToolTypography.caption)
                                .foregroundStyle(ToolTheme.textSecondary)
                            Text(dayNote)
                                .font(ToolTypography.caption)
                                .foregroundStyle(ToolTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }

                    if !workspace.nextRuns.isEmpty {
                        nextRunsSection
                    }

                    if let emptyText = explanationEmptyText {
                        Text(emptyText)
                            .font(ToolTypography.compactBody)
                            .foregroundStyle(ToolTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } accessory: {
                HStack(spacing: 10) {
                    if let identifier = workspace.previewTimeZoneIdentifier {
                        Text("时区 \(identifier)")
                            .font(ToolTypography.monoCaption)
                            .foregroundStyle(ToolTheme.textSecondary)
                            .lineLimit(1)
                    }
                    IndexIconButton(systemImage: "arrow.clockwise", help: "刷新下次运行时间") {
                        validate()
                    }
                }
            }
        }
        .onAppear { validate() }
    }

    /// 表达式的五段拆解：受限字段 accent 描边突出，通配字段弱化，
    /// 每段自带字段名、原文 token 与人话解释（悬停可见完整解释）。
    private func fieldSegmentBar(_ fields: [CronScheduler.CronFieldExplanation]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                fieldSegment(field)
            }
        }
    }

    private func fieldSegment(_ field: CronScheduler.CronFieldExplanation) -> some View {
        let shortLabel = field.label.components(separatedBy: " ").first ?? field.label
        return VStack(spacing: 3) {
            Text(shortLabel)
                .font(ToolTypography.micro)
                .foregroundStyle(ToolTheme.textSecondary)

            Text(field.token)
                .font(ToolTypography.monoLabel)
                .foregroundStyle(field.isWildcard ? ToolTheme.textTertiary : ToolTheme.accentHover)
                .textSelection(.enabled)

            Text(field.explanation)
                .font(ToolTypography.caption)
                .foregroundStyle(field.isWildcard ? ToolTheme.textTertiary : ToolTheme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .background(
            field.isWildcard ? ToolTheme.editorBackground : ToolTheme.accentSoft.opacity(0.45),
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
        )
        .overlay {
            if !field.isWildcard {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.accent.opacity(0.40), lineWidth: 0.5)
            }
        }
        .help(field.explanation)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(field.label)：\(field.token)，\(field.explanation)")
    }

    private var nextRunsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("下次运行")
                .font(ToolTypography.micro)
                .foregroundStyle(ToolTheme.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(workspace.nextRuns.enumerated()), id: \.offset) { index, run in
                    nextRunRow(run, ordinal: index)
                }
            }
        }
        .toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)
        .toolAnimation(ToolMotion.Preset.panelReveal, value: !workspace.nextRuns.isEmpty)
    }

    /// 首条最显眼（本地时间强调 + 人话相对时间），其余各条右侧给 UTC 对照。
    private func nextRunRow(_ date: Date, ordinal: Int) -> some View {
        let isFirst = ordinal == 0
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Self.nextRunsDateFormatter.string(from: date))
                .font(isFirst ? ToolTypography.monoValueSmall : ToolTypography.monoLabel)
                .foregroundStyle(isFirst ? ToolTheme.accentHover : ToolTheme.textSecondary)
                .textSelection(.enabled)

            Spacer(minLength: 12)

            if isFirst {
                Text(relativeLabel(for: date))
                    .font(ToolTypography.monoLabel)
                    .foregroundStyle(ToolTheme.accentHover)
            } else {
                Text(Self.utcRunFormatter.string(from: date))
                    .font(ToolTypography.monoCaption)
                    .foregroundStyle(ToolTheme.textTertiary)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func relativeLabel(for date: Date) -> String {
        let reference = workspace.generatedAt ?? Date()
        let seconds = max(0, Int(date.timeIntervalSince(reference).rounded()))
        if seconds < 60 { return "\(seconds) 秒后" }
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes < 60 { return "\(minutes) 分钟后" }
        let hours = Int((Double(minutes) / 60).rounded())
        if hours < 48 { return "\(hours) 小时后" }
        let days = Int((Double(hours) / 24).rounded())
        return "\(days) 天后"
    }

    private var explanationEmptyText: String? {
        let trimmed = workspace.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "输入 cron 表达式后显示解析与下次运行。"
        }
        if trimmed.lowercased() == "@reboot" {
            return "@reboot 会在系统启动时执行，没有固定日历预览"
        }
        return workspace.error == nil ? nil : "修正表达式后显示解析与下次运行。"
    }

    private func validate() {
        let trimmed = workspace.expression.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            workspace.error = nil
            workspace.nextRuns = []
            workspace.generatedAt = nil
            workspace.previewTimeZoneIdentifier = nil
            return
        }

        // @reboot has no calendar schedule; treat as valid with no preview.
        if trimmed.lowercased() == "@reboot" {
            workspace.error = nil
            workspace.nextRuns = []
            workspace.generatedAt = nil
            workspace.previewTimeZoneIdentifier = nil
            return
        }

        if let validationMessage = CronScheduler.validationMessage(workspace.expression) {
            workspace.error = validationMessage
            workspace.nextRuns = []
            workspace.generatedAt = nil
            workspace.previewTimeZoneIdentifier = nil
            return
        }

        workspace.error = nil
        let timeZoneIdentifier = TimeZone.current.identifier
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone.current
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let formatter = Self.nextRunsDateFormatter
        formatter.timeZone = timeZone

        let reference = Date()
        let runs = CronScheduler.nextRuns(workspace.expression, count: 5, after: reference, calendar: calendar)
        workspace.nextRuns = runs
        workspace.generatedAt = reference
        workspace.previewTimeZoneIdentifier = timeZoneIdentifier
    }

    private static let nextRunsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm (EEE)"
        return formatter
    }()

    private static let utcRunFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
