import Foundation
import Testing

struct NarrowWindowAdaptationSourceContractTests {
    @Test func mainWindowKeepsOneNativeResponsiveMinimumWithoutResizeMotion() throws {
        let app = try readSource("Sources/XTools/XToolsApp.swift")
        let root = try readSource("Sources/XTools/AppShell/RootView.swift")

        contains(app, ".frame(minWidth: 960, minHeight: 640)", "Outer content minimum must expose the validated narrow-window boundary")
        contains(root, ".frame(minWidth: 960, minHeight: 640)", "RootView and Scene must agree on one minimum size")
        contains(app, ".defaultSize(width: 1200, height: 800)", "Narrow-window support must not shrink the default desktop window")
        contains(app, ".windowResizability(.contentMinSize)", "The native window must continue deriving its floor from content")
        contains(app, ".windowStyle(HiddenTitleBarWindowStyle())", "The existing native macOS window chrome must remain")
        contains(app, ".windowToolbarStyle(.unifiedCompact(showsTitle: false))", "The narrow window must retain the native compact unified toolbar chrome rhythm")
        occurrenceCount(app, "Window(\"Tools\", id: \"main\")", 1, "The app must keep one main window scene")
        doesNotContain(app, "withAnimation(", "Continuous window resize must not gain explicit animation")
        doesNotContain(app, ".animation(", "Continuous window resize must not gain implicit animation")
        doesNotContain(app, "WebView", "Native adaptation must not introduce a web rendering layer")
        doesNotContain(app, "Tailwind", "Native adaptation must not introduce CSS framework concepts")
    }

    @Test func textEncryptionOwnsCompleteOneAndTwoRowControlCandidates() throws {
        let source = try readSource("Sources/XTools/ToolPages/Crypto/TextEncryptionPage.swift")
        let wideControls = sourceSlice(
            source,
            from: "private var wideControls: some View",
            to: "private var compactControls: some View"
        )
        let compactControls = sourceSlice(
            source,
            from: "private var compactControls: some View",
            to: "private var modeControl: some View"
        )

        doesNotContain(source, "} primaryAction: {", "Text encryption must not give the outer control bar a second width-allocation owner")
        contains(wideControls, "primaryActionButton", "The complete one-row candidate must keep the primary action beside the flexible password input")
        occurrenceCount(compactControls, "HStack", 2, "The compact candidate must keep exactly two task-oriented control rows")
        contains(compactControls, "primaryActionButton", "The compact password row must keep the primary action discoverable")
        doesNotContain(compactControls, "IndexFlowLayout", "Text encryption compact controls must not flow into an unbounded number of rows")
        contains(source, ".frame(minWidth: 76)", "The primary action must keep its text readable under width pressure")
    }
}
