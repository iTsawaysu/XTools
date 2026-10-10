import Foundation
import AppKit
@testable import XTools
import Testing

/// Symbol-level motion contract tests.
///
/// These anchors intentionally assert only symbol existence (type/enum/
/// function names, shared preset usage) and structural skeleton rules
/// ("no page-local animation owner", "no bounce vocabulary"). Concrete
/// duration/curve values live in ToolMotionTests; multi-line
/// indentation-sensitive needles and value-duplicate anchors were retired.
struct MotionSourceContractTests {
    @Test func motionVocabularyStaysSharedAndBounceFree() throws {
        let motion = try readSource("Sources/XTools/Shared/ToolMotion.swift")
        let metrics = try readSource("Sources/XTools/Shared/ToolMetrics.swift")

        contains(motion, "enum ToolMotion", "Motion tokens must live in a named shared vocabulary")
        contains(motion, "enum Duration", "Motion must expose shared duration tokens")
        contains(motion, "accessibilityDisplayShouldReduceMotion", "Motion helper must honor the system Reduce Motion preference outside SwiftUI views")
        contains(motion, "func withToolAnimation(", "Motion helper must centralize animated state mutation")
        contains(motion, "func toolAnimation<Value: Equatable>", "SwiftUI views must have a shared Reduce Motion-aware animation modifier")
        contains(motion, "smoothOutControlPoints", "SwiftUI and AppKit disclosure motion must share one curve definition")

        contains(motion, "static let accordion", "Disclosure accordions must keep a shared preset token")
        contains(motion, "static var accordion: AppKitMotion", "The AppKit sidebar renderer must consume the shared accordion token")
        contains(motion, "static func selectionSlide() -> CASpringAnimation", "The sidebar selection chrome must spring through a ToolMotion-owned CASpringAnimation factory")

        contains(motion, "enum OrderedDirection", "Ordered mode direction must use a shared semantic type")
        contains(motion, "static func orderedContent(_ direction: OrderedDirection) -> AnyTransition", "Ordered mode direction must come from a shared transition recipe")
        contains(motion, ".offset(x: direction.insertionOffsetX)", "Ordered mode call sites must not pass page-local distances")

        contains(motion, "static let pageArrival", "Tool pages must keep the shared arrival preset")
        contains(motion, "static let pageDeparture", "The outgoing page must keep its own departure preset")
        contains(motion, "static var scrim: AnyTransition", "Modal scrims must have a shared opacity-only transition token")
        contains(motion, "static let resultPresenceAppearance", "Short-result appearance must keep a shared timing owner")
        contains(motion, "static let resultPresenceExit", "Short-result exit must keep a distinct timing owner")
        contains(motion, "static let productiveExitControlPoints", "Result removal must use one shared accelerating curve owner")

        doesNotContain(motion, "static let completion", "Completion feedback must flow through iconSwap helpers, not a separate preset")
        doesNotContain(motion, "static let success", "Success feedback must not keep a legacy preset alias")
        doesNotContain(motion, "Curve.bounce", "No bounce curves may exist in the motion vocabulary")
        doesNotContain(motion, "pillStretch", "Pill stretch must not return beside the prototype spring")
        doesNotContain(motion, "static let pageContent", "Tool page switching is an entry hot path and must not define a page-content preset")
        doesNotContain(motion, "static var pageContent", "Tool page switching must not define a page-content transition token")
        occurrenceCount(metrics, "ToolMotion.Duration", 2, "Legacy ToolMetrics animation durations must forward to ToolMotion")
    }

    @Test func sidebarMotionHasOneAppKitOwner() throws {
        let sidebar = try readSource("Sources/XTools/AppShell/SidebarView.swift")
        let sidebarRenderer = try readSource("Sources/XTools/AppShell/SidebarNavigationListCoordinator.swift")
        let sidebarRowComponents = try readSource("Sources/XTools/AppShell/SidebarViewRowComponents.swift")
        let disclosureBody = try readSource("Sources/XTools/Shared/ToolDisclosureBody.swift")
        let track = try readSource("Sources/XTools/AppShell/SidebarNavigationTrackView.swift")

        contains(sidebar, "SidebarNavigationList(configuration:", "Sidebar tools must render through the single stable AppKit identity domain")
        contains(sidebar, "let favoriteOrder: [ToolID]", "Sidebar must receive the stable favorite ordering that triggers navigation moves")
        doesNotContain(sidebar, "ForEach(sidebarEntries)", "Sidebar must not regress to structural SwiftUI row insertion and removal")
        doesNotContain(sidebar, "collapsedToolList", "Sidebar must not regress to the 46-tool collapsed rail")
        contains(sidebarRowComponents, "ToolMotion.Preset.accordion", "Sidebar group chevron rotation must route through the shared accordion preset")
        contains(sidebarRenderer, "ToolMotion.AppKitPreset.accordion", "The AppKit renderer must use the shared disclosure motion adapter")

        contains(disclosureBody, "struct ToolDisclosureBody", "Disclosure body motion must live in one shared component")
        contains(disclosureBody, "withToolAnimation(animation, reduceMotion: reduceMotion)", "Disclosure height changes must route through ToolMotion")
        contains(disclosureBody, ".allowsHitTesting(isExpanded)", "Collapsed disclosure bodies must not receive pointer events")
        contains(disclosureBody, ".accessibilityHidden(!isExpanded)", "Collapsed disclosure bodies must be hidden from accessibility")
        doesNotContain(disclosureBody, ".offset(", "Disclosure collapse must not make rows fly away from the header")

        doesNotContain(track, "transform.scale.y", "The sliding selection chrome must stay pure translation — no deformation")

        // Search filtering presents directly: no per-row choreography may return.
        doesNotContain(sidebarRenderer, "runSearchArrivalStagger", "Search arrival must not stagger rows in")
        doesNotContain(sidebarRenderer, "crossfadeRefinementInserts", "Search refinement must not crossfade rows in")
        contains(sidebarRenderer, "configuration.isSearchActive || searchChanged", "Search state changes must keep routing through immediate (direct-presentation) mode")
        contains(sidebarRenderer, "removeAllAnimations()", "A row an interrupted fade was leaving partial must still be reclaimed at full alpha")
    }

    @Test func toolPageArrivalChoreographyStaysStageOwned() throws {
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")
        let host = try readSource("Sources/XTools/AppShell/ToolDetailHostView.swift")
        let stage = try readSource("Sources/XTools/AppShell/ToolPageStage.swift")
        let dashboard = try readSource("Sources/XTools/AppShell/DashboardView.swift")

        contains(host, ".toolPageArrival(id: tool.id.rawValue)", "Only real tool pages may keep the host-owned arrival modifier")
        contains(host, "ToolPageStage(target: pageKey)", "The detail host must swap tool, dashboard, and empty pages through the shared page stage")
        contains(root, ".toolAnimation(ToolMotion.Preset.pageArrival, value: viewModel.selectedToolID)", "Root must preserve existing tool-page arrival behavior")
        contains(stage, "withAnimation(ToolMotion.Preset.pageDeparture)", "The outgoing layer must depart through its own productiveExit transaction")
        contains(stage, "withAnimation(ToolMotion.Preset.pageArrival)", "The incoming layer must arrive through its own smoothOut transaction")
        contains(stage, "transaction.disablesAnimations = true", "Reduce Motion and first mount must swap pages directly without a transition")
        contains(stage, ".allowsHitTesting(key == displayed)", "Departing layers must stop hit testing immediately while their exit plays")
        doesNotContain(dashboard, ".toolPageArrival(", "V3 dashboard must not replay a page-arrival animation")
        doesNotContain(host, ".transition(", "Tool detail host must not animate tool page replacement outside the pageArrival whitelist")
        doesNotContain(host, ".toolTransition(", "Tool detail host must not animate tool page replacement outside the pageArrival whitelist")
    }

    @Test func commandPaletteMotionKeepsOneProgressOwner() throws {
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")
        let rootViewModel = try readSource("Sources/XTools/AppShell/RootViewModel.swift")
        let paletteGeometry = try readSource("Sources/XTools/AppShell/CommandPaletteVisibilityGeometry.swift")
        let paletteOverlayHost = try readSource("Sources/XTools/AppShell/CommandPaletteOverlayHost.swift")
        let commandPalette = try readSource("Sources/XTools/AppShell/CommandPalette.swift")
        let highlight = try readSource("Sources/XTools/AppShell/CommandPaletteSelectionHighlight.swift")
        let motion = try readSource("Sources/XTools/Shared/ToolMotion.swift")

        contains(motion, "enum PaletteMotion", "Palette choreography must own one terminal-value namespace")
        contains(paletteOverlayHost, "struct CommandPaletteOverlayHost: View", "Command palette presentation animation must live in its lightweight overlay observer")
        contains(paletteOverlayHost, "CommandPaletteScrim", "Command palette dimming must be a root-owned full-window layer")
        contains(paletteGeometry, "struct CommandPaletteVisibilityGeometry: Equatable", "Palette geometry must expose a pure regression-testable progress mapping")
        contains(rootViewModel, "ToolMotion.Preset.shellResize", "Root shell resize/focus motion must use ToolMotion")
        doesNotContain(root, "PaletteIconFlightCoordinator", "The decorative palette icon continuity flight is removed: palette jumps switch directly")
        doesNotContain(commandPalette, "scaleEffect", "Panel motion must not scale the native-view subtree")
        contains(commandPalette, "CommandPaletteSelectionHighlightHost(", "The list must host the floating selection highlight")
        contains(highlight, "struct CommandPaletteRowAnchorsKey: PreferenceKey", "Selectable-row bounds must publish through one preference key")
        doesNotContain(highlight, ".animation(", "The floating highlight must reposition instantly on every active-row change")
    }

    @Test func diagnosticAndToastMotionStayShared() throws {
        let shared = try readSharedBagComponents()
        let toast = try readSource("Sources/XTools/Shared/Components/ToastCenter.swift")
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")
        let diagnosticViews = try readSource("Sources/XTools/ToolPages/Workbench/Diagnostics/IndexFormatDiagnosticViews.swift")

        contains(toast, "ToolMotion.Preset.panelReveal", "Toast queue changes must use the shared panel reveal preset")
        contains(shared, "ToolMotion.Transition.diagnostic", "Workspace diagnostics may reveal only through the shared safe diagnostic transition")
        contains(workbench, "IndexDiagnosticStatusSlot(isActive: hasDiagnostic)", "Conversion banner presence must ride the shared status slot")
        contains(diagnosticViews, "struct IndexDiagnosticStatusSlot", "Workbench diagnostic status rows must share one sanctioned container")
        doesNotContain(workbench, "withAnimation(", "The fixed text conversion workbench must not retain a focus-mode animation path")
    }

    @Test func generateParseModeTransitionStaysShared() throws {
        let mode = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexGenerateParseMode.swift")
        let jwt = try readSource("Sources/XTools/ToolPages/Web/JWTParserPage.swift")
        let basic = try readSource("Sources/XTools/ToolPages/Web/BasicAuthGeneratorPage.swift")

        contains(mode, ".toolTransition(ToolMotion.Transition.orderedContent(direction), reduceMotion: reduceMotion)", "Mode content must disable its directional transition for Reduce Motion")
        contains(jwt, "IndexGenerateParseModeContent(", "JWT must reuse shared generate/parse motion")
        contains(basic, "IndexGenerateParseModeContent(", "Basic Auth must reuse shared generate/parse motion")
    }

    @Test func actionStateFeedbackUsesSharedLifecycleComponents() throws {
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")
        let copyButton = try readSource("Sources/XTools/Shared/Components/IndexCopyButton.swift")
        let feedbackState = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexEphemeralActionFeedback.swift")
        let html = try readSource("Sources/XTools/ToolPages/Development/HTMLToMarkdownPage.swift")
        let base64File = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        let crontab = try readSource("Sources/XTools/ToolPages/Development/CrontabGeneratorPage.swift")
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")

        contains(controls, "struct IndexProgressMotionLabel<ID: Hashable>: View", "Indeterminate action-state labels must live in a shared component")
        contains(html, "IndexProgressMotionLabel(", "HTML URL fetch action must use the shared indeterminate action-state label")
        contains(base64File, "private struct Base64FileActivityLabel: View", "Base64 file activity feedback must live in one page-private fixed-slot component")
        contains(base64File, "IndexProgressMotionLabel(", "Base64 file activity feedback must reuse the shared icon-slot progress label")
        occurrenceCount(base64File, "IndexMotionLabel(", 0, "Base64 decoded-save action must not keep a duplicate text-labelled branch")

        contains(feedbackState, "struct IndexEphemeralActionFeedbackState: Equatable", "Ephemeral copy/save feedback must use one testable value-state contract")
        contains(feedbackState, "generation &+= 1", "Every successful retrigger must invalidate older reset completions")
        contains(copyButton, "feedback.trigger()", "Copy feedback must retrigger the shared lifecycle")
        contains(copyButton, ".task(id: feedback.generation)", "Copy reset waits must be structurally cancelled on retrigger and view removal")
        contains(workbench, "feedback.trigger()", "Save feedback must retrigger the shared lifecycle")

        doesNotContain(crontab, "IndexPanel(\"下次运行时间\")", "Crontab next-runs must live inside the merged 解析结果 panel instead of a standalone panel")
        contains(crontab, ".toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)", "Crontab next-runs panel reveal must use the shared diagnostic transition")
    }

    @Test func highFrequencyValuesStayImmediate() throws {
        let caseConverter = try readSource("Sources/XTools/ToolPages/Converter/CaseConverterPage.swift")
        let textStats = try readSource("Sources/XTools/ToolPages/Utility/TextStatisticsPage.swift")
        let keycode = try readSource("Sources/XTools/ToolPages/Web/KeycodeInfoPage.swift")
        let fileType = try readSource("Sources/XTools/ToolPages/Utility/FileTypeDetectorPage.swift")
        let dropZone = try readSource("Sources/XTools/Shared/Components/IndexDropZone.swift")
        let color = try readSource("Sources/XTools/ToolPages/Image/ColorPickerPage.swift")

        contains(caseConverter, "valueMotion: .immediate", "Case conversion rows update on every edit and must not crossfade")
        contains(textStats, "valueMotion: .immediate", "Text statistics must not animate on every edit")
        contains(keycode, "valueMotion: .immediate", "Keycode rows must not animate on every keyDown")
        doesNotContain(color, "valueMotion", "Color result rows must render unconditionally while sliders move")
        contains(fileType, ".indexDropZone(", "File type drop targeting must route through the shared drop-zone owner")
        contains(dropZone, "withToolAnimation(ToolMotion.Preset.controlFeedback)", "Shared drop-zone targeting must mutate through the control-feedback motion owner")
        contains(keycode, "override var acceptsFirstResponder: Bool { true }", "Motion cleanup must preserve key capture first-responder capability")
        contains(keycode, "window.makeFirstResponder(self)", "Keyboard Event must preserve automatic key capture focus")
    }

    @Test func boundedPresenceCallersShareOneOwnerAndPrototypesStayOutside() throws {
        let shared = try readSharedBagComponents()
        let integerBase = try readSource("Sources/XTools/ToolPages/Converter/IntegerBaseConverterPage.swift")
        let dateTime = try readSource("Sources/XTools/ToolPages/Time/DateTimeConverterPage.swift")
        let keycode = try readSource("Sources/XTools/ToolPages/Web/KeycodeInfoPage.swift")
        let userAgent = try readSource("Sources/XTools/ToolPages/Web/UserAgentParserPage.swift")
        let basicAuth = try readSource("Sources/XTools/ToolPages/Web/BasicAuthGeneratorPage.swift")
        let jwt = try readSource("Sources/XTools/ToolPages/Web/JWTParserPage.swift")
        let fileType = try readSource("Sources/XTools/ToolPages/Utility/FileTypeDetectorPage.swift")
        let regex = try readSource("Sources/XTools/ToolPages/Development/RegexTesterPage.swift")
        let password = try readSource("Sources/XTools/ToolPages/Crypto/PasswordGeneratorPage.swift")
        let token = try readSource("Sources/XTools/ToolPages/Crypto/TokenGeneratorPage.swift")
        let uuid = try readSource("Sources/XTools/ToolPages/Crypto/UUIDGeneratorPage.swift")
        let imageStage = try readSource("Sources/XTools/ToolPages/Image/ImagePreviewStage.swift")
        let favicon = try readSource("Sources/XTools/ToolPages/Image/FaviconGeneratorPage.swift")
        let base64File = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")

        contains(shared, "enum IndexValueMotionPolicy", "Shared value surfaces must expose an explicit motion policy")
        contains(shared, "func indexValueMotion<ID: Hashable>(", "Value motion policy must be applied at the leaf view rather than the owning container")
        contains(shared, "struct IndexScrollableKVRow: Identifiable", "Scrollable KV must accept stable caller-owned row identities")
        contains(shared, "IndexResultPresence(", "Short KV and card results must share one presence owner")
        doesNotContain(shared, ".toolAnimation(ToolMotion.Preset.panelReveal, value: rows.isEmpty)", "Low-level IndexKV must not animate the entire descendant tree on empty/result changes")

        contains(integerBase, "IndexShortResultKV(", "Integer-base results must use shared bounded presence")
        contains(dateTime, "IndexShortResultKV(", "Timestamp results must share bounded presence")
        contains(keycode, "IndexResultPresence(", "Keycode must animate only the empty-to-first-snapshot boundary")
        contains(userAgent, "IndexResultPresence(", "UserAgent optional results must retain a presentation snapshot")
        contains(basicAuth, "IndexResultPresence(", "Basic Auth parsed credentials must use shared presence")
        appearsBefore(basicAuth, "showsParsedPassword = false", "session.parse()", "Basic Auth must restore the password mask before parsing can clear the result")
        contains(jwt, "IndexResultPresence(", "JWT local-check details must use shared presence")
        contains(fileType, "IndexResultPresence(", "File type detection must replace its old reveal with shared bounded presence")

        // Prototypes and unbounded surfaces must stay outside bounded presence.
        doesNotContain(regex, "IndexResultPresence(", "Unbounded Regex rows must remain outside bounded presence")
        doesNotContain(password, "IndexResultPresence(", "Password initial generation must not gain a structural appear lifecycle")
        doesNotContain(token, "IndexResultPresence(", "Token initial generation must not gain a structural appear lifecycle")
        doesNotContain(uuid, "IndexResultPresence(", "UUID initial generation must not gain a structural appear lifecycle")
        doesNotContain(imageStage, "IndexResultPresence(", "Image replacement must keep the preview-stage owner")
        doesNotContain(favicon, "IndexResultPresence(", "Favicon batch generation must keep its bounded batch owner")
        doesNotContain(base64File, "IndexResultPresence(", "Large Base64 output must update in place instead of crossfading its content")
    }

    @Test func shellChromeKeepsFixedSlotMicroInteractions() throws {
        let titlebar = try readSource("Sources/XTools/AppShell/TitlebarView.swift")
        let buttonStyles = try readSource("Sources/XTools/AppShell/TitlebarButtonStyles.swift")
        let sidebar = try readSource("Sources/XTools/AppShell/SidebarView.swift")

        doesNotContain(titlebar, "WindowToolbarToolContext", "Toolbar must not render a tool breadcrumb context view")
        contains(titlebar, ".toolMotionIconSwap(id: isSidebarVisible)", "Sidebar toggle must keep its fixed-slot visibility icon swap")
        contains(titlebar, ".toolMotionIconSwap(id: isFavorite)", "Toolbar favorite star must keep its fixed-slot icon swap")
        occurrenceCount(buttonStyles, ".toolAnimation(ToolMotion.Preset.controlFeedback,", 3, "Chrome button styles must animate hover/press through the shared control-feedback preset")
        doesNotContain(buttonStyles, ".scaleEffect", "Chrome button feedback must not scale the hit target")
        contains(sidebar, ".toolAnimation(ToolMotion.Preset.controlFeedback, value: isSearchFocused)", "Sidebar search focus ring must animate through the shared control-feedback preset")
    }

    @Test func asyncSurfacesAvoidFakeLoadingEffects() throws {
        let base64File = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        let favicon = try readSource("Sources/XTools/ToolPages/Image/FaviconGeneratorPage.swift")
        let imageStage = try readSource("Sources/XTools/ToolPages/Image/ImagePreviewStage.swift")

        contains(imageStage, "ObjectIdentifier(image)", "Image preview reveal must key off image replacement rather than pixels or processing loops")
        contains(imageStage, ".toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)", "Image preview stage must use a lightweight shared transition")
        contains(base64File, "private var filePickerStatusIcon: some View", "Base64 file reading feedback must stay inside one fixed icon slot")
        contains(base64File, ".toolAnimation(ToolMotion.Preset.controlFeedback, value: isFileDropTargeted)", "Base64 file drop target must use lightweight shared feedback")
        contains(favicon, ".toolAnimation(ToolMotion.Preset.panelReveal, value: session.package != nil)", "Favicon package rows are bounded and may reveal as one atomic batch")

        for (name, source) in [("ImagePreviewStage", imageStage), ("Base64File", base64File), ("Favicon", favicon)] {
            doesNotContain(source, ".blur(", "\(name) must not blur image pixels or content for a loading effect")
            doesNotContain(source, "shimmer", "\(name) must not use a shimmer placeholder")
            doesNotContain(source, "repeatForever", "\(name) must not run a looping custom spinner or pulse")
            doesNotContain(source, ".rotationEffect(", "\(name) must not spin a hand-rolled progress indicator")
        }
    }

    @Test func wave2NamespacesStayDeclaredAndDeformationStaysBanned() throws {
        let motion = try readSource("Sources/XTools/Shared/ToolMotion.swift")
        let shared = try readSource("Sources/XTools/Shared/Components/InteractionFeedback.swift")
        let theme = try readSource("Sources/XTools/Shared/ToolTheme.swift")
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexSegmentedControl.swift")
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexFormatWorkbench.swift")

        contains(motion, "enum OutputBreath", "Wave 2 output breath must own one terminal-value namespace")
        contains(shared, "withAnimation(ToolMotion.OutputBreath.rise)", "Breath rise must be its own transaction")
        contains(motion, "enum PaneHover", "Card-lift pane hover must own one timing namespace")
        contains(theme, "static let paneHoverResting", "Resting card shadow must flow through the restrained recipe token")
        contains(theme, "static let paneHoverLifted", "Lifted card shadow must flow through the restrained recipe token")
        contains(shared, ".toolShadowBehind(recipe, cornerRadius: cornerRadius)", "Hover depth must cast from a backing shape so native gutter hairlines survive")
        let modifier = sourceSlice(shared, from: "private struct ToolPaneHoverChromeModifier", to: "struct ToolOutputBreathModifier")
        doesNotContain(modifier, ".offset(", "Hover must not translate the pane (discipline: no hover transform)")
        doesNotContain(modifier, ".scaleEffect(", "Hover must not scale the pane (discipline: no hover transform)")

        contains(motion, "enum ErrorFeedback", "Error feedback must own one terminal-value namespace")
        doesNotContain(shared, "ToolShakeEffect", "The retired damped-sine shake must not return as a shared effect")
        doesNotContain(workbench, ".toolErrorShake(", "Formatter errors must not shake the editor workspace")
        contains(workbench, ".toolErrorTint(active: showsErrorState", "The error chrome must be state-held, not conditionally laid out")

        contains(motion, "enum CopyTick", "The copy tick must own one terminal-value namespace")
        let copyButton = try readSource("Sources/XTools/Shared/Components/IndexCopyButton.swift")
        occurrenceCount(copyButton, "IndexCopyTickIconSlot(generation: feedback.generation)", 2, "Both copy presentations must route through the fixed tick icon slot")
        doesNotContain(copyButton, #"Text(copied ? "已复制" : title)"#, "The copy button label must stay constant (no visual 已复制 swap)")
        contains(copyButton, #"copied ? "已复制" : title"#, "The 已复制 switch may live on the accessibility/help surface")

        contains(motion, "enum SegmentedCursor", "The segmented cursor must own one terminal-value namespace")
        contains(controls, "IndexSegmentedCursorLayer(", "The selected fill must float in the shared cursor layer behind the segments")
        contains(controls, "ToolMotion.SegmentedCursor.slide", "Cursor flights must ride the shared ToolMotion spring")

        contains(motion, "enum EmptyArrival", "Empty-state arrival must own one terminal-value namespace")
        contains(motion, "enum LocatingWash", "The locating wash must own one terminal-value namespace")
        contains(shared, "class ToolLocatingWashView: NSView", "The locating wash must be the shared AppKit-hosted component")
        contains(root, "withToolAnimation(ToolMotion.Preset.themeCrossfade", "The theme flip must dissolve through one animated transaction")
    }

    @Test func locatingWashWorkspaceWiringStaysPresent() throws {
        let workspace = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffMergeView.swift")

        contains(workspace, "ToolLocatingWashView()", "Each diff pane must host one wash surface")
        contains(workspace, "locatingWashGeneration += 1", "Each successful jump must bump the wash generation once")
        contains(workspace, "playLocatingWash(for: hunk, generation: locatingWashGeneration)", "A landed jump must fire the locating wash")
        doesNotContain(workspace, "gutterDeepeningFrame(", "No gutter-deepening remnant may stay in the jump path")
    }
}
