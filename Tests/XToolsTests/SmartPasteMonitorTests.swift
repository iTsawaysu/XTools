@testable import XTools
import AppKit
import Foundation
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
}
