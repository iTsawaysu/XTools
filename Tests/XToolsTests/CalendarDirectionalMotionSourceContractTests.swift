import Foundation
import Testing

struct CalendarDirectionalMotionSourceContractTests {
    @Test func sharedCalendarUsesOneFixedGenerationSafeDirectionalProjection() throws {
        let state = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexCalendarMonthNavigationState.swift")
        let picker = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexDatePicker.swift")

        contains(state, "struct IndexCalendarMonthNavigationState: Equatable", "Calendar month navigation must be testable without rendering SwiftUI")
        contains(state, "generation &+= 1", "Every real month change must advance the transition identity")
        contains(state, "Array(repeating: nil, count: 42)", "Calendar projection must reserve exactly six stable weeks")

        contains(picker, "@State private var navigation: IndexCalendarMonthNavigationState", "The shared calendar must own one local month navigation state")
        contains(picker, "@Environment(\\.accessibilityReduceMotion) private var reduceMotion", "Calendar motion must honor the system Reduce Motion environment")
        contains(picker, "private static let gridHeight: CGFloat = 212", "Six calendar rows must keep a fixed visual height")
        contains(picker, "navigation.navigate(by: -1, calendar: calendar)", "Previous month must declare backward intent")
        contains(picker, "navigation.navigate(by: 1, calendar: calendar)", "Next month must declare forward intent")
        occurrenceCount(picker, "ToolMotion.Transition.orderedContent(orderedDirection)", 2, "Month label and whole grid may each use one shared ordered transition owner")
        occurrenceCount(picker, "ToolMotion.Preset.orderedContent", 2, "Month label and whole grid must use the shared ordered timing")
        contains(picker, ".frame(height: Self.gridHeight)", "Calendar grid motion must not resize the popover")
        contains(picker, "ForEach(Array(navigation.daySlots(calendar: calendar).enumerated()), id: \\.offset)", "Calendar grid must render the fixed 42-slot projection")
        contains(picker, "selection = date", "Date selection must remain immediate")
        contains(picker, "dismiss()", "Selecting a date must keep the existing popover dismissal path")
        doesNotContain(picker, "ToolMotion.Duration.", "Calendar must not introduce a page-local duration")
        doesNotContain(picker, "withAnimation(", "Calendar state updates must route through shared ToolMotion modifiers")
        doesNotContain(picker, "matchedGeometryEffect", "Calendar cells must not animate identity across months")
        doesNotContain(picker, "delay(", "Calendar days must not stagger")
    }
}
