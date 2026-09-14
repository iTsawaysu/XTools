import SwiftUI
import XToolsCore

@MainActor
final class CrontabToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<CrontabToolWorkspaceModel>(toolID: "crontab-generator") { _ in
        CrontabToolWorkspaceModel()
    }

    @Published var expression = "*/5 * * * *"
    @Published var error: String?
    @Published var nextRuns: [String] = []
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

private struct IndexCrontabWorkspaceContent: View {
    @ObservedObject var workspace: CrontabToolWorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let presets = [
        ("每分钟", "* * * * *"), ("每 10 分钟", "*/10 * * * *"), ("每小时", "0 * * * *"),
        ("每 6 小时", "0 */6 * * *"), ("每 30 分钟", "*/30 * * * *"), ("每天", "0 0 * * *"),
        ("每天两次", "0 0,12 * * *"), ("工作日 9 点", "0 9 * * 1-5"), ("周末午夜", "0 0 * * 6,0"),
        ("每周", "0 0 * * 0"), ("每周一 8 点", "0 8 * * 1"), ("每月 1 号", "0 0 1 * *"),
        ("每季度", "0 0 1 */3 *"), ("每年", "0 0 1 1 *")
    ]
    private let fields = ["分钟 (0-59)", "小时 (0-23)", "日 (1-31)", "月 (1-12)", "星期 (0-7)"]

    private var rows: [(String, String, Color?)] {
        let resolved = CronScheduler.resolveExpression(workspace.expression)
        guard !resolved.isEmpty else { return [] }
        let parts = resolved.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5, CronScheduler.validationMessage(workspace.expression) == nil else { return [] }

        var result: [(String, String, Color?)] = parts.enumerated().map {
            (fields[$0.offset], "\($0.element) — \(CronScheduler.explainField($0.element, index: $0.offset))", nil)
        }
        if let explanation = CronScheduler.dayMatchingExplanation(workspace.expression) {
            result.append(("匹配规则", explanation, nil))
        }
        return result
    }

    var body: some View {
        IndexPage("Crontab 生成", subtitle: "用预设拼出 cron 表达式并给出说明。", workspaceSemantic: .naturalHeightShortResultPanel) {
            IndexPanel("常用预设") {
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
            IndexPanel("Cron 表达式") {
                HStack(spacing: 8) {
                    IndexClearButton(
                        isDisabled: !workspace.hasAnyContent,
                        title: "清空 Cron 表达式",
                        iconOnly: true,
                        action: workspace.clear
                    )
                    IndexCopyButton(text: workspace.expression.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } content: {
                IndexTextInput(placeholder: "*/5 * * * *", text: $workspace.expression, height: 44, alignment: .center)
                    .font(ToolTypography.valueMedium)
                    .onChange(of: workspace.expression) { _ in
                        workspace.debouncer.schedule(.milliseconds(250)) { validate() }
                    }
                    .indexWorkspaceDiagnostic(workspace.error)
            }
            IndexPanel("说明") {
                IndexShortResultKV(rows: rows, emptyText: explanationEmptyText, copyable: false, valueMotion: .immediate)
            }
            nextRunsSection
        }
        .onAppear { validate() }
    }

    @ViewBuilder
    private var nextRunsSection: some View {
        Group {
            if !workspace.nextRuns.isEmpty {
                IndexPanel("下次运行时间") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(workspace.nextRuns, id: \.self) { run in
                            Text(run)
                                .font(ToolTypography.monoLabel)
                                .foregroundStyle(ToolTheme.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                    }
                } accessory: {
                    if let identifier = workspace.previewTimeZoneIdentifier {
                        Text("时区 \(identifier)")
                            .font(ToolTypography.monoCaption)
                            .foregroundStyle(ToolTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)
            }
        }
        .toolAnimation(ToolMotion.Preset.panelReveal, value: !workspace.nextRuns.isEmpty)
    }

    private var explanationEmptyText: String {
        workspace.expression.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "@reboot"
            ? "@reboot 会在系统启动时执行，没有固定日历预览"
            : "cron 表达式需要 5 个字段"
    }

    private func validate() {
        let trimmed = workspace.expression.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            workspace.error = nil
            workspace.nextRuns = []
            workspace.previewTimeZoneIdentifier = nil
            return
        }

        // @reboot has no calendar schedule; treat as valid with no preview.
        if trimmed.lowercased() == "@reboot" {
            workspace.error = nil
            workspace.nextRuns = []
            workspace.previewTimeZoneIdentifier = nil
            return
        }

        if let validationMessage = CronScheduler.validationMessage(workspace.expression) {
            workspace.error = validationMessage
            workspace.nextRuns = []
            workspace.previewTimeZoneIdentifier = nil
            return
        }

        workspace.error = nil
        let timeZoneIdentifier = TimeZone.current.identifier
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone.current
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm (EEE)"

        let runs = CronScheduler.nextRuns(workspace.expression, count: 5, after: Date(), calendar: calendar)
        workspace.nextRuns = runs.map(formatter.string(from:))
        workspace.previewTimeZoneIdentifier = timeZoneIdentifier
    }
}
