import Foundation
import Testing

/// Source-string contracts for the smart-paste suggestion: clipboard privacy,
/// non-displacing presentation, and the Core/app layering boundary.
///
/// See `SourceContractTestSupport.swift` for why these source-string view
/// structure tests are retained.
struct SmartPasteSourceContractTests {
    @Test func detectorStaysPureAndBounded() throws {
        let detector = try readSource("Sources/XToolsCore/Utility/SmartPasteDetector.swift")

        contains(detector, "import Foundation", "Smart paste detection must be a Foundation-only Core value")
        doesNotContain(detector, "import AppKit", "Core detection must not depend on AppKit")
        doesNotContain(detector, "import SwiftUI", "Core detection must not depend on SwiftUI")
        doesNotContain(detector, "ToolID", "Core detection must not know tool identities; routing lives in the app layer")
        contains(detector, "public static let maxInspectedLength", "Detection must declare an explicit inspection bound")
        contains(detector, "isWithinCharacterLimit(text, limit: maxInspectedLength)", "Detection must refuse oversized clipboard payloads with a bounded grapheme check")
    }

    @Test func monitorSamplesOnActivationWithoutPolling() throws {
        let monitor = try readSource("Sources/XTools/AppShell/SmartPasteMonitor.swift")
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")

        doesNotContain(monitor, "Timer", "Clipboard sampling must not poll on a timer")
        doesNotContain(monitor, "scheduledTimer", "Clipboard sampling must not poll on a timer")
        contains(monitor, "pasteboard.changeCount", "Sampling must be gated on the pasteboard change count")
        contains(monitor, "guard changeCount != inspectedChangeCount else { return }", "Unchanged clipboard content must not be re-inspected")

        contains(root, "guard phase == .active else { return }", "Clipboard must only be sampled when the app comes forward")
        contains(root, "smartPaste.refresh(registry: registry)", "App activation must drive the clipboard refresh")
    }

    @Test func suggestionRespectsDismissalAndCurrentTool() throws {
        let monitor = try readSource("Sources/XTools/AppShell/SmartPasteMonitor.swift")

        contains(monitor, "private var dismissedChangeCount = -1", "Dismissal must be remembered per clipboard generation")
        contains(monitor, "guard changeCount != dismissedChangeCount else { return }", "A dismissed suggestion must not reappear for the same clipboard content")
        contains(monitor, "tool.id != currentToolID", "The tool already on screen must not be suggested")
        contains(monitor, "func noteSelectedTool", "Navigation must be able to retire a stale suggestion")
        contains(monitor, ": \"json-formatter\"", "Clipboard kinds must route to registered tool identities")
    }

    @Test func bannerFloatsWithoutDisplacingTheWorkspace() throws {
        let banner = try readSource("Sources/XTools/AppShell/SmartPasteSuggestionBanner.swift")
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")

        contains(banner, ".toolSurface(\n            .floating,", "The suggestion must reuse the shared floating material surface treatment")
        contains(banner, "autoDismissDelay", "The suggestion is transient by design and must auto-dismiss")
        contains(banner, "IndexSmallButtonStyle()", "The suggestion action must reuse the shared small button style")

        contains(root, ".overlay(alignment: .top) {\n            if let suggestion = smartPaste.suggestion {", "The suggestion must overlay the workspace instead of joining page layout")
        contains(root, "ToolMotion.Transition.topRowInsertion", "The suggestion must reuse the shared top-row insertion transition")
        contains(root, "onDismiss: smartPaste.dismiss", "Dismissing must be wired to the monitor so the hint stays dismissible")
    }
}
