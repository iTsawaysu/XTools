import SwiftUI
import XToolsCore

// Shared date-entry field: label, controlled text input, calendar popover and
// today shortcut. Domain pages supply the binding and commit callbacks.

struct ToolDateField: View {
    let title: String
    @Binding var input: ControlledDateInput
    let date: Date
    let weekdayText: String
    var autoFocus = false
    let onCommit: (Date) -> Void
    let onInvalidPaste: () -> Void
    let onSelectDate: (Date) -> Void
    let onToday: () -> Void

    @State private var showsCalendar = false

    var body: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
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
                        ToolButton("今天", role: .quiet, size: .compact28, help: "设为今天", action: onToday)
                        IndexIconButton(systemImage: "calendar", help: "选择日期") {
                            showsCalendar = true
                        }
                    }
                    .padding(.trailing, 6)
                }
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
            .frame(width: 280)
        }
    }
}
