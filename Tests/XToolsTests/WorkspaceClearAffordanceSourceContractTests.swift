import Foundation
@testable import XTools
import XToolsCore
import Testing

struct WorkspaceClearAffordanceSourceContractTests {
    @Test func clearButtonNamesItsScopeWithoutChangingTheExistingDefault() throws {
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")

        contains(controls, "var title = \"清空\"", "Existing clear buttons must keep the concise default title")
        contains(controls, "static let clear = \"xmark.circle\"", "The shared action vocabulary must own the clear symbol")
        contains(controls, "Label(title, systemImage: IndexActionSymbol.clear)", "Visible clear buttons must render the owning scope title with the shared symbol")
        contains(controls, ".help(title)", "Clear buttons must expose their concrete scope in help")
        contains(controls, ".accessibilityLabel(title)", "Clear buttons must expose their concrete scope to accessibility")
    }

    @Test func pageHeaderAccessoryIsOptInAndLeavesOrdinaryPagesOnTheOriginalHeaderBranch() throws {
        let pageShell = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexPageShell.swift")

        contains(pageShell, "struct IndexPage<Content: View, HeaderAccessory: View>: View", "IndexPage must type the optional header accessory without erasing the page content")
        contains(pageShell, "private let hasHeaderAccessory: Bool", "IndexPage must keep an explicit opt-in branch instead of wrapping every page header")
        contains(pageShell, "where HeaderAccessory == EmptyView", "The existing initializer must infer an empty accessory")
        contains(pageShell, "hasHeaderAccessory: false", "Ordinary pages must keep the original header branch")
        contains(pageShell, "hasHeaderAccessory: true", "Only explicit callers may render a header accessory")
        contains(pageShell, "if hasHeaderAccessory", "The body must branch before adding the accessory layout")
    }

    @Test func diffAndRegexPlaceWholeWorkspaceClearInLocalPanelHeaders() throws {
        let jsonDiff = try readSource("Sources/XTools/ToolPages/Development/JSONDiffPage.swift")
        let textDiff = try readSource("Sources/XTools/ToolPages/Development/TextDiffPage.swift")
        let regex = try readSource("Sources/XTools/ToolPages/Development/RegexTesterPage.swift")
        let editableDiff = try readSource("Sources/XTools/ToolPages/Workbench/Diff/IndexEditableDiffWorkspace.swift")

        for page in [jsonDiff, textDiff] {
            doesNotContain(page, "headerAccessory:", "Diff clear must not remain detached in the page title")
            contains(page, "onClear: workspace.clear", "Diff pages must pass whole-workspace clear into the shared DIFF panel")
            contains(page, "clearDisabled: !workspace.hasAnyContent", "Diff local clear must expose its disabled state")
            doesNotContain(page, "IndexActionBar", "Diff clear must not add a new action row above the editors")
        }
        contains(editableDiff, "var onClear: (() -> Void)? = nil", "The shared DIFF panel must own an optional whole-workspace clear callback")
        contains(editableDiff, "IndexClearButton(\n                    isDisabled: clearDisabled,\n                    title: \"清空对比\"", "Diff clear must be visible and name its scope in the local panel header")

        let regexPatternPanel = sourceSlice(
            regex,
            from: "IndexPanel(\n                \"正则表达式\"",
            to: "IndexPanel(\n                \"测试文本\""
        )
        doesNotContain(regex, "headerAccessory:", "Regex clear must not remain detached in the page title")
        contains(regexPatternPanel, "\"正则表达式\"", "Regex clear must stay beside the primary pattern input")
        contains(regexPatternPanel, "IndexClearButton(", "Regex pattern panel must retain the whole-workspace clear action")
        contains(regexPatternPanel, "title: \"清空工作区\"", "Regex local clear must visibly name its whole-workspace scope")
        doesNotContain(regex, "IndexActionBar", "Regex clear must not add a new action row")
    }
    @MainActor
    @Test func regexPresetIdentityTracksPatternAndFlagsButNotTestText() {
        let workspace = RegexToolWorkspaceModel()
        let email = try! #require(RegexMatcher.presets.first { $0.id == "email" })

        #expect(workspace.activePreset == nil)

        workspace.applyPreset(email)
        #expect(workspace.activePreset?.id == "email")
        #expect(workspace.pattern == email.pattern)
        #expect(workspace.flags == email.flags)
        #expect(workspace.text == email.exampleText)

        workspace.text = "custom@example.com"
        #expect(workspace.activePreset?.id == "email")

        workspace.pattern += "x"
        #expect(workspace.activePreset == nil)

        workspace.pattern = email.pattern
        #expect(workspace.activePreset?.id == "email")

        workspace.flags = "g"
        #expect(workspace.activePreset == nil)

        workspace.flags = "mg"
        #expect(workspace.activePreset?.id == "email")

        workspace.clear()
        #expect(workspace.activePreset == nil)
        #expect(workspace.flags == "g")
    }

    @MainActor
    @Test func diffWorkspaceClearRemovesAllContentAndDiagnostics() {
        let workspace = DiffToolWorkspaceModel()
        workspace.left = "private-left"
        workspace.right = "private-right"
        workspace.execution.invalidate(
            resetTo: DiffExecutionBinding(
                leftDisplayText: "formatted-left",
                rightDisplayText: "formatted-right",
                rows: [DiffAlignedRow(kind: .changed, left: nil, right: nil)],
                error: "session-error",
                warning: "session-warning"
            )
        )

        #expect(workspace.hasAnyContent)
        workspace.clear()

        #expect(!workspace.hasAnyContent)
        #expect(workspace.left.isEmpty)
        #expect(workspace.right.isEmpty)
        #expect(workspace.leftDisplayText == nil)
        #expect(workspace.rightDisplayText == nil)
        #expect(workspace.diffRows.isEmpty)
        #expect(workspace.error == nil)
        #expect(workspace.warning == nil)
    }

    @MainActor
    @Test func regexWorkspaceClearCancelsRunningWorkAndRestoresDefaultFlags() async throws {
        let workspace = RegexToolWorkspaceModel()
        workspace.pattern = "slow"
        workspace.flags = "ims"
        workspace.text = "private text"
        workspace.execution.run(pattern: "slow", text: "slow", flags: "g") { pattern, text, flags in
            Thread.sleep(forTimeInterval: 0.2)
            return try RegexMatcher.analyze(pattern: pattern, in: text, flags: flags)
        }

        #expect(workspace.hasAnyContent)
        #expect(workspace.execution.isRunning)
        workspace.clear()
        try await Task.sleep(for: .milliseconds(250))

        #expect(!workspace.hasAnyContent)
        #expect(workspace.pattern.isEmpty)
        #expect(workspace.flags == "g")
        #expect(workspace.text.isEmpty)
        #expect(workspace.execution.report == nil)
        #expect(workspace.execution.error == nil)
        #expect(!workspace.execution.isRunning)
    }

    @Test func retainedFormsAndSearchesUseOwningSurfaceClearActions() throws {
        let textComponents = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let crontab = try readSource("Sources/XTools/ToolPages/Development/CrontabGeneratorPage.swift")
        let userAgent = try readSource("Sources/XTools/ToolPages/Web/UserAgentParserPage.swift")
        let http = try readSource("Sources/XTools/ToolPages/Web/HTTPStatusCodesPage.swift")
        let math = try readSource("Sources/XTools/ToolPages/Utility/MathEvaluatorPage.swift")
        let emoji = try readSource("Sources/XTools/ToolPages/Utility/EmojiPickerPage.swift")

        contains(textComponents, "struct IndexSearchInput: View", "Retained query tools must share one clearable search input")
        contains(textComponents, "trailingInset: 40", "Search clear must reserve space inside the existing field rather than widen the action bar")
        contains(textComponents, "if !text.isEmpty", "Search clear must only appear when there is a query")
        contains(textComponents, "focusRequestToken:", "Search clear must request focus explicitly after the user activates it")
        contains(textComponents, "func requestFocus(", "The AppKit field coordinator must expose an opt-in explicit focus request")

        contains(crontab, "action: workspace.clear", "Crontab input header must route clear through its retained model")
        contains(userAgent, "action: workspace.clear", "UserAgent input header must route clear through its retained model")
        contains(math, "action: workspace.clear", "Math input header must route clear through its retained model")

        contains(http, "IndexSearchInput(", "HTTP status query must use the shared clearable search input")
        contains(http, "onClear: workspace.clearSearch", "HTTP clear must only route to query reset")
        contains(http, ".frame(maxWidth: 320)", "HTTP search width must remain unchanged")
        contains(emoji, "IndexSearchInput(", "Emoji query must use the shared clearable search input")
        contains(emoji, "onClear: workspace.clearSearch", "Emoji clear must preserve category and tone")
        contains(emoji, ".frame(maxWidth: 360)", "Emoji search width must remain unchanged")
    }

    @MainActor
    @Test func retainedFormClearMethodsRemoveDraftsAndDerivedState() {
        let crontab = CrontabToolWorkspaceModel()
        crontab.expression = "0 9 * * 1-5"
        crontab.nextRuns = ["2026-07-17 09:00"]
        crontab.error = "session-error"
        #expect(crontab.hasAnyContent)
        crontab.clear()
        #expect(!crontab.hasAnyContent)
        #expect(crontab.expression.isEmpty)
        #expect(crontab.nextRuns.isEmpty)
        #expect(crontab.error == nil)

        let userAgent = UserAgentToolWorkspaceModel()
        userAgent.input = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0 Safari/537.36"
        userAgent.parse()
        #expect(userAgent.hasAnyContent)
        userAgent.clear()
        #expect(!userAgent.hasAnyContent)
        #expect(userAgent.input.isEmpty)
        #expect(userAgent.browser.isEmpty)
        #expect(userAgent.error == nil)

        let math = MathToolWorkspaceModel()
        math.expression = "1 + 1"
        math.evaluation = .valid("2")
        #expect(math.hasAnyContent)
        math.clear()
        #expect(!math.hasAnyContent)
        #expect(math.expression.isEmpty)
        #expect(math.evaluation == .empty)
    }

    @MainActor
    @Test func searchClearPreservesHTTPAndEmojiSelections() {
        let http = HTTPStatusToolWorkspaceModel()
        http.query = "not found"
        http.category = "4xx 客户端错误"
        http.clearSearch()
        #expect(http.query.isEmpty)
        #expect(http.category == "4xx 客户端错误")

        let suiteName = "WorkspaceClearAffordanceSourceContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let emoji = EmojiToolWorkspaceModel(preferences: ToolPreferenceStore(defaults: defaults))
        emoji.query = "face"
        emoji.category = EmojiCatalog.specialSymbolGroupName
        emoji.toneIndex = 3
        emoji.clearSearch()
        #expect(emoji.query.isEmpty)
        #expect(emoji.category == EmojiCatalog.specialSymbolGroupName)
        #expect(emoji.toneIndex == 3)
    }

}
