import Foundation
import AppKit
@testable import XTools
import Testing

/// Shared UI infrastructure source-string contracts.
///
/// The full rationale for retaining these source-string view-structure tests
/// lives in `SourceContractTestSupport.swift`. This suite keeps only the shared
/// UI, diagnostic, input, and page-shell contracts; domain-specific contracts
/// live in their own `*SourceContractTests` files.
struct UIInfrastructureSourceTests {
    @Test func sharedTextAreaUsesUndoableAppKitTextView() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let textEditingConfig = try readSource("Sources/XTools/Shared/Components/AppKitTextEditingConfiguration.swift")

        contains(source, "struct IndexUndoableTextView: NSViewRepresentable", "Shared text areas must use the AppKit-backed text view")
        contains(source, "AppKitTextEditingConfiguration.configurePlainTextEditor(textView)", "Shared text areas must enable native NSTextView undo through the shared AppKit text configuration")
        contains(textEditingConfig, "textView.allowsUndo = allowsUndo", "Shared AppKit text configuration must enable native undo")
        contains(source, "func textDidChange(_ notification: Notification)", "Shared text areas must sync NSTextView edits back into SwiftUI state")
        contains(source, "IndexUndoableTextView(", "IndexTextArea must render the undoable text view")
        contains(source, "var growsWithContent: Bool", "Shared text areas must expose content growth for behavior tests")
        contains(source, "hasVerticalScroller = !growsWithContent", "Content-growing text areas must not show their own vertical scroller")
        contains(source, "func measure(_ textView: NSTextView)", "Content-growing text areas must measure NSTextView content height")
        contains(source, "struct IndexTextAreaInputPolicy", "Shared text areas must expose an optional input policy for high-risk editors")
        contains(source, "shouldChangeTextIn affectedCharRange: NSRange", "Shared text areas must reject configured oversized edits before insertion")
        contains(source, "attemptedUTF8Bytes <= maxUTF8Bytes", "Shared text areas must enforce configured UTF-8 byte limits before binding sync")
        contains(source, "func undoManager(for view: NSTextView) -> UndoManager?", "Shared text areas must always vend a private undo manager, never the shared window manager")
        contains(source, "privateUndo.configureLevels(inputPolicy?.undoLevels)", "Configured text areas must keep undo unbounded by default and only cap depth from an explicit policy")
        contains(source, "var caretPlacementRequestToken: Int? = nil", "Shared multiline inputs must expose explicit programmatic caret placement without changing ordinary edits")
        contains(source, "textView.setSelectedRange(selection)", "Programmatic replacement requests must place the caret at the requested UTF-16 selection")
        contains(source, "caretPlacementState", "Each AppKit coordinator must consume a caret placement request once")
        contains(source, "var temporaryHighlights: IndexTextAreaTemporaryHighlights? = nil", "Shared multiline inputs must keep temporary highlighting opt-in")
        contains(source, "context.coordinator.refreshTemporaryHighlights(temporaryHighlights, in: textView)", "Only the measured AppKit text path must apply temporary display attributes")
        contains(source, "IndexTextAreaTemporaryHighlightRenderer.clear(in: textView)", "User edits must clear stale temporary backgrounds before binding publication")
    }

    @Test func programmaticCaretPlacementUsesUTF16AndWaitsForComposition() {
        var state = IndexTextAreaCaretPlacementState()
        let text = "A😀"

        #expect(state.selectionRange(requestToken: 1, text: text, hasMarkedText: false) == NSRange(location: 3, length: 0))
        #expect(state.selectionRange(requestToken: 1, text: text, hasMarkedText: false) == nil)
        #expect(state.selectionRange(requestToken: 2, text: text, hasMarkedText: true) == nil)
        #expect(state.selectionRange(requestToken: 2, text: text, hasMarkedText: false) == NSRange(location: 3, length: 0))
    }

    @Test @MainActor func boundedTextAreaUsesAnIsolatedTextKit2ViewportPath() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let viewport = sourceSlice(
            source,
            from: "struct IndexTextKit2ViewportTextView: NSViewRepresentable",
            to: "// MARK: - Legacy measured text view"
        )

        contains(source, "case textKit2Viewport", "Shared text areas must expose an explicit TextKit 2 viewport opt-in")
        contains(viewport, "IndexCaretTextView(usingTextLayoutManager: true)", "The bounded viewport must construct a real TextKit 2 text view")
        contains(viewport, "textView.textLayoutManager != nil", "The viewport path must verify that TextKit 2 remains active")
        contains(viewport, "textView.scrollRangeToVisible", "The viewport path must reveal the insertion point through the high-level text view API")
        doesNotContain(viewport, "textView.layoutManager", "The TextKit 2 viewport must never request the legacy layout manager")
        doesNotContain(viewport, "ensureLayout(for:", "The TextKit 2 viewport must not force full document layout")
        doesNotContain(viewport, "usedRect(for:", "The TextKit 2 viewport must not measure full document geometry")
        doesNotContain(viewport, "temporaryHighlights", "The TextKit 2 viewport must not accept legacy temporary-highlight state")
        doesNotContain(viewport, "TemporaryHighlightRenderer", "The TextKit 2 viewport must not access the TextKit 1 temporary-attribute renderer")

        let textView = IndexTextKit2ViewportTextView.makeTextView()
        #expect(textView.textLayoutManager != nil)
    }

    @Test func sharedSingleLineInputUsesUndoableAppKitTextField() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let geometry = try readSource("Sources/XTools/Shared/Components/AppKitTextFieldGeometry.swift")
        let dateCalculator = try readSource("Sources/XTools/ToolPages/Time/DateCalculatorPage.swift")
        let textEditingConfig = try readSource("Sources/XTools/Shared/Components/AppKitTextEditingConfiguration.swift")
        let inputSurface = sourceSlice(
            source,
            from: "struct IndexTextInput: View",
            to: "private struct IndexUndoableTextField: NSViewRepresentable"
        )

        contains(source, "struct IndexUndoableTextField: NSViewRepresentable", "Shared single-line inputs must use an AppKit-backed text field")
        contains(source, "IndexUndoableTextField(", "IndexTextInput must render the undoable text field")
        doesNotContain(source, "TextField(placeholder, text: $text)", "IndexTextInput must not use the SwiftUI TextField because Command-Z is unreliable there")
        doesNotContain(source, "SecureField(placeholder, text: $text)", "IndexTextInput secure mode must also use the shared AppKit-backed field")
        contains(source, "AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: textField)", "Shared single-line inputs must enable native field-editor undo through the shared AppKit text configuration")
        contains(textEditingConfig, "configureCurrentFieldEditor(for textField: NSTextField", "Shared AppKit text configuration must support NSTextField field editors")
        contains(source, "func controlTextDidChange(_ notification: Notification)", "Shared single-line inputs must sync NSTextField edits back into SwiftUI state")
        contains(source, "var onEscape: (() -> Void)? = nil", "Shared single-line inputs must expose an optional Escape action")
        contains(source, "#selector(NSResponder.cancelOperation(_:))", "The AppKit field bridge must handle Escape through native command routing")
        contains(source, "shouldPlaceCursorAtEndAfterFocus", "Shared single-line autofocus must track the first programmatic focus selection")
        contains(source, "textField.currentEditor()?.selectedRange = NSRange(location: end, length: 0)", "Autofocused single-line inputs must place the cursor at the end unless select-all is explicit")
        contains(geometry, "class IndexPaddedTextFieldCell: NSTextFieldCell", "Shared inputs must keep plain text in an AppKit cell with internal content geometry")
        contains(geometry, "final class IndexPaddedSecureTextFieldCell: NSSecureTextFieldCell", "Secure inputs must preserve NSSecureTextFieldCell semantics while applying the same content geometry")
        contains(geometry, "override func edit(", "Shared text cells must apply the content rectangle to the field editor")
        contains(geometry, "override func select(", "Shared text cells must apply the content rectangle to native selection")
        contains(inputSurface, "contentInsets: IndexTextFieldContentInsets(leading: 11, trailing: trailingInset)", "IndexTextInput must pass its visual padding into the AppKit cell")
        contains(inputSurface, ".frame(maxWidth: .infinity, maxHeight: .infinity)", "IndexTextInput must let the native field fill the complete visible background")
        contains(source, "func sizeThatFits(\n        _ proposal: ProposedViewSize,", "The AppKit bridge must accept the visible field height instead of keeping NSTextField's intrinsic 15pt height")
        contains(source, "return CGSize(width: proposal.width ?? textField.fittingSize.width, height: height)", "The AppKit field must use the complete proposed height for hit testing")
        doesNotContain(inputSurface, ".padding(.leading, 11)", "IndexTextInput must not shrink the native hit target with outer leading padding")
        doesNotContain(inputSurface, ".padding(.trailing, trailingInset)", "IndexTextInput must not shrink the native hit target with outer trailing padding")
        doesNotContain(dateCalculator, "TextField(\"\", value: $amount", "Date calculator amount input must not bypass the shared undoable input component")
        contains(dateCalculator, "IndexNumberInput(value: $session.amount", "Date calculator amount input must reuse the shared undoable number input via session binding")
    }

    @Test func windowChromeDismissesEditingOnOutsideMouseDownWithoutConsumingClicks() throws {
        let source = try readSource("Sources/XTools/AppShell/WindowChromeConfigurator.swift")

        doesNotContain(source, "titlebarAppearsTransparent", "Native toolbar presentation must not be replaced by a custom transparent titlebar")
        doesNotContain(source, "fullSizeContentView", "Window focus infrastructure must not reintroduce full-size custom chrome")
        contains(source, "NSEvent.addLocalMonitorForEvents(", "The app window must monitor local mouse-down events to end text editing")
        contains(source, "[.leftMouseDown, .rightMouseDown, .otherMouseDown]", "Outside-click dismissal must cover ordinary and alternate mouse buttons")
        contains(source, "WindowTextEditingFocusPolicy.shouldDismissEditing", "The event monitor must delegate target classification to a testable policy")
        contains(source, "window.makeFirstResponder(nil)", "Outside clicks must end the current AppKit text-editing session")
        contains(source, "return event", "Outside-click dismissal must preserve the original button or background click")
        contains(source, "NSEvent.removeMonitor", "Window monitor teardown must remove the local event monitor")
    }

    @Test @MainActor func windowTextEditingFocusPolicyKeepsEditingTargetsAndDismissesElsewhere() {
        let activeEditor = NSTextView()
        activeEditor.isEditable = true

        let button = NSButton()
        #expect(WindowTextEditingFocusPolicy.shouldDismissEditing(
            firstResponder: activeEditor,
            clickedView: button
        ))

        let textField = NSTextField()
        textField.isEditable = true
        textField.isEnabled = true
        #expect(!WindowTextEditingFocusPolicy.shouldDismissEditing(
            firstResponder: activeEditor,
            clickedView: textField
        ))

        let textArea = NSTextView()
        textArea.isEditable = true
        #expect(!WindowTextEditingFocusPolicy.shouldDismissEditing(
            firstResponder: activeEditor,
            clickedView: textArea
        ))

        let pageScrollView = NSScrollView()
        let pageDocument = NSView()
        let nestedEditor = NSTextView()
        nestedEditor.isEditable = true
        let unrelatedButton = NSButton()
        pageDocument.addSubview(nestedEditor)
        pageDocument.addSubview(unrelatedButton)
        pageScrollView.documentView = pageDocument
        #expect(WindowTextEditingFocusPolicy.shouldDismissEditing(
            firstResponder: activeEditor,
            clickedView: unrelatedButton
        ))

        #expect(!WindowTextEditingFocusPolicy.shouldDismissEditing(
            firstResponder: button,
            clickedView: NSView()
        ))
    }

    @Test func toolPageEntryTraceUsesDebugOnlySignposts() throws {
        let trace = try readSource("Sources/XTools/AppShell/ToolPageEntryTrace.swift")
        let actions = try readSource("Sources/XTools/AppShell/ToolNavigationActions.swift")
        let host = try readSource("Sources/XTools/AppShell/ToolDetailHostView.swift")
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")
        let textComponents = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")

        contains(trace, "#if DEBUG\nimport AppKit\nimport os\n#endif", "Tool page entry tracing must keep AppKit benchmark and OSLog imports out of release-only builds")
        contains(trace, "ProcessInfo.processInfo.environment[\"TOOLS_TOOL_PAGE_TRACE\"] == \"1\"", "Tool page entry tracing must be opt-in during Debug runs")
        contains(trace, "os_signpost(\n            .begin,\n            log: log,\n            name: \"Tool Page Entry\"", "Tool page entry tracing must expose an entry interval for Instruments")
        contains(trace, "name: \"Tool Make Page Started\"", "Tool page entry tracing must mark makePage start")
        contains(trace, "name: \"Tool Make Page Finished\"", "Tool page entry tracing must mark makePage completion")
        contains(trace, "name: \"Tool Page Appeared\"", "Tool page entry tracing must mark first page appearance")
        contains(trace, "name: \"Tool Primary Input Focus\"", "Tool page entry tracing must measure AppKit primary-input focus")
        contains(trace, "\"primary-input-ready\" as NSString", "Tool page entry tracing must end the entry interval when the primary input is ready")
        contains(trace, "endEntryIfActive(context, status: \"page-visible\")", "Tool page entry tracing must end no-autofocus page intervals when the page is visible")
        contains(trace, "focusPendingToolIDs.insert(context.toolID)", "Tool page entry tracing must keep autofocus pages open until focus completion")
        contains(trace, "ProcessInfo.processInfo.environment[\"TOOLS_TOOL_PAGE_BENCHMARK\"] == \"1\"", "Tool page entry benchmark must be explicitly enabled")
        contains(trace, "ProcessInfo.processInfo.environment[\"TOOLS_TOOL_PAGE_BENCHMARK_QUERIES\"]", "Tool page entry benchmark must support custom tool query sequences for focused diagnosis")
        contains(trace, "TOOL_PAGE_ENTRY_PHASE_RESULT tool=%@ title=%@ phase=%@ milliseconds=%.3f", "Tool page entry benchmark must emit phase timing results beyond first appearance")
        contains(trace, "TOOL_PAGE_ENTRY_RESULT tool=%@ title=%@ milliseconds=%.3f", "Tool page entry benchmark must emit machine-readable timing results")
        contains(trace, "emitBenchmarkPhaseMeasurement(context, phase: \"appeared\")", "Tool page entry benchmark must separately measure first appearance")
        contains(trace, "emitBenchmarkReadyMeasurement(context)", "Tool page entry benchmark must emit the primary result only when the page is ready")
        contains(trace, "registry.tool(for: ToolID(rawValue: $0)) ?? registry.matchingTools(query: $0).first", "Tool page entry benchmark must resolve exact tool identities before falling back to registry search")
        contains(trace, "NSApp.terminate(nil)", "Tool page entry benchmark must terminate after its bounded run")

        contains(actions, "ToolPageEntryTrace.toolSelected(tool)", "Navigation actions must start entry tracing before selectedToolID changes")
        contains(host, "ToolPageEntryTrace.makePageStarted(tool)", "Tool detail host must mark page factory start")
        contains(host, "ToolPageEntryTrace.makePageFinished(tool)", "Tool detail host must mark page factory completion")
        contains(host, ".environment(\\.toolPageEntryTraceContext, traceContext)", "Tool detail host must pass the current tool trace context to page controls")
        contains(host, ".id(tool.id)\n                            .onAppear { ToolPageEntryTrace.pageAppeared(traceContext) }", "Tool detail host must give each selected tool an identity-bound page appearance marker")
        contains(root, "ToolPageEntryBenchmark.runIfRequested(", "Root view must expose the opt-in page entry benchmark through the real navigation path")
        contains(textComponents, "@Environment(\\.toolPageEntryTraceContext) private var toolPageEntryTraceContext", "Single-line inputs must read the current tool trace context")
        contains(textComponents, "entryTraceContext: toolPageEntryTraceContext", "IndexTextInput must pass trace context into its AppKit bridge")
        contains(textComponents, "ToolPageEntryTrace.inputFocusRequested(entryTraceContext, placeholder: placeholder)", "Autofocus must mark primary-input focus start")
        contains(textComponents, "ToolPageEntryTrace.inputFocusCompleted(entryTraceContext, placeholder: placeholder)", "Autofocus must mark primary-input focus completion")
    }

    @Test func appDefinesStandardUndoRedoCommands() throws {
        let source = try readSource("Sources/XTools/XToolsApp.swift")

        contains(source, "CommandGroup(replacing: .undoRedo)", "App must own the standard Undo/Redo command group")
        contains(source, "AppKitUndoCommandRouter.perform(.undo)", "Undo command must resolve the current bridged AppKit editor")
        contains(source, "AppKitUndoCommandRouter.perform(.redo)", "Redo command must resolve the current bridged AppKit editor")
        contains(source, "activeTextEditor(in: activeWindow)?.undoManager", "Undo routing must select the active editor's private manager before the window fallback")
        contains(source, "application.sendAction(action.managerSelector, to: manager, from: nil)", "Undo routing must execute the private manager through NSApplication")
        contains(source, "application.sendAction(action.responderSelector, to: nil, from: nil)", "Non-text undo commands must retain responder-chain fallback behavior")
        contains(source, ".keyboardShortcut(\"z\", modifiers: .command)", "Undo must keep the standard Command-Z shortcut")
    }

    @Test func persistentCardSurfaceHasDedicatedQuietElevation() throws {
        let surface = try readSource("Sources/XTools/Shared/Components/IndexSurface.swift")
        let metrics = try readSource("Sources/XTools/Shared/ToolMetrics.swift")
        let theme = try readSource("Sources/XTools/Shared/ToolTheme.swift")

        contains(surface, "case card", "Persistent content cards must have an explicit surface semantic")
        contains(surface, "case .card: return ToolMetrics.CornerRadius.card", "Card surfaces must use the shared card radius token")
        contains(surface, "case .card:\n            content.toolShadow(ToolTheme.Shadow.card)", "Card surfaces must use the dedicated quiet card elevation")
        contains(metrics, "static let card: CGFloat = 12", "Card radius must be named and shared")
        contains(metrics, "static let panelInset: CGFloat = 14", "Panel inset must come from a shared spacing token")
        contains(theme, "static let card = ShadowRecipe", "Card elevation must be distinct from panel/modal recipes")
        doesNotContain(surface, "case .card:\n            content.toolShadow(ToolTheme.Shadow.modal)", "Persistent cards must never use modal elevation")
    }

    @Test func pageHeaderWithoutAccessoryKeepsAccessorySlotUnclaimed() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexPageShell.swift")
        contains(source, "self.hasAccessory = false", "Headers without an accessory must not enter the accessory HStack layout")
    }

    @Test func diagnosticBannerRendersThroughSharedOwner() throws {
        let panel = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexPageShell.swift")

        contains(panel, "if reservesDiagnosticStatusSlot, let diagnostic = workspaceDiagnostic {\n                IndexDiagnosticBanner(", "Diagnostic-capable panels must render the shared banner for the current payload")
        contains(panel, "func withoutDiagnosticStatusSlot() -> IndexPanel", "Panels without diagnostics must opt out explicitly")
    }

    @Test func sidebarSearchUsesUndoableAppKitTextField() throws {
        let source = try readSource("Sources/XTools/AppShell/SidebarView.swift")
        let lifecycle = try readSource("Sources/XTools/Shared/Components/AppKitSearchFieldLifecycle.swift")
        let searchSurface = sourceSlice(
            source,
            from: "private var searchField: some View",
            to: "private var expandedToolList: some View"
        )

        contains(source, "private struct SidebarSearchTextField: NSViewRepresentable", "Sidebar search must keep its AppKit-backed adapter port")
        contains(source, "AppKitSearchFieldLifecycle.makeTextField(", "Sidebar search must delegate native field creation to the shared lifecycle")
        contains(source, "processedFocusToken: 0", "Sidebar search must treat the launch token as already processed")
        contains(source, "focusRetryDelays: [0.05]", "Sidebar search must preserve its one delayed focus retry")
        contains(source, "textField.setAccessibilityIdentifier(\"sidebar.search\")", "Sidebar search must expose a stable automation and accessibility identity")
        contains(lifecycle, "let textField = IndexPaddedTextField()", "Shared search lifecycle must create the full-bounds plain NSTextField")
        contains(lifecycle, "textField.indexContentInsets = configuration.contentInsets", "Shared search lifecycle must synchronize AppKit cell content insets")
        contains(lifecycle, "AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: textField)", "Shared search lifecycle must enable native field-editor undo")
        contains(searchSurface, "contentInsets: IndexTextFieldContentInsets(", "Sidebar search must reserve icon and clear-button slots inside the AppKit cell")
        contains(searchSurface, ".allowsHitTesting(false)", "Sidebar search icon must pass clicks through to the native field")
        contains(searchSurface, ".frame(maxWidth: .infinity, maxHeight: .infinity)", "Sidebar native search field must fill the complete 32pt visible surface")
        contains(searchSurface, "if !searchText.isEmpty {", "Sidebar clear control must leave the accessibility tree when no clearing action is available")
        doesNotContain(searchSurface, ".opacity(searchText.isEmpty ? 0 : 1)", "Sidebar clear control must not remain as an invisible accessibility element")
        doesNotContain(searchSurface, ".iBeamCursorOnHover()", "Sidebar search must not advertise a false outer I-beam target")
        contains(source, "func sizeThatFits(\n        _ proposal: ProposedViewSize,", "Sidebar AppKit search port must accept the complete visible height")
        doesNotContain(source, "final class Coordinator", "Sidebar search must not duplicate the shared coordinator")
        doesNotContain(source, "private func requestFocus", "Sidebar search must not duplicate shared focus scheduling")
        doesNotContain(source, "TextField(\"搜索工具...\", text: $searchText)", "Sidebar search must not use SwiftUI TextField because Command-Z is unreliable there")
        doesNotContain(source, "@FocusState private var isSearchFocused", "Sidebar search focus state must follow the AppKit first responder callbacks")
    }

    @Test func appUsesSingleMainWindowScene() throws {
        let source = try readSource("Sources/XTools/XToolsApp.swift")

        contains(source, "Window(\"Tools\", id: \"main\")", "App must use a single main window scene instead of a multi-window WindowGroup")
        contains(source, ".frame(minWidth: 960, minHeight: 640)", "Main window content minimum must match the validated RootView boundary")
        contains(source, ".windowResizability(.contentMinSize)", "Main window must derive resize limits from content constraints")
        doesNotContain(source, "WindowGroup", "App must not expose duplicate main windows through WindowGroup")
        doesNotContain(source, "NSApplicationDelegateAdaptor", "Single-window close behavior should stay on SwiftUI's Window lifecycle, not a custom reopen bridge")
    }

    @Test func workspaceDiagnosticUsesNonDisplacingAnchorByDefault() throws {
        let source = try readSharedBagComponents()
        let pageShell = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexPageShell.swift")
        let diagnostic = sourceSlice(
            source,
            from: "struct IndexWorkspaceDiagnostic: View",
            to: "struct IndexDiagnosticStatusButton: View"
        )
        let compactDiagnostic = sourceSlice(
            source,
            from: "struct IndexDiagnosticStatusButton: View",
            to: "struct IndexWorkspaceDiagnosticRegion<Content: View>: View"
        )
        let panel = sourceSlice(
            pageShell,
            from: "struct IndexPanel<Content: View, Accessory: View>: View",
            to: "// MARK: - IndexActionBar"
        )
        let defaultModifier = sourceSlice(
            source,
            from: "func indexWorkspaceDiagnostic(\n        _ text: String?",
            to: "func indexWorkspaceDiagnosticOverlay("
        )
        let overlayModifier = sourceSlice(
            source,
            from: "func indexWorkspaceDiagnosticOverlay(",
            to: "// MARK: - IndexStatGrid"
        )

        contains(source, "struct IndexWorkspaceDiagnostic: View", "Shared components must define a persistent workspace diagnostic")
        contains(source, "struct IndexWorkspaceDiagnosticRegion<Content: View>: View", "Shared components must provide a persistent diagnostic anchor")
        contains(source, "var tone: ToolFeedbackTone = .error", "Workspace diagnostics must use the shared feedback tone model")
        contains(diagnostic, "lineLimit(6)", "Workspace diagnostic copy must fit two-sided JSON diff diagnostics without becoming an unbounded panel")
        contains(diagnostic, ".frame(maxWidth: maxWidth, alignment: .trailing)", "Workspace diagnostics must have a bounded width")
        contains(diagnostic, ".frame(maxWidth: .infinity, alignment: .trailing)", "Workspace diagnostics must align to the trailing edge")
        contains(diagnostic, ".allowsHitTesting(false)", "Workspace diagnostics must not intercept editor/workspace input")
        contains(diagnostic, ".accessibilityLabel(\"\\(tone.accessibilityPrefix)：\\(text)\")", "Workspace diagnostics must expose tone and text to accessibility")
        doesNotContain(diagnostic, "Button", "Persistent workspace diagnostics must not expose a manual close or details action")
        doesNotContain(diagnostic, "详情", "Persistent workspace diagnostics must not expose a technical details entry in this task")
        doesNotContain(diagnostic, "原始错误", "Persistent workspace diagnostics must not expose raw errors in this task")
        doesNotContain(diagnostic, "日志", "Persistent workspace diagnostics must not expose logs in this task")
        doesNotContain(pageShell, ".overlayPreferenceValue(IndexWorkspaceDiagnosticPreferenceKey.self", "IndexPage must not lift panel diagnostics into a root overlay that can cover controls")
        contains(panel, "@State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?", "IndexPanel must own the current diagnostic from its descendant surface")
        contains(panel, "@State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()", "IndexPanel must gate first-appearance diagnostic HUD feedback locally")
        contains(panel, ".onPreferenceChange(IndexWorkspaceDiagnosticPreferenceKey.self)", "IndexPanel must consume descendant diagnostics at the owning panel boundary")
        contains(panel, "IndexDiagnosticBanner(\n                    diagnostic: nil,", "IndexPanel must render diagnostics through the shared banner owner")
        contains(panel, "toastCenter?.show(announcement.text, tone: announcement.tone)", "IndexPanel must copy a newly appearing or escalating diagnostic into the window HUD")
        contains(panel, "IndexPanelOutline(", "IndexPanel must keep a semantic outline after the transient HUD disappears")
        let outline = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexPageShell.swift")
        contains(outline, "diagnostic.tone.tint.opacity(0.55)", "Diagnostics must always tint the panel outline")
        contains(outline, "colorScheme == .dark", "Light mode separates panels via the surface ladder, dark keeps the hairline")
        doesNotContain(panel, "IndexTrafficLights()", "IndexPanel must not keep decorative traffic lights beside a diagnostic marker")
        contains(source, "struct IndexDiagnosticStatusButton: View", "Shared components must own one reusable icon-only diagnostic status button")
        contains(compactDiagnostic, "Button {", "Persistent panel diagnostics must be keyboard-accessible buttons")
        contains(compactDiagnostic, ".popover(isPresented:", "Persistent panel diagnostics must let users reopen the short summary")
        contains(compactDiagnostic, ".help(payload.text)", "Persistent panel diagnostics must expose their summary through Help")
        contains(compactDiagnostic, ".accessibilityLabel(\"\\(payload.tone.accessibilityPrefix)：\\(payload.text)\")", "Panel diagnostics must expose tone and summary to accessibility")
        doesNotContain(compactDiagnostic, "Label(payload.text", "Panel diagnostics must not place their prose in the fixed-height header")
        contains(source, ".preference(key: IndexWorkspaceDiagnosticPreferenceKey.self, value: diagnosticPayload)", "Default workspace diagnostics must publish an anchor payload without inserting a layout row")
        doesNotContain(source, "VStack(alignment: .leading, spacing: visibleText == nil ? 0 : spacing)", "Default workspace diagnostics must not reserve dynamic body space")
        contains(source, "struct IndexWorkspaceDiagnosticPreferenceKey: PreferenceKey", "Shared diagnostics must use one preference key inside an owning panel")
        doesNotContain(source, "value = value ?? nextValue()", "Workspace diagnostic priority must not depend on view traversal order")
        contains(defaultModifier, "IndexWorkspaceDiagnosticRegion(text, tone: tone, maxWidth: maxWidth)", "Default workspace diagnostic modifier must use the non-displacing anchor")
        doesNotContain(defaultModifier, "VStack(alignment:", "Default workspace diagnostic modifier must not insert a body row")
        contains(overlayModifier, "func indexWorkspaceDiagnosticOverlay(", "Explicit overlay escape hatch must be named separately")
        contains(overlayModifier, "overlay(alignment: alignment)", "Explicit overlay escape hatch may use overlay only under the reviewed name")
        doesNotContain(source, "func indexFloatingError", "Old floating-error modifier must not remain as a parallel presentation API")
    }

    @Test func workspaceDiagnosticPreferencePrioritizesSeverity() {
        var primary: IndexWorkspaceDiagnosticPayload? = .init(text: "warning", tone: .warning, maxWidth: 460)

        IndexWorkspaceDiagnosticPreferenceKey.reduce(value: &primary) {
            .init(text: "error", tone: .error, maxWidth: 460)
        }
        #expect(primary?.text == "error")
        #expect(primary?.tone == .error)

        IndexWorkspaceDiagnosticPreferenceKey.reduce(value: &primary) {
            .init(text: "info", tone: .info, maxWidth: 460)
        }
        #expect(primary?.text == "error")
    }

    @Test func workspaceDiagnosticPresentationAnnouncesAppearanceEscalationAndReappearanceOnly() {
        let warning = IndexWorkspaceDiagnosticPayload(text: "warning", tone: .warning, maxWidth: 460)
        let updatedWarning = IndexWorkspaceDiagnosticPayload(text: "updated", tone: .warning, maxWidth: 460)
        let error = IndexWorkspaceDiagnosticPayload(text: "error", tone: .error, maxWidth: 460)
        var state = IndexWorkspaceDiagnosticPresentationState()

        #expect(state.update(to: warning) == warning)
        #expect(state.update(to: updatedWarning) == nil)
        #expect(state.update(to: error) == error)
        #expect(state.update(to: nil) == nil)
        #expect(state.update(to: warning) == warning)
    }

    @Test func toolPagesDoNotHandBuildPersistentDiagnostics() throws {
        let packageRoot = try sourcePackageRoot()
        let root = packageRoot.appendingPathComponent("Sources/XTools/ToolPages")
        let fileManager = FileManager.default
        let enumerator = try #require(fileManager.enumerator(at: root, includingPropertiesForKeys: nil))
        let swiftFiles = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }

        for url in swiftFiles {
            let source = try String(contentsOf: url, encoding: .utf8)
            let relativePath = url.path.replacingOccurrences(of: packageRoot.path + "/", with: "")
            let isSharedDiagnosticOwner = (relativePath.hasSuffix("Sources/XTools/ToolPages/Workbench/Diagnostics/IndexResultDisplays.swift") || relativePath.hasSuffix("Sources/XTools/ToolPages/Workbench/PageChrome/IndexPageShell.swift") || relativePath.hasSuffix("Sources/XTools/ToolPages/Workbench/PageChrome/IndexWorkspaceSurfaces.swift"))

            if !isSharedDiagnosticOwner {
                doesNotContain(source, "IndexWorkspaceDiagnostic(text:", "\(relativePath) must not insert workspace diagnostics as ordinary body content")
                doesNotContain(source, "ToolFeedbackTone.error.systemImage", "\(relativePath) must not hand-build persistent error labels; use indexWorkspaceDiagnostic")
                doesNotContain(source, "ToolFeedbackTone.error.softFill", "\(relativePath) must not hand-build persistent error card fills; use indexWorkspaceDiagnostic")
                doesNotContain(source, ".accessibilityLabel(\"错误：", "\(relativePath) must not hand-build persistent error accessibility labels; use indexWorkspaceDiagnostic")
            }

            doesNotContain(source, "IndexInputErrorLine", "\(relativePath) must not use the removed inline input-error row")
            doesNotContain(source, ".indexFloatingError(", "\(relativePath) must not use the removed floating-error API")
        }
    }

    @Test func toastCenterUsesBottomTrailingSafeAreaAndBoundedQueue() throws {
        let source = try readSource("Sources/XTools/Shared/Components/ToastCenter.swift")
        let tone = try readSource("Sources/XTools/Shared/Components/ToolFeedbackTone.swift")
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")

        contains(tone, "enum ToolFeedbackTone: Equatable", "Transient feedback and diagnostics must share one tone model")
        contains(tone, "case success", "Feedback tone must include success")
        contains(tone, "case error", "Feedback tone must include error")
        contains(tone, "case warning", "Feedback tone must include warning")
        contains(tone, "case info", "Feedback tone must include info")
        contains(tone, "var defaultToastDuration: TimeInterval", "Tone must own default toast duration")
        contains(source, "static let maxVisibleMessages = 4", "Toast queue must cap visible messages at four")
        contains(source, "@Published private(set) var messages: [ToolToastMessage] = []", "Toast center must expose a bounded message stack")
        contains(source, "messages.removeFirst(overflow)", "Toast overflow must discard the oldest messages")
        contains(source, "func pauseDismissal(for id: UUID)", "Toast center must support hover pause")
        contains(source, "func resumeDismissal(for id: UUID)", "Toast center must support hover resume")
        contains(source, "Button {\n                center.dismiss(message.id)", "Toast card must provide an always-visible close button")
        contains(source, "ZStack(alignment: .bottomTrailing)", "Toast host must follow the bottom-right convention used by mature developer tools")
        contains(source, "ForEach(center.messages)", "Bottom-right messages must keep the newest toast nearest the window edge")
        contains(source, ".frame(maxWidth: 360, alignment: .bottomTrailing)", "Toast host must keep the existing bounded card width at the trailing edge")
        contains(source, "ToolAccessibilityAnnouncer", "Toast center must use an accessibility announcement adapter")
        doesNotContain(source, "@Published private(set) var current", "Old single-current toast state must not remain")
        doesNotContain(source, "ZStack(alignment: .bottom)", "Toast host must not remain centered across the sidebar and workspace")
        doesNotContain(source, "ZStack(alignment: .topTrailing)", "Toast host must not stack downward across the page action row")
        contains(root, "toastCenter.show(nowFavorite ? \"已加入收藏\" : \"已取消收藏\", tone: .success)", "Favorite changes must use success feedback")
        contains(root, "toastCenter.show(next.toastMessage, tone: .success)", "Theme changes must use success feedback")
        doesNotContain(root, ".alert(\"设置\"", "Non-critical settings placeholder must not use a modal alert")
    }

    @Test @MainActor func toastCenterKeepsBoundedMessagesCurrentWithoutDelayedReplay() {
        let announcer = RecordingToolAccessibilityAnnouncer()
        let center = ToolToastCenter(announcer: announcer)

        center.show("one", tone: .info)
        center.show("two", tone: .warning)
        center.show("three", tone: .error)
        center.show("four", tone: .success)
        center.show("five", tone: .info)

        #expect(center.messages.map(\.text) == ["two", "three", "four", "five"])
        #expect(announcer.announcements == [
            "信息：one",
            "警告：two",
            "错误：three",
            "成功：four",
            "信息：five",
        ])

        while let current = center.messages.first {
            center.dismiss(current.id)
        }
    }

    @Test func emptyResultSurfacesAvoidScrollContainers() throws {
        let textComponents = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let sharedComponents = try readSharedBagComponents()
        let resultPresence = try readSource("Sources/XTools/ToolPages/Workbench/Diagnostics/IndexResultPresence.swift")
        let chronometer = try readSource("Sources/XTools/ToolPages/Time/ChronometerPage.swift")
        let httpStatus = try readSource("Sources/XTools/ToolPages/Web/HTTPStatusCodesPage.swift")

        contains(textComponents, "if text.isEmpty", "Output surfaces must branch on empty text before creating a ScrollView")
        contains(textComponents, "placeholderBody", "Output surfaces must render empty placeholders without creating a ScrollView")
        contains(textComponents, "if scrollsInternally {\n                    ScrollView {", "Output surfaces must only create ScrollView for non-empty internally scrolling output")
        contains(textComponents, "private var placeholderBody: some View", "Output surfaces must have a non-scrolling placeholder body")
        contains(textComponents, ".frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)", "Output surfaces must keep non-scrolling content top-aligned instead of centering it in tall panes")
        contains(sharedComponents, "struct IndexScrollableKV: View", "Shared scrollable KV remains available for explicit scrolling exceptions")
        contains(resultPresence, "if presentation.phase == .empty", "Scrollable result presence must render empty content without a ScrollView")
        contains(resultPresence, "} else if let displayedValue {\n            ScrollView {", "Scrollable result presence must create its internal ScrollView only for non-empty history")
        contains(chronometer, "IndexScrollableKV(rows: lapRows, emptyText: IndexEmptyStateCopy.noRecords, copyable: false, valueMotion: .immediate)", "Chronometer must keep leaf text replacement immediate while structural presence owns lap motion")
        contains(httpStatus, "if filtered.isEmpty {\n                    emptyState\n                } else {\n                    List(filtered) { row in", "HTTP status empty search results must stay outside the native list")
    }

    @Test func fillingOutputSurfacesUseCompactEmptyMinimumHeight() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")

        contains(source, "private var effectiveMinHeight: CGFloat", "Output surfaces must compute a compact minimum height for filling layouts")
        contains(source, "fillsHeight ? 60 : minHeight", "Filling output surfaces must use the same compact 60pt floor as input text areas")
        contains(source, "minHeight: effectiveMinHeight", "Output placeholder and content bodies must use the compact minimum height")
    }

    @Test func sharedNumberInputSupportsDirectEditingAndBounds() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")

        contains(source, "struct IndexNumberInput: View", "Shared controls must define an IndexNumberInput")
        contains(source, "let range: ClosedRange<Int>", "IndexNumberInput must accept an integer range")
        contains(source, "@Binding var value: Int", "IndexNumberInput must bind to an integer value")
        contains(source, "IndexTextInput(", "IndexNumberInput must support direct text entry")
        doesNotContain(source, "stepButton(systemImage: \"minus\"", "IndexNumberInput must not show a minus button")
        doesNotContain(source, "stepButton(systemImage: \"plus\"", "IndexNumberInput must not show a plus button")
        contains(source, "onSubmit: commitText", "IndexNumberInput must normalize typed input on submit")
        contains(source, "onFocusChange: { focused in", "IndexNumberInput must normalize typed input when focus leaves the field")
    }

    @Test func sliderControlsUsePureSwiftUIToAvoidNSSliderEntryLag() throws {
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")
        let color = try readSource("Sources/XTools/ToolPages/Image/ColorPickerPage.swift")
        let imageConverter = try readSource("Sources/XTools/ToolPages/Image/ImageConverterPage.swift")
        let imageWatermark = try readSource("Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift")

        // 根因（实测）：SwiftUI.Slider 桥接 AppKit NSSlider，本工具链上单个实例化约
        // 230ms；颜色页三个 Slider 叠加约 700ms，是「点击进入颜色转换要等一下」的唯一
        // 主因。经 B1/B3/B4/B5a/B6/B7 单变量 A/B 逐个证伪其他假设后确认。替换为纯 SwiftUI
        // 自绘 IndexSlider 后，进入首帧从约 816ms 降到约 158ms。此契约防止任何页面回退到
        // 原生 Slider 而让卡顿复发。
        contains(controls, "struct IndexSlider: View", "Shared controls must define a pure-SwiftUI slider to avoid the NSSlider entry cost")
        contains(controls, "DragGesture(minimumDistance: 0)", "IndexSlider must drive its value from a SwiftUI drag gesture rather than an AppKit bridge")
        contains(controls, "accessibilityAdjustableAction", "IndexSlider must stay keyboard/VoiceOver adjustable")

        doesNotContain(color, " Slider(", "Color page sliders must use IndexSlider; native Slider reintroduces the measured NSSlider entry lag")
        doesNotContain(imageConverter, " Slider(", "Image converter quality slider must use IndexSlider to avoid NSSlider entry lag")
        doesNotContain(imageWatermark, " Slider(", "Image watermark opacity slider must use IndexSlider to avoid NSSlider entry lag")
        contains(color, "IndexSlider(value: value, range: range, step: 1, track: track)", "Color page must drive H/S/L through the shared IndexSlider")
        contains(imageConverter, "IndexSlider(value: $quality, range: 0.1...1.0, step: 0)", "Image converter must keep a continuous quality slider through IndexSlider")
        contains(imageWatermark, "IndexSlider(value: $opacity, range: 0.1...1.0, step: 0)", "Image watermark must keep a continuous opacity slider through IndexSlider")
    }

    @Test func sharedOptionControlsPreventCompressedVerticalLabels() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")

        contains(source, "struct IndexOptionLabel: View", "Shared controls must define a non-wrapping option label")
        contains(source, ".lineLimit(1)", "Option labels must stay on one line instead of stacking vertically")
        contains(source, ".fixedSize(horizontal: true, vertical: false)", "Option labels and groups must keep their intrinsic width under pressure")
    }

    @Test func appRemovesObsoleteSearchAndRunHints() throws {
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")
        let sidebar = try readSource("Sources/XTools/AppShell/SidebarView.swift")
        let uuidGenerator = try readSource("Sources/XTools/ToolPages/Crypto/UUIDGeneratorPage.swift")

        doesNotContain(root, "/ 搜索", "Status bar must not advertise slash search")
        doesNotContain(root, "⌘↵ 运行", "Status bar must not advertise Command-Return run")
        doesNotContain(root, "K 命令", "Status bar must not advertise command actions")
        doesNotContain(sidebar, "Text(\"/\")", "Sidebar search field must not show the slash keycap")
        // The prototype reintroduced per-page ⌘↩ as an in-page primary action
        // (UUID 生成 / JSON 格式化); the shell-level "run" advertising stays gone.
        contains(uuidGenerator, ".keyboardShortcut(.return, modifiers: .command)", "UUID generator binds Command-Return to its primary generate action")
    }

    @Test func task11UIConsistencyUsesIndexControls() throws {
        let integerBase = try readSource("Sources/XTools/ToolPages/Converter/IntegerBaseConverterPage.swift")
        let jsonFormatter = try readSource("Sources/XTools/ToolPages/Development/JSONFormatterPage.swift")
        let base64File = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        let fileType = try readSource("Sources/XTools/ToolPages/Utility/FileTypeDetectorPage.swift")

        doesNotContain(integerBase, "Picker(\"\", selection: $base)", "Integer base input base selection must not use the native Picker")
        contains(integerBase, "items: [(\"2\", \"二进制\"), (\"8\", \"八进制\"), (\"10\", \"十进制\"), (\"16\", \"十六进制\")]", "Integer base input base selection must use the shared IndexOptionPicker")
        contains(integerBase, "IndexClearButton(isDisabled: workspace.input.isEmpty && workspace.error == nil)", "Integer base clear action must use the shared IndexClearButton in the input panel header")

        contains(jsonFormatter, "IndexFormatWorkbench(", "JSON formatter must use the shared prototype workbench")
        contains(jsonFormatter, "IndexSegmentedControl(", "JSON indent must use the shared segmented control inside the workbench toolbar")
        contains(jsonFormatter, "outputLineNumbers: true", "JSON must keep the line-number gutters on both panes")
        doesNotContain(jsonFormatter, "Toggle(\"键排序\"", "JSON formatter must not fall back to a native Toggle")
        doesNotContain(jsonFormatter, "Picker(\"缩进\"", "JSON formatter must not fall back to a native Picker")
        contains(jsonFormatter, "IndexOptionSwitch(", "JSON formatter provides the key-sort switch")
        doesNotContain(jsonFormatter, ".animation(", "Optional-control reveal must not bind page-level animations")

        contains(base64File, "Text(\"选择或拖入文件\")", "Base64 file page may advertise drag and drop only because it implements the workflow")
        doesNotContain(base64File, "Text(\"正在读取文件...\")", "Base64 import must not collapse the stable two-line picker into a transient loading row")
        contains(base64File, "if session.isReadingFile && isShowingFileReadProgress {\n                IndexProgressSpinner()", "Base64 import must keep delayed reading feedback inside the fixed icon slot")
        contains(base64File, ".indexDropZone(", "Base64 file page drag-and-drop promise must be backed by the shared drop zone")

        contains(fileType, "Text(\"也可拖入单个普通文件\")", "File type detector must advertise its implemented single-file drop path")
        contains(fileType, ".indexDropZone(", "File type detector drag-and-drop promise must be backed by the shared drop zone")
        let dropZone = try readSource("Sources/XTools/Shared/Components/IndexDropZone.swift")
        contains(dropZone, ".dropDestination(for: URL.self)", "The shared drop zone must implement the platform drop destination once")
        contains(dropZone, "withToolAnimation(ToolMotion.Preset.controlFeedback) {\n                    isTargeted = targeted\n                }", "The shared drop zone must expose targeted feedback through the shared motion transaction")
    }

    @Test @MainActor func fixedInternalTextAreaRevealsInsertionPointAfterLargePaste() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        scrollView.hasVerticalScroller = true
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 1600))
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 13, height: 12)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        scrollView.documentView = textView

        textView.string = (0..<240).map { "line-\($0)" }.joined(separator: "\n")
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.frame.size.height = max(textView.frame.height, textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? textView.frame.height)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        IndexTextAreaScrollPositioning.revealInsertionPointNow(in: textView, growsWithContent: false)

        #expect(scrollView.contentView.bounds.maxY >= insertionPointMaxY(in: textView) - 1, "Large paste should scroll the fixed internal editor to the insertion point at the end")
        #expect(scrollView.contentView.bounds.origin.y > 0, "Large paste should move the internal scroll view away from the top")
    }

    @Test @MainActor func contentGrowingTextAreaRevealDoesNotMoveInternalClipView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 1600))
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        textView.string = (0..<240).map { "line-\($0)" }.joined(separator: "\n")
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        IndexTextAreaScrollPositioning.revealInsertionPointNow(in: textView, growsWithContent: true)

        #expect(scrollView.contentView.bounds.origin == .zero, "Naturally growing text areas rely on the page scroll and must not scroll their hidden internal clip view")
    }

    @MainActor
    private func insertionPointMaxY(in textView: NSTextView) -> CGFloat {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return textView.visibleRect.maxY
        }

        layoutManager.ensureLayout(for: textContainer)
        let textLength = (textView.string as NSString).length
        guard textLength > 0 else {
            return 0
        }

        let characterRange = NSRange(location: textLength - 1, length: 1)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        return glyphRect.maxY + textView.textContainerInset.height
    }

    @Test func sharedNumberInputFiltersAndClampsEditingText() throws {
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")

        contains(controls, "var minimumDigits = 1", "Shared number input must support fixed-width date/time fields without changing existing call sites")
        contains(controls, "selectAllOnFocus: true", "Shared number input must select the whole number on focus so replacements do not require cursor surgery")
        contains(controls, ".onChange(of: text) { _ in\n            sanitizeEditingText()", "Shared number input must validate editing text while the field is focused")
        contains(controls, "let digitsOnly = text.filter(\\.isNumber)", "Shared number input must reject non-numeric typed characters")
        contains(controls, "typedValue > range.upperBound", "Shared number input must detect values beyond the configured range")
        contains(controls, "setValue(range.upperBound)", "Shared number input must clamp overflow text back to the configured upper bound")
    }

    @Test func pageLayoutDefaultIsFillProtectsUnnamedPages() throws {
        let source = try readSharedBagComponents()

        contains(source, "case fill", "IndexPageLayout must have a fill case as the default layout")
        contains(source, "case scroll", "IndexPageLayout must have a scroll case")
        contains(source, "enum IndexPageLayout", "IndexPageLayout must be defined as an enum")
        contains(source, "var scrollsExternally: Bool", "IndexPageLayout must expose a scrollsExternally query")
        contains(source, "case .fill: return false", "fill mode must indicate no external scrolling")
        contains(source, "case .scroll: return true", "scroll mode must indicate external scrolling")
    }

    @Test func sharedIOPairDoesNotDefaultToExternallyScrolling() throws {
        let source = try readSharedBagComponents()

        contains(source, "var layout: IndexPageLayout = .fill", "IndexPage default must be fill to protect unnamed pages from automatically migrating to external scrolling")
    }

    @Test func appShellSidebarAndPageChromeUseUnifiedToolIdentity() throws {
        let app = try readSource("Sources/XTools/XToolsApp.swift")
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")
        let sidebarCommands = try readSource("Sources/XTools/AppShell/SidebarCommands.swift")
        let toolbar = try readSource("Sources/XTools/AppShell/TitlebarView.swift")
        let sidebar = try readSource("Sources/XTools/AppShell/SidebarView.swift")
        let typography = try readSource("Sources/XTools/Shared/ToolTypography.swift")
        let sharedComponents = try readSharedBagComponents()
        let converter = try readSource("Sources/XTools/ToolPages/Workbench/Converter/IndexConverterPage.swift")
        let json = try readSource("Sources/XTools/ToolPages/Development/JSONFormatterPage.swift")
        let sql = try readSource("Sources/XTools/ToolPages/Development/SQLPrettifyPage.swift")

        contains(root, "enum SidebarVisibility: Equatable", "Root shell must use an explicit sidebar visibility state")
        contains(root, "private var detailColumn: some View", "Detail chrome must stay in one stable detail column")
        contains(root, "ToolDetailHostView(", "Tool detail must consume the full detail-column height below the native toolbar")
        doesNotContain(root, "ToolStatusBar", "App shell must not retain a bottom status bar without exclusive persistent state")
        doesNotContain(root, "statusMessage", "App shell must not duplicate tool identity or static ready copy below every tool")
        doesNotContain(root, "isWorkspaceFocused", "Root state must not duplicate sidebar hiding with a workspace-focus flag")
        doesNotContain(root, "sidebarVisibilityBeforeFocus", "Root state must not retain a focus-only sidebar snapshot")
        doesNotContain(root, "toggleWorkspaceFocus", "Root must not expose a second action with the same layout result as hiding the sidebar")
        contains(root, ".frame(width: viewModel.sidebarVisibility == .visible ? SidebarView.idealWidth : 0)", "Sidebar visibility must animate one stable pane width instead of swapping rail trees")
        contains(root, ".focusedSceneObject(viewModel)", "Root must expose the current window's observable app-shell actions to scene commands")
        contains(root, "var sidebarTogglePresentation: SidebarTogglePresentation", "Root state must publish one sidebar presentation seam")
        contains(root, "func toggleSidebar(reduceMotion: Bool)", "Root state must publish one sidebar action seam")
        contains(root, "sidebarVisibility == .visible ? .hide : .show", "Sidebar presentation must derive only from actual visibility")
        contains(root, "sidebarVisibility = sidebarVisibility == .hidden ? .visible : .hidden", "Sidebar action must perform a direct visible-hidden transition")
        doesNotContain(root, "Button(\"Toggle Sidebar\"", "Root must not keep a second invisible Command-B registration")
        doesNotContain(root, "registry.toolCount", "App shell chrome must not expose the registry size as status")
        contains(sidebarCommands, "CommandGroup(before: .sidebar)", "Sidebar visibility must live in the standard View-menu command area")
        contains(sidebarCommands, "return \"显示侧边栏\"", "Sidebar show copy must have one shared source")
        contains(sidebarCommands, "return \"隐藏侧边栏\"", "Sidebar hide copy must have one shared source")
        contains(sidebarCommands, "\"\\(title)（⌘B）\"", "Sidebar contextual help must append the discoverable shortcut to the current action")
        doesNotContain(sidebarCommands, "statusHint", "Sidebar presentation must not retain copy used only by the removed bottom bar")
        contains(sidebarCommands, "@FocusedObject private var viewModel: RootViewModel?", "Sidebar commands must target the focused window")
        contains(sidebarCommands, "viewModel?.toggleSidebar(reduceMotion: reduceMotion)", "The menu and toolbar must share the same sidebar state transition")
        contains(sidebarCommands, ".keyboardShortcut(\"b\", modifiers: .command)", "The menu command must own the standard Command-B shortcut")
        contains(sidebarCommands, ".disabled(viewModel == nil)", "The sidebar menu command must disable without a focused window action")
        contains(app, "SidebarMenuCommands()", "The app scene must install the sidebar menu command")
        doesNotContain(root, "isSidebarCollapsed", "Root must not retain the ambiguous collapsed sidebar state")
        doesNotContain(root, "NavigationSplitView(", "The custom sidebar must not add a duplicate system sidebar or toolbar")
        contains(app, ".windowToolbarStyle(.unifiedCompact(showsTitle: false))", "The window must use the native compact unified macOS toolbar")
        contains(root, ".toolbar {", "Root must project shell actions into the native toolbar")
        doesNotContain(root, "TitlebarView(", "The detail column must not keep a second custom titlebar row")
        contains(toolbar, "struct WindowToolbarContent: ToolbarContent", "App shell chrome must use native toolbar placements")
        contains(toolbar, "ToolbarItem(placement: .navigation)", "Sidebar toggle must live at the toolbar leading edge")
        contains(toolbar, "SidebarToggleButton(", "Leading navigation must host the sidebar toggle")
        doesNotContain(toolbar, "WindowToolbarToolContext", "Toolbar must not retain a tool breadcrumb context view")
        doesNotContain(toolbar, "leadingItemSpacing", "Toolbar leading slot no longer pairs toggle with breadcrumb spacing")
        doesNotContain(toolbar, "categoryTitle", "Toolbar must not accept category breadcrumb plumbing")
        contains(toolbar, "if #available(macOS 26, *) {\n            ToolbarSpacer(.flexible)\n        }", "Modern macOS must use the native flexible toolbar spacer while older supported systems retain placement fallback")
        contains(toolbar, "ToolbarItemGroup(placement: .primaryAction)", "Favorite and command palette must live in the toolbar action area")
        contains(toolbar, "let isSidebarVisible: Bool", "Toolbar must receive explicit complete-sidebar visibility")
        contains(toolbar, "let selectedTool: RegisteredTool?", "Toolbar keeps selected tool only for favorite visibility")
        doesNotContain(toolbar, "isWorkspaceFocused", "Toolbar must not retain a focus state that only duplicates sidebar hiding")
        doesNotContain(toolbar, "onToggleWorkspaceFocus", "Toolbar must expose only one sidebar-visibility action")
        doesNotContain(toolbar, "isCollapsed", "Toolbar sidebar control must use actual visibility naming")
        contains(toolbar, ".help(presentation.help)", "The toolbar toggle must disclose Command-B through the shared contextual help")
        contains(toolbar, ".accessibilityLabel(presentation.title)", "The toolbar toggle must expose the current action as its accessible name")
        contains(toolbar, ".accessibilityHint(SidebarTogglePresentation.accessibilityHint)", "The toolbar toggle must expose the shortcut separately as an accessibility hint")
        contains(toolbar, "Text(\"跳转工具…\")", "The command trigger must keep its visible label instead of collapsing to an icon-only toolbar item")
        contains(toolbar, "Text(\"⌘K\")", "The command trigger must remain the only visible keyboard hint in window chrome")
        contains(sidebar, "static let idealWidth: CGFloat = 220", "Sidebar must expose one stable ideal pane width")
        doesNotContain(sidebar, "isCollapsed", "Sidebar must not retain the collapsed rail state")
        contains(sidebar, "static let titlebarHeight: CGFloat = 40", "Sidebar brand band must stay compact under the native unified toolbar")
        contains(sidebar, ".frame(height: SidebarMetrics.titlebarHeight, alignment: .center)", "Brand mark + copy must stay vertically centered in the brand band")
        contains(sidebar, "static let searchTopPadding: CGFloat = 0", "Search must sit flush under the brand band")
        contains(sidebar, "static let searchBottomPadding: CGFloat = 8", "Search must keep a stable bottom inset before the navigation list")
        contains(sidebar, ".padding(.top, SidebarMetrics.searchTopPadding)", "Search top inset must use the shared metric token")
        contains(sidebar, ".padding(.bottom, SidebarMetrics.searchBottomPadding)", "Search bottom inset must use the shared metric token")
        contains(sidebar, "HStack(spacing: 8) {\n                BrandMark()", "Brand mark and copy must share one compact 8pt identity stack")
        contains(typography, "static let pageTitle = Font.system(size: 18, weight: .semibold)", "All tool pages must share the same static in-page title typography")
        contains(typography, "static let pageSubtitle = Font.system(size: 12.5)", "All tool pages must share the same static in-page subtitle typography")
        contains(sharedComponents, "enum IndexPageChrome", "Tool pages must expose page-level chrome density")
        contains(sharedComponents, "case compactWorkspace", "Editor-heavy workbenches must have a compact page chrome option")
        contains(sharedComponents, "case .standard, .compactWorkspace: return 30", "All tool pages must share one content left edge")
        contains(sharedComponents, "case .standard: return 6", "Standard pages must keep a compact top inset under the toolbar")
        contains(sharedComponents, "case .compactWorkspace: return 5", "Compact workbenches must sit slightly tighter under the toolbar")
        contains(sharedComponents, "var topPadding: CGFloat", "Page chrome must expose an asymmetric top padding token")
        contains(sharedComponents, "var bottomPadding: CGFloat", "Page chrome must expose an asymmetric bottom padding token")
        contains(sharedComponents, "case .standard: return 10", "Standard pages must keep a slightly larger bottom inset than the top")
        contains(sharedComponents, "case .compactWorkspace: return 8", "Compact workbenches must keep a slightly larger bottom inset than the top")
        contains(sharedComponents, "case .standard: return 10", "Title-to-content section spacing must keep Clay Warmth breathing room")
        contains(sharedComponents, "case .standard: return 5", "Header bottom padding must stay compact under the subtitle")
        contains(sharedComponents, "var headerBottomPadding: CGFloat", "All tool pages must share one header-to-workspace separation token")
        contains(sharedComponents, ".padding(.top, chrome.topPadding)", "The shared page must apply the top chrome inset")
        contains(sharedComponents, ".padding(.bottom, chrome.bottomPadding)", "The shared page must apply the bottom chrome inset")
        contains(sharedComponents, ".padding(.bottom, chrome.headerBottomPadding)", "The shared page header must reserve its approved bottom rhythm")
        contains(sharedComponents, "VStack(alignment: .leading, spacing: 2)", "Title and subtitle must use a tight 2pt stack")
        contains(sharedComponents, ".overlay(alignment: .bottom)", "The shared page header must draw one semantic bottom divider")
        contains(sharedComponents, "private var header: some View", "Every tool page must render one shared content-area header")
        contains(sharedComponents, ".font(ToolTypography.pageTitle)", "IndexPage title must use the shared page title token")
        contains(sharedComponents, ".font(ToolTypography.pageSubtitle)", "IndexPage subtitle must use the shared page subtitle token")
        contains(sharedComponents, ".lineLimit(2)", "Shared subtitles must fit compact pages without overflowing")
        doesNotContain(sharedComponents, "IndexPageHeaderStyle", "Page chrome must not fork standard and compact title treatments")
        doesNotContain(sharedComponents, "headerStyle", "Page chrome must control density, not title treatment")
        doesNotContain(sharedComponents, "standardHeader", "Standard pages must not keep a separate large title block")
        doesNotContain(sharedComponents, "compactHeader", "Compact pages must not use a page-specific title block")
        doesNotContain(sharedComponents, "showsHeader", "Compact workspace chrome must not hide tool identity inside the content area")
        contains(sharedComponents, ".padding(.horizontal, chrome.horizontalPadding)", "Page horizontal padding must come from the chrome density")
        contains(converter, "IndexPage(title, subtitle: subtitle, workspaceSemantic: .copyTransformWorkspace)", "Shared converter workbenches must resolve chrome through the settled copy-transform semantic")
        contains(json, "workspaceSemantic: .structuredEditorTransform", "JSON must opt into the semantic that resolves the compact fixed editor workbench shell")
        contains(sql, "workspaceSemantic: .structuredEditorTransform", "SQL must opt into the semantic that resolves the compact fixed editor workbench shell")
    }

    @Test func layoutSafetyContractIsDocumentedInChinese() throws {
        let source = try readSharedBagComponents()

        contains(source, "布局安全护栏", "IndexPageLayout must document layout safety guards in Chinese")
        contains(source, "布局安全合同", "IndexPageLayout must document the layout safety contract in Chinese")
        contains(source, "默认值安全规则", "IndexPageLayout must document the default-value safety rule in Chinese")
        contains(source, "未点名页面不会被自动迁移", "Default value safety must explicitly say unnamed pages are not auto-migrated")
        contains(source, "固定输入工作区", "Layout safety must protect fixed input workspaces")
        contains(source, "复制型转换工作区", "Layout safety must protect copy-conversion workspaces")
        contains(source, "查询列表工作区", "Layout safety must protect query/list workspaces")
        contains(source, "不通过 spacer、空白占位、额外容器或整体下移制造外层滚动效果", "Layout safety must forbid spacers, blanks, and shifting to create external scrolling")
    }

    @Test func sidebarNavigationUsesOneStableAppKitRenderer() throws {
        let sidebar = try readSource("Sources/XTools/AppShell/SidebarView.swift")
        let entries = try readSource("Sources/XTools/AppShell/SidebarNavigationEntry.swift")
        let renderer = try [
            readSource("Sources/XTools/AppShell/SidebarNavigationList.swift"),
            readSource("Sources/XTools/AppShell/SidebarNavigationListRepresentable.swift"),
            readSource("Sources/XTools/AppShell/SidebarNavigationListCoordinator.swift"),
            readSource("Sources/XTools/AppShell/SidebarNavigationTrackView.swift"),
        ].joined(separator: "\n")

        let toolRow = sourceSlice(
            sidebar,
            from: "struct SidebarToolRow: View",
            to: "@MainActor\nprivate final class SidebarHoverState"
        )

        contains(sidebar, "SidebarNavigationList(configuration:", "SidebarView must keep one production list renderer")
        doesNotContain(sidebar, "ForEach(sidebarEntries)", "Sidebar disclosure must not structurally remove live tool rows")
        contains(entries, "id: \"tool.\\(item.id.rawValue)\"", "Tool tracks must preserve stable ToolID identity")
        contains(renderer, "final class SidebarNavigationScrollView: NSScrollView", "The renderer must own one native scroll viewport")
        contains(renderer, "let documentView = SidebarNavigationDocumentView()", "The coordinator must own one flipped flat document")
        contains(renderer, "NSHostingView<SidebarNavigationTrackRoot>", "Each semantic track must keep a real hosted SwiftUI view")
        contains(renderer, "tracksByID[target.id] ?? makeTrack", "The renderer must reuse cached tracks instead of duplicating tools")
        contains(renderer, "animator().frame = target.frame", "Disclosure motion must animate real wrapper frames")
        contains(renderer, "animationGate.accepts(token)", "Animation completion must reject stale generations")
        contains(renderer, "shouldSkipPresentationUpdate", "Unchanged plan + presentation inputs must short-circuit full hosted rewrites")
        contains(renderer, "guard activeAnimationToken == nil else", "Presentation short-circuit must never suppress an in-flight animation generation")
        contains(renderer, "HostedContentKey", "Hosted rootView rewrites must key on entry/selection/interaction presentation inputs")
        contains(renderer, "hostedContentKeysByTrackID[track.trackID] == key", "Equal hosted content keys must skip NSHostingView.rootView assignment")
        contains(renderer, "guard currentIDs != targetIDs else { return }", "Track reorder must no-op when the active ID sequence is already correct")
        contains(renderer, "applyAccessibilityHidden", "Collapse preparation must recursively leave the accessibility tree")
        contains(renderer, "applyControlsEnabled", "Collapse preparation must disable real hosted controls")
        contains(renderer, "acceptsPresentationSelection", "Expanding tracks must distinguish visible presentation selection from model-frame hit testing")
        contains(renderer, "layer?.presentation()?.frame", "Animated selection must resolve the visible presentation frame instead of the final model frame")
        contains(renderer, "finishActiveAnimationIfNeeded", "User input must safely land the latest animation target before navigation")
        contains(renderer, "final class SidebarNavigationTrackHoverState: ObservableObject", "Stable AppKit tool tracks must own reusable hover presentation state")
        contains(renderer, "NSTrackingArea(", "The stable document view must own native pointer tracking")
        contains(renderer, ".mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect", "Sidebar pointer tracking must follow the visible document area in the key window")
        contains(renderer, "mouseLocationOutsideOfEventStream", "Geometry changes must reconcile hover without waiting for a new pointer event")
        contains(renderer, "func updatePointerLocation(_ point: CGPoint?)", "Document events and geometry reconciliation must share one deterministic pointer input seam")
        contains(toolRow, "@ObservedObject var hoverState: SidebarNavigationTrackHoverState", "Tool rows must consume AppKit-owned hover state across favorite migration")
        doesNotContain(toolRow, ".onHover", "Tool rows must not keep a second SwiftUI hover truth after AppKit moves their stable track")
        contains(toolRow, ".contentShape(Rectangle())", "Sidebar favorite controls must expose the complete fixed slot as the pointer target")
        doesNotContain(renderer, "Timer.", "Sidebar disclosure must remain event-driven")
        doesNotContain(renderer, "snapshot", "Sidebar disclosure must not animate bitmap snapshots")
        doesNotContain(renderer, "SidebarNavigationLayout.interpolate", "Production layout must not keep the deleted interpolate helper")
        doesNotContain(entries, "isDisclosureContent", "Disclosure collapse is encoded by presented heights, not a production flag")
        doesNotContain(entries, "SpacingRole", "Spacing tracks use stable IDs; production must not keep unused role discriminators")
    }
}

@MainActor
private final class RecordingToolAccessibilityAnnouncer: ToolAccessibilityAnnouncing {
    private(set) var announcements: [String] = []

    func announceStatus(_ text: String) {
        announcements.append(text)
    }
}
