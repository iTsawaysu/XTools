import AppKit
import Foundation
import SwiftUI
@testable import XTools
import Testing

@Suite(.serialized)
struct CommandPalettePresentationTests {
    @Test @MainActor
    func realRootWindowAttachesLaysOutFocusesAndSuspendsRetainedPalette() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }

        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.openCommandPalette()
        }
        let field = try await Self.waitForReadyField(in: fixture)

        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.closeCommandPalette()
        }
        try await Self.waitForCondition(label: "real palette field suspension") {
            fixture.flush()
            let ownsEditor = field.currentEditor().map {
                fixture.window.firstResponder === $0
            } ?? false
            return !field.isEnabled && !ownsEditor
        }
    }

    @Test @MainActor
    func realRootWindowKeepsLocalQueryOnRefocusAndResetsItForANewSession() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }

        fixture.activateWindow()
        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.openCommandPalette()
        }
        let oldField = try await Self.waitForReadyField(in: fixture)
        let oldEditor = try #require(oldField.currentEditor() as? NSTextView)
        let oldDelegate = try #require(oldField.delegate)
        Self.replaceText("jwt", in: oldField, delegate: oldDelegate)
        var filteredRows: [CommandPaletteRevealView] = []
        try await Self.waitForCondition(label: "filtered palette rows") {
            fixture.flush()
            filteredRows = Self.commandPaletteRevealViews(in: fixture.hostingView)
            return filteredRows.count == 1
        }
        let filteredRowIdentifiers = Set(filteredRows.map(ObjectIdentifier.init))
        let selectionBeforeStaleCommand = fixture.viewModel.selectedToolID

        fixture.viewModel.openCommandPalette()
        fixture.flush()
        #expect(fixture.viewModel.commandPalettePresentationSession == 1)
        #expect(oldField.stringValue == "jwt")

        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.closeCommandPalette()
        }
        #expect(oldField.stringValue == "jwt")
        #expect(!oldField.isEnabled)
        #expect(
            Set(Self.commandPaletteRevealViews(in: fixture.hostingView).map(ObjectIdentifier.init))
                == filteredRowIdentifiers
        )
        #expect(Self.sendCommand(
            #selector(NSResponder.insertNewline(_:)),
            field: oldField,
            editor: oldEditor,
            delegate: oldDelegate
        ))
        #expect(fixture.viewModel.selectedToolID == selectionBeforeStaleCommand)

        Self.replaceText("base64", in: oldField, delegate: oldDelegate)
        #expect(Self.sendCommand(
            #selector(NSResponder.cancelOperation(_:)),
            field: oldField,
            editor: oldEditor,
            delegate: oldDelegate
        ))
        #expect(!fixture.viewModel.showsCommandPalette)

        fixture.activateWindow()
        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.openCommandPalette()
        }
        #expect(Self.sendCommand(
            #selector(NSResponder.insertNewline(_:)),
            field: oldField,
            editor: oldEditor,
            delegate: oldDelegate
        ))
        #expect(fixture.viewModel.showsCommandPalette)
        #expect(fixture.viewModel.selectedToolID == selectionBeforeStaleCommand)

        let newField = try await Self.waitForReadyField(in: fixture, excluding: oldField)
        #expect(newField.stringValue.isEmpty)
        Self.replaceText("regex", in: oldField, delegate: oldDelegate)
        #expect(Self.sendCommand(
            #selector(NSResponder.insertNewline(_:)),
            field: oldField,
            editor: oldEditor,
            delegate: oldDelegate
        ))
        #expect(fixture.viewModel.showsCommandPalette)
        #expect(fixture.viewModel.selectedToolID == selectionBeforeStaleCommand)
        #expect(newField.stringValue.isEmpty)
    }

    @Test @MainActor
    func reopeningRetainsTheSameNativeRowViewsAfterTheFirstPresentation() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }

        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.openCommandPalette()
        }
        let oldField = try await Self.waitForReadyField(in: fixture)
        let oldEditor = try #require(oldField.currentEditor() as? NSTextView)
        let oldDelegate = try #require(oldField.delegate)
        var oldRows: [CommandPaletteRevealView] = []
        try await Self.waitForCondition(label: "initial palette native rows") {
            fixture.flush()
            oldRows = Self.commandPaletteRevealViews(in: fixture.hostingView)
            return oldRows.count == 50 && oldRows.allSatisfy { $0.window === fixture.window }
        }
        let oldRowIdentifiers = Set(oldRows.map(ObjectIdentifier.init))
        #expect(oldRowIdentifiers.count == 50)
        let scrollView = try #require(oldRows.first?.enclosingScrollView)
        let initialScrollOrigin = scrollView.contentView.bounds.origin
        for _ in 0..<25 {
            #expect(Self.sendCommand(
                #selector(NSResponder.moveDown(_:)),
                field: oldField,
                editor: oldEditor,
                delegate: oldDelegate
            ))
        }
        try await Self.waitForCondition(label: "palette keyboard scroll") {
            fixture.flush()
            return abs(scrollView.contentView.bounds.origin.y - initialScrollOrigin.y) > 100
        }

        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.closeCommandPalette()
        }
        try await Self.waitForCondition(label: "closed palette native row retention") {
            fixture.flush()
            let retainedRows = Self.commandPaletteRevealViews(in: fixture.hostingView)
            return !oldField.isEnabled
                && Set(retainedRows.map(ObjectIdentifier.init)) == oldRowIdentifiers
        }

        fixture.activateWindow()
        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.openCommandPalette()
        }
        _ = try await Self.waitForReadyField(in: fixture)
        var newRows: [CommandPaletteRevealView] = []
        try await Self.waitForCondition(label: "reopened palette native rows") {
            fixture.flush()
            newRows = Self.commandPaletteRevealViews(in: fixture.hostingView)
            return newRows.count == 50 && newRows.allSatisfy { $0.window === fixture.window }
        }
        let newRowIdentifiers = Set(newRows.map(ObjectIdentifier.init))

        #expect(newRowIdentifiers == oldRowIdentifiers)
        try await Self.waitForCondition(
            label: "new session scroll reset",
            diagnostic: {
                let current = scrollView.contentView.bounds.origin
                let reopenedScrollView = newRows.first?.enclosingScrollView
                let reopened = reopenedScrollView?.contentView.bounds.origin
                let documentBounds = reopenedScrollView?.documentView?.bounds
                let isFlipped = reopenedScrollView?.documentView?.isFlipped
                return "initial=\(initialScrollOrigin) retained=\(current) reopened=\(String(describing: reopened)) document=\(String(describing: documentBounds)) flipped=\(String(describing: isFlipped))"
            }
        ) {
            fixture.flush()
            guard let documentView = scrollView.documentView else { return false }
            let topY = documentView.isFlipped
                ? documentView.bounds.minY
                : max(
                    documentView.bounds.minY,
                    documentView.bounds.maxY - scrollView.contentView.bounds.height
                )
            return abs(scrollView.contentView.bounds.origin.y - topY) < 1
        }
    }

    @Test @MainActor
    func reopeningAfterConsumingUUIDPreviewProvidesANewPreviewCommand() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }

        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.openCommandPalette()
        }
        let firstPreview = try #require(fixture.viewModel.commandPalettePreviewValue)
        let firstField = try await Self.waitForReadyField(in: fixture)
        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.closeCommandPalette()
        }
        fixture.viewModel.consumeCommandPalettePreviewValue()
        fixture.flush()
        #expect(!fixture.viewModel.showsCommandPalette)
        #expect(fixture.viewModel.commandPalettePreviewValue == nil)

        fixture.activateWindow()
        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.openCommandPalette()
        }
        let secondPreview = try #require(fixture.viewModel.commandPalettePreviewValue)
        #expect(secondPreview != firstPreview)
        let secondField = try await Self.waitForReadyField(in: fixture, excluding: firstField)
        let secondDelegate = try #require(secondField.delegate)
        Self.replaceText("生成并复制", in: secondField, delegate: secondDelegate)
        try await Self.waitForCondition(label: "reopened UUID preview row") {
            fixture.flush()
            return Self.commandPaletteRevealViews(in: fixture.hostingView).count == 1
        }
        #expect(fixture.viewModel.commandPalettePreviewValue == secondPreview)
    }

    @Test @MainActor
    func realRootWindowImmediateEditThenSubmitUsesCurrentQuerySnapshot() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }

        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.openCommandPalette()
        }
        let field = try await Self.waitForReadyField(in: fixture)
        let editor = try #require(field.currentEditor() as? NSTextView)
        let delegate = try #require(field.delegate)
        let expectedToolID = try #require(ToolRegistry.default.matchingTools(query: "jwt").first?.id)

        Self.replaceText("jwt", in: field, delegate: delegate)
        let handled = Self.sendCommand(
            #selector(NSResponder.insertNewline(_:)),
            field: field,
            editor: editor,
            delegate: delegate
        )

        #expect(handled)
        #expect(fixture.viewModel.selectedToolID == expectedToolID)
        #expect(!fixture.viewModel.showsCommandPalette)
    }

    @Test @MainActor
    func realPaletteFieldLeavesNavigationCommandsToActiveIMEComposition() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }

        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.openCommandPalette()
        }
        let field = try await Self.waitForReadyField(in: fixture)
        let editor = try #require(field.currentEditor() as? NSTextView)
        let delegate = try #require(field.delegate)
        Self.replaceText("jwt", in: field, delegate: delegate)
        let selectionBeforeComposition = fixture.viewModel.selectedToolID
        editor.setMarkedText(
            "拼",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        #expect(editor.hasMarkedText())

        for command in [
            #selector(NSResponder.moveUp(_:)),
            #selector(NSResponder.moveDown(_:)),
            #selector(NSResponder.insertNewline(_:)),
            #selector(NSResponder.cancelOperation(_:))
        ] {
            #expect(!Self.sendCommand(command, field: field, editor: editor, delegate: delegate))
        }
        #expect(fixture.viewModel.showsCommandPalette)
        #expect(fixture.viewModel.selectedToolID == selectionBeforeComposition)

        editor.unmarkText()
        #expect(!editor.hasMarkedText())
        Self.replaceText("jwt", in: field, delegate: delegate)
        #expect(Self.sendCommand(
            #selector(NSResponder.insertNewline(_:)),
            field: field,
            editor: editor,
            delegate: delegate
        ))
        #expect(
            fixture.viewModel.selectedToolID
                == ToolRegistry.default.matchingTools(query: "jwt").first?.id
        )
        #expect(!fixture.viewModel.showsCommandPalette)
    }

    @Test @MainActor
    func presentationAndLocalQueryDoNotInvalidateRootOrSidebarProjection() async throws {
        guard ProcessInfo.processInfo.environment["TOOLS_COMMAND_PALETTE_BENCHMARK"] == "1" else {
            return
        }
        let fixture = try Fixture()
        defer { fixture.dispose() }

        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.openCommandPalette()
        }
        let field = try await Self.waitForReadyField(in: fixture)
        let delegate = try #require(field.delegate)
        let session = fixture.viewModel.commandPalettePresentationSession
        let before = try #require(CommandPaletteTrace.snapshot(session: session))
        #expect(before.counters[.rootBody, default: 0] == 0)
        #expect(before.counters[.sidebarProjection, default: 0] == 0)
        #expect(before.counters[.commandProjection, default: 0] == 1)
        #expect(before.counters[.rowSnapshot, default: 0] == 1)

        fixture.viewModel.openCommandPalette()
        try await Self.waitForCondition(label: "palette refocus update") {
            fixture.flush()
            guard let afterRefocus = CommandPaletteTrace.snapshot(session: session) else {
                return false
            }
            return afterRefocus.counters[.paletteBody, default: 0]
                > before.counters[.paletteBody, default: 0]
        }
        let afterRefocus = try #require(CommandPaletteTrace.snapshot(session: session))
        #expect(afterRefocus.counters[.rootBody, default: 0] == 0)
        #expect(afterRefocus.counters[.sidebarProjection, default: 0] == 0)
        #expect(afterRefocus.counters[.commandProjection, default: 0] == 1)
        #expect(afterRefocus.counters[.rowSnapshot, default: 0] == 1)

        Self.replaceText("jwt", in: field, delegate: delegate)
        try await Self.waitForCondition(label: "local query snapshot rebuild") {
            fixture.flush()
            guard let after = CommandPaletteTrace.snapshot(session: session) else { return false }
            return after.counters[.commandProjection, default: 0]
                > before.counters[.commandProjection, default: 0]
                && after.counters[.paletteBody, default: 0]
                    > before.counters[.paletteBody, default: 0]
                && after.counters[.revealDismantle, default: 0]
                    > before.counters[.revealDismantle, default: 0]
        }
        let after = try #require(CommandPaletteTrace.snapshot(session: session))

        #expect(after.counters[.rootBody, default: 0] == before.counters[.rootBody, default: 0])
        #expect(after.counters[.sidebarProjection, default: 0] == before.counters[.sidebarProjection, default: 0])
        #expect(after.counters[.rowSnapshot, default: 0] == before.counters[.rowSnapshot, default: 0] + 1)

        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.closeCommandPalette()
        }
        try await Self.waitForCondition(label: "isolated palette close") {
            fixture.flush()
            let ownsEditor = field.currentEditor().map {
                fixture.window.firstResponder === $0
            } ?? false
            return !field.isEnabled && !ownsEditor
        }
        let afterClose = try #require(CommandPaletteTrace.snapshot(session: session))
        #expect(afterClose.counters[.rootBody, default: 0] == 0)
        #expect(afterClose.counters[.sidebarProjection, default: 0] == 0)
        let commandProjectionCount = afterClose.counters[.commandProjection, default: 0]
        let rowSnapshotCount = afterClose.counters[.rowSnapshot, default: 0]
        fixture.window.setContentSize(NSSize(width: 1_160, height: 760))
        fixture.flush()
        let afterHiddenResize = try #require(CommandPaletteTrace.snapshot(session: session))
        #expect(afterHiddenResize.counters[.commandProjection, default: 0] == commandProjectionCount)
        #expect(afterHiddenResize.counters[.rowSnapshot, default: 0] == rowSnapshotCount)
        CommandPaletteTrace.finish(session: session)
    }

    @Test @MainActor
    func realRootWindowPresentationBenchmark() async throws {
        guard ProcessInfo.processInfo.environment["TOOLS_COMMAND_PALETTE_BENCHMARK"] == "1" else {
            return
        }
        let fixture = try Fixture()
        defer { fixture.dispose() }

        _ = try await Self.runPresentation(ordinal: 0, kind: "warmup", fixture: fixture)
        let repeatCount = Int(
            ProcessInfo.processInfo.environment["TOOLS_COMMAND_PALETTE_BENCHMARK_REPEATS"] ?? ""
        ) ?? 30
        var readySamples: [Double] = []
        var layoutSamples: [Double] = []
        var focusSamples: [Double] = []
        for ordinal in 1...max(1, repeatCount) {
            let sample = try await Self.runPresentation(
                ordinal: ordinal,
                kind: "warm",
                fixture: fixture
            )
            readySamples.append(sample.readyMilliseconds)
            layoutSamples.append(sample.layoutMilliseconds)
            focusSamples.append(sample.focusMilliseconds)
        }

        Self.emitSummary(metric: "field_layout_and_focus_ready", samples: readySamples)
        Self.emitSummary(metric: "field_layout", samples: layoutSamples)
        Self.emitSummary(metric: "focus", samples: focusSamples)
    }

    @MainActor
    private static func runPresentation(
        ordinal: Int,
        kind: String,
        fixture: Fixture
    ) async throws -> PresentationSample {
        fixture.activateWindow()
        let startedAt = ContinuousClock.now
        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.openCommandPalette()
        }
        let session = fixture.viewModel.commandPalettePresentationSession
        var layoutMilliseconds: Double?
        var focusMilliseconds: Double?
        try await waitForCondition(
            label: "palette session \(session) layout and focus",
            diagnostic: { fieldDiagnostic(in: fixture.hostingView, window: fixture.window) }
        ) {
            fixture.flush()
            guard let field = commandPaletteField(in: fixture.hostingView) else { return false }
            if layoutMilliseconds == nil,
               fixture.hostingView.frame.width > 0,
               fixture.hostingView.frame.height > 0,
               field.window === fixture.window,
               field.frame.width > 0,
               field.frame.height > 0 {
                layoutMilliseconds = milliseconds(from: startedAt, to: .now)
            }
            if focusMilliseconds == nil,
               let editor = field.currentEditor(),
               fixture.window.firstResponder === editor {
                focusMilliseconds = milliseconds(from: startedAt, to: .now)
            }
            return layoutMilliseconds != nil && focusMilliseconds != nil
        }

        // Field readiness may precede the end of the modal interpolation.
        // Observe its terminal modifier sample separately without treating it
        // as a displayed frame or adding it to layout/focus latency.
        try await waitForCondition(label: "palette session \(session) interpolation terminal") {
            fixture.flush()
            let terminalSampleCount = CommandPaletteTrace.snapshot(session: session)?
                .counters[.visibilityTerminalSample, default: 0] ?? 0
            return terminalSampleCount > 0
        }
        let snapshot = try #require(CommandPaletteTrace.snapshot(session: session))
        #expect(snapshot.counters[.rootBody, default: 0] == 0)
        #expect(snapshot.counters[.sidebarProjection, default: 0] == 0)
        #expect(snapshot.counters[.commandProjection, default: 0] == 1)
        #expect(snapshot.counters[.rowSnapshot, default: 0] == 1)
        #expect(snapshot.counters[.visibleAnimatedTransaction, default: 0] > 0)
        #expect(snapshot.counters[.visibleDisabledTransaction, default: 0] == 0)
        #expect(snapshot.counters[.visibilityTerminalSample, default: 0] > 0)
        if ordinal == 0 {
            #expect(snapshot.counters[.revealMake, default: 0] == 50)
        } else {
            #expect(snapshot.counters[.revealMake, default: 0] == 0)
        }
        #expect(snapshot.counters[.hoverMake, default: 0] == 0)
        let layout = try #require(layoutMilliseconds)
        let focus = try #require(focusMilliseconds)
        let ready = max(layout, focus)
        FileHandle.standardError.write(Data(String(
            format: "COMMAND_PALETTE_WINDOW_BENCHMARK_RESULT kind=%@ ordinal=%d session=%d workload=base64-file-converter trigger=root_view_model_modal_transaction key_dispatch=false row_bridge_makes=%d field_layout_ms=%.3f focus_ms=%.3f field_layout_and_focus_ready_ms=%.3f\n",
            kind, ordinal, session,
            snapshot.counters[.revealMake, default: 0],
            layout, focus, ready
        ).utf8))

        withToolAnimation(ToolMotion.Preset.modal) {
            fixture.viewModel.closeCommandPalette()
        }
        try await waitForCondition(label: "palette session \(session) suspension") {
            fixture.flush()
            guard let field = commandPaletteField(in: fixture.hostingView),
                  let afterClose = CommandPaletteTrace.snapshot(session: session)
            else {
                return false
            }
            let ownsEditor = field.currentEditor().map {
                fixture.window.firstResponder === $0
            } ?? false
            return !field.isEnabled
                && !ownsEditor
                && afterClose.counters[.revealDismantle, default: 0] == 0
                && afterClose.counters[.hiddenTransaction, default: 0] > 0
        }
        CommandPaletteTrace.finish(session: session)
        return PresentationSample(
            layoutMilliseconds: layout,
            focusMilliseconds: focus,
            readyMilliseconds: ready
        )
    }

    @MainActor
    private static func waitForCondition(
        label: String,
        timeout: TimeInterval = 2,
        diagnostic: () -> String = { "" },
        condition: () -> Bool
    ) async throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() {
            guard Date() < deadline else {
                Issue.record("Timed out waiting for \(label). \(diagnostic())")
                throw PresentationBenchmarkError.timeout(label)
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @MainActor
    private static func waitForReadyField(
        in fixture: Fixture,
        excluding excludedField: NSTextField? = nil
    ) async throws -> NSTextField {
        var readyField: NSTextField?
        try await waitForCondition(
            label: "current palette field layout and focus",
            diagnostic: { fieldDiagnostic(in: fixture.hostingView, window: fixture.window) }
        ) {
            fixture.flush()
            readyField = commandPaletteFields(in: fixture.hostingView).first { field in
                guard field !== excludedField,
                      field.window === fixture.window,
                      field.frame.width > 0,
                      field.frame.height > 0,
                      let editor = field.currentEditor()
                else {
                    return false
                }
                return fixture.window.firstResponder === editor
            }
            return readyField != nil
        }
        return try #require(readyField)
    }

    @MainActor
    private static func replaceText(
        _ text: String,
        in field: NSTextField,
        delegate: any NSTextFieldDelegate
    ) {
        field.stringValue = text
        delegate.controlTextDidChange?(Notification(
            name: NSControl.textDidChangeNotification,
            object: field
        ))
    }

    @MainActor
    private static func sendCommand(
        _ command: Selector,
        field: NSTextField,
        editor: NSTextView,
        delegate: any NSTextFieldDelegate
    ) -> Bool {
        delegate.control?(field, textView: editor, doCommandBy: command) ?? false
    }

    @MainActor
    private static func commandPaletteField(in root: NSView) -> NSTextField? {
        if let field = root as? NSTextField,
           field.accessibilityIdentifier() == "command-palette.search" {
            return field
        }
        for subview in root.subviews {
            if let field = commandPaletteField(in: subview) { return field }
        }
        return nil
    }

    @MainActor
    private static func commandPaletteFields(in root: NSView) -> [NSTextField] {
        var fields: [NSTextField] = []
        if let field = root as? NSTextField,
           field.accessibilityIdentifier() == "command-palette.search" {
            fields.append(field)
        }
        for subview in root.subviews {
            fields.append(contentsOf: commandPaletteFields(in: subview))
        }
        return fields
    }

    @MainActor
    private static func commandPaletteRevealViews(in root: NSView) -> [CommandPaletteRevealView] {
        var rows: [CommandPaletteRevealView] = []
        if let row = root as? CommandPaletteRevealView {
            rows.append(row)
        }
        for subview in root.subviews {
            rows.append(contentsOf: commandPaletteRevealViews(in: subview))
        }
        return rows
    }

    @MainActor
    private static func fieldDiagnostic(in root: NSView, window: NSWindow) -> String {
        guard let field = commandPaletteField(in: root) else {
            return "field=nil key=\(window.isKeyWindow) first=\(String(describing: window.firstResponder))"
        }
        return "fieldWindow=\(field.window === window) fieldFrame=\(field.frame) key=\(window.isKeyWindow) currentEditor=\(String(describing: field.currentEditor())) first=\(String(describing: window.firstResponder))"
    }

    private static func emitSummary(metric: String, samples: [Double]) {
        let sorted = samples.sorted()
        guard let maximum = sorted.last else { return }
        FileHandle.standardError.write(Data(String(
            format: "COMMAND_PALETTE_WINDOW_BENCHMARK_SUMMARY workload=base64-file-converter repeats=%d trigger=root_view_model_modal_transaction key_dispatch=false metric=%@ p50_ms=%.3f p95_ms=%.3f max_ms=%.3f\n",
            sorted.count, metric, percentile(0.5, sorted: sorted),
            percentile(0.95, sorted: sorted), maximum
        ).utf8))
    }

    private static func percentile(_ value: Double, sorted: [Double]) -> Double {
        let index = max(0, min(sorted.count - 1, Int(ceil(value * Double(sorted.count))) - 1))
        return sorted[index]
    }

    private static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Double {
        let value = (end - start).components
        return Double(value.seconds) * 1_000
            + Double(value.attoseconds) / 1_000_000_000_000_000
    }
}

@MainActor
final class CommandPaletteWindowFixture {
    let suiteName: String
    let defaults: UserDefaults
    let viewModel: RootViewModel
    let hostingView: NSHostingView<AnyView>
    let window: NSWindow

    init(reduceMotion: Bool = false) throws {
        suiteName = "CommandPalettePresentationTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        viewModel = RootViewModel()
        viewModel.selectedToolID = ToolID(rawValue: "base64-file-converter")
        hostingView = NSHostingView(rootView: AnyView(
            RootView(viewModel: viewModel, defaults: defaults)
                .environment(\._accessibilityReduceMotion, reduceMotion)
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 1_200, height: 800)
        window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        flush()
    }

    func flush() {
        hostingView.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func activateWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
    }

    func dispose() {
        window.resignKey()
        window.orderOut(nil)
        window.contentView = nil
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private typealias Fixture = CommandPaletteWindowFixture

private struct PresentationSample {
    let layoutMilliseconds: Double
    let focusMilliseconds: Double
    let readyMilliseconds: Double
}

private enum PresentationBenchmarkError: Error {
    case timeout(String)
}
