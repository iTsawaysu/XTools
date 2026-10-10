import Foundation
import AppKit
@testable import XTools
import Testing

/// Shared UI infrastructure contracts.
///
/// Symbol-level and structural anchors only: shared components must exist,
/// pages must consume them, and forbidden patterns (SwiftUI TextField for
/// undoable editors, native Slider, hand-built persistent diagnostics) must
/// not return. Behavior tests below assert the runtime halves that can be
/// driven directly; multi-line indentation-sensitive needles were retired.
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
        contains(source, "struct IndexTextAreaInputPolicy", "Shared text areas must expose an optional input policy for high-risk editors")
        contains(source, "shouldChangeTextIn affectedCharRange: NSRange", "Shared text areas must reject configured oversized edits before insertion")
        contains(source, "func undoManager(for view: NSTextView) -> UndoManager?", "Shared text areas must always vend a private undo manager, never the shared window manager")
        contains(source, "var temporaryHighlights: IndexTextAreaTemporaryHighlights? = nil", "Shared multiline inputs must keep temporary highlighting opt-in")
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
        doesNotContain(viewport, "textView.layoutManager", "The TextKit 2 viewport must never request the legacy layout manager")
        doesNotContain(viewport, "ensureLayout(for:", "The TextKit 2 viewport must not force full document layout")
        doesNotContain(viewport, "usedRect(for:", "The TextKit 2 viewport must not measure full document geometry")
        doesNotContain(viewport, "TemporaryHighlightRenderer", "The TextKit 2 viewport must not access the TextKit 1 temporary-attribute renderer")

        let textView = IndexTextKit2ViewportTextView.makeTextView()
        #expect(textView.textLayoutManager != nil)
    }

    @Test func sharedSingleLineInputUsesUndoableAppKitTextField() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let geometry = try readSource("Sources/XTools/Shared/Components/AppKitTextFieldGeometry.swift")
        let dateCalculator = try readSource("Sources/XTools/ToolPages/Time/DateCalculatorPage.swift")
        let textEditingConfig = try readSource("Sources/XTools/Shared/Components/AppKitTextEditingConfiguration.swift")

        contains(source, "struct IndexUndoableTextField: NSViewRepresentable", "Shared single-line inputs must use an AppKit-backed text field")
        contains(source, "IndexUndoableTextField(", "IndexTextInput must render the undoable text field")
        doesNotContain(source, "TextField(placeholder, text: $text)", "IndexTextInput must not use the SwiftUI TextField because Command-Z is unreliable there")
        doesNotContain(source, "SecureField(placeholder, text: $text)", "IndexTextInput secure mode must also use the shared AppKit-backed field")
        contains(source, "AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: textField)", "Shared single-line inputs must enable native field-editor undo through the shared AppKit text configuration")
        contains(textEditingConfig, "configureCurrentFieldEditor(for textField: NSTextField", "Shared AppKit text configuration must support NSTextField field editors")
        contains(source, "func controlTextDidChange(_ notification: Notification)", "Shared single-line inputs must sync NSTextField edits back into SwiftUI state")
        contains(source, "var onEscape: (() -> Void)? = nil", "Shared single-line inputs must expose an optional Escape action")
        contains(source, "#selector(NSResponder.cancelOperation(_:))", "The AppKit field bridge must handle Escape through native command routing")
        contains(geometry, "class IndexPaddedTextFieldCell: NSTextFieldCell", "Shared inputs must keep plain text in an AppKit cell with internal content geometry")
        contains(geometry, "final class IndexPaddedSecureTextFieldCell: NSSecureTextFieldCell", "Secure inputs must preserve NSSecureTextFieldCell semantics while applying the same content geometry")
        doesNotContain(dateCalculator, "TextField(\"\", value: $amount", "Date calculator amount input must not bypass the shared undoable input component")
        contains(dateCalculator, "IndexNumberInput(value: $session.amount", "Date calculator amount input must reuse the shared undoable number input via session binding")
    }

    @Test func windowChromeDismissesEditingOnOutsideMouseDownWithoutConsumingClicks() throws {
        let source = try readSource("Sources/XTools/AppShell/WindowChromeConfigurator.swift")

        doesNotContain(source, "titlebarAppearsTransparent", "Native toolbar presentation must not be replaced by a custom transparent titlebar")
        doesNotContain(source, "fullSizeContentView", "Window focus infrastructure must not reintroduce full-size custom chrome")
        contains(source, "NSEvent.addLocalMonitorForEvents(", "The app window must monitor local mouse-down events to end text editing")
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

    @Test func toolPageEntryTraceStaysDebugOnlyAndOptIn() throws {
        let trace = try readSource("Sources/XTools/AppShell/ToolPageEntryTrace.swift")
        let actions = try readSource("Sources/XTools/AppShell/ToolNavigationActions.swift")
        let host = try readSource("Sources/XTools/AppShell/ToolDetailHostView.swift")
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")
        let textComponents = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")

        contains(trace, "#if DEBUG", "Tool page entry tracing must stay out of release builds")
        contains(trace, "ProcessInfo.processInfo.environment[\"TOOLS_TOOL_PAGE_TRACE\"] == \"1\"", "Tool page entry tracing must be opt-in during Debug runs")
        contains(trace, "os_signpost(", "Tool page entry tracing must expose an entry interval for Instruments")
        contains(trace, "ProcessInfo.processInfo.environment[\"TOOLS_TOOL_PAGE_BENCHMARK\"] == \"1\"", "Tool page entry benchmark must be explicitly enabled")
        contains(trace, "NSApp.terminate(nil)", "Tool page entry benchmark must terminate after its bounded run")

        contains(actions, "ToolPageEntryTrace.toolSelected(tool)", "Navigation actions must start entry tracing before selectedToolID changes")
        contains(host, "ToolPageEntryTrace.makePageStarted(tool)", "Tool detail host must mark page factory start")
        contains(host, "ToolPageEntryTrace.makePageFinished(tool)", "Tool detail host must mark page factory completion")
        contains(host, "ToolPageEntryTrace.pageAppeared(traceContext)", "Tool detail host must give each selected tool an identity-bound page appearance marker")
        contains(root, "ToolPageEntryBenchmark.runIfRequested(", "Root view must expose the opt-in page entry benchmark through the real navigation path")
        contains(textComponents, "ToolPageEntryTrace.inputFocusRequested(entryTraceContext, placeholder: placeholder)", "Autofocus must mark primary-input focus start")
        contains(textComponents, "ToolPageEntryTrace.inputFocusCompleted(entryTraceContext, placeholder: placeholder)", "Autofocus must mark primary-input focus completion")
    }

    @Test func appDefinesStandardUndoRedoCommands() throws {
        let source = try readSource("Sources/XTools/XToolsApp.swift")

        contains(source, "CommandGroup(replacing: .undoRedo)", "App must own the standard Undo/Redo command group")
        contains(source, "AppKitUndoCommandRouter.perform(.undo)", "Undo command must resolve the current bridged AppKit editor")
        contains(source, "AppKitUndoCommandRouter.perform(.redo)", "Redo command must resolve the current bridged AppKit editor")
        contains(source, "application.sendAction(action.managerSelector, to: manager, from: nil)", "Undo routing must execute the private manager through NSApplication")
        contains(source, ".keyboardShortcut(\"z\", modifiers: .command)", "Undo must keep the standard Command-Z shortcut")
    }

    @Test func persistentCardSurfaceHasDedicatedQuietElevation() throws {
        let surface = try readSource("Sources/XTools/Shared/Components/IndexSurface.swift")
        let metrics = try readSource("Sources/XTools/Shared/ToolMetrics.swift")
        let theme = try readSource("Sources/XTools/Shared/ToolTheme.swift")

        contains(surface, "case card", "Persistent content cards must have an explicit surface semantic")
        contains(surface, "case .card: return ToolMetrics.CornerRadius.card", "Card surfaces must use the shared card radius token")
        contains(surface, "ToolTheme.Shadow.card", "Card surfaces must use the dedicated quiet card elevation")
        contains(metrics, "static let card", "Card radius must be named and shared")
        contains(theme, "static let card = ShadowRecipe", "Card elevation must be distinct from panel/modal recipes")
    }

    @Test func pageHeaderWithoutAccessoryKeepsAccessorySlotUnclaimed() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexPageShell.swift")
        contains(source, "self.hasAccessory = false", "Headers without an accessory must not enter the accessory HStack layout")
    }

    @Test func diagnosticBannerRendersThroughSharedOwner() throws {
        let panel = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexPageShell.swift")

        contains(panel, "IndexDiagnosticStatusSlot(isActive: workspaceDiagnostic != nil)", "Diagnostic-capable panels must route banner presence through the shared status slot")
        contains(panel, "func withoutDiagnosticStatusSlot() -> IndexPanel", "Panels without diagnostics must opt out explicitly")
    }

    @Test func sidebarSearchUsesUndoableAppKitTextField() throws {
        let source = try readSource("Sources/XTools/AppShell/SidebarView.swift")
        let sidebarSearchField = try readSource("Sources/XTools/AppShell/SidebarSearchTextField.swift")
        let lifecycle = try readSource("Sources/XTools/Shared/Components/AppKitSearchFieldLifecycle.swift")

        contains(sidebarSearchField, "struct SidebarSearchTextField: NSViewRepresentable", "Sidebar search must keep its AppKit-backed adapter port")
        contains(sidebarSearchField, "AppKitSearchFieldLifecycle.makeTextField(", "Sidebar search must delegate native field creation to the shared lifecycle")
        contains(sidebarSearchField, "textField.setAccessibilityIdentifier(\"sidebar.search\")", "Sidebar search must expose a stable automation and accessibility identity")
        contains(lifecycle, "AppKitTextEditingConfiguration.configureCurrentFieldEditor(for: textField)", "Shared search lifecycle must enable native field-editor undo")
        doesNotContain(source, "final class Coordinator", "Sidebar search must not duplicate the shared coordinator")
        doesNotContain(source, "private func requestFocus", "Sidebar search must not duplicate shared focus scheduling")
        doesNotContain(source, "TextField(\"搜索工具...\", text: $searchText)", "Sidebar search must not use SwiftUI TextField because Command-Z is unreliable there")
        doesNotContain(source, "@FocusState private var isSearchFocused", "Sidebar search focus state must follow the AppKit first responder callbacks")
    }

    @Test func appUsesSingleMainWindowScene() throws {
        let source = try readSource("Sources/XTools/XToolsApp.swift")

        contains(source, "Window(\"Tools\", id: \"main\")", "App must use a single main window scene instead of a multi-window WindowGroup")
        contains(source, ".windowResizability(.contentMinSize)", "Main window must derive resize limits from content constraints")
        doesNotContain(source, "WindowGroup", "App must not expose duplicate main windows through WindowGroup")
        contains(source, "NSApplicationDelegateAdaptor(XToolsAppDelegate.self)", "App must bind XToolsAppDelegate to preserve background process on window close")
    }

    @Test func workspaceDiagnosticUsesNonDisplacingAnchorByDefault() throws {
        let source = try readSharedBagComponents()
        let pageShell = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexPageShell.swift")
        let diagnostic = sourceSlice(
            source,
            from: "struct IndexWorkspaceDiagnostic: View",
            to: "struct IndexDiagnosticStatusButton: View"
        )

        contains(source, "struct IndexWorkspaceDiagnostic: View", "Shared components must define a persistent workspace diagnostic")
        contains(source, "struct IndexWorkspaceDiagnosticRegion<Content: View>: View", "Shared components must provide a persistent diagnostic anchor")
        contains(source, "struct IndexWorkspaceDiagnosticPreferenceKey: PreferenceKey", "Shared diagnostics must use one preference key inside an owning panel")
        contains(source, "struct IndexDiagnosticStatusButton: View", "Shared components must own one reusable icon-only diagnostic status button")
        contains(source, ".preference(key: IndexWorkspaceDiagnosticPreferenceKey.self", "Default workspace diagnostics must publish an anchor payload without inserting a layout row")
        contains(source, "func indexWorkspaceDiagnosticOverlay(", "Explicit overlay escape hatch must be named separately")
        doesNotContain(source, "func indexFloatingError", "Old floating-error modifier must not remain as a parallel presentation API")
        doesNotContain(diagnostic, "Button", "Persistent workspace diagnostics must not expose a manual close or details action")
        contains(pageShell, ".onPreferenceChange(IndexWorkspaceDiagnosticPreferenceKey.self)", "IndexPanel must consume descendant diagnostics at the owning panel boundary")
        doesNotContain(pageShell, ".overlayPreferenceValue(IndexWorkspaceDiagnosticPreferenceKey.self", "IndexPage must not lift panel diagnostics into a root overlay that can cover controls")
        contains(source, ".popover(isPresented:", "Persistent panel diagnostics must let users reopen the short summary")
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
        contains(tone, "var defaultToastDuration: TimeInterval", "Tone must own default toast duration")
        contains(source, "static let maxVisibleMessages", "Toast queue must cap visible messages")
        contains(source, "messages.removeFirst(overflow)", "Toast overflow must discard the oldest messages")
        contains(source, "func pauseDismissal(for id: UUID)", "Toast center must support hover pause")
        contains(source, "func resumeDismissal(for id: UUID)", "Toast center must support hover resume")
        contains(source, "ZStack(alignment: .bottomTrailing)", "Toast host must follow the bottom-right convention used by mature developer tools")
        contains(source, "ToolAccessibilityAnnouncer", "Toast center must use an accessibility announcement adapter")
        doesNotContain(source, "@Published private(set) var current", "Old single-current toast state must not remain")
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
        let outputSurface = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexOutputSurface.swift")
        let sharedComponents = try readSharedBagComponents()
        let resultPresence = try readSource("Sources/XTools/ToolPages/Workbench/Diagnostics/IndexResultPresence.swift")

        contains(textComponents, "if text.isEmpty", "Output surfaces must branch on empty text before creating a ScrollView")
        contains(outputSurface, "private var placeholderBody: some View", "Output surfaces must have a non-scrolling placeholder body")
        contains(sharedComponents, "struct IndexScrollableKV: View", "Shared scrollable KV remains available for explicit scrolling exceptions")
        contains(resultPresence, "if presentation.phase == .empty", "Scrollable result presence must render empty content without a ScrollView")
    }

    @Test func fillingOutputSurfacesUseCompactEmptyMinimumHeight() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let outputSurface = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexOutputSurface.swift")

        contains(outputSurface, "private var effectiveMinHeight: CGFloat", "Output surfaces must compute a compact minimum height for filling layouts")
        contains(outputSurface, "minHeight: effectiveMinHeight", "Output placeholder and content bodies must use the compact minimum height")
        contains(source, "fillsHeight ? 60 : minHeight", "Filling output surfaces must use the same compact floor as input text areas")
    }

    @Test func sharedNumberInputSupportsDirectEditingAndBounds() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexSliderAndNumberInput.swift")

        contains(source, "struct IndexNumberInput: View", "Shared controls must define an IndexNumberInput")
        contains(source, "IndexTextInput(", "IndexNumberInput must support direct text entry")
        doesNotContain(source, "stepButton(systemImage: \"minus\"", "IndexNumberInput must not show a minus button")
        doesNotContain(source, "stepButton(systemImage: \"plus\"", "IndexNumberInput must not show a plus button")
        contains(source, "onSubmit: commitText", "IndexNumberInput must normalize typed input on submit")
        contains(source, "selectAllOnFocus: true", "Shared number input must select the whole number on focus")
        contains(source, "let digitsOnly = text.filter(\\.isNumber)", "Shared number input must reject non-numeric typed characters")
        contains(source, "setValue(range.upperBound)", "Shared number input must clamp overflow text back to the configured upper bound")
        doesNotContain(source, "minimumDigits", "The retired fixed-digit formatting path must not return; number display is always plain")
    }

    @Test func sliderControlsUsePureSwiftUIToAvoidNSSliderEntryLag() throws {
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexSliderAndNumberInput.swift")
        let color = try readSource("Sources/XTools/ToolPages/Image/ColorPickerPage.swift")
        let imageConverter = try readSource("Sources/XTools/ToolPages/Image/ImageConverterPage.swift")
        let imageWatermark = try readSource("Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift")

        // 根因（实测）：SwiftUI.Slider 桥接 AppKit NSSlider，本工具链上单个实例化约
        // 230ms；颜色页三个 Slider 叠加约 700ms。替换为纯 SwiftUI 自绘 IndexSlider 后，
        // 进入首帧从约 816ms 降到约 158ms。此契约防止任何页面回退到原生 Slider。
        contains(controls, "struct IndexSlider: View", "Shared controls must define a pure-SwiftUI slider to avoid the NSSlider entry cost")
        contains(controls, "DragGesture(minimumDistance: 0)", "IndexSlider must drive its value from a SwiftUI drag gesture rather than an AppKit bridge")
        contains(controls, "accessibilityAdjustableAction", "IndexSlider must stay keyboard/VoiceOver adjustable")

        doesNotContain(color, " Slider(", "Color page sliders must use IndexSlider; native Slider reintroduces the measured NSSlider entry lag")
        doesNotContain(imageConverter, " Slider(", "Image converter quality slider must use IndexSlider to avoid NSSlider entry lag")
        doesNotContain(imageWatermark, " Slider(", "Image watermark opacity slider must use IndexSlider to avoid NSSlider entry lag")
        contains(color, "IndexSlider(", "Color page must drive its sliders through the shared IndexSlider")
        contains(imageConverter, "IndexSlider(", "Image converter must keep its quality slider through IndexSlider")
        contains(imageWatermark, "IndexSlider(", "Image watermark must keep its opacity slider through IndexSlider")
    }

    @Test func sharedOptionControlsPreventCompressedVerticalLabels() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexOptionControls.swift")

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
        let dropZone = try readSource("Sources/XTools/Shared/Components/IndexDropZone.swift")

        doesNotContain(integerBase, "Picker(\"\", selection: $base)", "Integer base input base selection must not use the native Picker")
        contains(integerBase, "IndexClearButton(", "Integer base clear action must use the shared IndexClearButton in the input panel header")

        contains(jsonFormatter, "IndexFormatWorkbench(", "JSON formatter must use the shared prototype workbench")
        contains(jsonFormatter, "IndexSegmentedControl(", "JSON indent must use the shared segmented control inside the workbench toolbar")
        doesNotContain(jsonFormatter, "Toggle(\"键排序\"", "JSON formatter must not fall back to a native Toggle")
        doesNotContain(jsonFormatter, "Picker(\"缩进\"", "JSON formatter must not fall back to a native Picker")
        contains(jsonFormatter, "IndexOptionsMenu(", "JSON formatter provides the key-sort option through the toolbar options menu")
        doesNotContain(jsonFormatter, ".animation(", "Optional-control reveal must not bind page-level animations")

        doesNotContain(base64File, "Text(\"正在读取文件...\")", "Base64 import must not collapse the stable two-line picker into a transient loading row")
        contains(base64File, ".indexDropZone(", "Base64 file page drag-and-drop promise must be backed by the shared drop zone")
        contains(fileType, ".indexDropZone(", "File type detector drag-and-drop promise must be backed by the shared drop zone")
        contains(dropZone, ".dropDestination(for: URL.self)", "The shared drop zone must implement the platform drop destination once")
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

    @Test func pageLayoutDefaultIsFillProtectsUnnamedPages() throws {
        let source = try readSharedBagComponents()

        contains(source, "enum IndexPageLayout", "IndexPageLayout must be defined as an enum")
        contains(source, "case fill", "IndexPageLayout must have a fill case as the default layout")
        contains(source, "case scroll", "IndexPageLayout must have a scroll case")
        contains(source, "var scrollsExternally: Bool", "IndexPageLayout must expose a scrollsExternally query")
        contains(source, "var layout: IndexPageLayout = .fill", "IndexPage default must be fill to protect unnamed pages from automatically migrating to external scrolling")
    }

    @Test func appShellSidebarAndPageChromeUseUnifiedToolIdentity() throws {
        let app = try readSource("Sources/XTools/XToolsApp.swift")
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")
        let appShellThemeValues = try readSource("Sources/XTools/AppShell/AppShellThemeValues.swift")
        let rootViewModel = try readSource("Sources/XTools/AppShell/RootViewModel.swift")
        let sidebarCommands = try readSource("Sources/XTools/AppShell/SidebarCommands.swift")
        let toolbar = try readSource("Sources/XTools/AppShell/TitlebarView.swift")
        let sidebar = try readSource("Sources/XTools/AppShell/SidebarView.swift")
        let typography = try readSource("Sources/XTools/Shared/ToolTypography.swift")
        let sharedComponents = try readSharedBagComponents()
        let converter = try readSource("Sources/XTools/ToolPages/Workbench/Converter/IndexConverterPage.swift")
        let formatterHub = try readSource("Sources/XTools/ToolPages/Development/FormatterHubPage.swift")

        contains(appShellThemeValues, "enum SidebarVisibility: Equatable", "Root shell must use an explicit sidebar visibility state")
        contains(root, "ToolDetailHostView(", "Tool detail must consume the full detail-column height below the native toolbar")
        contains(root, ".focusedSceneObject(viewModel)", "Root must expose the current window's observable app-shell actions to scene commands")
        doesNotContain(root, "ToolStatusBar", "App shell must not retain a bottom status bar without exclusive persistent state")
        doesNotContain(root, "isWorkspaceFocused", "Root state must not duplicate sidebar hiding with a workspace-focus flag")
        doesNotContain(root, "NavigationSplitView(", "The custom sidebar must not add a duplicate system sidebar or toolbar")
        contains(rootViewModel, "var sidebarTogglePresentation: SidebarTogglePresentation", "Root state must publish one sidebar presentation seam")
        contains(rootViewModel, "func toggleSidebar(reduceMotion: Bool)", "Root state must publish one sidebar action seam")
        contains(sidebarCommands, "CommandGroup(before: .sidebar)", "Sidebar visibility must live in the standard View-menu command area")
        contains(sidebarCommands, ".keyboardShortcut(\"b\", modifiers: .command)", "The menu command must own the standard Command-B shortcut")
        doesNotContain(sidebarCommands, "statusHint", "Sidebar presentation must not retain copy used only by the removed bottom bar")
        contains(app, "SidebarMenuCommands()", "The app scene must install the sidebar menu command")
        contains(app, ".windowToolbarStyle(.unifiedCompact(showsTitle: false))", "The window must use the native compact unified macOS toolbar")
        contains(toolbar, "struct WindowToolbarContent: ToolbarContent", "App shell chrome must use native toolbar placements")
        contains(toolbar, "ToolbarItem(placement: .navigation)", "Sidebar toggle must live at the toolbar leading edge")
        doesNotContain(toolbar, "WindowToolbarToolContext", "Toolbar must not retain a tool breadcrumb context view")
        doesNotContain(toolbar, "isWorkspaceFocused", "Toolbar must not retain a focus state that only duplicates sidebar hiding")
        contains(sidebar, "static let idealWidth", "Sidebar must expose one stable ideal pane width")
        doesNotContain(sidebar, "isCollapsed", "Sidebar must not retain the collapsed rail state")
        contains(typography, "static let pageTitle", "All tool pages must share the same static in-page title typography")
        contains(typography, "static let pageSubtitle", "All tool pages must share the same static in-page subtitle typography")
        contains(sharedComponents, "enum IndexPageChrome", "Tool pages must expose page-level chrome density")
        contains(sharedComponents, "case compactWorkspace", "Editor-heavy workbenches must have a compact page chrome option")
        contains(sharedComponents, ".font(ToolTypography.pageTitle)", "IndexPage title must use the shared page title token")
        contains(sharedComponents, ".font(ToolTypography.pageSubtitle)", "IndexPage subtitle must use the shared page subtitle token")
        doesNotContain(sharedComponents, "IndexPageHeaderStyle", "Page chrome must not fork standard and compact title treatments")
        contains(converter, "workspaceSemantic: .copyTransformWorkspace", "Shared converter workbenches must resolve chrome through the settled copy-transform semantic")
        contains(formatterHub, "workspaceSemantic: .structuredEditorTransform", "Formatter segments must opt into the semantic that resolves the compact fixed editor workbench shell")
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

        contains(sidebar, "SidebarNavigationList(configuration:", "SidebarView must keep one production list renderer")
        doesNotContain(sidebar, "ForEach(sidebarEntries)", "Sidebar disclosure must not structurally remove live tool rows")
        contains(entries, "id: \"tool.\\(item.id.rawValue)\"", "Tool tracks must preserve stable ToolID identity")
        contains(renderer, "final class SidebarNavigationScrollView: NSScrollView", "The renderer must own one native scroll viewport")
        contains(renderer, "NSHostingView<SidebarNavigationTrackRoot>", "Each semantic track must keep a real hosted SwiftUI view")
        contains(renderer, "tracksByID[target.id] ?? makeTrack", "The renderer must reuse cached tracks instead of duplicating tools")
        contains(renderer, "animator().frame = target.frame", "Disclosure motion must animate real wrapper frames")
        contains(renderer, "animationGate.accepts(token)", "Animation completion must reject stale generations")
        contains(renderer, "finishActiveAnimationIfNeeded", "User input must safely land the latest animation target before navigation")
        contains(renderer, "final class SidebarNavigationTrackHoverState: ObservableObject", "Stable AppKit tool tracks must own reusable hover presentation state")
        contains(renderer, "final class SidebarSelectionIndicatorView: NSView", "Selection chrome must live in one flat-renderer indicator instead of per-row painting")
        contains(renderer, "ToolMotion.AppKitPreset.selectionSlide()", "The sliding selection chrome must spring through the shared ToolMotion adapter")
        doesNotContain(renderer, "Timer.", "Sidebar disclosure must remain event-driven")
        doesNotContain(renderer, "snapshot", "Sidebar disclosure must not animate bitmap snapshots")
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
