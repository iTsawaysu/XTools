import AppKit
import SwiftUI
import Testing
@testable import XTools
@testable import XToolsCore

@Suite(.serialized)
@MainActor
struct WorkbenchAccessibilityTests {
    /// These are injected-environment and in-process accessibility contracts.
    /// They do not replace VoiceOver speech, visual contrast or keyboard Tab
    /// traversal acceptance on the user's configured system. The separately
    /// hosted system popover does not inherit this root's test-only semantic
    /// tree activation: its copy button must be checked by an external AX
    /// client against the packaged app, not claimed as covered by this suite.
    @Test(arguments: Array(0..<16))
    func diagnosticActionsRemainAccessibleAcrossAppearancePreferences(_ flags: Int) async throws {
        let preferences = AccessibilityPreferences(flags: flags)
        let model = AccessibilityWorkbenchModel()
        let hosting = NSHostingView(rootView: AccessibilityWorkbenchProbe(model: model)
            // Swift Testing has no assistive-technology client to activate the
            // SwiftUI semantic tree. Enable it through the public environment
            // value for this fixture only; never toggle global VoiceOver.
            .environment(\.accessibilityEnabled, true)
            .environment(\.colorScheme, preferences.dark ? .dark : .light)
            .environment(\._colorSchemeContrast, preferences.increasedContrast ? .increased : .standard)
            .environment(\._accessibilityReduceMotion, preferences.reduceMotion)
            .environment(\._accessibilityReduceTransparency, preferences.reduceTransparency))
        hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 500)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: preferences.appearance)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        func wait(_ stage: String, until condition: () -> Bool) async throws {
            try await waitUntil(hosting, stage: stage, diagnostics: {
                let elements = accessibleElements(in: window)
                let tree = elements.prefix(60).map {
                    let rawTypes = $0.children.map { String(describing: type(of: $0.object)) }.joined(separator: ",")
                    return "\(type(of: $0.object)) \($0.role ?? "nil"):\($0.label ?? ""):\(($0.value ?? "").prefix(100)) children=[\(rawTypes)]"
                }.joined(separator: " | ")
                return "flags=\(flags) expected=\(preferences) observed=\(String(describing: model.observedPreferences)) accessibilityEnabled=\(model.observedAccessibilityEnabled) editor=\(findEditor(hosting) != nil) formatCount=\(model.formatCount) AX=\(tree)"
            }, condition)
        }
        try await wait("environment and native editor") {
            model.observedPreferences == preferences && model.observedAccessibilityEnabled && findEditor(hosting) != nil
        }
        let editor = try #require(findEditor(hosting))
        let scrollView = try #require(editor.enclosingScrollView)
        let originalFrame = scrollView.convert(scrollView.bounds, to: hosting)
        let originalText = editor.string
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(window.makeFirstResponder(editor))

        // Exercise the actual SwiftUI keyboard shortcut through the window,
        // rather than calling the fixture's closure directly.
        let commandReturn = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))
        #expect(window.performKeyEquivalent(with: commandReturn))
        try await wait("Command-Return dispatch") { model.formatCount == 1 }
        try await wait("diagnostic accessibility publication") { findAction("查看诊断详情", in: window) != nil }
        #expect(findEditor(hosting) === editor)
        let expectedDiagnosticFrame = NSRect(
            x: originalFrame.minX,
            y: originalFrame.minY + (hosting.isFlipped ? 36 : 0),
            width: originalFrame.width,
            height: originalFrame.height - 36
        )
        // Capture the settled frame, not a subpixel intermediate animation
        // value that would falsely implicate the subsequent details popover.
        try await wait("visible diagnostic geometry") {
            scrollView.convert(scrollView.bounds, to: hosting) == expectedDiagnosticFrame
        }
        let diagnosticFrame = scrollView.convert(scrollView.bounds, to: hosting)
        #expect(diagnosticFrame.minX == originalFrame.minX && diagnosticFrame.width == originalFrame.width)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
        let summaryTexts = accessibleText(in: window)
        #expect(summaryTexts.contains { $0.contains("错误：缺少右括号") })
        #expect(!summaryTexts.contains { $0.contains("PRIVATE_DIAGNOSTIC_EXCERPT") })

        let locate = try #require(findAction("定位问题，第 1 行，第 8 列", in: window))
        #expect(locate.isEnabled)
        #expect(!locate.frame.isEmpty)
        #expect(locate.press())
        try await wait("locate selection") { editor.selectedRange() == NSRange(location: 7, length: 1) }
        #expect(window.firstResponder === editor)
        #expect(editor.string.utf8.elementsEqual(originalText.utf8))

        let details = try #require(findAction("查看诊断详情", in: window))
        #expect(details.isEnabled)
        #expect(!details.frame.isEmpty)
        #expect(details.press())
        try await wait("detail popover accessibility publication") {
            accessibleText(in: window).contains { $0.contains("补全右括号后重试。") }
        }
        // The real popover's selectable AppKit text is available in process;
        // its SwiftUI-only copy action is verified externally on the app build.
        // Do not replace that check with a direct closure call or a fake button.
        #expect(!accessibleText(in: window).contains { $0.contains("PRIVATE_DIAGNOSTIC_EXCERPT") })
        #expect(findEditor(hosting) === editor)
        #expect(scrollView.convert(scrollView.bounds, to: hosting) == diagnosticFrame)

        model.showsDiagnostic = false
        try await wait("diagnostic cleared and space reclaimed") {
            findAction("查看诊断详情", in: window) == nil
                && scrollView.convert(scrollView.bounds, to: hosting) == originalFrame
        }
        #expect(findEditor(hosting) === editor)
        #expect(scrollView.convert(scrollView.bounds, to: hosting) == originalFrame)
        #expect(editor.string.utf8.elementsEqual(originalText.utf8))
    }

    private func findEditor(_ root: NSView) -> NSTextView? {
        if let editor = root as? NSTextView, editor.isEditable { return editor }
        return root.subviews.lazy.compactMap { findEditor($0) }.first
    }

    private func accessibleElements(in window: NSWindow) -> [AccessibilityTestElement] {
        var pending = [AccessibilityTestElement(object: window)]
        pending.append(contentsOf: (window.childWindows ?? []).map(AccessibilityTestElement.init))
        var result: [AccessibilityTestElement] = []
        var visited = Set<ObjectIdentifier>()
        while let element = pending.popLast(), result.count < 2000 {
            guard visited.insert(ObjectIdentifier(element.object)).inserted else { continue }
            result.append(element)
            pending.append(contentsOf: element.children)
        }
        return result
    }

    private func accessibleText(in window: NSWindow) -> [String] {
        accessibleElements(in: window).flatMap { element in
            [element.label, element.value].compactMap { $0 }
        }
    }

    private func findAction(_ label: String, in window: NSWindow) -> AccessibilityTestElement? {
        accessibleElements(in: window).first {
            $0.role == NSAccessibility.Role.button.rawValue && $0.label == label
        }
    }

    private func waitUntil(
        _ hosting: NSView, stage: String, diagnostics: () -> String, _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        repeat {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            hosting.window?.displayIfNeeded()
            CATransaction.flush()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        throw AccessibilityTestError.timeout(stage: stage, diagnostics: diagnostics())
    }
}

/// SwiftUI's virtual AccessibilityNode objects implement public accessibility
/// selectors without declaring NSAccessibilityProtocol. Objective-C optional
/// dispatch preserves those nodes and the declared return types without an
/// unchecked protocol cast. The informal attribute API remains a fallback for
/// legacy AppKit elements; no private AX attributes are used.
@MainActor
private struct AccessibilityTestElement {
    let object: NSObject
    private var dynamic: AnyObject { object }

    var role: String? { dynamic.accessibilityRole?()?.rawValue ?? attribute("AXRole") as? String }
    var label: String? {
        dynamic.accessibilityLabel?() ?? attribute("AXDescription") as? String ?? attribute("AXTitle") as? String
    }
    var value: String? {
        // AppKit declares this selector with String, NSNumber and Any return
        // types on different protocols. The object-valued getter is unambiguous
        // at Objective-C runtime; only textual values enter this test's summary.
        let selector = NSSelectorFromString("accessibilityValue")
        let value = object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
        return value as? String ?? attribute("AXValue") as? String
    }
    var isEnabled: Bool { dynamic.isAccessibilityEnabled?() ?? (attribute("AXEnabled") as? NSNumber)?.boolValue ?? false }
    var frame: NSRect {
        if let frame = dynamic.accessibilityFrame?() { return frame }
        guard let position = attribute("AXPosition") as? NSValue,
              let size = attribute("AXSize") as? NSValue else { return .zero }
        return NSRect(origin: position.pointValue, size: size.sizeValue)
    }
    var children: [AccessibilityTestElement] {
        let children = dynamic.accessibilityChildren?() ?? attribute("AXChildren") as? [Any] ?? []
        return children.compactMap { ($0 as? NSObject).map(AccessibilityTestElement.init) }
    }

    func press() -> Bool {
        if let result = dynamic.accessibilityPerformPress?() { return result }
        let names = NSSelectorFromString("accessibilityActionNames")
        let action = NSSelectorFromString("accessibilityPerformAction:")
        guard object.responds(to: names), object.responds(to: action),
              let actions = object.perform(names)?.takeUnretainedValue() as? [String],
              actions.contains("AXPress") else { return false }
        object.perform(action, with: "AXPress")
        return true // The caller also verifies the resulting selection/popover.
    }

    private func attribute(_ name: String) -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector, with: name)?.takeUnretainedValue()
    }
}

private enum AccessibilityTestError: Error { case timeout(stage: String, diagnostics: String) }

private struct AccessibilityPreferences: Equatable {
    let dark: Bool
    let increasedContrast: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool

    init(flags: Int) {
        dark = flags & 1 != 0
        increasedContrast = flags & 2 != 0
        reduceMotion = flags & 4 != 0
        reduceTransparency = flags & 8 != 0
    }

    init(environment: EnvironmentValues) {
        dark = environment.colorScheme == .dark
        increasedContrast = environment.colorSchemeContrast == .increased
        reduceMotion = environment.accessibilityReduceMotion
        reduceTransparency = environment.accessibilityReduceTransparency
    }

    var appearance: NSAppearance.Name {
        if increasedContrast { return dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua }
        return dark ? .darkAqua : .aqua
    }
}

@MainActor
private final class AccessibilityWorkbenchModel: ObservableObject {
    @Published var input = "SELECT (1"
    @Published var showsDiagnostic = false
    var formatCount = 0
    var observedPreferences: AccessibilityPreferences?
    var observedAccessibilityEnabled = false
    let diagnostic = FormatDiagnostic(
        formatName: "SQL", message: "缺少右括号", line: 1, column: 8,
        excerpt: "PRIVATE_DIAGNOSTIC_EXCERPT", suggestion: "补全右括号后重试。",
        sourceUTF16Range: NSRange(location: 7, length: 1)
    )
}

private struct AccessibilityWorkbenchProbe: View {
    @ObservedObject var model: AccessibilityWorkbenchModel
    var body: some View {
        IndexFormatWorkbench(
            inputTitle: "SQL 输入", outputTitle: "输出", input: $model.input, output: "",
            diagnostic: model.showsDiagnostic ? model.diagnostic.message : nil,
            diagnosticDetail: model.showsDiagnostic ? model.diagnostic : nil,
            diagnosticMarker: model.showsDiagnostic
                ? IndexTextAreaDiagnosticMarker(diagnostic: model.diagnostic, sourceText: model.input) : nil,
            autoFocus: false,
            onFormat: {
                model.formatCount += 1
                model.showsDiagnostic = true
            },
            onClear: {}
        )
        .background(AccessibilityEnvironmentProbe(model: model).frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

private struct AccessibilityEnvironmentProbe: NSViewRepresentable {
    let model: AccessibilityWorkbenchModel
    func makeNSView(context: Context) -> NSView {
        model.observedPreferences = AccessibilityPreferences(environment: context.environment)
        model.observedAccessibilityEnabled = context.environment.accessibilityEnabled
        return NSView()
    }
    func updateNSView(_ view: NSView, context: Context) {
        model.observedPreferences = AccessibilityPreferences(environment: context.environment)
        model.observedAccessibilityEnabled = context.environment.accessibilityEnabled
    }
}
