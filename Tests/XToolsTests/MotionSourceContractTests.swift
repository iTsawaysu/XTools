import Foundation
import AppKit
@testable import XTools
import Testing

struct MotionSourceContractTests {
    @Test func toolMotionOwnsShellToastAndDiagnosticAnimations() throws {
        let motion = try readSource("Sources/XTools/Shared/ToolMotion.swift")
        let metrics = try readSource("Sources/XTools/Shared/ToolMetrics.swift")
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")
        let sidebar = try readSource("Sources/XTools/AppShell/SidebarView.swift")
        let sidebarRenderer = try readSource("Sources/XTools/AppShell/SidebarNavigationListCoordinator.swift")
        let disclosureBody = try readSource("Sources/XTools/Shared/ToolDisclosureBody.swift")
        let resultPresence = try readSource("Sources/XTools/ToolPages/Workbench/Diagnostics/IndexResultPresence.swift")
        let resultPresenceState = try readSource("Sources/XToolsCore/Utility/ResultPresenceState.swift")
        let resultPresenceShim = try readSource("Sources/XTools/ToolPages/Workbench/Diagnostics/IndexResultPresenceState.swift")
        let toast = try readSource("Sources/XTools/Shared/Components/ToastCenter.swift")
        let shared = try readSharedBagComponents()
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")
        let commandPalette = try readSource("Sources/XTools/AppShell/CommandPalette.swift")
        let host = try readSource("Sources/XTools/AppShell/ToolDetailHostView.swift")

        contains(motion, "enum ToolMotion", "Motion tokens must live in a named shared vocabulary")
        contains(motion, "enum Duration", "Motion must expose shared duration tokens")
        contains(motion, "static let quick: TimeInterval = 0.15", "Motion must keep the quick feedback duration explicit")
        contains(motion, "static let medium: TimeInterval = 0.35", "Motion must keep panel reveal inside the agreed lightweight range")
        contains(motion, "accessibilityDisplayShouldReduceMotion", "Motion helper must honor the system Reduce Motion preference outside SwiftUI views")
        contains(motion, "func withToolAnimation(", "Motion helper must centralize animated state mutation")
        contains(motion, "func toolAnimation<Value: Equatable>", "SwiftUI views must have a shared Reduce Motion-aware animation modifier")
        contains(motion, "static let accordion = Curve.smoothOut(duration: Duration.medium)", "Disclosure accordions must use a slightly longer smooth-out curve instead of a symmetric ease that feels sticky on collapse")
        contains(motion, "static let navigationReorder = accordion", "Navigation reordering must stay synchronized with disclosure movement")
        contains(motion, "static var accordion: AppKitMotion", "The AppKit sidebar renderer must consume the shared accordion token")
        contains(motion, "smoothOutControlPoints", "SwiftUI and AppKit disclosure motion must share one curve definition")
        doesNotContain(root, ".toolAnimation(ToolMotion.Preset.navigationReorder, value: favorites.favoriteIDs)", "Root must not own sidebar item layout animation outside the real identity container")
        contains(root, "favoriteOrder: favorites.favoriteIDs", "Root must pass favorite order as a narrow sidebar animation trigger")
        contains(root, "onToggleFavorite: { toggleFavorite($0, showsToast: false) }", "Sidebar and titlebar favorite actions must share the same reorder path")
        contains(sidebar, "let favoriteOrder: [ToolID]", "Sidebar must receive the stable favorite ordering that triggers navigation moves")
        contains(sidebar, "SidebarNavigationList(configuration:", "Sidebar tools must render through the single stable AppKit identity domain")
        contains(sidebarRenderer, "configuration.favoriteOrder != currentConfiguration.favoriteOrder", "The flat coordinator must classify favorite reordering independently")
        contains(sidebarRenderer, "expansionState(in: configuration.entries)", "The flat coordinator must classify disclosure changes independently")
        contains(sidebarRenderer, "ToolMotion.AppKitPreset.accordion", "The AppKit renderer must use the shared disclosure motion adapter")
        doesNotContain(sidebar, "ForEach(sidebarEntries)", "Sidebar must not regress to structural SwiftUI row insertion and removal")
        doesNotContain(sidebar, ".animation(disclosureAnimation, value: expandedGroupIDs)", "Sidebar disclosure geometry must have one AppKit animation owner")
        doesNotContain(sidebar, ".toolAnimation(ToolMotion.Preset.navigationReorder, value: searchText)", "Search filtering must not trigger favorite reorder motion")
        doesNotContain(sidebar, "private var chevronAnimation: Animation?", "Sidebar group chevrons must not keep a local Animation? helper outside ToolMotion.animation")
        contains(sidebar, "ToolMotion.animation(\n                ToolMotion.Preset.accordion,\n                reduceMotion: reduceMotion || isSearchActive\n            )", "Sidebar group chevron rotation must route through ToolMotion.animation with search/Reduce Motion short-circuit")
        doesNotContain(sidebar, "ToolDisclosureBody(", "Sidebar movable tool rows must not be split across clipped per-group identity domains")
        contains(motion, "static let orderedContent = Curve.smoothOut(duration: Duration.fast)", "Ordered mode reveals must use a shared structural timing")
        contains(motion, "AppKit sidebar owns reorder", "navigationReorder must document AppKit ownership and forbid SwiftUI search bindings")
        contains(motion, "enum OrderedDirection", "Ordered mode direction must use a shared semantic type")
        contains(motion, "case backward", "Ordered mode transitions must support backward navigation")
        contains(motion, "case forward", "Ordered mode transitions must support forward navigation")
        contains(motion, "static func orderedContent(_ direction: OrderedDirection) -> AnyTransition", "Ordered mode direction must come from a shared transition recipe")
        contains(motion, ".offset(x: direction.insertionOffsetX)", "Ordered mode call sites must not pass page-local distances")
        doesNotContain(motion, "static let completion", "Completion feedback must flow through iconSwap helpers, not a separate preset")
        doesNotContain(motion, "static let success", "Success feedback must not keep a legacy preset alias")
        doesNotContain(motion, "Curve.bounce", "No bounce curves may exist in the motion vocabulary")
        contains(metrics, "static let fast: TimeInterval = ToolMotion.Duration.micro", "Legacy ToolMetrics animation duration must forward to ToolMotion")
        contains(metrics, "static let base: TimeInterval = ToolMotion.Duration.quick", "Legacy ToolMetrics base duration must forward to ToolMotion")

        contains(motion, "static var scrim: AnyTransition", "Modal scrims must have an opacity-only transition token")
        doesNotContain(motion, "static let pageContent", "Tool page switching is an entry hot path and must not define a page-content animation preset")
        doesNotContain(motion, "static var pageContent", "Tool page switching is an entry hot path and must not define a page-content transition token")

        contains(root, "ToolMotion.Preset.shellResize", "Root shell resize/focus motion must use ToolMotion")
        contains(root, "CommandPaletteScrim", "Command palette dimming must be a root-owned full-window layer")
        contains(root, ".toolTransition(ToolMotion.Transition.scrim, reduceMotion: reduceMotion)", "Command palette scrim must use the opacity-only scrim transition")
        contains(root, ".toolTransition(ToolMotion.Transition.commandPalette, reduceMotion: reduceMotion)", "v3: palette panel must use the dedicated scale-and-settle transition")
        contains(root, "withToolAnimation(ToolMotion.Preset.modal) {\n            navigationActions.closeCommandPalette()", "v3: palette open/close must run inside one explicit animation transaction")
        doesNotContain(commandPalette, "ToolMotion.Preset.orderedContent.delay", "Command palette rows must not create per-row arrival animations during modal presentation")
        contains(root, "commandPaletteOverlay\n                .toolAnimation(ToolMotion.Preset.modal, value: viewModel.showsCommandPalette)", "Command palette animation must be scoped to the overlay layers")
        contains(root, "withToolAnimation(ToolMotion.Preset.shellResize, reduceMotion: reduceMotion)", "Root shell explicit toggles must route through ToolMotion")
        contains(root, "PaletteIconGhostView(flight: flight", "v3: palette-to-title continuity must render through the shared decorative ghost")
        contains(root, "ToolMotion.animation(ToolMotion.Preset.settle, reduceMotion: reduceMotion), value: arrived)", "v3: the palette icon ghost must animate through the shared settle spring with Reduce Motion gating")
        contains(root, "if !reduceMotion,\n           let tool = registry.tool(for: toolID)", "v3: palette launches must skip the continuity flight under Reduce Motion")
        doesNotContain(root, ".animation(ToolMotion.animation(ToolMotion.Preset.modal, reduceMotion: reduceMotion), value: viewModel.showsCommandPalette)", "Command palette modal animation must not apply to the whole root tree")
        doesNotContain(root, ".easeOut(duration: 0.18)", "Root shell must not keep hard-coded shell animation durations")
        doesNotContain(commandPalette, "Color.black.opacity(0.30)", "Command palette panel view must not own the full-window scrim")

        let dashboard = try readSource("Sources/XTools/AppShell/DashboardView.swift")
        doesNotContain(host, "@Environment(\\.accessibilityReduceMotion) private var reduceMotion", "Tool detail host must not carry Reduce Motion directly; the shared page-arrival modifier owns the gate")
        doesNotContain(host, "ToolMotion.Transition.pageContent", "Tool detail host must not animate selected tool page replacement")
        doesNotContain(host, "ToolMotion.Preset.pageContent", "Tool detail host must not animate selectedToolID page replacement")
        contains(motion, "static let pageArrival = Curve.smoothOut(duration: Duration.arrival)", "Existing tool pages must retain the shared arrival preset")
        contains(host, ".toolPageArrival(id: tool.id.rawValue)", "Only real tool pages may keep the host-owned arrival modifier")
        doesNotContain(dashboard, ".toolPageArrival(", "V3 dashboard must not replay a page-arrival animation")
        contains(root, ".toolAnimation(ToolMotion.Preset.pageArrival, value: viewModel.selectedToolID)", "Root must preserve existing tool-page arrival behavior")
        let emptyState = try readSource("Sources/XTools/Shared/Components/IndexEmptyState.swift")
        contains(emptyState, ".toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)", "Empty-state host swaps must use a shared lightweight transition")
        contains(emptyState, ".toolMotionIconSwap(id: systemImage)", "Empty-state glyph changes must use the fixed-slot icon swap helper")
        contains(emptyState, ".toolMotionTextSwap(id: title)", "Empty-state title changes must use the shared text swap helper")
        contains(emptyState, "ToolTheme.panelBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control", "Empty-state glyph must sit on the shared panel-background plate")
        doesNotContain(emptyState, ".shadow(", "Empty-state must not add local elevation outside the shared panel chrome")
        let converter = try readSource("Sources/XTools/ToolPages/Workbench/Converter/IndexConverterPage.swift")
        contains(converter, "IndexSegmentedControl(items: modes.map", "Shared converter mode chrome must stay on IndexSegmentedControl")
        doesNotContain(converter, ".toolAnimation(ToolMotion.Preset.panelReveal, value: workspace.mode)", "Converter mode changes must not animate workbench panel geometry")
        doesNotContain(converter, ".toolAnimation(ToolMotion.Preset.orderedContent, value: workspace.mode)", "Converter mode changes must not animate the fixed text-conversion pair layout")
        let toolPageIdentityCount = host.components(separatedBy: ".id(tool.id)").count - 1
        #expect(toolPageIdentityCount == 1, "Tool detail host must reserve .id(tool.id) for the page appeared marker, not wrap selected content in an identity transition")
        contains(host, ".id(tool.id)\n                            .onAppear { ToolPageEntryTrace.pageAppeared(traceContext) }", "Tool detail host must keep the identity-bound page appeared marker without adding page content motion")

        contains(sidebarRenderer, "ToolMotion.AppKitPreset.accordion", "Sidebar disclosure motion must use the shared accordion preset")
        contains(root, "enum SidebarVisibility: Equatable", "Sidebar visibility must be an explicit AppShell state")
        contains(root, "withToolAnimation(ToolMotion.Preset.shellResize, reduceMotion: reduceMotion)", "Sidebar visibility changes must have one explicit motion owner")
        doesNotContain(root, ".animation(ToolMotion.animation(ToolMotion.Preset.shellResize", "Root must not add a second implicit shell animation")
        doesNotContain(sidebar, "collapsedToolList", "Sidebar must not regress to the 46-tool collapsed rail")
        doesNotContain(sidebar, "Animation.easeOut(duration: 0.18)", "Sidebar resize motion must not keep a local hard-coded duration")
        doesNotContain(sidebar, "Animation.easeInOut(duration: 0.16)", "Sidebar disclosure motion must not keep a local hard-coded duration")
        contains(disclosureBody, "struct ToolDisclosureBody", "Disclosure body motion must live in one shared component")
        contains(disclosureBody, "_keepsContentMounted = State(initialValue: isExpanded)", "Initially expanded disclosure bodies must stay mounted before the first collapse")
        contains(disclosureBody, ".onChange(of: isExpanded) { expanded in", "Expanded disclosure bodies must synchronously keep content mounted for rapid toggle cycles")
        contains(disclosureBody, ".fixedSize(horizontal: false, vertical: true)", "Disclosure content must keep natural layout while the outer track clips")
        contains(disclosureBody, "@State private var visibleHeight: CGFloat = 0", "Disclosure body must own an explicit animating height to avoid implicit measurement jumps")
        contains(disclosureBody, ".frame(height: visibleHeight, alignment: .top)", "Disclosure body must animate the clipped track height")
        contains(disclosureBody, "setVisibleHeight(0, animated: true)", "Disclosure collapse must explicitly animate height to zero")
        contains(disclosureBody, "withToolAnimation(animation, reduceMotion: reduceMotion)", "Disclosure height changes must route through ToolMotion")
        doesNotContain(disclosureBody, ".animation(resolvedAnimation, value: isExpanded)", "Disclosure body must not rely on implicit isExpanded animation for layout height")
        doesNotContain(disclosureBody, ".animation(resolvedAnimation, value: measuredContentHeight)", "Disclosure body must not animate measurement updates implicitly")
        doesNotContain(disclosureBody, ".opacity(isExpanded ? 1 : 0)", "Disclosure collapse must not fade the whole list before the clipped height finishes")
        doesNotContain(disclosureBody, ".offset(", "Disclosure collapse must not make rows fly away from the header")
        contains(disclosureBody, ".allowsHitTesting(isExpanded)", "Collapsed disclosure bodies must not receive pointer events")
        contains(disclosureBody, ".accessibilityHidden(!isExpanded)", "Collapsed disclosure bodies must be hidden from accessibility")
        contains(disclosureBody, "keepsContentMounted = false", "Collapsed disclosure bodies should unmount after the collapse animation")

        contains(motion, "static let resultPresenceAppearance = Curve.smoothOut(duration: ResultPresence.appearanceDuration)", "Short-result appearance must keep its shared decelerating ToolMotion timing")
        contains(motion, "static let resultPresenceExit = Curve.productiveExit(duration: ResultPresence.exitDuration)", "Short-result exit must use a distinct accelerating ToolMotion timing")
        contains(motion, "static let productiveExitControlPoints = (", "Result removal must use one shared accelerating curve owner")
        contains(motion, "static let exitDuration = Duration.fast", "Result removal must finish faster than appearance")
        contains(resultPresenceState, "struct ResultPresenceState<Value>", "Result presence lifecycle must be testable outside SwiftUI in Core")
        contains(resultPresenceState, "case empty, appearing, presented, exiting", "Result presence must distinguish business presence from visual lifetime")
        contains(resultPresenceState, "enum ResultPresenceMotionPolicy: Equatable, Sendable", "Bounded result presence must expose an explicit caller-owned motion policy")
        contains(resultPresenceShim, "typealias IndexResultPresenceState = ResultPresenceState", "Mac must keep Index* aliases over Core result presence state")
        contains(resultPresenceShim, "ToolMotion.ResultPresence.appearanceDuration", "Mac must own action-specific presence durations via ToolMotion")
        contains(resultPresence, "applyTarget(value, reduceMotion: reduceMotion || motion == .immediate)", "Immediate callers must settle through the same tested no-motion state transition as Reduce Motion")
        contains(resultPresence, ".frame(height: visibleHeight, alignment: .top)", "Result presence must animate one explicit clipped height track")
        contains(resultPresence, ".clipped()", "Result presence must reveal and remove natural-height content by clipping")
        contains(resultPresence, "resultOpacity = 0", "Accelerating result removal must finish visually clear before empty takeover")
        contains(resultPresence, "ToolMotion.Preset.resultPresenceAppearance", "Result appearance must use the shared appearance timing")
        contains(resultPresence, "ToolMotion.Preset.resultPresenceExit", "Result exit must use the shared exit timing")
        contains(resultPresence, "request.duration", "Presence finalization must wait for the matching action-specific duration")
        doesNotContain(resultPresence, ".mask(alignment: .top)", "Result removal must not reintroduce the disproven moving-edge mask")
        contains(resultPresence, ".allowsHitTesting(presentation.phase != .exiting)", "Outgoing result snapshots must leave the operable tree immediately")
        contains(resultPresence, ".accessibilityHidden(presentation.phase == .exiting)", "Outgoing result snapshots must leave the accessibility tree immediately")
        contains(resultPresence, ".task(id: updateID)", "Presence target updates must read the current projection instead of an old onChange capture")
        contains(resultPresence, ".task(id: completionRequest)", "Presence completion must be cancellable when the target reverses")
        doesNotContain(resultPresence, "removal: .opacity", "Result collapse must not add an independent transition removal beside the coordinated exit transaction")

        contains(toast, ".toolTransition(ToolMotion.Transition.toastPanel, reduceMotion: reduceMotion)", "Toast cards must use the shared panel reveal transition")
        contains(toast, "ToolMotion.Preset.panelReveal", "Toast queue changes must use the shared panel reveal preset")
        doesNotContain(toast, "withAnimation(.easeOut(duration: 0.18)", "Toast state changes must not keep a local hard-coded animation")

        contains(shared, ".toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)", "Workspace diagnostics may reveal, but only through the shared safe diagnostic transition")
        contains(shared, ".toolAnimation(ToolMotion.Preset.diagnostic, value: text)", "Workspace diagnostic regions must animate through ToolMotion")
        contains(shared, ".toolErrorShake(trigger: errorShakeTrigger)", "v3: error-tone diagnostic arrivals must shake the status slot through the shared bounded shake")
        doesNotContain(shared, ".easeInOut(duration: 0.15)", "Workspace diagnostics must not keep hard-coded diagnostic animation durations")

        doesNotContain(workbench, ".animation(", "The fixed text conversion workbench must not add structural implicit animation")
        doesNotContain(workbench, "withAnimation(", "The fixed text conversion workbench must not retain a focus-mode animation path")
        doesNotContain(commandPalette, "withAnimation(.easeInOut(duration: 0.12))", "Command palette row reveal must remain unanimated")
        doesNotContain(commandPalette, "GeometryReader", "Command palette row reveal must not add continuous geometry measurement")
        doesNotContain(commandPalette, "Timer.", "Command palette row reveal must remain event-driven")
    }

    @Test func generateParseModeTransitionStaysSubtleAndShared() throws {
        let motion = try readSource("Sources/XTools/Shared/ToolMotion.swift")
        let mode = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexGenerateParseMode.swift")
        let jwt = try readSource("Sources/XTools/ToolPages/Web/JWTParserPage.swift")
        let basic = try readSource("Sources/XTools/ToolPages/Web/BasicAuthGeneratorPage.swift")

        contains(motion, "static func orderedContent(_ direction: OrderedDirection) -> AnyTransition", "Generate/parse content must use the shared ordered-direction transition token")
        let transition = sourceSlice(motion, from: "static func orderedContent(_ direction: OrderedDirection) -> AnyTransition", to: "static var systemReduceMotionEnabled")
        contains(transition, ".opacity.combined(with: .offset(x: direction.insertionOffsetX))", "Ordered mode content may move only by the shared directional distance")
        contains(transition, "removal: .opacity", "Outgoing mode content must only fade out")
        doesNotContain(transition, ".scale", "Mode content must not use a noticeable scale effect")
        doesNotContain(transition, "bounce", "Mode content must not bounce")

        contains(mode, "modeBranch(generateContent, direction: .backward)", "Generate branch must enter from the leading edge in mode order")
        contains(mode, "modeBranch(parseContent, direction: .forward)", "Parse branch must enter from the trailing edge in mode order")
        contains(mode, ".toolTransition(ToolMotion.Transition.orderedContent(direction), reduceMotion: reduceMotion)", "Mode content must disable its directional transition for Reduce Motion")
        contains(mode, "ToolMotion.animation(ToolMotion.Preset.orderedContent, reduceMotion: reduceMotion)", "Mode content must disable animation for Reduce Motion")
        contains(jwt, "IndexGenerateParseModeContent(mode: modeBinding.wrappedValue)", "JWT must reuse shared generate/parse motion")

        contains(basic, "IndexGenerateParseModeContent(mode: modeBinding.wrappedValue)", "Basic Auth must reuse shared generate/parse motion")
    }

    @Test func sharedActionStateMotionIsCentralizedAndCrontabRowsStayUnanimated() throws {
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")
        let html = try readSource("Sources/XTools/ToolPages/Development/HTMLToMarkdownPage.swift")
        let base64File = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        let crontab = try readSource("Sources/XTools/ToolPages/Development/CrontabGeneratorPage.swift")

        contains(controls, "struct IndexMotionLabel<ID: Hashable>: View", "Short action-state labels must live in a shared component")
        contains(controls, "Text(title)\n                .toolMotionTextSwap(id: id)", "Shared action-state labels must animate only the short text identity")
        contains(controls, "Image(systemName: systemImage)\n                .toolMotionIconSwap(id: id)", "Shared action-state labels must animate only the short icon identity")
        contains(controls, "struct IndexMotionIcon<ID: Hashable>: View", "Compact icon-only action states must share the same motion component")
        contains(controls, "struct IndexProgressMotionLabel<ID: Hashable>: View", "Indeterminate action-state labels must live in a shared component")
        contains(controls, "if isProcessing {\n                    ProgressView()", "The shared processing label must use a native indeterminate spinner")

        contains(html, "IndexProgressMotionLabel(\n                title: session.isURLProcessing ? \"正在解析…\" : \"获取\"", "HTML URL fetch action must use the shared indeterminate action-state label")
        doesNotContain(html, "if session.isURLProcessing {\n                            ProgressView()", "HTML URL fetch action must not hand-roll its spinner branch")

        occurrenceCount(base64File, "Base64FileActivityLabel(", 6, "Base64 file async actions must use one fixed icon-slot activity label")
        contains(base64File, "private struct Base64FileActivityLabel: View", "Base64 file activity feedback must live in one page-private fixed-slot component")
        contains(base64File, "IndexProgressMotionLabel(", "Base64 file activity feedback must reuse the shared icon-slot progress label")
        occurrenceCount(base64File, "IndexMotionLabel(", 0, "Base64 decoded-save action must not keep a duplicate text-labelled branch")
        occurrenceCount(base64File, "IndexMotionIcon(", 0, "Base64 decoded-save action must use the same fixed progress slot as other file actions")
        doesNotContain(base64File, "label: {\n            Label(session.outputAction ==", "Base64 file output actions must not hand-roll conditional labels")
        doesNotContain(base64File, "Image(systemName: session.outputAction ==", "Base64 file compact output actions must not hand-roll conditional icons")
        doesNotContain(base64File, "Label(session.isDecoding", "Base64 file decode action must not hand-roll its conditional label")
        doesNotContain(base64File, "Image(systemName: session.isDecoding", "Base64 file compact decode action must not hand-roll its conditional icon")
        doesNotContain(base64File, "title: session.isSavingDecoded ?", "Base64 file decoded-save action must not hand-roll a conditional text label")
        doesNotContain(base64File, "Image(systemName: session.isSavingDecoded", "Base64 file compact decoded-save action must not hand-roll its conditional icon")

        let encodedOutputHeader = sourceSlice(
            base64File,
            from: "private var copyFullOutputButton: some View",
            to: "private var decodeInputHeaderActions: some View"
        )
        doesNotContain(encodedOutputHeader, "ViewThatFits", "Base64 encoded-output actions must not switch responsive branches while operation state changes")
        doesNotContain(encodedOutputHeader, "IndexOptionLabel(\"格式\")", "The Base64/Data URL segmented control must not repeat a redundant format label")
        occurrenceCount(encodedOutputHeader, ".buttonStyle(IndexIconActionButtonStyle())", 3, "Encoded output must keep preview, copy, and save as fixed-size toolbar actions")
        contains(encodedOutputHeader, ".help(\"在解码结果中预览\")", "Encoded-output preview icon must remain discoverable")
        contains(encodedOutputHeader, ".help(\"复制完整输出\")", "Encoded-output copy icon must remain discoverable")
        contains(encodedOutputHeader, ".help(\"保存完整输出\")", "Encoded-output save icon must remain discoverable")

        let decodeInputHeader = sourceSlice(
            base64File,
            from: "private var decodeInputHeaderActions: some View",
            to: "private var decodedFileNameEditor: some View"
        )
        contains(decodeInputHeader, "isProcessing: session.decodeActivity == .manualInput", "Manual decode progress must stay on the decode action")
        contains(decodeInputHeader, "isProcessing: session.decodeActivity == .encodedTextImport", "Encoded-text import progress must stay on the import action")
        doesNotContain(decodeInputHeader, "title: session.isDecoding", "Decode activity must not change button text width")
        doesNotContain(decodeInputHeader, "compactControl:", "Decode toolbar activity must not trigger responsive branch replacement")

        contains(crontab, "@Environment(\\.accessibilityReduceMotion) private var reduceMotion", "Crontab next-runs reveal must honor Reduce Motion")
        contains(crontab, "private var nextRunsSection: some View", "Crontab next-runs reveal must be scoped to the optional panel section")
        contains(crontab, "IndexPanel(\"下次运行时间\")", "Crontab must keep the next-runs result as one panel")
        contains(crontab, ".toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)", "Crontab next-runs panel reveal must use the shared diagnostic transition")
        contains(crontab, ".toolAnimation(ToolMotion.Preset.panelReveal, value: !workspace.nextRuns.isEmpty)", "Crontab next-runs animation must key off panel presence, not row changes")
        let nextRunsRows = sourceSlice(crontab, from: "ForEach(workspace.nextRuns, id: \\.self)", to: "                }\n                .toolTransition")
        doesNotContain(nextRunsRows, ".toolTransition", "Crontab must not animate individual next-run rows")
        doesNotContain(nextRunsRows, ".toolAnimation", "Crontab must not animate individual next-run rows")
    }

    @Test func copyAndSaveFeedbackUseGenerationSafeSharedLifecycle() throws {
        let feedbackState = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexEphemeralActionFeedback.swift")
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")

        contains(feedbackState, "struct IndexEphemeralActionFeedbackState: Equatable", "Ephemeral copy/save feedback must use one testable value-state contract")
        contains(feedbackState, "generation &+= 1", "Every successful retrigger must invalidate older reset completions")
        contains(feedbackState, "guard isPresented, generation == self.generation", "Only the latest presented generation may clear feedback")
        contains(feedbackState, "static let holdDuration: Duration = .milliseconds(1_200)", "The existing 1.2-second hold must remain a feedback-lifecycle token, not a ToolMotion duration")

        contains(controls, "@State private var feedback = IndexEphemeralActionFeedbackState()", "Copy feedback must use the shared lifecycle state")
        contains(controls, "feedback.trigger()", "Successful copy must retrigger the shared lifecycle")
        contains(controls, ".task(id: feedback.generation)", "Copy reset waits must be structurally cancelled on retrigger and view removal")
        contains(controls, "try await Task.sleep(for: IndexEphemeralActionFeedbackState.holdDuration)", "Copy feedback must preserve the shared 1.2-second hold window")
        contains(controls, "feedback.finish(generation: generation)", "Copy reset completion must pass through the shared stale-generation gate")
        doesNotContain(controls, "try? await Task.sleep(for: .seconds(1.2))", "Copy feedback must not retain an unprotected local reset task")

        contains(workbench, "@State private var feedback = IndexEphemeralActionFeedbackState()", "Save feedback must use the shared lifecycle state")
        contains(workbench, "feedback.trigger()", "Successful save must retrigger the shared lifecycle")
        contains(workbench, ".task(id: feedback.generation)", "Save reset waits must be structurally cancelled on retrigger and view removal")
        contains(workbench, "try await Task.sleep(for: IndexEphemeralActionFeedbackState.holdDuration)", "Save feedback must preserve the shared 1.2-second hold window")
        contains(workbench, "feedback.finish(generation: generation)", "Save reset completion must pass through the shared stale-generation gate")
        doesNotContain(workbench, "try? await Task.sleep(for: .seconds(1.2))", "Save feedback must not retain an unprotected local reset task")

        contains(controls, ".toolMotionSuccessSwap(id: copied)", "Copy feedback must preserve the existing icon transition with the delight spring")
        contains(controls, ".toolMotionTextSwap(id: copied)", "Copy feedback must preserve the existing text transition")
        contains(workbench, ".toolMotionSuccessSwap(id: saved)", "Save feedback must preserve the existing icon transition with the delight spring")
        contains(workbench, ".toolMotionTextSwap(id: saved)", "Save feedback must preserve the existing text transition")
    }

    @Test func highFrequencyDerivedValuesUseImmediateMotionPolicy() throws {
        let caseConverter = try readSource("Sources/XTools/ToolPages/Converter/CaseConverterPage.swift")
        let regex = try readSource("Sources/XTools/ToolPages/Development/RegexTesterPage.swift")
        let regexComponents = try readSource("Sources/XTools/ToolPages/Development/RegexTesterComponents.swift")
        let color = try readSource("Sources/XTools/ToolPages/Image/ColorPickerPage.swift")
        let textStats = try readSource("Sources/XTools/ToolPages/Utility/TextStatisticsPage.swift")
        let keycode = try readSource("Sources/XTools/ToolPages/Web/KeycodeInfoPage.swift")
        let userAgent = try readSource("Sources/XTools/ToolPages/Web/UserAgentParserPage.swift")
        let math = try readSource("Sources/XTools/ToolPages/Utility/MathEvaluatorPage.swift")
        let fileType = try readSource("Sources/XTools/ToolPages/Utility/FileTypeDetectorPage.swift")
        let dropZone = try readSource("Sources/XTools/Shared/Components/IndexDropZone.swift")
        let dateCalculator = try readSource("Sources/XTools/ToolPages/Time/DateCalculatorPage.swift")

        contains(caseConverter, "valueMotion: .immediate", "Case conversion rows update on every edit and must not crossfade")
        contains(regex, "RegexMatchList(matches: report.matches, valueMotion: .immediate)", "Regex match rows must update immediately")
        contains(regexComponents, "var valueMotion: IndexValueMotionPolicy = .immediate", "Regex grouped match values must default to immediate updates")
        let regexSummary = sourceSlice(
            regexComponents,
            from: "struct RegexResultSummary: View",
            to: "struct RegexMatchList: View"
        )
        doesNotContain(regexSummary, ".toolMotionTextSwap", "Regex statistics must not crossfade on every input update")
        doesNotContain(regexSummary, ".toolAnimation", "Regex statistics must not animate on every input update")
        contains(color, "valueMotion: .immediate", "Color values must not animate while sliders move")
        contains(textStats, "valueMotion: .immediate", "Text statistics must not animate on every edit")
        contains(keycode, "valueMotion: .immediate", "Keycode rows must not animate on every keyDown")
        occurrenceCount(userAgent, "valueMotion: .immediate", 5, "User-Agent result rows must not animate on every edit")
        doesNotContain(math, ".toolMotionTextSwap(id: resultText)", "Math valid-to-valid results must update immediately")
        occurrenceCount(fileType, "valueMotion: .immediate", 7, "File type detection must keep one result container without row-level value swaps")
        contains(fileType, ".indexDropZone(", "File type drop targeting must route through the shared drop-zone owner")
        doesNotContain(fileType, ".toolAnimation(ToolMotion.Preset.controlFeedback, value: isFileDropTargeted)", "File type drop targeting motion must stay owned by the shared drop zone, not a page-local animation")
        contains(dropZone, "withToolAnimation(ToolMotion.Preset.controlFeedback) {\n                    isTargeted = targeted\n                }", "Shared drop-zone targeting must mutate through the control-feedback motion owner")
        occurrenceCount(dateCalculator, "valueMotion: .immediate", 2, "Date secondary values must stay static while the hero remains the only emphasis")

        contains(keycode, "override var acceptsFirstResponder: Bool { true }", "Motion cleanup must preserve key capture first-responder capability")
        contains(keycode, "window.makeFirstResponder(self)", "Keyboard Event must preserve automatic key capture focus without animating page entry")
        contains(keycode, "override func mouseDown(with event: NSEvent)", "Motion cleanup must preserve click-to-refocus behavior")
    }

    @Test func boundedKVCallersShareOnePresenceOwner() throws {
        let integerBase = try readSource("Sources/XTools/ToolPages/Converter/IntegerBaseConverterPage.swift")
        let dateTime = try readSource("Sources/XTools/ToolPages/Time/DateTimeConverterPage.swift")
        let color = try readSource("Sources/XTools/ToolPages/Image/ColorPickerPage.swift")
        let keycode = try readSource("Sources/XTools/ToolPages/Web/KeycodeInfoPage.swift")
        let crontab = try readSource("Sources/XTools/ToolPages/Development/CrontabGeneratorPage.swift")

        contains(integerBase, "IndexShortResultKV(rows: rows, emptyText: IndexEmptyStateCopy.autoCalculate(\"数值\"), valueMotion: .immediate)", "Integer-base results must use shared bounded presence without animating every valid edit")
        contains(dateTime, "IndexShortResultKV(rows: workspace.rows, emptyText: IndexEmptyStateCopy.autoCalculate(\"时间戳或时间\"), valueMotion: .immediate)", "Timestamp results must share presence while keeping live values immediate")
        contains(color, "resultRows(commonValues, emptyText: IndexEmptyStateCopy.autoShow(\"有效 CSS 颜色\"))", "Color results must use one bounded result surface with immediate leaf values")
        contains(keycode, "IndexResultPresence(\n                value: workspace.snapshot", "Keycode must animate only the empty-to-first-snapshot boundary")
        contains(keycode, "IndexKVRow(", "Keycode must keep row-level values inside the stable result surface")
        contains(keycode, "valueMotion: .immediate", "Keycode row values must remain immediate after the surface is present")
        contains(crontab, "IndexShortResultKV(rows: rows, emptyText: explanationEmptyText, copyable: false, valueMotion: .immediate)", "Crontab explanations must use shared bounded presence")
    }

    @Test func userAgentUsesSharedResultPresence() throws {
        let userAgent = try readSource("Sources/XTools/ToolPages/Web/UserAgentParserPage.swift")

        contains(userAgent, "IndexResultPresence(\n                            value: resultProjection,\n                            updateID: resultPresenceUpdateID", "UserAgent optional results must retain a presentation snapshot")
        contains(userAgent, "IndexKVRow(key: \"浏览器\", value: result.browser, valueLineBreakMode: .byCharWrapping, valueMotion: .immediate)", "UserAgent live valid updates must stay immediate inside presence")
    }

    @Test func basicAuthUsesSensitiveSharedResultPresence() throws {
        let basicAuth = try readSource("Sources/XTools/ToolPages/Web/BasicAuthGeneratorPage.swift")

        contains(basicAuth, "IndexResultPresence(\n                    value: session.parsedCredentials,\n                    updateID: parsedCredentialsPresenceUpdateID", "Basic Auth parsed credentials must use shared presence")
        appearsBefore(basicAuth, "showsParsedPassword = false", "session.parse()", "Basic Auth must restore the password mask before parsing can clear the result")
        let basicClear = sourceSlice(basicAuth, from: "private func clearAll()", to: "private func transferGeneratedToParse()")
        appearsBefore(basicClear, "showsParsedPassword = false", "session.clearAll()", "Basic Auth clear must restore the password mask before the outgoing snapshot exits")
    }

    @Test func jwtVerificationUsesSharedResultPresence() throws {
        let jwt = try readSource("Sources/XTools/ToolPages/Web/JWTParserPage.swift")

        contains(jwt, "IndexResultPresence(\n                value: session.localCheckPresentation,\n                updateID: localCheckPresenceUpdateID", "JWT local-check details must use shared presence")
        contains(jwt, "ForEach(Array(presentation.details.enumerated()), id: \\.offset)", "JWT must preserve its bounded local-check detail order")
    }

    @Test func fileTypeReplacesItsOldResultRevealOwner() throws {
        let fileType = try readSource("Sources/XTools/ToolPages/Utility/FileTypeDetectorPage.swift")

        let resultPanel = sourceSlice(fileType, from: "IndexPanel(\"检测结果\")", to: "    }\n}")
        contains(resultPanel, "IndexResultPresence(", "File type detection must replace its old reveal with shared bounded presence")
        contains(resultPanel, "value: session.report", "File type presence must follow the report boundary rather than progress state")
        contains(resultPanel, "updateID: reportPresenceUpdateID", "File type presence must update an already-present report without restarting presence")
        contains(resultPanel, "motion: .immediate", "File type results must settle immediately instead of clipping seven rows through a height reveal")
        doesNotContain(fileType, ".toolAnimation(ToolMotion.Preset.panelReveal, value: session.report != nil)", "File type results must not stack the old panel reveal on shared presence")
        doesNotContain(fileType, ".toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)", "File type result rows must not keep a second transition owner")
    }

    @Test func resultPresenceRolloutKeepsProtectedMotionOwners() throws {
        let regex = try readSource("Sources/XTools/ToolPages/Development/RegexTesterPage.swift")
        let deviceInfo = try readSource("Sources/XTools/ToolPages/Utility/DeviceInformationPage.swift")
        let chronometer = try readSource("Sources/XTools/ToolPages/Time/ChronometerPage.swift")
        let password = try readSource("Sources/XTools/ToolPages/Crypto/PasswordGeneratorPage.swift")
        let token = try readSource("Sources/XTools/ToolPages/Crypto/TokenGeneratorPage.swift")
        let uuid = try readSource("Sources/XTools/ToolPages/Crypto/UUIDGeneratorPage.swift")
        let crontab = try readSource("Sources/XTools/ToolPages/Development/CrontabGeneratorPage.swift")
        let imageStage = try readSource("Sources/XTools/ToolPages/Image/ImagePreviewStage.swift")
        let favicon = try readSource("Sources/XTools/ToolPages/Image/FaviconGeneratorPage.swift")

        doesNotContain(regex, "IndexResultPresence(", "Unbounded Regex rows must remain outside bounded presence")
        contains(regex, "private enum RegexResultMotionIntent: Equatable", "Regex result motion must be gated by an explicit preset or clear action")
        contains(regex, "case preset(RegexWorkspaceInput)", "Regex preset results may opt into one whole-block appearance")
        contains(regex, "case clear", "Regex clear may opt into one whole-block exit")
        contains(regex, "case immediate", "Regex typing must retain an explicit immediate path")
        contains(regex, "RegexMatchList(matches: report.matches, valueMotion: .immediate)", "Regex match rows must remain immediate inside any explicit whole-block transition")
        doesNotContain(regex, ".toolAnimation(ToolMotion.Preset.panelReveal, value: report", "Regex reports must not gain an unconditional animation on every publish")
        doesNotContain(deviceInfo, "IndexResultPresence(", "Query-list snapshots must remain outside bounded presence")
        doesNotContain(chronometer, "IndexResultPresence(", "Chronometer laps and timer values must remain outside bounded presence")
        contains(password, "IndexGeneratedValueRowList", "Password must keep generated-list item motion through the prototype row list")
        doesNotContain(password, "IndexResultPresence(", "Password initial generation must not gain a structural appear lifecycle")
        contains(token, "IndexGeneratedValueRowList", "Token must keep generated-list item motion through the prototype row list")
        doesNotContain(token, "IndexResultPresence(", "Token initial generation must not gain a structural appear lifecycle")
        // UUID uses the prototype v3 row list: generation-scoped pop-in replay
        // replaces the card list's text-swap value motion.
        contains(uuid, "IndexGeneratedValueRowList", "UUID must keep generated-list motion through the prototype row list")
        doesNotContain(uuid, "IndexResultPresence(", "UUID initial generation must not gain a structural appear lifecycle")
        contains(crontab, ".toolAnimation(ToolMotion.Preset.panelReveal, value: !workspace.nextRuns.isEmpty)", "Crontab next-runs must keep its existing panel-level owner")
        doesNotContain(imageStage, "IndexResultPresence(", "Image replacement must keep the preview-stage owner")
        doesNotContain(favicon, "IndexResultPresence(", "Favicon batch generation must keep its bounded batch owner")
    }

    @Test func appShellChromeUsesStableSlotMicroInteractions() throws {
        let titlebar = try readSource("Sources/XTools/AppShell/TitlebarView.swift")
        let buttonStyles = try readSource("Sources/XTools/AppShell/TitlebarButtonStyles.swift")
        let sidebar = try readSource("Sources/XTools/AppShell/SidebarView.swift")
        let palette = try readSource("Sources/XTools/AppShell/CommandPalette.swift")
        let detailHost = try readSource("Sources/XTools/AppShell/ToolDetailHostView.swift")

        // Surface 1: toolbar no longer carries a tool breadcrumb; identity lives in sidebar/IndexPage.
        doesNotContain(titlebar, "WindowToolbarToolContext", "Toolbar must not render a tool breadcrumb context view")
        doesNotContain(titlebar, ".toolMotionIconSwap(id: selectedTool.systemImage)", "Toolbar must not crossfade a selected-tool identity icon")
        doesNotContain(titlebar, ".toolMotionTextSwap(id: categoryTitle)", "Toolbar must not crossfade a category breadcrumb label")
        doesNotContain(titlebar, ".toolMotionTextSwap(id: selectedTool.title)", "Toolbar must not crossfade a tool-title breadcrumb label")
        contains(titlebar, ".toolMotionIconSwap(id: isSidebarVisible)", "Sidebar toggle must keep its fixed-slot visibility icon swap")
        contains(titlebar, ".toolMotionIconSwap(id: isFavorite)", "Toolbar favorite star must keep its fixed-slot icon swap")

        // Surface 2: chrome button feedback flows through the shared control-feedback preset.
        occurrenceCount(buttonStyles, ".toolAnimation(ToolMotion.Preset.controlFeedback,", 3, "Chrome button styles must animate hover/press through the shared control-feedback preset")
        doesNotContain(buttonStyles, ".scaleEffect", "Chrome button feedback must not scale the hit target")

        // Surface 3: sidebar search focus ring animates color/width only, not the AppKit field.
        contains(sidebar, ".toolAnimation(ToolMotion.Preset.controlFeedback, value: isSearchFocused)", "Sidebar search focus ring must animate through the shared control-feedback preset")

        // Surface 4: both clear buttons keep a fixed slot while unavailable controls leave the accessibility tree.
        contains(sidebar, "if !searchText.isEmpty {", "Sidebar search clear must be conditionally presented inside its fixed slot")
        contains(sidebar, ".allowsHitTesting(!searchText.isEmpty)", "Sidebar search clear must disable hit testing when hidden")
        contains(palette, "if !query.isEmpty {", "Command palette clear must be conditionally presented inside its fixed slot")
        contains(palette, ".allowsHitTesting(!query.isEmpty)", "Command palette clear must disable hit testing when hidden")
        doesNotContain(palette, ".accessibilityHidden(query.isEmpty)", "Command palette clear must not rely on an ineffective hidden accessibility wrapper")

        // Surface 5: favorite star keeps a fixed trailing slot, revealing via opacity on hover/favorite.
        contains(sidebar, ".opacity(isFavorite || hoverState.isHovered ? 1 : 0)", "Sidebar favorite star must occupy a fixed trailing slot and reveal via opacity")
        contains(sidebar, ".allowsHitTesting(isFavorite || hoverState.isHovered)", "Sidebar favorite star must disable hit testing when hidden")
        contains(sidebar, ".toolMotionIconSwap(id: isFavorite)", "Sidebar favorite star must keep its shared icon swap")

        // Forbidden zone: tool page replacement animates only through the
        // whitelisted host-owned `.toolPageArrival` modifier; no raw
        // transition wiring is allowed in the host.
        doesNotContain(detailHost, ".transition(", "Tool detail host must not animate tool page replacement outside the pageArrival whitelist")
        doesNotContain(detailHost, ".toolTransition(", "Tool detail host must not animate tool page replacement outside the pageArrival whitelist")
    }

    @Test func base64FileMotionAvoidsTransientProcessingContent() throws {
        let base64File = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")

        contains(base64File, "private var filePickerStatusIcon: some View", "Base64 file reading feedback must stay inside one fixed icon slot")
        doesNotContain(base64File, "Text(\"正在读取文件...\")", "Base64 file reading must not replace the stable picker text with a one-row transient state")
        doesNotContain(base64File, "正在生成输出预览", "Base64 output mode changes must retain the ready preview instead of flashing a processing surface")
        doesNotContain(base64File, "IndexResultPresence(", "Large Base64 output must update in place instead of crossfading its content")
    }

    @Test func toolMotionCoversResultImageAndSafePagePolishWithoutHotPathAnimation() throws {
        let shared = try readSharedBagComponents()
        let imageStage = try readSource("Sources/XTools/ToolPages/Image/ImagePreviewStage.swift")
        let base64File = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        let favicon = try readSource("Sources/XTools/ToolPages/Image/FaviconGeneratorPage.swift")
        let chronometer = try readSource("Sources/XTools/ToolPages/Time/ChronometerPage.swift")
        let timezone = try readSource("Sources/XTools/ToolPages/Time/TimezoneViewerPage.swift")
        let generatedPresence = sourceSlice(
            shared,
            from: "private struct IndexGeneratedResultCardListPresence: View",
            to: "private struct IndexResultCardStack: View"
        )

        contains(shared, "enum IndexValueMotionPolicy", "Shared value surfaces must expose an explicit motion policy")
        contains(shared, "case textSwap", "Low-frequency short values must be able to opt into text swap motion")
        contains(shared, "case immediate", "High-frequency values must be able to update without identity animation")
        contains(shared, "func indexValueMotion<ID: Hashable>(", "Value motion policy must be applied at the leaf view rather than the owning container")
        contains(shared, "case .immediate:\n            self", "Immediate value updates must leave the leaf view unanimated")
        occurrenceCount(shared, "var valueMotion: IndexValueMotionPolicy = .textSwap", 4, "KV wrappers, result rows, and stat grids must expose the shared value-motion policy")
        contains(shared, "IndexResultPresence(", "Short KV and card results must share one presence owner")
        doesNotContain(shared, ".toolAnimation(ToolMotion.Preset.panelReveal, value: rows.isEmpty)", "Low-level IndexKV must not animate the entire descendant tree on empty/result changes")
        contains(shared, "struct IndexScrollableKVRow: Identifiable", "Scrollable KV must accept stable caller-owned row identities")
        contains(shared, "IndexScrollableResultPresence(", "Scrollable KV must delegate empty/result presentation to the dedicated scrollable owner")
        contains(shared, "ToolMotion.Transition.topRowInsertion", "New chronometer laps must use the shared top-row transition")
        contains(shared, "reduceMotion: reduceMotion", "The top-row transition must honor Reduce Motion")
        contains(shared, ".toolAnimation(ToolMotion.Preset.orderedContent, value: snapshot.map(\\.id))", "Only a stable lap-ID projection may animate a row insertion")
        doesNotContain(shared, ".toolAnimation(ToolMotion.Preset.panelReveal, value: rows.count)", "Ordinary added laps must not restart the whole scrollable result reveal")
        contains(shared, "return items.prefix(8).map(\\.id).joined(separator: \"|\")", "Generated result cards must cap reveal identity to the first eight items")
        contains(shared, ".toolTransition(revealsItems && index < 8 ? ToolMotion.Transition.diagnostic : .identity, reduceMotion: reduceMotion)", "Generated result cards must not animate every row in large batches")
        contains(shared, "IndexResultCardStack(items: snapshot, revealsItems: false)", "Short result cards must leave structural motion to the shared presence owner")
        contains(shared, "indexGeneratedResultValueMotion(index: index, limit: valueMotionLimit)", "Generated result cards must choose text motion from the bounded slot budget")
        contains(shared, "valueMotionLimit: animatesItemUpdates ? 8 : 0", "Only presented generator updates may animate the first eight values")
        doesNotContain(generatedPresence, "withToolAnimation(ToolMotion.Preset.textSwap", "Generated list updates must not animate the whole batch outside the first-eight leaf budget")
        contains(shared, "firstAppearance: .immediate", "The first delayed automatic generation must settle without a manufactured reveal")
        contains(shared, ".allowsHitTesting(resultInteractionEnabled)", "An outgoing generated-result snapshot must stop accepting copy actions immediately")
        contains(shared, ".accessibilityHidden(!resultInteractionEnabled)", "An outgoing generated-result snapshot must leave the accessibility tree immediately")
        contains(shared, "ToolMotion.Preset.resultPresenceAppearance", "Regeneration after clear must use the shared result appearance timing")
        contains(shared, "ToolMotion.Preset.resultPresenceExit", "Generator clear must use the shorter shared result exit timing")
        contains(shared, ".onChange(of: reduceMotion)", "Generated result presence must settle when Reduce Motion becomes enabled")

        contains(imageStage, "ObjectIdentifier(image).hashValue", "Image preview reveal must key off image replacement rather than pixels or processing loops")
        contains(imageStage, ".toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)", "Image preview stage must use a lightweight shared transition")
        contains(imageStage, "replacementMotion == .animated", "Image preview stage must animate image/placeholder identity only when the caller keeps the default replacement policy")
        contains(imageStage, "ToolMotion.animation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion)", "Animated image replacement must retain the shared Reduce Motion-aware preset")
        contains(imageStage, "case immediate", "Live image workspaces must be able to replace raster content without whole-stage animation")
        contains(imageStage, "transaction.disablesAnimations = true", "Immediate raster replacement must also suppress inherited content crossfades")

        contains(base64File, ".toolAnimation(ToolMotion.Preset.controlFeedback, value: isFileDropTargeted)", "Base64 file drop target must use lightweight shared feedback")
        contains(base64File, "private var filePickerStatusIcon: some View", "Base64 file reading feedback must have one fixed icon-slot owner")
        contains(base64File, "static let fileReadProgressDelay: Duration = .milliseconds(150)", "Base64 file reading progress must use a short display threshold")
        contains(base64File, ".task(id: session.isReadingFile)", "Base64 file reading progress must be cancelled when the busy state changes or the picker leaves the view")
        contains(base64File, "try await Task.sleep(for: Base64FileLayout.fileReadProgressDelay)", "Base64 file reading must suppress feedback for short local tasks")
        contains(base64File, "guard !Task.isCancelled, session.isReadingFile else { return }", "Base64 file reading progress must not publish after completion or cancellation")
        contains(base64File, ".onDisappear {\n            isShowingFileReadProgress = false", "Base64 file reading progress must reset when its picker leaves the view")
        doesNotContain(base64File, ".toolMotionIconSwap(id: filePickerVisualState)", "Base64 file picker status must settle directly without a second icon transition")
        doesNotContain(base64File, ".toolTransition(.opacity, reduceMotion: reduceMotion)", "Base64 file selection feedback must not crossfade the whole picker content")
        doesNotContain(base64File, ".toolAnimation(ToolMotion.Preset.textSwap, value: filePickerVisualState)", "Base64 file selection feedback must not animate text or picker layout")
        doesNotContain(base64File, ".toolAnimation(ToolMotion.Preset.panelReveal, value: filePickerVisualState)", "Base64 file selection feedback must not animate panel or layout geometry")
        contains(base64File, ".toolMotionTextSwap(id: text)", "Base64 processing text may swap state labels")
        contains(favicon, ".toolAnimation(ToolMotion.Preset.panelReveal, value: session.package != nil)", "Favicon package rows are bounded and may reveal as one atomic batch")

        // Async file/image surfaces must express only real busy/result state; no
        // fake loaders, blur over pixels, or per-row stagger.
        for (name, source) in [("ImagePreviewStage", imageStage), ("Base64File", base64File), ("Favicon", favicon)] {
            doesNotContain(source, ".blur(", "\(name) must not blur image pixels or content for a loading effect")
            doesNotContain(source, "shimmer", "\(name) must not use a shimmer placeholder")
            doesNotContain(source, "repeatForever", "\(name) must not run a looping custom spinner or pulse")
            doesNotContain(source, ".rotationEffect(", "\(name) must not spin a hand-rolled progress indicator")
        }

        contains(chronometer, ".animation(minimumInterval: 0.01, paused: !chronometer.isRunning)", "Chronometer must limit high-frequency refreshes to the running state")
        contains(chronometer, ".toolMotionTextSwap(id: primaryActionTitle)", "Chronometer may animate start/pause text")
        contains(chronometer, "valueMotion: .immediate", "Chronometer lap values must not keep outgoing rows alive during Reset")
        doesNotContain(chronometer, "ChronometerFormatter.format(currentTime(tick: context.date)))\n                            .toolMotionTextSwap", "Chronometer main 0.01s timer value must not animate")
        contains(timezone, "IndexDisclosure(", "Timezone disclosure motion is owned by the shared IndexDisclosure component")
        doesNotContain(timezone, "formatTime(for: group.cities[0].timezone, currentTime: currentTime))\n                        .toolMotionTextSwap", "Timezone per-second time text must not animate")
    }
}
