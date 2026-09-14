import SwiftUI

// MARK: - IndexDatePicker

/// Custom date picker styled to match the app's design language. Uses a button
/// that opens a popover with a custom calendar, fully styled to match the theme.
struct IndexDatePicker: View {
    @Binding var selection: Date
    @State private var showPopover = false

    @MainActor private static let dateDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    private func formatted(_ date: Date) -> String {
        Self.dateDisplayFormatter.string(from: date)
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: ToolMetrics.IconSize.medium))
                    .foregroundStyle(ToolTheme.textSecondary)
                Text(formatted(selection))
                    .font(ToolTypography.body)
                    .foregroundStyle(ToolTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: ToolMetrics.IconSize.micro, weight: .semibold))
                    .foregroundStyle(ToolTheme.textTertiary)
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .help("选择日期")
        .accessibilityLabel("选择日期")
        .accessibilityValue(formatted(selection))
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            IndexCalendarView(selection: $selection, dismiss: { showPopover = false })
                .frame(width: 280)
        }
    }
}

// MARK: - IndexCalendarView

/// Custom calendar view styled to match the app's design language.
struct IndexCalendarView: View {
    @Binding var selection: Date
    let dismiss: () -> Void
    @State private var navigation: IndexCalendarMonthNavigationState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let gridHeight: CGFloat = 212

    init(selection: Binding<Date>, dismiss: @escaping () -> Void) {
        _selection = selection
        self.dismiss = dismiss
        _navigation = State(
            initialValue: IndexCalendarMonthNavigationState(
                selection: selection.wrappedValue,
                calendar: .current
            )
        )
    }

    private var calendar: Calendar { Calendar.current }

    @MainActor private static let yearMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年 M月"
        return f
    }()

    private var yearMonth: String {
        Self.yearMonthFormatter.string(from: navigation.displayedMonth)
    }

    private var weekdaySymbols: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    private var orderedDirection: ToolMotion.OrderedDirection {
        switch navigation.direction {
        case .backward:
            return .backward
        case .forward:
            return .forward
        }
    }

    private func isSameDay(_ d1: Date, _ d2: Date) -> Bool {
        calendar.isDate(d1, inSameDayAs: d2)
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IndexCalendarNavButton(systemImage: "chevron.left", help: "上一个月") {
                    navigation.navigate(by: -1, calendar: calendar)
                }

                ZStack {
                    Text(yearMonth)
                        .font(ToolTypography.sectionTitle)
                        .foregroundStyle(ToolTheme.textPrimary)
                        .id(navigation.generation)
                        .toolTransition(
                            ToolMotion.Transition.orderedContent(orderedDirection),
                            reduceMotion: reduceMotion
                        )
                }
                .frame(maxWidth: .infinity)
                .clipped()
                .toolAnimation(ToolMotion.Preset.orderedContent, value: navigation.generation)

                IndexCalendarNavButton(systemImage: "chevron.right", help: "下一个月") {
                    navigation.navigate(by: 1, calendar: calendar)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(ToolTypography.fieldLabel)
                        .foregroundStyle(ToolTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
            }
            .padding(.horizontal, 16)

            ZStack(alignment: .top) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                    ForEach(Array(navigation.daySlots(calendar: calendar).enumerated()), id: \.offset) { _, date in
                        if let date = date {
                            IndexCalendarDayCell(
                                date: date,
                                isSelected: isSameDay(date, selection),
                                isToday: isToday(date)
                            ) {
                                selection = date
                                dismiss()
                            }
                        } else {
                            Color.clear
                                .frame(height: 32)
                        }
                    }
                }
                .id(navigation.generation)
                .toolTransition(
                    ToolMotion.Transition.orderedContent(orderedDirection),
                    reduceMotion: reduceMotion
                )
            }
            .frame(height: Self.gridHeight)
            .clipped()
            .toolAnimation(ToolMotion.Preset.orderedContent, value: navigation.generation)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(ToolTheme.panelBackground)
        .onAppear {
            navigation.reset(to: selection, calendar: calendar)
        }
        .onChange(of: selection) { navigation.reset(to: $0, calendar: calendar) }
    }
}

// MARK: - Calendar subcontrols

/// Month-navigation arrow with shared hover feedback.
private struct IndexCalendarNavButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: ToolMetrics.IconSize.small, weight: .semibold))
                .foregroundStyle(ToolTheme.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    isHovering ? ToolTheme.hoverFill : Color.clear,
                    in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withToolAnimation(ToolMotion.Preset.controlFeedback) { isHovering = hovering }
        }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Single day cell: selected/today/hover states share the app-wide grammar.
private struct IndexCalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void
    @State private var isHovering = false
    private let calendar = Calendar.current

    var body: some View {
        Button(action: action) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: ToolMetrics.IconSize.medium, weight: isSelected ? .semibold : .regular, design: .rounded))
                .foregroundStyle(
                    isSelected ? ToolTheme.onAccent :
                    isToday ? ToolTheme.accentHover :
                    ToolTheme.textPrimary
                )
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    isSelected ? ToolTheme.accent :
                    isHovering ? ToolTheme.hoverFill :
                    isToday ? ToolTheme.accentSoft :
                    Color.clear,
                    in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                )
                .overlay {
                    if !isSelected && isHovering {
                        RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                            .strokeBorder(ToolTheme.selectionStroke, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withToolAnimation(ToolMotion.Preset.controlFeedback) { isHovering = hovering }
        }
        .accessibilityLabel("\(calendar.component(.day, from: date)) 日")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
