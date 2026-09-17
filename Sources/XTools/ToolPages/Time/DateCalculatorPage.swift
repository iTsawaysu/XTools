import XToolsCore
import SwiftUI

@MainActor
final class DateCalcToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<DateCalcToolWorkspaceModel>(toolID: "date-calculator") { _ in
        DateCalcToolWorkspaceModel()
    }

    @Published var session = DateCalcWorkspace()
}

struct IndexDateCalcPage: View {
    var body: some View {
        ToolWorkspaceHost(key: DateCalcToolWorkspaceModel.key) { _, bindings in
            IndexDateCalcWorkspaceContent(session: bindings.session)
        }
    }
}

private struct IndexDateCalcWorkspaceContent: View {
    @Binding var session: DateCalcWorkspace

    private var detailRows: [(String, String, Color?)] {
        let absDays = abs(session.totals.days)
        return [
            ("周数+天数", "\(absDays / 7) 周 \(absDays % 7) 天", nil),
            ("总小时", "\(abs(session.totals.hours)) 小时", nil),
            ("总分钟", "\(abs(session.totals.minutes)) 分钟", nil),
            ("方向", session.direction, nil)
        ]
    }

    private var totalDaysText: String {
        session.totalDaysText
    }

    private var diffError: String? {
        session.diffError
    }

    private var resultDateText: String {
        session.resultDateText
    }

    private var resultWeekdayText: String {
        session.resultWeekdayText
    }

    private var resultCopyText: String {
        session.resultCopyText
    }

    private var breakdownStats: [(String, String)] {
        session.breakdownStats
    }

    var body: some View {
        IndexPage("日期计算", subtitle: "计算两个日期之间的间隔，或在某个日期上加减时间。", layout: .scroll) {
            IndexPanel("两日期间隔") {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("常用范围")
                            .font(ToolTypography.buttonSmall)
                            .foregroundStyle(ToolTheme.textSecondary)
                        IndexFlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(DateCalcWorkspace.DiffPreset.allCases, id: \.rawValue) { preset in
                                IndexBadge(preset.title) {
                                    session.applyPreset(preset)
                                }
                            }
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            startField()
                            endField()
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            startField()
                            endField()
                        }
                    }

                    DateCalculatorInlineOption(
                        title: "包含结束日（+1 天）",
                        isOn: $session.includeEndDate
                    )

                    DateCalculatorHeroResult(
                        value: totalDaysText,
                        subtitle: "总天数"
                    )

                    IndexStatGrid(stats: breakdownStats, valueMotion: .immediate)
                    IndexKV(rows: detailRows, copyable: false, valueMotion: .immediate)
                }
                .indexWorkspaceDiagnostic(diffError)
            } accessory: {
                IndexCopyButton(text: totalDaysText, title: "复制总天数")
            }

            IndexPanel("日期加减") {
                VStack(alignment: .leading, spacing: 14) {
                    baseField()

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            addControls
                            Spacer(minLength: 0)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            addControls
                        }
                    }

                    DateCalculatorHeroResult(
                        value: resultDateText,
                        subtitle: resultWeekdayText
                    )
                }
                .indexWorkspaceDiagnostic(session.baseInputError)
            } accessory: {
                IndexCopyButton(text: resultCopyText)
            }
        }
    }

    @ViewBuilder
    private func startField(autoFocus: Bool = false) -> some View {
        DateCalculatorDateField(
            title: "开始日期",
            input: $session.startInput,
            date: session.start,
            autoFocus: autoFocus,
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
            onCommit: { session.commitBaseInputDate($0) },
            onInvalidPaste: { session.markBaseInvalidPaste() },
            onSelectDate: { session.applyBaseDate($0) },
            onToday: { session.setBaseToday() }
        )
    }

    @ViewBuilder
    private var addControls: some View {
        IndexSegmentedControl(
            items: [("1", "加"), ("-1", "减")],
            selection: $session.op
        )
        .frame(width: 100)

        IndexNumberInput(value: $session.amount, range: 0...100_000, fieldWidth: 56)

        IndexSegmentedControl(
            items: DateCalcEngine.Unit.allCases.map { ($0.rawValue, $0.label) },
            selection: Binding(
                get: { session.unit.rawValue },
                set: { session.unit = DateCalcEngine.Unit(rawValue: $0) ?? .day }
            )
        )
    }
}

private struct DateCalculatorDateField: View {
    let title: String
    @Binding var input: ControlledDateInput
    let date: Date
    var autoFocus = false
    let onCommit: (Date) -> Void
    let onInvalidPaste: () -> Void
    let onSelectDate: (Date) -> Void
    let onToday: () -> Void

    @State private var showsCalendar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ToolTypography.buttonSmall)
                .foregroundStyle(ToolTheme.textSecondary)

            HStack(spacing: 8) {
                IndexControlledDateInput(
                    input: $input,
                    placeholder: "2026-07-06",
                    timeZone: TimeZone.current,
                    autoFocus: autoFocus,
                    trailingInset: 82,
                    onCommit: onCommit,
                    onInvalidPaste: onInvalidPaste
                ) {
                    HStack(spacing: 2) {
                        DateCalculatorTodayButton(action: onToday)
                        IndexIconButton(systemImage: "calendar", help: "选择日期") {
                            showsCalendar = true
                        }
                    }
                    .padding(.trailing, 6)
                }
            }
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
            .frame(width: 280)
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
                .padding(.horizontal, 6)
                .frame(height: 24)
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
        }
        .buttonStyle(IndexBareButtonStyle())
        .help("设为今天")
        .accessibilityLabel("设为今天")
        .background(
            isHovering ? ToolTheme.hoverFill : Color.clear,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
        )
        .onHover { hovering in
            withToolAnimation(ToolMotion.Preset.controlFeedback) { isHovering = hovering }
        }
        .focused($isFocused)
        .indexFocusRing(active: isFocused, cornerRadius: ToolMetrics.CornerRadius.nestedControl)
    }
}

private struct DateCalculatorInlineOption: View {
    let title: String
    @Binding var isOn: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: ToolMetrics.IconSize.medium, weight: .semibold))
                    .foregroundStyle(isOn ? ToolTheme.accentHover : ToolTheme.textSecondary)
                    .frame(width: 16, height: 16)
                    .toolMotionIconSwap(id: isOn)

                Text(title)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(IndexBareButtonStyle())
        .help("包含首尾日期")
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

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(ToolTypography.heroValue)
                .foregroundStyle(ToolTheme.accentHover)
                .textSelection(.enabled)
                .toolMotionTextSwap(id: value)
            Text(subtitle)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .indexSurface(.field, fill: ToolTheme.editorBackground, border: ToolTheme.border)
    }
}
