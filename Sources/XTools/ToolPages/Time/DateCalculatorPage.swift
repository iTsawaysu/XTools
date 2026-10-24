import XToolsCore
import SwiftUI
import XToolsDesign

@MainActor
final class DateCalcToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<DateCalcToolWorkspaceModel>(toolID: "date-calculator") { preferences in
        DateCalcToolWorkspaceModel(preferences: preferences)
    }

    enum Mode: String, CaseIterable, Sendable {
        case interval
        case offset

        var title: String {
            switch self {
            case .interval: return "日期间隔"
            case .offset: return "日期加减"
            }
        }

        var panelTitle: String {
            switch self {
            case .interval: return "两日期间隔"
            case .offset: return "日期加减"
            }
        }
    }

    /// 当前模式；切换即写入偏好，重启后回到上次使用的模式（全新用户默认间隔）。
    @Published var mode: Mode {
        didSet {
            guard mode != oldValue else { return }
            preferences.set(mode.rawValue, for: TextDevelopmentToolPreferenceKeys.dateCalcMode)
        }
    }

    @Published var session = DateCalcWorkspace()

    private let preferences: ToolPreferenceStore

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        mode = Mode(rawValue: preferences.value(for: TextDevelopmentToolPreferenceKeys.dateCalcMode)) ?? .interval
    }
}

struct IndexDateCalcPage: View {
    var body: some View {
        ToolWorkspaceHost(key: DateCalcToolWorkspaceModel.key) { _, bindings in
            IndexDateCalcWorkspaceContent(mode: bindings.mode, session: bindings.session)
        }
    }
}

/// 统一壳装配（page-rollout A1）：模式分段是页面级模式（间隔/加减，切换
/// 整页内容并持久化偏好），归标题行 titleAccessory（Base64File 编码/解码
/// 分段先例）；「复制结果」归输出 pane 尾部 ActionBar（首个 copy 同步壳级
/// actions 注册 ⇧⌘C）；双栏需固定高度，语义切 queryList（DateTime 先例
/// 授权）。输入/结果两组内容投影逐字保留。
private struct IndexDateCalcWorkspaceContent: View {
    @Binding var mode: DateCalcToolWorkspaceModel.Mode
    @Binding var session: DateCalcWorkspace

    private var intervalDetailRows: [(String, String, Color?)] {
        [
            ("周数+天数", session.weeksDaysText, nil),
            ("总小时", "\(abs(session.totals.hours)) 小时", nil),
            ("总分钟", "\(abs(session.totals.minutes)) 分钟", nil)
        ]
    }

    private var resultCopyText: String {
        mode == .interval ? session.totalDaysText : session.resultCopyText
    }

    private var copyAction: WorkbenchActionBarAction {
        .copy(text: resultCopyText, title: "复制结果")
    }

    var body: some View {
        IndexPage("日期计算", subtitle: "计算两个日期之间的间隔，或在某个日期上加减时间。", workspaceSemantic: .queryListWorkspace) {
            WorkbenchSurface(title: nil, shape: .inputOutput, actions: [copyAction]) {
                WorkbenchIOPair(
                    leadingTitle: mode.panelTitle,
                    trailingTitle: "结果",
                    trailingActions: [copyAction]
                ) {
                    Group {
                        if mode == .interval {
                            intervalInput
                        } else {
                            offsetInput
                        }
                    }
                } trailing: {
                    Group {
                        if mode == .interval {
                            intervalResult
                        } else {
                            offsetResult
                        }
                    }
                }
            }
        }
    }

    private var intervalInput: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.base) {
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                Text("常用范围")
                    .font(ToolTypography.buttonSmall)
                    .foregroundStyle(ToolTheme.textSecondary)
                IndexFlowLayout(spacing: ToolMetrics.Spacing.fine, lineSpacing: 6) {
                    ForEach(DateCalcWorkspace.DiffPreset.allCases, id: \.rawValue) { preset in
                        IndexBadge(preset.title) {
                            session.applyPreset(preset)
                        }
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: ToolMetrics.Spacing.md) {
                    startField()
                    endField()
                }
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
                    startField()
                    endField()
                }
            }

            DateCalculatorInlineOption(
                title: "包含结束日",
                help: "把结束日期当天也计入结果（+1 天）",
                isOn: $session.includeEndDate
            )
        }
        .indexWorkspaceDiagnostic(session.diffError)
    }

    private var intervalResult: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.base) {
            DateCalculatorHeroResult(
                value: session.totalDaysText,
                subtitle: session.direction
            )

            IndexStatGrid(stats: session.breakdownStats, valueMotion: .immediate)
            IndexKV(rows: intervalDetailRows, copyable: false, valueMotion: .immediate)
        }
    }

    private var offsetInput: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.base) {
            baseField()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ToolMetrics.Spacing.sm) {
                    offsetControls
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
                    offsetControls
                }
            }
        }
        .indexWorkspaceDiagnostic(session.baseInputError)
    }

    private var offsetResult: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.base) {
            DateCalculatorHeroResult(
                value: session.resultDateText,
                subtitle: session.resultWeekdayText,
                footnote: session.resultRelativeToTodayText()
            )
        }
    }

    @ViewBuilder
    private var offsetControls: some View {
        IndexSegmentedControl(
            items: DateCalcWorkspace.Op.allCases.map { ($0, $0.label) },
            selection: $session.op
        )
        .frame(width: ToolMetrics.Control.slider)

        IndexNumberInput(value: $session.amount, range: 0...100_000, fieldWidth: 56)

        IndexSegmentedControl(
            items: DateCalcEngine.Unit.allCases.map { ($0, $0.label) },
            selection: $session.unit
        )
    }

    // MARK: - Date fields

    @ViewBuilder
    private func startField() -> some View {
        DateCalculatorDateField(
            title: "开始日期",
            input: $session.startInput,
            date: session.start,
            weekdayText: session.startWeekdayText,
            isFocusTarget: true,
            onCommit: { session.commitStartInputDate($0) },
            onInvalidPaste: { session.markStartInvalidPaste() },
            onSelectDate: { session.applyStartDate($0) },
            onToday: { session.setStartToday() }
        )
    }

    @ViewBuilder
    private func endField() -> some View {
        DateCalculatorDateField(
            title: "结束日期",
            input: $session.endInput,
            date: session.end,
            weekdayText: session.endWeekdayText,
            onCommit: { session.commitEndInputDate($0) },
            onInvalidPaste: { session.markEndInvalidPaste() },
            onSelectDate: { session.applyEndDate($0) },
            onToday: { session.setEndToday() }
        )
    }

    @ViewBuilder
    private func baseField() -> some View {
        DateCalculatorDateField(
            title: "基准日期",
            input: $session.baseInput,
            date: session.base,
            weekdayText: session.baseWeekdayText,
            isFocusTarget: true,
            onCommit: { session.commitBaseInputDate($0) },
            onInvalidPaste: { session.markBaseInvalidPaste() },
            onSelectDate: { session.applyBaseDate($0) },
            onToday: { session.setBaseToday() }
        )
    }
}

/// 首个聚焦声明只落页面当前模式的第一个日期字段（间隔 = 开始日期，
/// 加减 = 基准日期）；声明与请求正交，非目标字段不消费请求。
private struct DateCalculatorConditionalFocusTarget: ViewModifier {
    let active: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            content.workbenchFocusTarget()
        } else {
            content
        }
    }
}

private struct DateCalculatorDateField: View {
    let title: String
    @Binding var input: ControlledDateInput
    let date: Date
    let weekdayText: String
    var autoFocus = false
    var isFocusTarget = false
    let onCommit: (Date) -> Void
    let onInvalidPaste: () -> Void
    let onSelectDate: (Date) -> Void
    let onToday: () -> Void

    @State private var showsCalendar = false

    var body: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.fine) {
            Text(title)
                .font(ToolTypography.buttonSmall)
                .foregroundStyle(ToolTheme.textSecondary)

            HStack(spacing: ToolMetrics.Spacing.sm) {
                IndexControlledDateInput(
                    input: $input,
                    placeholder: "2026-07-06",
                    timeZone: TimeZone.current,
                    autoFocus: autoFocus,
                    trailingInset: 82,
                    onCommit: onCommit,
                    onInvalidPaste: onInvalidPaste
                ) {
                    HStack(spacing: ToolMetrics.Spacing.xxs) {
                        DateCalculatorTodayButton(action: onToday)
                        IndexIconButton(systemImage: "calendar", help: "选择日期") {
                            showsCalendar = true
                        }
                    }
                    .padding(.trailing, ToolMetrics.Spacing.fine)
                }
                .modifier(DateCalculatorConditionalFocusTarget(active: isFocusTarget))
            }

            Text(weekdayText)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .popover(isPresented: $showsCalendar, arrowEdge: .bottom) {
            IndexCalendarView(
                selection: Binding(
                    get: { date },
                    set: { onSelectDate($0) }
                ),
                dismiss: { showsCalendar = false }
            )
            .frame(width: ToolMetrics.Control.calendar)
        }
    }
}

private struct DateCalculatorTodayButton: View {
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text("今天")
                .font(ToolTypography.buttonSmall)
                .foregroundStyle(isHovering ? ToolTheme.textPrimary : ToolTheme.textSecondary)
                .padding(.horizontal, ToolMetrics.Spacing.fine)
                .frame(height: ToolMetrics.Control.small)
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
        }
        .buttonStyle(IndexQuietChromeStyle(look: .bare))
        .accessibilityLabel("设为今天")
        .indexRowHoverBackground(isHovering, cornerRadius: ToolMetrics.CornerRadius.nestedControl)
        .onHover { hovering in
            withToolAnimation(ToolMotion.Preset.controlFeedback) { isHovering = hovering }
        }
        .focused($isFocused)
        .indexFocusRing(active: isFocused, cornerRadius: ToolMetrics.CornerRadius.nestedControl)
    }
}

private struct DateCalculatorInlineOption: View {
    let title: String
    var help: String? = nil
    @Binding var isOn: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        if let help, !help.isEmpty {
            optionLabel.help(help)
        } else {
            optionLabel
        }
    }

    private var optionLabel: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(ToolTypography.icon(ToolMetrics.IconSize.medium, .semibold))
                    .foregroundStyle(isOn ? ToolTheme.accentHover : ToolTheme.textSecondary)
                    .frame(width: ToolMetrics.Control.tiny, height: ToolMetrics.Control.tiny)
                    .toolMotionIconSwap(id: isOn)

                Text(title)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(IndexQuietChromeStyle(look: .bare))
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "开启" : "关闭")
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isOn)
        .focused($isFocused)
        .indexFocusRing(active: isFocused, cornerRadius: ToolMetrics.CornerRadius.nestedControl)
    }
}

private struct DateCalculatorHeroResult: View {
    let value: String
    let subtitle: String
    var footnote: String? = nil

    var body: some View {
        VStack(spacing: ToolMetrics.Spacing.fine) {
            Text(value)
                .font(ToolTypography.heroValue)
                .foregroundStyle(ToolTheme.accentHover)
                .textSelection(.enabled)
                .toolMotionTextSwap(id: value)
            Text(subtitle)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
            if let footnote {
                Text(footnote)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ToolMetrics.Spacing.xxl)
        .indexSurface(.field, fill: ToolTheme.editorBackground, border: ToolTheme.border)
    }
}
