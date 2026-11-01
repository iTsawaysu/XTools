import XToolsCore
import SwiftUI

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

    var body: some View {
        IndexPage("日期计算", subtitle: "计算两个日期之间的间隔，或在某个日期上加减时间。", layout: .scroll) {
            IndexSegmentedControl(
                items: DateCalcToolWorkspaceModel.Mode.allCases.map { ($0, $0.title) },
                selection: $mode
            )

            IndexModeContent(id: mode) { currentMode in
                switch currentMode {
                case .interval:
                    intervalPanel
                case .offset:
                    offsetPanel
                }
            }
        }
    }

    // MARK: - Interval mode

    private var intervalPanel: some View {
        IndexPanel(mode.panelTitle) {
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

                IndexOptionSwitch(title: "包含结束日", style: .checkbox, isOn: $session.includeEndDate)
                    .indexTooltip("把结束日期当天也计入结果（+1 天）", wantsVisibleBubble: false)

                DateCalculatorHeroResult(
                    value: session.totalDaysText,
                    subtitle: session.direction
                )

                IndexStatGrid(stats: session.breakdownStats, valueMotion: .immediate)
                IndexKV(rows: intervalDetailRows, copyable: false, valueMotion: .immediate)
            }
            .indexWorkspaceDiagnostic(session.diffError)
        } accessory: {
            ToolCopyButton(text: session.totalDaysText, title: "复制总天数")
        }
    }

    // MARK: - Offset mode

    private var offsetPanel: some View {
        IndexPanel(mode.panelTitle) {
            VStack(alignment: .leading, spacing: 14) {
                baseField()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        offsetControls
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        offsetControls
                    }
                }

                DateCalculatorHeroResult(
                    value: session.resultDateText,
                    subtitle: session.resultWeekdayText,
                    footnote: session.resultRelativeToTodayText()
                )
            }
            .indexWorkspaceDiagnostic(session.baseInputError)
        } accessory: {
            ToolCopyButton(text: session.resultCopyText)
        }
    }

    @ViewBuilder
    private var offsetControls: some View {
        IndexSegmentedControl(
            items: DateCalcWorkspace.Op.allCases.map { ($0, $0.label) },
            selection: $session.op
        )
        .frame(width: 100)

        IndexNumberInput(value: $session.amount, range: 0...100_000, fieldWidth: 56)

        IndexSegmentedControl(
            items: DateCalcEngine.Unit.allCases.map { ($0, $0.label) },
            selection: $session.unit
        )
    }

    // MARK: - Date fields

    @ViewBuilder
    private func startField() -> some View {
        ToolDateField(
            title: "开始日期",
            input: $session.startInput,
            date: session.start,
            weekdayText: session.startWeekdayText,
            onCommit: { session.commitStartInputDate($0) },
            onInvalidPaste: { session.markStartInvalidPaste() },
            onSelectDate: { session.applyStartDate($0) },
            onToday: { session.setStartToday() }
        )
    }

    @ViewBuilder
    private func endField() -> some View {
        ToolDateField(
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
        ToolDateField(
            title: "基准日期",
            input: $session.baseInput,
            date: session.base,
            weekdayText: session.baseWeekdayText,
            onCommit: { session.commitBaseInputDate($0) },
            onInvalidPaste: { session.markBaseInvalidPaste() },
            onSelectDate: { session.applyBaseDate($0) },
            onToday: { session.setBaseToday() }
        )
    }
}

private struct DateCalculatorHeroResult: View {
    let value: String
    let subtitle: String
    var footnote: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(ToolTypography.heroValue)
                .foregroundStyle(ToolTheme.accentHover)
                .textSelection(.enabled)
                .arrowCursorOnHover()
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
        .padding(.vertical, 20)
        .indexSurface(.field, fill: ToolTheme.editorBackground, border: ToolTheme.border)
    }
}
