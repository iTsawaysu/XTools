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
        contains(monitor, ": \"formatter\"", "Clipboard kinds must route to registered tool identities")
        contains(monitor, "hubSegment: \"json\"", "Clipboard JSON must deep-link into the formatter hub's JSON segment")
        contains(monitor, "hubSegment: \"xml\"", "Clipboard XML must deep-link into the formatter hub's XML segment")
        contains(monitor, ": \"text-encoding\"", "URL-encoded and Base64 clipboards must route into the encoding hub")
        contains(monitor, "hubSegment: \"url\"", "Clipboard URL-encoded text must deep-link into the encoding hub's URL segment")
        contains(monitor, "hubSegment: \"base64\"", "Clipboard Base64 must deep-link into the encoding hub's Base64 segment")
    }

    @Test func bannerFloatsWithoutDisplacingTheWorkspace() throws {
        let banner = try readSource("Sources/XTools/AppShell/SmartPasteSuggestionBanner.swift")
        let monitor = try readSource("Sources/XTools/AppShell/SmartPasteMonitor.swift")
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")

        contains(banner, ".toolSurface(\n            .floating,", "The suggestion must reuse the shared floating material surface treatment")
        contains(banner, "autoDismissDelay", "The suggestion is transient by design and must auto-dismiss")
        contains(banner, "IndexSmallButtonStyle()", "The suggestion action must reuse the shared small button style")

        // Hover-pause bookkeeping mirrors ToastCenter: the banner must never be
        // pulled out from under the pointer, and leaving resumes the remainder.
        contains(banner, "func pauseDismissal()", "Hovering must freeze the auto-dismiss countdown")
        contains(banner, "func resumeDismissal()", "Leaving the banner must resume the remaining countdown, not restart it")
        contains(banner, ".onHover { hovering in", "The banner must wire hover into the pause/resume bookkeeping")

        // Every suggestion mutation rides the shared panelReveal transaction so
        // the banner animates in and out instead of popping.
        contains(monitor, "applyToolMotion {", "Suggestion mutations must run inside the shared panelReveal transaction (ToastCenter-isomorphic)")

        contains(root, ".overlay(alignment: .top) {\n            if let suggestion = smartPaste.suggestion {", "The suggestion must overlay the workspace instead of joining page layout")
        contains(root, "ToolMotion.Transition.toastPanel", "The suggestion must reuse the shared floating-panel transition so removal fades out (topRowInsertion's removal is identity and would vanish)")
        contains(root, ".id(suggestion)", "Replacing the suggestion must replay the transition instead of an unanimated same-tick content swap")
        contains(root, "onDismiss: smartPaste.dismiss", "Dismissing must be wired to the monitor so the hint stays dismissible")
    }
}
