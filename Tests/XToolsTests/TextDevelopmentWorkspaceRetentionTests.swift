import Foundation
import Testing
@testable import XTools
@testable import XToolsCore

struct TextDevelopmentWorkspaceRetentionTests {
    @MainActor
    @Test func genericConverterAndWorkbenchSurviveNavigationButResetOnRelaunch() {
        let defaults = Self.defaults()
        let key = ToolWorkspaceKey<IndexConverterToolWorkspaceModel>(toolID: "base64-string") { _ in
            IndexConverterToolWorkspaceModel(
                initialMode: "dec",
                errorMessage: { _ in "session-error" },
                convert: { _, _ in throw IndexConverterFailure.invalidInput }
            )
        }
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let workspace = repository.model(for: key)
        workspace.mode = "enc"
        workspace.input = "session-only"
        #expect(workspace.error == "session-error")
        #expect(repository.model(for: key) === workspace)

        let relaunched = ToolWorkspaceRepository(defaults: defaults).model(for: key)
        #expect(relaunched.mode == "dec")
        #expect(relaunched.input.isEmpty)
        #expect(relaunched.error == nil)
    }

    @MainActor
    @Test func formatterRecipesPersistWithoutFormatterContent() {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let json = repository.model(for: JSONFormatterToolWorkspaceModel.key)
        json.input = "private-json"
        json.execution.invalidate(
            resetTo: FormatBinding(output: "formatted", error: "error")
        )
        json.indentOption = .four

        let sql = repository.model(for: SQLPrettifyToolWorkspaceModel.key)
        sql.input = "private-sql"
        sql.execution.invalidate(
            resetTo: FormatBinding(output: "formatted")
        )
        sql.keywordCase = .lower

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
        let relaunchedJSON = relaunched.model(for: JSONFormatterToolWorkspaceModel.key)
        let relaunchedSQL = relaunched.model(for: SQLPrettifyToolWorkspaceModel.key)
        #expect(relaunchedJSON.input.isEmpty)
        #expect(relaunchedJSON.output.isEmpty)
        #expect(relaunchedJSON.error == nil)
        #expect(relaunchedJSON.indentOption == .four)
        #expect(relaunchedSQL.input.isEmpty)
        #expect(relaunchedSQL.output.isEmpty)
        #expect(relaunchedSQL.keywordCase == .lower)
    }

    @MainActor
    @Test func jsonFormatterUsesFourSpaceProductDefaultWithoutOverwritingSavedIndent() {
        let productDefaults = Self.defaults()
        let defaultWorkspace = ToolWorkspaceRepository(defaults: productDefaults)
            .model(for: JSONFormatterToolWorkspaceModel.key)
        #expect(defaultWorkspace.indentOption == .four)

        let savedDefaults = Self.defaults()
        savedDefaults.set("2", forKey: TextDevelopmentToolPreferenceKeys.jsonIndent.rawKey)
        let savedWorkspace = ToolWorkspaceRepository(defaults: savedDefaults)
            .model(for: JSONFormatterToolWorkspaceModel.key)
        #expect(savedWorkspace.indentOption == .two)
    }

    @MainActor
    @Test func invalidPreferencesUseProductDefaultsAndIgnoreLegacyWorkbenchLayout() {
        let defaults = Self.defaults()
        defaults.set("3", forKey: TextDevelopmentToolPreferenceKeys.jsonIndent.rawKey)
        defaults.set("future", forKey: TextDevelopmentToolPreferenceKeys.sqlKeywordCase.rawKey)
        defaults.set("32", forKey: TextDevelopmentToolPreferenceKeys.integerBase.rawKey)
        defaults.set(99, forKey: TextDevelopmentToolPreferenceKeys.emojiToneIndex.rawKey)
        defaults.set(0.95, forKey: "tools.workspace.json-formatter.splitRatio.v1")

        let repository = ToolWorkspaceRepository(defaults: defaults)
        #expect(repository.model(for: JSONFormatterToolWorkspaceModel.key).indentOption == .four)
        #expect(repository.model(for: SQLPrettifyToolWorkspaceModel.key).keywordCase == .upper)
        #expect(repository.model(for: IntegerBaseToolWorkspaceModel.key).base == "10")
        #expect(repository.model(for: EmojiToolWorkspaceModel.key).toneIndex == 0)
    }

    @MainActor
    @Test func shortDiffRegexAndUtilityModelsRespectRepositoryBoundary() {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)

        let integer = repository.model(for: IntegerBaseToolWorkspaceModel.key)
        integer.base = "16"
        integer.input = "GG"
        #expect(integer.error == "十六进制数只能包含 0–9、A–F，可在开头使用正负号。")

        let roman = repository.model(for: RomanNumeralToolWorkspaceModel.key)
        roman.mode = "toNum"
        roman.input = "MMXXIV"

        let dateTime = repository.model(for: DateTimeToolWorkspaceModel.key)
        dateTime.timestamp = "123"
        dateTime.humanError = "session-error"

        let regex = repository.model(for: RegexToolWorkspaceModel.key)
        regex.pattern = "a+"
        regex.text = "aaa"

        let math = repository.model(for: MathToolWorkspaceModel.key)
        math.expression = "1+1"
        math.evaluation = .valid("2")

        let color = repository.model(for: ColorToolWorkspaceModel.key)
        color.send(.draftChanged("#FF0000"))

        let emoji = repository.model(for: EmojiToolWorkspaceModel.key)
        emoji.query = "private-query"
        emoji.category = "session-category"
        emoji.toneIndex = 3

        #expect(repository.model(for: IntegerBaseToolWorkspaceModel.key) === integer)
        #expect(repository.model(for: RomanNumeralToolWorkspaceModel.key) === roman)
        #expect(repository.model(for: DateTimeToolWorkspaceModel.key) === dateTime)
        #expect(repository.model(for: RegexToolWorkspaceModel.key) === regex)
        #expect(repository.model(for: MathToolWorkspaceModel.key) === math)
        #expect(repository.model(for: ColorToolWorkspaceModel.key) === color)
        #expect(repository.model(for: EmojiToolWorkspaceModel.key) === emoji)

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
        let relaunchedInteger = relaunched.model(for: IntegerBaseToolWorkspaceModel.key)
        #expect(relaunchedInteger.base == "16")
        #expect(relaunchedInteger.input.isEmpty)
        #expect(relaunchedInteger.error == nil)
        #expect(relaunched.model(for: RomanNumeralToolWorkspaceModel.key).mode == "toRoman")
        #expect(relaunched.model(for: RomanNumeralToolWorkspaceModel.key).input.isEmpty)
        #expect(relaunched.model(for: RegexToolWorkspaceModel.key).pattern.isEmpty)
        #expect(relaunched.model(for: MathToolWorkspaceModel.key).expression.isEmpty)
        #expect(relaunched.model(for: ColorToolWorkspaceModel.key).state.draft == "#7C8CFF")
        let relaunchedEmoji = relaunched.model(for: EmojiToolWorkspaceModel.key)
        #expect(relaunchedEmoji.query.isEmpty)
        #expect(relaunchedEmoji.category == "笑脸与情感")
        #expect(EmojiCatalog.groups.first?.name == "笑脸与情感")
        #expect(relaunchedEmoji.toneIndex == 3)
    }

    @MainActor
    @Test func sharedDraftTransformDiffAndUtilityFamiliesRespectRepositoryBoundary() {
        let defaults = Self.defaults()
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let draftKey = ToolWorkspaceKey<IndexTextDraftWorkspaceModel>(
            toolID: "case-converter",
            slot: "retention-test"
        ) { _ in
            IndexTextDraftWorkspaceModel()
        }
        let transformKey = ToolWorkspaceKey<IndexTextTransformWorkspaceModel>(
            toolID: "xml-formatter",
            slot: "retention-test"
        ) { _ in
            IndexTextTransformWorkspaceModel()
        }
        let diffKey = ToolWorkspaceKey<DiffToolWorkspaceModel>(
            toolID: "json-diff",
            slot: "retention-test"
        ) { _ in
            DiffToolWorkspaceModel()
        }

        let draft = repository.model(for: draftKey)
        draft.text = "session-draft"
        let transform = repository.model(for: transformKey)
        transform.input = "<private/>"
        transform.execution.invalidate(
            resetTo: FormatBinding(
                output: "formatted",
                error: "session-error",
                warning: "session-warning"
            )
        )
        let diff = repository.model(for: diffKey)
        diff.left = "private-left"
        diff.right = "private-right"
        diff.execution.invalidate(resetTo: DiffExecutionBinding(error: "session-error"))
        let crontab = repository.model(for: CrontabToolWorkspaceModel.key)
        crontab.expression = "0 9 * * 1-5"
        crontab.nextRuns = ["session-run"]
        crontab.error = "session-error"
        let port = repository.model(for: RandomPortToolWorkspaceModel.key)
        port.generate()
        let generatedPort = port.output
        let chmod = repository.model(for: ChmodToolWorkspaceModel.key)
        chmod.u1 = true
        chmod.o4 = false

        #expect(repository.model(for: draftKey) === draft)
        #expect(repository.model(for: transformKey) === transform)
        #expect(repository.model(for: diffKey) === diff)
        #expect(repository.model(for: CrontabToolWorkspaceModel.key) === crontab)
        #expect(repository.model(for: RandomPortToolWorkspaceModel.key) === port)
        #expect(repository.model(for: ChmodToolWorkspaceModel.key) === chmod)
        #expect(generatedPort != nil)

        let relaunched = ToolWorkspaceRepository(defaults: defaults)
        #expect(relaunched.model(for: draftKey).text.isEmpty)
        let relaunchedTransform = relaunched.model(for: transformKey)
        #expect(relaunchedTransform.input.isEmpty)
        #expect(relaunchedTransform.output.isEmpty)
        #expect(relaunchedTransform.error == nil)
        #expect(relaunchedTransform.warning == nil)
        let relaunchedDiff = relaunched.model(for: diffKey)
        #expect(relaunchedDiff.left.isEmpty)
        #expect(relaunchedDiff.right.isEmpty)
        #expect(relaunchedDiff.error == nil)
        let relaunchedCrontab = relaunched.model(for: CrontabToolWorkspaceModel.key)
        #expect(relaunchedCrontab.expression == "*/5 * * * *")
        #expect(relaunchedCrontab.nextRuns.isEmpty)
        #expect(relaunchedCrontab.error == nil)
        let relaunchedPort = relaunched.model(for: RandomPortToolWorkspaceModel.key)
        #expect(relaunchedPort.output == nil)
        #expect(!relaunchedPort.hasAttemptedGeneration)
        let relaunchedChmod = relaunched.model(for: ChmodToolWorkspaceModel.key)
        #expect(!relaunchedChmod.u1)
        #expect(relaunchedChmod.o4)
    }

    @MainActor
    @Test func htmlOperationCompletesWhileOnlyRepositoryOwnsSession() async throws {
        let key = ToolWorkspaceKey<HTMLToMarkdownSession>(toolID: "html-to-markdown", slot: "continuity-test") { _ in
            HTMLToMarkdownSession(
                manualOperation: { html in
                    Thread.sleep(forTimeInterval: 0.15)
                    return HTMLToMarkdownConversionResult(markdown: "retained:\(html)", warnings: [])
                },
                manualDebounce: .zero
            )
        }
        let repository = ToolWorkspaceRepository(defaults: Self.defaults())
        do {
            let session = repository.model(for: key)
            session.userEditedHTML("<p>work</p>")
        }

        let restored = repository.model(for: key)
        try await Self.waitUntil { restored.markdown == "retained:<p>work</p>" }
        #expect(restored.error == nil)
    }

    @Test func pagesUseRepositoryHostsWithoutMovingPresentationState() throws {
        let paths = [
            "Sources/XTools/ToolPages/Converter/CaseConverterPage.swift",
            "Sources/XTools/ToolPages/Converter/IntegerBaseConverterPage.swift",
            "Sources/XTools/ToolPages/Converter/RomanNumeralPage.swift",
            "Sources/XTools/ToolPages/Converter/CaseConverterPage.swift",
            "Sources/XTools/ToolPages/Time/DateTimeConverterPage.swift",
            "Sources/XTools/ToolPages/Development/JSONFormatterPage.swift",
            "Sources/XTools/ToolPages/Development/SQLPrettifyPage.swift",
            "Sources/XTools/ToolPages/Development/XMLFormatterPage.swift",
            "Sources/XTools/ToolPages/Development/YAMLPrettifyPage.swift",
            "Sources/XTools/ToolPages/Development/JSONDiffPage.swift",
            "Sources/XTools/ToolPages/Development/TextDiffPage.swift",
            "Sources/XTools/ToolPages/Development/RegexTesterPage.swift",
            "Sources/XTools/ToolPages/Development/DockerRunToComposePage.swift",
            "Sources/XTools/ToolPages/Development/CrontabGeneratorPage.swift",
            "Sources/XTools/ToolPages/Development/RandomPortPage.swift",
            "Sources/XTools/ToolPages/Development/ChmodCalculatorPage.swift",
            "Sources/XTools/ToolPages/Development/HTMLToMarkdownPage.swift",
            "Sources/XTools/ToolPages/Utility/MathEvaluatorPage.swift",
            "Sources/XTools/ToolPages/Utility/TextStatisticsPage.swift",
            "Sources/XTools/ToolPages/Image/ColorPickerPage.swift",
            "Sources/XTools/ToolPages/Utility/EmojiPickerPage.swift"
        ]
        for path in paths {
            contains(try readSource(path), "ToolWorkspaceHost(key:", "\(path) must resolve App-session work from the repository")
        }

        let html = try readSource("Sources/XTools/ToolPages/Development/HTMLToMarkdownPage.swift")
        doesNotContain(html, ".onDisappear", "HTML navigation must not cancel user-started work")
        let color = try readSource("Sources/XTools/ToolPages/Image/ColorPickerPage.swift")
        contains(color, "@State private var showsSystemColorPicker = false", "Color picker presentation must remain view-scoped")
        let emojiCollection = try readSource("Sources/XTools/ToolPages/Utility/EmojiCollectionView.swift")
        contains(emojiCollection, "private var hoveredIndexPath: IndexPath?", "Emoji hover presentation must remain native renderer state instead of workspace state")
        doesNotContain(emojiCollection, "@AppStorage", "Emoji hover presentation must never enter persisted preferences")
    }

    @MainActor
    @Test func preferenceKeySurfaceExcludesContentAndWorkbenchLayout() {
        let expectedKeys = Set([
            "tools.integerBase.inputBase.v1",
            "tools.jsonFormatter.indent.v1",
            "tools.sqlFormatter.keywordCase.v1",
            "tools.emoji.toneIndex.v1"
        ])
        let keys = Set(TextDevelopmentToolPreferenceKeys.allRawKeys)
        #expect(keys == expectedKeys)

        for key in keys {
            let normalized = key.lowercased()
            #expect(!normalized.contains("inputtext"))
            #expect(!normalized.contains("output"))
            #expect(!normalized.contains("error"))
            #expect(!normalized.contains("urltext"))
            #expect(!normalized.contains("pattern"))
            #expect(!normalized.contains("expression"))
        }
    }

    private static func defaults() -> UserDefaults {
        let suiteName = "TextDevelopmentWorkspaceRetentionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @MainActor
    private static func waitUntil(
        timeout: Duration = .seconds(20),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(condition())
    }
}
