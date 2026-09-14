import Foundation
import AppKit
@testable import XTools
import Testing

struct TimeAndDateSourceContractTests {
    @Test func timezoneViewerFavoritesAndRegionsShareDisclosureContract() throws {
        let timezone = try readSource("Sources/XTools/ToolPages/Time/TimezoneViewerPage.swift")
        let timezoneProjection = try readSource("Sources/XTools/ToolPages/Time/TimezoneViewerProjection.swift")
        let disclosureStore = try readSource("Sources/XTools/Shared/DisclosureExpansionStore.swift")
        let typography = try readSource("Sources/XTools/Shared/ToolTypography.swift")

        contains(timezone, "subtitle: \"显示精选全球城市的当前时间，按大洲折叠并按 UTC 偏移量分组。\"", "Timezone viewer must describe its curated city catalog without implying complete global coverage")
        doesNotContain(timezone, "显示全球各地区时区的当前时间", "Timezone viewer must not overstate the curated catalog as complete global timezone coverage")
        contains(timezone, "final class TimezoneViewerDisclosureExpansionStore: PersistentDisclosureExpansionStore", "Timezone viewer disclosure state must reuse the app's collapsed-id persistence pattern")
        contains(timezone, "static let storageKey = \"tools.timezoneViewer.collapsedSections.v1\"", "Timezone viewer disclosure state must persist under a versioned page preference key")
        contains(timezone, "@StateObject private var disclosureSections = TimezoneViewerDisclosureExpansionStore()", "Timezone viewer must own disclosure state as page UI state")
        contains(disclosureStore, "class PersistentDisclosureExpansionStore: ObservableObject", "Disclosure persistence must be shared instead of copied into the timezone page")
        contains(disclosureStore, "@Published private(set) var collapsedGroupIDs: Set<String>", "Shared disclosure persistence must store collapsed ids so new sections default expanded")
        contains(disclosureStore, "defaults.set(collapsedGroupIDs.sorted(), forKey: storageKey)", "Shared disclosure persistence must write stable collapsed-id arrays")
        contains(timezone, "final class TimezoneViewerFavoriteStore: ObservableObject", "Timezone favorites must be owned by a persistent page store")
        contains(timezone, "static let storageKey = \"tools.timezoneViewer.favorites.v1\"", "Timezone favorites must persist under a versioned page preference key")
        contains(timezone, "@Published private(set) var favoriteKeys: Set<String>", "Timezone favorite keys must be observable persisted state")
        contains(timezone, "@StateObject private var favoriteStore = TimezoneViewerFavoriteStore()", "Timezone page must keep favorites across tool switching through a state object")
        contains(timezone, "defaults.set(favoriteKeys.sorted(), forKey: Self.storageKey)", "Timezone favorite persistence must write stable arrays")
        contains(timezone, "if favoriteStore.toggle(keys: keys) {\n            disclosureSections.expand(Self.favoritesDisclosureID)\n        }", "Favoriting a timezone group must persist it and reveal the favorites section")
        doesNotContain(timezone, "@State private var favoriteKeys: Set<String>", "Timezone favorites must not be local view state that resets when switching tools")

        contains(timezoneProjection, "enum TimezoneCityCatalog", "Timezone static city catalog must live outside the SwiftUI page rendering owner")
        contains(timezoneProjection, "static let defaultRegions: [TimezoneRegion]", "Timezone default region catalog must have one named owner")
        contains(timezoneProjection, "struct TimezoneViewerProjection", "Timezone favorite and visible-region projections must have one named pure owner")
        contains(timezoneProjection, "regions: [TimezoneRegion] = TimezoneCityCatalog.defaultRegions", "Timezone projection must default to the shared catalog instead of page-local static data")
        contains(timezoneProjection, "info.timezone.secondsFromGMT(for: date)", "Timezone grouping must keep date-sensitive UTC offset semantics")
        contains(timezone, "let projection = TimezoneViewerProjection(favoriteKeys: favoriteStore.favoriteKeys, date: currentTime)", "Timezone page must render the catalog projection instead of owning catalog construction")
        contains(timezone, "let favorites = projection.favoriteGroups", "Timezone page must read favorite groups from the projection")
        contains(timezone, "ForEach(projection.visibleRegions) { regionGroup in", "Timezone page must read visible region groups from the projection")
        doesNotContain(timezone, "private static let timezonesByRegion", "Timezone page must not own the static city catalog")
        doesNotContain(timezone, "enum TimezoneViewerLogic", "Timezone page must not own timezone grouping logic")
        doesNotContain(timezone, "struct TimezoneInfo", "Timezone page must not own timezone domain record definitions")

        contains(timezone, "if !favorites.isEmpty {\n                            timezoneDisclosureSection(", "Favorites must render only when non-empty and must use a disclosure header")
        contains(timezone, "sectionID: Self.favoritesDisclosureID,\n                                title: \"收藏\"", "Favorites must keep a global favorites section instead of becoming a normal region")
        contains(timezone, "ForEach(favorites) { group in", "Favorites must keep rendering the existing global UTC-offset favorite groups")
        doesNotContain(timezone, "Text(\"收藏\")\n                                    .font", "Favorites must not keep a plain non-disclosure header")

        contains(timezone, "sectionID: Self.regionDisclosureID(regionGroup.region)", "Normal continent sections must use the same disclosure section helper")
        contains(timezone, "private func timezoneDisclosureSection<Content: View>", "Timezone disclosure sections must have one shared section helper")
        occurrenceCount(timezone, "timezoneDisclosureSection(", 2, "Favorites and normal regions must share the same disclosure section contract")
        contains(timezone, "IndexDisclosure(", "Timezone disclosure sections must delegate to the shared disclosure component")
        contains(timezone, ".inline()", "Timezone disclosures must stay inline inside the owning panel")
        doesNotContain(timezone, "private struct TimezoneDisclosureHeader: View", "Timezone must not hand-roll a local disclosure header")
        contains(typography, "static let sectionTitle = Font.system(size: 14, weight: .semibold)", "Timezone section hierarchy must use one static semantic typography token")
        contains(timezone, "title: title,", "Timezone disclosure titles must flow through the shared component API")
        doesNotContain(timezone, #"detail: "\(favorites.reduce(0) { $0 + $1.cities.count }) 城市""#, "Favorites disclosure must not show a dynamic city count beside its title")
        doesNotContain(timezone, #"detail: "\(regionGroup.cityCount) 城市""#, "Continent disclosures must not show dynamic remaining-city counts")
        doesNotContain(timezone, "let detail: String?", "Timezone disclosure headers must not keep an unused count-detail slot")
        doesNotContain(timezone, "Image(systemName: isExpanded ? \"chevron.down\" : \"chevron.right\")", "Timezone region disclosure must not keep the older glyph-swapping header")
        doesNotContain(timezone, "@State private var expandedRegions", "Timezone page must not keep a second disclosure-state standard for continent sections")

        contains(timezone, "if favoriteStore.toggle(keys: keys) {\n            disclosureSections.expand(Self.favoritesDisclosureID)\n        }", "Favoriting from the normal list must persist and auto-expand the favorites disclosure")
        contains(timezone, "if keys.isSubset(of: favoriteKeys) {\n            favoriteKeys.subtract(keys)", "Unfavoriting must remove the favorite keys so an empty favorites section disappears instead of leaving a shell")
    }

    @Test func dateAndTimestampPagesUseScrollableLayout() throws {
        let dateCalculator = try readSource("Sources/XTools/ToolPages/Time/DateCalculatorPage.swift")
        let timestampConverter = try readSource("Sources/XTools/ToolPages/Time/DateTimeConverterPage.swift")

        contains(dateCalculator, "IndexPage(\"日期计算\", subtitle: \"计算两个日期之间的间隔，或在某个日期上加减时间。\", layout: .scroll)", "Date calculator must scroll at the minimum window size")
        contains(timestampConverter, "IndexPage(\"时间戳转换\", subtitle: \"Unix 时间戳与人类可读时间互转。\", layout: .scroll)", "Timestamp converter must scroll at the minimum window size")
    }

    @Test func dateCalculatorUsesEditableDateFieldsAndExplicitInclusiveOption() throws {
        let dateCalculator = try readSource("Sources/XTools/ToolPages/Time/DateCalculatorPage.swift")
        let workspace = try readSource("Sources/XToolsCore/Time/DateCalcWorkspace.swift")
        let controlledInput = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControlledSegmentInput.swift")

        // Page binds Core field session; orchestration lives in DateCalcWorkspace (behavior-tested).
        contains(dateCalculator, "ToolWorkspaceHost(key: DateCalcToolWorkspaceModel.key)", "Date calculator must resolve its retained Core field session")
        contains(dateCalculator, "@Binding var session: DateCalcWorkspace", "Date calculator visible content must bind the retained Core field session")
        contains(dateCalculator, "$session.startInput", "Date calculator must bind controlled start-date text state through the session")
        contains(dateCalculator, "$session.endInput", "Date calculator must bind controlled end-date text state through the session")
        contains(dateCalculator, "$session.baseInput", "Date calculator must bind controlled base-date text state through the session")
        contains(dateCalculator, "$session.includeEndDate", "Date calculator must bind the inclusive-end toggle through the session")
        contains(dateCalculator, "DateCalculatorInlineOption(\n                        title: \"包含结束日（+1 天）\",", "Date calculator must expose a lightweight explicit inclusive-end option")
        contains(workspace, "DateCalcEngine.totals(from: start, to: end, calendar: cal, includeEndDate: includeEndDate)", "Date calculator session must route totals through inclusive/exclusive mode")
        contains(workspace, "DateCalcEngine.breakdown(from: start, to: end, calendar: cal, includeEndDate: includeEndDate)", "Date calculator session must route breakdown through inclusive/exclusive mode")
        contains(dateCalculator, "struct DateCalculatorDateField: View", "Date calculator must use a dedicated editable date-field surface instead of a decorative arrow row")
        contains(dateCalculator, "IndexControlledDateInput(", "Date calculator date fields must use the shared controlled segmented date editor")
        contains(dateCalculator, "onCommit: { session.commitStartInputDate($0) }", "Start-date segment commits must delegate to the session without external replace")
        contains(dateCalculator, "onCommit: { session.commitEndInputDate($0) }", "End-date segment commits must delegate to the session without external replace")
        contains(dateCalculator, "onCommit: { session.commitBaseInputDate($0) }", "Base-date segment commits must delegate to the session without external replace")
        contains(workspace, "public mutating func commitStartInputDate(_ date: Date)", "Session commitStart must update results without replacing the active input state")
        contains(workspace, "public mutating func commitEndInputDate(_ date: Date)", "Session commitEnd must update results without replacing the active input state")
        contains(workspace, "public mutating func commitBaseInputDate(_ date: Date)", "Session commitBase must update results without replacing the active input state")
        contains(workspace, "start = normalized(date)\n        startInputError = nil", "Start commit must clear error without replace")
        contains(workspace, "end = normalized(date)\n        endInputError = nil", "End commit must clear error without replace")
        contains(workspace, "base = normalized(date)\n        baseInputError = nil", "Base commit must clear error without replace")
        contains(dateCalculator, "placeholder: \"2026-07-06\"", "Date calculator editable date fields must guide the normalized date format")
        contains(dateCalculator, "trailingInset: 82", "Date calculator editable date fields must reserve space for embedded field actions")
        contains(dateCalculator, "DateCalculatorTodayButton(action: onToday)", "Date calculator Today actions must be embedded inside the date field")
        contains(dateCalculator, "IndexCalendarView(", "Date calculator editable fields must keep calendar selection as an auxiliary path")
        contains(controlledInput, "input.wrappedValue.inputCharacter(character, timeZone: timeZone)", "Date calculator keyboard input must route through the shared controlled date model adapter")
        contains(controlledInput, "input.wrappedValue.paste(text, timeZone: timeZone)", "Date calculator paste validation must route through the shared controlled date model adapter")
        contains(controlledInput, "struct IndexControlledDateInput", "Shared controlled input must expose a date-only wrapper")
        contains(dateCalculator, "DateCalculatorHeroResult(\n                        value: totalDaysText,\n                        subtitle: \"总天数\"", "Date calculator must promote total days to the primary result")
        contains(dateCalculator, "IndexCopyButton(text: totalDaysText, title: \"复制总天数\")", "Date calculator must keep the primary day-count result copyable")
        contains(workspace, "case next7Days", "Date calculator session must own the four visible range presets")
        contains(workspace, "return \"未来 7 天\"", "Date calculator session must keep the 7-day preset title")
        doesNotContain(dateCalculator, "Text(\"→\")", "Date calculator must not keep the decorative arrow as a layout crutch")
        doesNotContain(dateCalculator, "Button(\"今天\", action: onToday)", "Date calculator Today actions must not sit as separate buttons outside date inputs")
        doesNotContain(dateCalculator, "IndexTextInput(\n                    placeholder: \"2026-07-06\"", "Date calculator date editing must not use unrestricted single-line text input")
        doesNotContain(dateCalculator, "onCommit: applyStartDate", "Start-date segment commits must not call the external replacement path")
        doesNotContain(dateCalculator, "onCommit: applyEndDate", "End-date segment commits must not call the external replacement path")
        doesNotContain(dateCalculator, "onCommit: applyBaseDate", "Base-date segment commits must not call the external replacement path")
        doesNotContain(dateCalculator, "ControlledDateInputRepresentable", "Date calculator must not keep a page-local AppKit date bridge")
        doesNotContain(dateCalculator, "ControlledDateNSTextField", "Date calculator must not keep a page-local AppKit date text field")
        doesNotContain(dateCalculator, "\"未来 90 天\"", "Date calculator must remove the low-frequency 90-day preset from the visible range shortcuts")
        doesNotContain(workspace, "\"未来 90 天\"", "Date calculator session must not reintroduce the 90-day preset")
        doesNotContain(dateCalculator, "IndexDatePicker(selection: $start)", "Date calculator start date must no longer be picker-only")
        doesNotContain(dateCalculator, "IndexDatePicker(selection: $end)", "Date calculator end date must no longer be picker-only")
        doesNotContain(dateCalculator, "IndexDatePicker(selection: $base)", "Date calculator base date must no longer be picker-only")
        doesNotContain(dateCalculator, "IndexDatePicker(selection: $session.start)", "Date calculator must not reintroduce picker-only start binding on session")
        doesNotContain(dateCalculator, "IndexDatePicker(selection: $session.end)", "Date calculator must not reintroduce picker-only end binding on session")
        doesNotContain(dateCalculator, "IndexDatePicker(selection: $session.base)", "Date calculator must not reintroduce picker-only base binding on session")
    }

    @Test func timestampConverterUsesControlledHumanTimeAndUnixSecondsOnly() throws {
        let timestampConverter = try readSource("Sources/XTools/ToolPages/Time/DateTimeConverterPage.swift")
        let controlledInput = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControlledSegmentInput.swift")
        let controlledSurface = sourceSlice(
            controlledInput,
            from: "private struct IndexControlledSegmentInput<TrailingAccessory: View>: View",
            to: "private enum IndexControlledSegmentPasteResult"
        )

        contains(timestampConverter, "@Published var humanTimeInput: ControlledHumanTimeInput", "Timestamp human-time editor must use the controlled segment state")
        occurrenceCount(timestampConverter, "TimestampInterpreter.canonicalWholeSecondDate(for: date)", 2, "Timestamp initialization and apply must share one Core whole-second canonicalization path")
        contains(timestampConverter, "humanTimeInput = ControlledHumanTimeInput(date: canonicalDate, timeZone: TimeZone.current)", "Timestamp converter should seed the controlled editor from the canonical local second")
        contains(timestampConverter, "rows = dateTimeResultRows(for: canonicalDate)", "Timestamp converter must open with rows derived from the canonical second")
        contains(timestampConverter, "workspace.activeDate = canonicalDate", "Timestamp apply must retain the same canonical second used by every result row")
        doesNotContain(timestampConverter, ".rounded(.towardZero)", "Timestamp page must delegate whole-second precision to Core instead of copying its rounding contract")
        contains(timestampConverter, "IndexPanel(\"Unix 时间戳（秒）\")", "Unix input panel must be seconds-only")
        doesNotContain(timestampConverter, "autoFocus: true", "Timestamp converter must not auto-focus the Unix seconds input because AppKit can select the seeded value")
        doesNotContain(timestampConverter, "selectAllOnFocus: true", "Unix seconds input must never opt into selecting the whole current timestamp")
        contains(timestampConverter, "TimestampInterpreter.evaluate(workspace.timestamp)", "Timestamp parsing must route through the typed Core input-state interpreter")
        doesNotContain(timestampConverter, "TimestampInterpreter.filteredIntegerSecondsText(timestamp)", "Timestamp editing must not silently extract digits from invalid pasted content")
        contains(timestampConverter, "IndexControlledHumanTimeInput(", "Timestamp page must render the shared controlled human-time input")
        contains(timestampConverter, "IndexPanel(\"人类可读时间（本地时区）\")", "Timestamp human-time input must expose its local-timezone interpretation beside the field")
        doesNotContain(timestampConverter, "IndexPanel(\"人类可读时间\")", "Timestamp human-time input must not keep the timezone-ambiguous panel title")
        contains(timestampConverter, "placeholder: \"选择或粘贴时间\"", "Controlled human-time input must use the approved compact placeholder")
        contains(timestampConverter, "private func applyFromHumanTimeInput(_ date: Date) {\n        apply(date, updateHumanInput: false)\n    }", "Human-time segment commits must update results without replacing the active controlled input state")
        contains(timestampConverter, "private var unixTimestampInput: some View", "Unix timestamp input remains a dedicated panel body view")
        doesNotContain(timestampConverter, "timestampClearTrailingInset", "Unix timestamp input must not reserve space for an in-field clear button")
        doesNotContain(timestampConverter, "IndexClearButton", "Unix timestamp input must not show an in-field clear button")
        doesNotContain(timestampConverter, "clearUnixInput", "Unix timestamp page must not keep a dedicated in-field clear action")
        contains(timestampConverter, "IndexPanel(\"Unix 时间戳（秒）\") {\n                unixTimestampInput\n            } accessory: {\n                currentTimePageAction\n            }", "Current time action must live in the Unix panel title row as a page-level time-source action")
        contains(timestampConverter, "private var humanTimeInputView: some View", "Complete Time input must be a named local control")
        contains(timestampConverter, "private var currentTimePageAction: some View", "Current time action must be named as a page-level action")
        doesNotContain(timestampConverter, "private var humanTimeCopyAction: some View", "Human-time input must not keep a duplicate local copy action")
        doesNotContain(timestampConverter, "trailingInset: humanTimeNowTrailingInset", "Human-time input must not reserve an in-field slot for the page-level Now action")
        doesNotContain(timestampConverter, "currentTimeInputAction", "Current time action must no longer be modeled as an input-scoped action")
        doesNotContain(timestampConverter, "IndexCopyButton(text: activeHumanText, title: \"复制时间\")", "Human-time copy must be removed from the input panel")
        appearsBefore(timestampConverter, "Text(\"日期与时间\")", "IndexControlledHumanTimeInput(", "Date and Time title row must stay above the segmented local-time input")
        doesNotContain(timestampConverter, "Text(\"完整时间\")", "Timestamp input must not keep the ambiguous Complete Time field label")
        contains(controlledInput, "input.wrappedValue.commitActiveSegment(timeZone: timeZone)", "Controlled human-time input must commit segment edits through Core")
        contains(controlledInput, "input.wrappedValue.inputCharacter(character, timeZone: timeZone)", "Controlled human-time input must route character handling through Core")
        contains(controlledInput, "input.wrappedValue.paste(text, timeZone: timeZone)", "Controlled human-time paste must route through Core parsing")
        contains(controlledInput, "override func mouseDown(with event: NSEvent)", "Controlled segmented field editor must route mouse clicks while the field is already editing")
        contains(controlledInput, "let wasEditing = currentEditor() != nil", "Controlled segmented text field must detect clicks that occur while a field editor is already active")
        contains(controlledInput, "if wasEditing {", "Controlled segmented text fields must distinguish inset clicks from first-click setup")
        contains(controlledInput, "segmentHandler?.handleClick(atDisplayOffset: offset, in: self)\n            return", "Editing-time inset clicks must route synchronously without scheduling a stale first-click callback")
        contains(controlledInput, "let singleLinePoint = NSPoint(x: editorPoint.x, y: editor.bounds.midY)", "Controlled segmented edge clicks must project only their vertical coordinate into the single-line editor")
        contains(controlledInput, "editor.characterIndexForInsertion(at: singleLinePoint)", "Controlled segmented inset clicks must use native TextKit insertion mapping instead of estimating character widths")
        contains(controlledInput, "let offset = selectedRange.location", "Controlled segmented click selection must read the native field-editor insertion location after AppKit handles the click")
        contains(controlledInput, "handleClick(atDisplayOffset: offset, in: textField)", "Controlled segmented clicks must update the Core active segment before the next key press")
        contains(controlledInput, "final class IndexControlledSegmentFieldEditor: NSTextView", "Controlled segmented fields must intercept keys in the real AppKit field editor")
        contains(controlledInput, "override func keyDown(with event: NSEvent)", "Controlled segmented field editor must route typed keys through the shared coordinator")
        contains(controlledInput, "override func fieldEditor(for controlView: NSView) -> NSTextView?", "Controlled segmented text fields must vend their own field editor instead of relying on NSTextField.keyDown")
        contains(controlledInput, "final class IndexControlledSegmentNSTextField: IndexPaddedTextField", "Controlled segmented fields must reuse the shared full-bounds native field")
        contains(controlledInput, "final class IndexControlledSegmentTextFieldCell: IndexPaddedTextFieldCell", "Controlled segmented cells must reuse shared title, draw, edit, and selection geometry")
        contains(controlledSurface, "contentInsets: IndexTextFieldContentInsets(leading: 11, trailing: trailingInset)", "Controlled segmented inputs must pass visual spacing into the AppKit cell")
        contains(controlledSurface, ".frame(maxWidth: .infinity, maxHeight: .infinity)", "Controlled segmented native fields must fill the complete visible background")
        doesNotContain(controlledSurface, ".padding(.leading, 11)", "Controlled segmented inputs must not shrink their native target with outer leading padding")
        doesNotContain(controlledSurface, ".padding(.trailing, trailingInset)", "Controlled segmented inputs must not shrink their native target with outer trailing padding")
        doesNotContain(controlledSurface, ".iBeamCursorOnHover()", "Controlled segmented inputs must use the native full-bounds cursor rect without covering trailing accessories")
        contains(controlledInput, "func sizeThatFits(\n        _ proposal: ProposedViewSize,", "Controlled segmented representables must accept the visible 38pt height")
        contains(controlledInput, "textField.indexContentInsets = contentInsets", "Controlled segmented fields must synchronize cell insets in both make and update paths")
        contains(controlledInput, "struct IndexControlledHumanTimeInput", "Shared controlled input must expose a human-time wrapper")
        contains(timestampConverter, "Label(\"现在\", systemImage: \"clock\")", "Current time page action must show clock plus Now")
        contains(timestampConverter, ".help(\"使用当前时间\")", "Current time page action must keep an explicit help label")
        contains(timestampConverter, ".accessibilityLabel(\"使用当前时间\")", "Current time page action must keep an explicit accessibility label")
        contains(timestampConverter, "NSApp.keyWindow?.makeFirstResponder(nil)", "Current time action must end active text editing before programmatic timestamp backfill so AppKit does not select the new value")
        doesNotContain(timestampConverter, "IndexClearButton", "Unix clear must not live in the panel header or input field")
        contains(timestampConverter, "Label(\"全部清空\", systemImage: IndexActionSymbol.clear)", "Whole-page clear must live on the result panel")
        contains(timestampConverter, ".indexWorkspaceDiagnostic(workspace.timestampError)", "Unix validation must stay as a persistent panel diagnostic")
        contains(timestampConverter, ".indexWorkspaceDiagnostic(workspace.humanError)", "Human-time paste validation must stay as a persistent non-displacing panel diagnostic")
        contains(timestampConverter, "(\"Unix 毫秒\", millisecondsText, nil)", "Unix milliseconds must remain as a derived result row")
        doesNotContain(timestampConverter, "@State private var human = \"\"", "Timestamp converter must not keep the old full-time editable field as primary state")
        doesNotContain(timestampConverter, "@State private var humanInput = \"\"", "Timestamp converter must not keep an unrestricted human-time string")
        doesNotContain(timestampConverter, ".onChange(of: humanTimeInput)", "Timestamp human-time input must not parse and rewrite itself through SwiftUI on every keystroke")
        doesNotContain(timestampConverter, "suppressNextHumanChange", "Timestamp converter should not need a suppress flag for keystroke-driven human parsing")
        doesNotContain(timestampConverter, "componentInput(\"分\"", "Timestamp converter must not force minute edits through separate segmented fields")
        doesNotContain(timestampConverter, "componentInput(\"秒\"", "Timestamp converter must not force second edits through separate segmented fields")
        doesNotContain(timestampConverter, "IndexActionBar", "Timestamp converter must remove the old top action bar")
        doesNotContain(timestampConverter, "IndexOptionLabel(\"时区\")", "Timestamp converter must remove the input timezone selector")
        doesNotContain(timestampConverter, "IndexOptionLabel(\"单位\")", "Timestamp converter must remove the timestamp unit selector")
        doesNotContain(timestampConverter, "Label(\"应用时间\", systemImage: \"checkmark.circle\")", "Timestamp converter must remove the explicit apply-time button")
        doesNotContain(timestampConverter, "Label(\"当前时间\", systemImage: \"clock\")", "Current time action must not remain as an external old-style button")
        doesNotContain(timestampConverter, "ControlledHumanTimeInputRepresentable", "Timestamp converter must not keep a page-local AppKit human-time bridge")
        doesNotContain(timestampConverter, "ControlledHumanTimeNSTextField", "Timestamp converter must not keep a page-local AppKit human-time text field")
        doesNotContain(timestampConverter, "@State private var timestampUnitMode", "Timestamp converter must not keep unit-mode state")
        doesNotContain(timestampConverter, "@State private var humanTimeZoneMode", "Timestamp converter must not keep local/UTC input-mode state")
        doesNotContain(timestampConverter, "秒 / 毫秒", "Input-facing Unix milliseconds wording must be removed")
        doesNotContain(timestampConverter, "TimestampInterpreter.seconds(fromTrimmed: value, mode: timestampMode)", "Timestamp page must not use the old unit-mode parser path")
    }

    @MainActor
    @Test func controlledSegmentFieldEditorRoutesKeyEventsAfterClick() throws {
        let textField = IndexControlledSegmentNSTextField()
        let handler = RecordingSegmentHandler()
        textField.segmentHandler = handler

        let cell = try #require(textField.cell as? IndexControlledSegmentTextFieldCell)
        let editor = try #require(cell.fieldEditor(for: textField) as? IndexControlledSegmentFieldEditor)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "2",
            charactersIgnoringModifiers: "2",
            isARepeat: false,
            keyCode: 19
        ))

        editor.keyDown(with: event)

        #expect(handler.keyDownCharacters == ["2"])
        #expect(handler.keyDownTextField === textField)
    }

    @MainActor
    @Test func controlledSegmentFieldEditorRoutesMouseClicksWhileEditing() throws {
        let textField = IndexControlledSegmentNSTextField()
        let handler = RecordingSegmentHandler()
        textField.segmentHandler = handler

        let cell = try #require(textField.cell as? IndexControlledSegmentTextFieldCell)
        let editor = try #require(cell.fieldEditor(for: textField) as? IndexControlledSegmentFieldEditor)
        editor.textField = textField
        editor.segmentHandler = handler
        editor.selectedRange = NSRange(location: 0, length: 0)

        editor.routeClick()

        #expect(handler.clickOffsets == [0])
        #expect(handler.clickTextField === textField)
    }

    @Test func chronometerUsesContinuousClockPausedScheduleAndCoreCapabilities() throws {
        let chronometer = try readSource("Sources/XTools/ToolPages/Time/ChronometerPage.swift")
        let resultDisplays = try readSource("Sources/XTools/ToolPages/Workbench/Diagnostics/IndexResultDisplays.swift")
        let resultPresence = try readSource("Sources/XTools/ToolPages/Workbench/Diagnostics/IndexResultPresence.swift")
        let scrollableKV = sourceSlice(
            resultDisplays,
            from: "struct IndexScrollableKV: View",
            to: "struct IndexShortResultKV: View"
        )
        let motion = try readSource("Sources/XTools/Shared/ToolMotion.swift")

        contains(chronometer, "ToolWorkspaceHost(key: ChronometerToolWorkspaceModel.key)", "Chronometer page must resolve retained elapsed-time state")
        contains(chronometer, "@Binding var chronometer: ChronometerState", "Chronometer visible content must bind the retained Core state value")
        contains(chronometer, "ContinuousClock()", "Chronometer must use the monotonic clock that continues across Mac sleep")
        contains(chronometer, "origin.duration(to: clock.now)", "Chronometer must project ContinuousClock instants into injectable relative seconds")
        contains(chronometer, ".animation(minimumInterval: 0.01, paused: !chronometer.isRunning)", "Chronometer must stop display refreshes while initial or paused")
        contains(chronometer, "chronometer.elapsed(at: monotonicNow())", "Chronometer display must ask Core state for elapsed time")
        contains(chronometer, "chronometer.toggle(at: monotonicNow())", "Chronometer start/pause must use the monotonic time reading")
        contains(chronometer, "chronometer.recordLap(at: monotonicNow())", "Chronometer lap recording must use the monotonic time reading")
        contains(chronometer, "chronometer.isRunning ? \"暂停\" : (chronometer.hasElapsed ? \"继续\" : \"开始\")", "Chronometer primary title must follow the initial, running, and paused state matrix")
        contains(chronometer, "chronometer.isRunning ? \"pause.fill\" : \"play.fill\"", "Chronometer pause action must use the semantic pause icon")
        contains(chronometer, ".disabled(!chronometer.canRecordLap)", "Chronometer Lap availability must come from Core state")
        contains(chronometer, ".disabled(!chronometer.canReset)", "Chronometer Reset availability must come from Core state")
        contains(chronometer, "本次 \\(ChronometerFormatter.format(lap.interval)) · 累计 \\(ChronometerFormatter.format(lap.split))", "Chronometer laps must show both interval and cumulative split")
        contains(chronometer, "id: \"lap-\\(lapNumber)\"", "Chronometer lap projection must preserve stable identities across top insertion")
        contains(chronometer, "IndexScrollableKV(rows: lapRows, emptyText: IndexEmptyStateCopy.noRecords, copyable: false, valueMotion: .immediate)", "Chronometer lap rows must avoid leaf text-swap motion while the structural owner animates")
        contains(resultDisplays, "struct IndexScrollableKVRow: Identifiable", "Scrollable KV rows must expose caller-provided stable identities")
        contains(scrollableKV, "let rows: [IndexScrollableKVRow]", "Scrollable KV must receive identified rows instead of deriving animation identity from offsets")
        contains(scrollableKV, "IndexScrollableResultPresence(", "Chronometer history must use one explicit scrollable presence owner")
        contains(scrollableKV, "ToolMotion.Transition.topRowInsertion", "Subsequent laps must use the shared top-row insertion transition")
        contains(scrollableKV, ".toolAnimation(ToolMotion.Preset.orderedContent, value: snapshot.map(\\.id))", "Only stable row identities may drive subsequent-lap layout motion")
        contains(resultPresence, "struct IndexScrollableResultPresence<", "Scrollable result presence must reuse the tested snapshot lifecycle")
        contains(resultPresence, "ScrollView {", "Scrollable presence must keep long histories inside an internal scroll owner")
        contains(resultPresence, ".allowsHitTesting(presentation.phase != .exiting)", "Outgoing lap snapshots must leave the operable tree immediately")
        contains(resultPresence, ".accessibilityHidden(presentation.phase == .exiting)", "Outgoing lap snapshots must leave the accessibility tree immediately")
        contains(resultPresence, ".frame(height: visibleHeight, alignment: .top)", "Scrollable presence must animate one explicit clipped height track")
        contains(resultPresence, "collapsedPresenceHeight(", "Short lap histories must still use the explicit clipped track when empty and result heights match")
        contains(resultPresence, "visibleHeight = collapsedPresenceHeight(", "Reset must collapse the outgoing surface while it fades")
        contains(resultPresence, "ToolMotion.Distance.medium", "The equal-height clipped-track fallback must use a shared motion distance token")
        doesNotContain(resultPresence, ".mask(alignment: .top)", "Scrollable presence must not restore the disproven moving-edge mask")
        contains(resultPresence, "ToolMotion.Preset.resultPresenceAppearance", "First lap must reuse the shared short-result appearance timing")
        contains(resultPresence, "ToolMotion.Preset.resultPresenceExit", "Reset must reuse the shared short-result exit timing")
        contains(resultPresence, "applyTarget(value, reduceMotion: true, maximumHeight: proxy.size.height)", "Scrollable presence must settle immediately when Reduce Motion becomes enabled")
        doesNotContain(scrollableKV, "rows.count", "Chronometer must not replay the whole list from row count changes")
        doesNotContain(motion, "scrollableResultPresence", "Shared motion vocabulary must not restore the rejected whole-list transition")
        doesNotContain(motion, "scrollableEmptyPresence", "Shared motion vocabulary must not restore delayed empty-state motion")
        doesNotContain(chronometer, "TimelineView(.periodic", "Chronometer must not keep an always-running periodic schedule")
        doesNotContain(chronometer, "ProcessInfo.processInfo.systemUptime", "Chronometer must not exclude Mac sleep from elapsed time")
        doesNotContain(chronometer, "Date().timeIntervalSince", "Chronometer page must not compute elapsed time from wall-clock Date differences")
    }

    @MainActor
    private final class RecordingSegmentHandler: IndexControlledSegmentFieldHandling {
        var keyDownCharacters: [String] = []
        weak var keyDownTextField: IndexControlledSegmentNSTextField?
        var clickOffsets: [Int] = []
        weak var clickTextField: IndexControlledSegmentNSTextField?

        func handleKeyDown(_ event: NSEvent, in textField: IndexControlledSegmentNSTextField) -> Bool {
            keyDownCharacters.append(event.charactersIgnoringModifiers ?? "")
            keyDownTextField = textField
            return true
        }

        func handlePaste(in textField: IndexControlledSegmentNSTextField) -> Bool {
            false
        }

        func handleClick(atDisplayOffset offset: Int, in textField: IndexControlledSegmentNSTextField) {
            clickOffsets.append(offset)
            clickTextField = textField
        }
    }

}
