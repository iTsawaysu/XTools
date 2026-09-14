import Foundation
import Testing

struct KeyboardEventInspectorSourceContractTests {
    @Test func inspectorUsesTypedSnapshotAndBoundedCaptureCard() throws {
        let page = try readSource("Sources/XTools/ToolPages/Web/KeycodeInfoPage.swift")
        let registry = try readSource("Sources/XTools/ToolRegistry/ToolRegistry.swift")

        contains(registry, "id: \"keycode-info\"", "Keyboard Event must preserve its stable tool ID")
        contains(registry, "title: \"键盘事件\"", "Keyboard Event must use the event-oriented display name")
        contains(page, "\"键盘事件\",\n            subtitle:", "Page title must match the registry")
        contains(page, "subtitle: \"根据本机按键事件推导对应的 Web KeyboardEvent 字段。\"", "Subtitle must distinguish local projection from browser runtime events")
        contains(page, "@Published var snapshot: KeyboardEventSnapshot?", "Retained workspace must own one typed latest snapshot")
        contains(page, "private let captureCardHeight: CGFloat = 152", "Capture surface must use the tighter evidence-based bounded height")
        contains(page, ".frame(height: captureCardHeight)", "Capture card must not accept a vertically filling proposal")
        contains(page, "private func resultRows(for snapshot: KeyboardEventSnapshot)", "Latest snapshot must expose one concise result projection")
        let resultRows = sourceSlice(page, from: "private func resultRows", to: "private var captureAccessibilitySummary")
        contains(resultRows, "(\"事件类型\", eventTypeDisplay(snapshot.kind), nil)", "Results must identify the native event kind")
        contains(resultRows, "(\"event.key\", webKeyDisplay(snapshot.webKey), nil)", "Results must prioritize Web key")
        contains(resultRows, "(\"event.code\", snapshot.webCode, nil)", "Results must prioritize physical Web code")
        contains(resultRows, "(\"event.location\", snapshot.location.displayText, nil)", "Results must keep key location visible")
        contains(resultRows, "(\"修饰键\", snapshot.modifiers.displayText, nil)", "Results must keep modifier state visible")
        contains(resultRows, "(\"重复事件\", snapshot.isRepeat ? \"是\" : \"否\", nil)", "Results must expose repeat state without a disclosure")
        contains(resultRows, "(\"macOS keyCode\", \"\\(snapshot.keyCode)\", nil)", "Results must keep the native keyCode visible")
        doesNotContain(page, "showsAdvancedFields", "The concise result must not retain disclosure state")
        doesNotContain(page, "isAdvancedFieldsHovering", "The removed disclosure must not retain hover state")
        doesNotContain(page, "ToolDisclosureBody", "The result must not hide essential fields behind a disclosure")
        doesNotContain(page, "更多字段", "The result must not expose a redundant advanced-fields entry")
        doesNotContain(page, "snapshot.nativeKeyName", "Native key name duplicates the visible Web and macOS identifiers")
        doesNotContain(page, "snapshot.legacyKeyCode", "Deprecated Web keyCode must not add noise to the result")
        doesNotContain(page, "snapshot.asciiCode", "Locally derived ASCII must not be presented as browser event data")
        let latestResult = sourceSlice(page, from: "private var latestEventResult", to: "private func resultRow")
        contains(latestResult, "IndexResultPresence(", "The empty/latest boundary must keep the shared result presence owner")
        contains(latestResult, "value: workspace.snapshot", "Result presence must retain the typed latest snapshot")
        occurrenceCount(latestResult, "IndexKVSurface {", 1, "All essential rows must share one continuous surface")
        contains(latestResult, "resultRows(for: snapshot)", "The result surface must render the complete concise projection")
        doesNotContain(page, "@Published var rows: [(String, String, Color?)]", "Workspace must not retain untyped UI tuples")
    }

    @Test func nativeCaptureTracksRealFocusAndModifierEventsWithoutGlobalMonitoring() throws {
        let page = try readSource("Sources/XTools/ToolPages/Web/KeycodeInfoPage.swift")

        contains(page, "@State private var focusRequestToken = 0", "Page entry must own a one-shot focus request token")
        contains(page, ".onAppear {\n            focusRequestToken &+= 1\n        }", "Every page entry must issue one explicit capture-focus request")
        contains(page, "nsView.requestInitialFocus(token: focusRequestToken)", "Representable updates must bridge the page-entry focus request after overlays dismiss")
        contains(page, "private let initialFocusRetryDelays: [TimeInterval] = [0.05, ToolMotion.Duration.fast + 0.05]", "Initial capture focus must retry beyond the shared modal transition without polling")
        contains(page, "name: NSWindow.didBecomeKeyNotification", "A page launched before its window becomes key must finish the pending initial focus request on activation")
        contains(page, "@objc private func windowDidBecomeKey", "Window activation must bridge deferred initial focus without a global event monitor")
        contains(page, "override func becomeFirstResponder() -> Bool", "Listening must begin only when AppKit accepts first responder")
        contains(page, "override func resignFirstResponder() -> Bool", "Listening must stop when the capture surface loses focus")
        contains(page, "override func flagsChanged(with event: NSEvent)", "Modifier-only keys must flow through flagsChanged")
        contains(page, "if event.keyCode == 0x35", "Escape must have an explicit exit path after snapshot delivery")
        contains(page, "window?.makeFirstResponder(nil)", "Escape must release keyboard capture")
        contains(page, "setAccessibilityRole(.button)", "Capture surface must expose interactive accessibility semantics")
        contains(page, "setAccessibilityLabel(\"键盘事件捕获\")", "Capture surface must expose a stable accessibility label")
        contains(page, "setAccessibilityValue(accessibilityValue)", "Visible listening/latest-event state must reach accessibility")
        contains(page, "override func accessibilityPerformPress() -> Bool", "VoiceOver press must restore capture focus")
        doesNotContain(page, "NSEvent.addGlobalMonitorForEvents", "Inspector must never become a global key logger")
        doesNotContain(page, "NSEvent.addLocalMonitorForEvents", "Inspector must stay inside the normal responder chain")
        doesNotContain(page, "override func performKeyEquivalent", "Inspector must not steal App menu shortcuts")
    }
}
