import AppKit
import SwiftUI
import XToolsCore

@MainActor
final class DateTimeToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<DateTimeToolWorkspaceModel>(toolID: "date-time-converter") { _ in
        DateTimeToolWorkspaceModel()
    }

    @Published var timestamp: String
    @Published var humanTimeInput: ControlledHumanTimeInput
    @Published var rows: [(String, String, Color?)]
    @Published var timestampError: String?
    @Published var humanError: String?
    @Published var activeDate: Date?
    @Published var suppressNextTimestampChange = false

    init(date: Date = Date()) {
        if let canonicalDate = TimestampInterpreter.canonicalWholeSecondDate(for: date) {
            timestamp = TimestampInterpreter.wholeSecondText(for: canonicalDate) ?? ""
            humanTimeInput = ControlledHumanTimeInput(date: canonicalDate, timeZone: TimeZone.current)
            rows = dateTimeResultRows(for: canonicalDate)
            activeDate = canonicalDate
        } else {
            timestamp = ""
            humanTimeInput = ControlledHumanTimeInput()
            rows = []
            timestampError = TimestampInterpreter.ValidationIssue.outOfRange.errorDescription
            activeDate = nil
        }
    }
}

struct IndexDateTimePage: View {
    var body: some View {
        ToolWorkspaceHost(key: DateTimeToolWorkspaceModel.key) { workspace, _ in
            IndexDateTimeWorkspaceContent(workspace: workspace)
        }
    }
}

private struct IndexDateTimeWorkspaceContent: View {
    @ObservedObject var workspace: DateTimeToolWorkspaceModel

    var body: some View {
        IndexPage("时间戳转换", subtitle: "Unix 时间戳与人类可读时间互转。", layout: .scroll) {
            IndexPanel("Unix 时间戳（秒）") {
                unixTimestampInput
            } accessory: {
                currentTimePageAction
            }
            IndexPanel("人类可读时间（本地时区）") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("日期与时间")
                        .font(ToolTypography.buttonSmall)
                        .foregroundStyle(ToolTheme.textSecondary)

                    humanTimeInputView
                }
                .indexWorkspaceDiagnostic(workspace.humanError)
            }
            IndexPanel("各格式") {
                IndexShortResultKV(rows: workspace.rows, emptyText: IndexEmptyStateCopy.autoCalculate("时间戳或时间"), valueMotion: .immediate)
            } accessory: {
                HStack(spacing: 8) {
                    clearAllButton
                    IndexCopyButton(text: allRowsText, title: "全部复制")
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .withoutDiagnosticStatusSlot()
        }
    }

    private var unixTimestampInput: some View {
        IndexTextInput(
            placeholder: "例如 1718900000",
            text: $workspace.timestamp,
            onSubmit: parseTimestamp
        )
            .onChange(of: workspace.timestamp) { _ in
                handleTimestampChange()
            }
            .indexWorkspaceDiagnostic(workspace.timestampError)
    }

    private var humanTimeInputView: some View {
        IndexControlledHumanTimeInput(
            input: $workspace.humanTimeInput,
            placeholder: "选择或粘贴时间",
            timeZone: TimeZone.current,
            onCommit: applyFromHumanTimeInput,
            onInvalidPaste: showHumanPasteError
        )
    }

    private func handleTimestampChange() {
        guard !workspace.suppressNextTimestampChange else {
            workspace.suppressNextTimestampChange = false
            return
        }

        parseTimestamp()
    }

    private func parseTimestamp() {
        switch TimestampInterpreter.evaluate(workspace.timestamp) {
        case .empty, .incomplete:
            workspace.timestampError = nil
        case .invalid(let issue):
            workspace.timestampError = issue.errorDescription
            workspace.rows = []
            workspace.activeDate = nil
        case .valid(let seconds):
            apply(Date(timeIntervalSince1970: seconds), timestampText: workspace.timestamp.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private var allRowsText: String {
        workspace.rows.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
    }

    private var currentTimePageAction: some View {
        Button(action: applyCurrentTime) {
            Label("现在", systemImage: "clock")
                .font(ToolTypography.buttonSmall)
        }
        .buttonStyle(IndexSmallButtonStyle())
        .help("使用当前时间")
        .accessibilityLabel("使用当前时间")
        .fixedSize(horizontal: true, vertical: false)
    }

    private func applyCurrentTime() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        apply(Date())
    }

    private var clearAllButton: some View {
        Button(action: clearAll) {
            Label("全部清空", systemImage: IndexActionSymbol.clear)
                .font(ToolTypography.buttonSmall)
        }
        .buttonStyle(IndexSmallButtonStyle())
        .disabled(workspace.timestamp.isEmpty && workspace.humanTimeInput.isEmpty && workspace.rows.isEmpty && workspace.timestampError == nil && workspace.humanError == nil)
        .help("全部清空")
        .accessibilityLabel("全部清空")
    }

    private func applyFromHumanTimeInput(_ date: Date) {
        apply(date, updateHumanInput: false)
    }

    private func showHumanPasteError() {
        workspace.humanError = "无法识别时间。支持 ISO 8601 或 yyyy-MM-dd HH:mm:ss。"
    }

    private func clearAll() {
        workspace.timestamp = ""
        workspace.humanTimeInput.clear()
        workspace.rows = []
        workspace.timestampError = nil
        workspace.humanError = nil
        workspace.activeDate = nil
        workspace.suppressNextTimestampChange = false
    }

    private func apply(_ date: Date, timestampText: String? = nil, updateHumanInput: Bool = true) {
        guard let canonicalDate = TimestampInterpreter.canonicalWholeSecondDate(for: date),
              let secondsText = TimestampInterpreter.wholeSecondText(for: canonicalDate),
              let millisecondsText = TimestampInterpreter.millisecondText(for: canonicalDate) else {
            workspace.timestampError = TimestampInterpreter.ValidationIssue.outOfRange.errorDescription
            return
        }

        workspace.timestampError = nil
        workspace.humanError = nil
        workspace.activeDate = canonicalDate

        let nextTimestamp = timestampText ?? secondsText
        if workspace.timestamp != nextTimestamp {
            workspace.suppressNextTimestampChange = true
            workspace.timestamp = nextTimestamp
        }

        if updateHumanInput {
            workspace.humanTimeInput.replace(with: canonicalDate, timeZone: TimeZone.current)
        }

        workspace.rows = dateTimeResultRows(
            for: canonicalDate,
            secondsText: secondsText,
            millisecondsText: millisecondsText
        )
    }

}

private func dateTimeResultRows(for date: Date) -> [(String, String, Color?)] {
    guard let secondsText = TimestampInterpreter.wholeSecondText(for: date),
          let millisecondsText = TimestampInterpreter.millisecondText(for: date) else {
        return []
    }

    return dateTimeResultRows(for: date, secondsText: secondsText, millisecondsText: millisecondsText)
}

private func dateTimeResultRows(
    for date: Date,
    secondsText: String,
    millisecondsText: String
) -> [(String, String, Color?)] {
    let localHuman = HumanDateTimeConversion.string(from: date, timeZone: TimeZone.current)

    return [
        ("Unix 秒", secondsText, nil),
        ("Unix 毫秒", millisecondsText, nil),
        ("ISO 8601", ISO8601DateFormatter().string(from: date), nil),
        ("人类时间（本地）", localHuman, nil),
        ("本地时间", dateTimeLocalDisplayText(for: date), nil),
        ("UTC", dateTimeUTCDisplayText(for: date), nil)
    ]
}

private func dateTimeLocalDisplayText(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter.string(from: date)
}

private func dateTimeUTCDisplayText(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    return formatter.string(from: date)
}
