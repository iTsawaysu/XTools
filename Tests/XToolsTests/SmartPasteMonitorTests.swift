@testable import XTools
import AppKit
import Foundation
import Observation
import os
import Testing
import XToolsCore

@MainActor
struct SmartPasteMonitorTests {
    @Test func boundedLengthCheckPreservesUnicodeCharacterBoundary() {
        let grapheme = "👨‍👩‍👧‍👦"
        let maximum = SmartPasteDetector.maxInspectedLength

        #expect(SmartPasteMonitor.isWithinInspectionLimit(String(repeating: grapheme, count: maximum)))
        #expect(!SmartPasteMonitor.isWithinInspectionLimit(String(repeating: grapheme, count: maximum + 1)))
    }

    @Test func refreshClassifiesIndependentPasteboardAndRejectsOversizedContent() {
        let monitor = SmartPasteMonitor()
        let pasteboard = NSPasteboard(name: .init("SmartPasteMonitorTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString(#"{"name":"x"}"#, forType: .string)

        monitor.refresh(registry: .default, pasteboard: pasteboard)
        #expect(monitor.suggestion?.kind == .json)

        pasteboard.clearContents()
        pasteboard.setString(
            String(repeating: "a", count: SmartPasteDetector.maxInspectedLength + 1),
            forType: .string
        )
        monitor.refresh(registry: .default, pasteboard: pasteboard)
        #expect(monitor.suggestion == nil)
    }

    @Test func forceRefreshResurfacesSuggestionWhenLeavingOwningTool() {
        let monitor = SmartPasteMonitor()
        let pasteboard = NSPasteboard(name: .init("SmartPasteMonitorForceTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString(#"{"name":"x"}"#, forType: .string)

        monitor.noteSelectedTool("formatter")
        monitor.refresh(registry: .default, pasteboard: pasteboard)
        #expect(monitor.suggestion == nil)

        monitor.noteSelectedTool(nil)
        monitor.refresh(registry: .default, pasteboard: pasteboard, force: true)
        #expect(monitor.suggestion?.kind == .json)
        #expect(monitor.suggestion?.toolID == "formatter")
    }

    @Test func observationInvalidatesOnlyWhenTheDisplayedSuggestionChanges() {
        let monitor = SmartPasteMonitor()
        let pasteboard = NSPasteboard(name: .init("SmartPasteObservationTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString(#"{"name":"x"}"#, forType: .string)
        monitor.refresh(registry: .default, pasteboard: pasteboard)
        #expect(monitor.suggestion?.kind == .json)

        let changes = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = monitor.suggestion
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        monitor.noteSelectedTool("text-encoding")
        monitor.refresh(registry: .default, pasteboard: pasteboard, force: true)
        #expect(changes.withLock { $0 } == 0)

        monitor.dismiss()
        #expect(changes.withLock { $0 } == 1)
        #expect(monitor.suggestion == nil)
    }

}
