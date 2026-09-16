import Foundation
import AppKit
@testable import XTools
import Testing

struct TextWorkbenchSourceContractTests {
    @Test func converterDiagnosticsUseTypedCoreErrorsWithoutInputEchoes() throws {
        let integerBase = try readSource("Sources/XTools/ToolPages/Converter/IntegerBaseConverterPage.swift")
        let base64 = try readSource("Sources/XTools/ToolPages/Converter/Base64StringPage.swift")
        let url = try readSource("Sources/XTools/ToolPages/Converter/URLCoderPage.swift")
        let asciiBinary = try readSource("Sources/XTools/ToolPages/Converter/ASCIIBinaryPage.swift")
        let unicode = try readSource("Sources/XTools/ToolPages/Converter/UnicodePage.swift")
        let roman = try readSource("Sources/XTools/ToolPages/Converter/RomanNumeralPage.swift")

        contains(integerBase, "IntegerBaseConverter.prepare", "Base converter must derive results and typed validation from one prepared input")
        doesNotContain(integerBase, #"\(input)"#, "Base converter diagnostics must not echo the complete input")
        contains(base64, "Base64Conversion.ConversionError", "Base64 string page must preserve Base64 and UTF-8 error categories")
        contains(url, "URLPercentCoding.CodingError", "URL page must preserve percent syntax and UTF-8 error categories")
        contains(asciiBinary, "ASCIIBinaryConversion.ConversionError", "ASCII/binary page must preserve conversion error categories")
        contains(unicode, "UnicodeEscaping.DecodingError", "Unicode page must preserve escape and surrogate error categories")
        contains(roman, "RomanNumeralConverter.ValidationIssue", "Roman page must preserve character, range, and canonical-form errors")
    }

    @Test func integerBaseRoutesOnePreparedResultIntoAStableProcessingSurface() throws {
        let integerBase = try readSource("Sources/XTools/ToolPages/Converter/IntegerBaseConverterPage.swift")

        contains(integerBase, "workspace.conversions", "Base converter rows must render the workspace-owned result instead of recomputing in the View")
        contains(integerBase, #"IndexProgressLabel(message: "正在换算…")"#, "Long base conversion must explain processing through the shared progress label")
        contains(integerBase, ".frame(minHeight: 70)", "Processing must preserve the short-result surface minimum height")
        doesNotContain(integerBase, ".onChange(of: workspace.input)", "Input changes must be owned by the workspace model rather than a second View validation path")
        doesNotContain(integerBase, "private func validate()", "Base converter must not retain a duplicate full-conversion validation path")
    }

    @Test func formatterAndDockerInputsShowCharacterCounts() throws {
        let docker = try readSource("Sources/XTools/ToolPages/Development/DockerRunToComposePage.swift")
        let yaml = try readSource("Sources/XTools/ToolPages/Development/YAMLPrettifyPage.swift")
        let xml = try readSource("Sources/XTools/ToolPages/Development/XMLFormatterPage.swift")
        let json = try readSource("Sources/XTools/ToolPages/Development/JSONFormatterPage.swift")
        let sql = try readSource("Sources/XTools/ToolPages/Development/SQLPrettifyPage.swift")
        let shared = try readSharedBagComponents()
        let pageShell = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexPageShell.swift")

        // The prototype toolbar has no counter slot: the whole structured
        // family dropped the character count with the migration.
        for path in ["Development/JSONFormatterPage.swift", "Development/SQLPrettifyPage.swift", "Development/XMLFormatterPage.swift", "Development/YAMLPrettifyPage.swift", "Development/DockerRunToComposePage.swift", "Development/HTMLToMarkdownPage.swift"] {
            let page = try readSource("Sources/XTools/ToolPages/\(path)")
            contains(page, "IndexFormatWorkbench", "\(path) must delegate its panes to the shared prototype workbench")
            doesNotContain(page, "showsInputCount: false", "\(path) must not force-hide a count it no longer renders")
        }
        doesNotContain(sql, "private var clearButton", "SQL formatter must not keep a local full clear button copy")
        doesNotContain(sql, "private var compactClearButton", "SQL formatter must not keep a local compact clear button copy")
        contains(shared, "struct IndexInputHeaderAccessory", "Shared components must define the responsive input header accessory")
        contains(shared, ".fixedSize(horizontal: true, vertical: false)", "Input header accessory candidates must keep intrinsic width so ViewThatFits can switch to compact controls instead of squeezing the panel title")
        contains(shared, "struct IndexInputCountLabel", "Shared components must define the input character count label")
        contains(shared, "text = \"\\(count) 字符\"", "IndexInputCountLabel must retain the default character-count caption")
        contains(shared, "Text(text)", "IndexInputCountLabel must render an explicitly selected bounded metric")
        contains(pageShell, "IndexBadge(terminalTag, tone: .accent, isCapsule: true)", "Terminal stream tags must render through the shared badge (capsule, single-line by construction)")
        contains(pageShell, ".layoutPriority(3)", "Terminal stream tags must resist compression before truncatable panel titles")
    }

    @Test func formatterErrorsUseInputPanelWorkspaceDiagnostics() throws {
        let yaml = try readSource("Sources/XTools/ToolPages/Development/YAMLPrettifyPage.swift")
        let xml = try readSource("Sources/XTools/ToolPages/Development/XMLFormatterPage.swift")
        let json = try readSource("Sources/XTools/ToolPages/Development/JSONFormatterPage.swift")
        let sql = try readSource("Sources/XTools/ToolPages/Development/SQLPrettifyPage.swift")
        let shared = try readSharedBagComponents()
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")

        contains(shared, "struct IndexWorkspaceDiagnostic: View", "Shared components must provide a persistent non-displacing diagnostic")
        contains(shared, "var inputError: String? = nil", "IndexIOPair must accept an optional input-panel error")
        contains(workbench, "var inputError: String? = nil", "Shared text conversion workbench must accept an optional input-panel error")
        contains(workbench, "private var inputDiagnosticText: String?", "Shared text conversion workbench must normalize errors and warnings into one diagnostic text")
        contains(workbench, "private var inputDiagnosticTone: ToolFeedbackTone", "Shared text conversion workbench must select a diagnostic tone from the active error/warning state")
        contains(shared, "struct IndexWorkspaceDiagnosticRegion", "Shared components must provide a safe diagnostic region outside editor text")
        contains(workbench, ".indexWorkspaceDiagnostic(inputDiagnosticText, tone: inputDiagnosticTone)", "Shared text conversion workbench must attach errors and warnings as input-panel safe diagnostics")
        contains(shared, ".indexWorkspaceDiagnostic(inputError, tone: .error)", "Legacy IO pairs must attach errors as input-panel safe diagnostics")
        contains(json, "diagnostic: execution.binding.error ?? execution.binding.warning", "JSON formatter diagnostics must render inside the prototype workbench toolbar")
        contains(json, "diagnosticTone: execution.binding.error == nil ? .warning : .error", "JSON formatter must select the diagnostic tone from the active error/warning state")
        for (name, needle) in [("XML", "diagnostic: execution.binding.error"), ("YAML", "diagnostic: execution.binding.error"), ("SQL", "diagnostic: execution.binding.error")] {
            let source = try readSource("Sources/XTools/ToolPages/Development/\(name == "XML" ? "XMLFormatterPage" : name == "YAML" ? "YAMLPrettifyPage" : "SQLPrettifyPage").swift")
            contains(source, needle, "\(name) formatter errors must render inside the prototype workbench toolbar")
        }
        contains(try readSource("Sources/XTools/ToolPages/Development/DockerRunToComposePage.swift"), "diagnostic: execution.binding.error ?? execution.binding.warning", "Docker diagnostics must render inside the prototype workbench toolbar")
        doesNotContain(workbench, "IndexInputErrorLine(text: inputError)", "Workbench errors must not use an inline row that resizes the panel")
        doesNotContain(workbench, "IndexInputErrorLine(text: inputDiagnosticText)", "Workbench diagnostics must not use an inline row that resizes the panel")
        doesNotContain(json, ".indexFloatingError(error)", "JSON formatter errors must not use the old floating-error API")
        doesNotContain(sql, ".indexFloatingError(error)", "SQL formatter errors must not use the old floating-error API")
        doesNotContain(xml, ".indexFloatingError(error)", "XML formatter errors must not use the old floating-error API")
        doesNotContain(yaml, ".indexFloatingError(error)", "YAML formatter errors must not use the old floating-error API")
    }

    @Test func nonEditorRepresentativePagesDoNotUseTextConversionWorkbench() throws {
        let representativePages = [
            "Sources/XTools/ToolPages/Crypto/HashTextPage.swift",
            "Sources/XTools/ToolPages/Web/JWTParserPage.swift",
            "Sources/XTools/ToolPages/Web/UserAgentParserPage.swift",
            "Sources/XTools/ToolPages/Web/BasicAuthGeneratorPage.swift",
            "Sources/XTools/ToolPages/Converter/CaseConverterPage.swift",
            "Sources/XTools/ToolPages/Utility/FileTypeDetectorPage.swift",
            "Sources/XTools/ToolPages/Converter/IntegerBaseConverterPage.swift",
            "Sources/XTools/ToolPages/Converter/RomanNumeralPage.swift",
            "Sources/XTools/ToolPages/Development/ChmodCalculatorPage.swift",
            "Sources/XTools/ToolPages/Image/ColorPickerPage.swift",
            "Sources/XTools/ToolPages/Utility/MathEvaluatorPage.swift",
            "Sources/XTools/ToolPages/Time/DateCalculatorPage.swift",
            "Sources/XTools/ToolPages/Crypto/TokenGeneratorPage.swift",
            "Sources/XTools/ToolPages/Crypto/UUIDGeneratorPage.swift",
            "Sources/XTools/ToolPages/Crypto/PasswordGeneratorPage.swift",
            "Sources/XTools/ToolPages/Development/RandomPortPage.swift",
            "Sources/XTools/ToolPages/Development/CrontabGeneratorPage.swift",
            "Sources/XTools/ToolPages/Utility/TextStatisticsPage.swift",
            "Sources/XTools/ToolPages/Development/RegexTesterPage.swift",
            "Sources/XTools/ToolPages/Development/TextDiffPage.swift",
            "Sources/XTools/ToolPages/Development/JSONDiffPage.swift",
            "Sources/XTools/ToolPages/Utility/DeviceInformationPage.swift",
            "Sources/XTools/ToolPages/Web/HTTPStatusCodesPage.swift",
            "Sources/XTools/ToolPages/Time/TimezoneViewerPage.swift",
            "Sources/XTools/ToolPages/Utility/EmojiPickerPage.swift",
            "Sources/XTools/ToolPages/Web/KeycodeInfoPage.swift",
            "Sources/XTools/ToolPages/Image/ImageConverterPage.swift",
            "Sources/XTools/ToolPages/Image/ImageCompressorPage.swift",
            "Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift",
            "Sources/XTools/ToolPages/Image/ImageGrayscalePage.swift",
            "Sources/XTools/ToolPages/Image/FaviconGeneratorPage.swift",
            "Sources/XTools/ToolPages/Time/ChronometerPage.swift"
        ]

        for path in representativePages {
            let source = try readSource(path)
            doesNotContain(source, "IndexTextConversionWorkbench(", "\(path) must not opt into the text conversion editor workbench")
            doesNotContain(source, "workspaceSemantic: .copyTransformWorkspace", "\(path) must not inherit copy-transform workspace semantics")
            doesNotContain(source, "workspaceSemantic: .structuredEditorTransform", "\(path) must not inherit structured formatter workspace semantics")
        }
    }

    @Test func urlCoderReusesAutomaticConverterShell() throws {
        let source = try readSource("Sources/XTools/ToolPages/Converter/URLCoderPage.swift")

        contains(source, "IndexConverterPage(", "URL coder must keep using the shared copy-transform module")
        contains(source, "subtitle: \"对路径片段、查询参数值等 URL 组件进行百分号编码与解码。\"", "URL coder must state that it operates on URL components")
        contains(source, "placeholder: \"输入路径片段或查询参数值\"", "URL coder input must prompt for a component rather than a complete URL")
        doesNotContain(source, "placeholder: \"https://", "URL coder must not imply that complete URL structure is preserved")
        #expect(source.components(separatedBy: "IndexConverterMode(").count - 1 == 2, "URL coder must keep exactly the encode and decode modes")
        doesNotContain(source, "showsConvertButton:", "URL coder must inherit the settled no-primary-button behavior")
        doesNotContain(source, "usesTextConversionWorkbench:", "URL coder must not retain the completed workbench migration flag")
        contains(source, "backfillsOutputOnModeChange: true", "URL coder must backfill the current valid output when switching direction")
        doesNotContain(source, "outputFileName:", "URL coder must not retain an unreachable generic text-save filename")
        doesNotContain(source, "embedsClearButtonInInputPanel", "URL coder must not pass the removed embed-clear switch (clear is now always embedded)")
    }

    @Test func unicodeAndAsciiBinaryUseRoundTripBackfillContracts() throws {
        let asciiBinary = try readSource("Sources/XTools/ToolPages/Converter/ASCIIBinaryPage.swift")
        let unicode = try readSource("Sources/XTools/ToolPages/Converter/UnicodePage.swift")

        contains(unicode, "backfillsOutputOnModeChange: true", "Unicode conversion must backfill the current valid output when switching direction")

        contains(asciiBinary, "IndexConverterMode(id: \"bin\", label: \"文本→二进制\")", "ASCII/binary must keep an explicit text-to-binary mode")
        contains(asciiBinary, "IndexConverterMode(id: \"debin\", label: \"二进制→文本\")", "ASCII/binary must expose the binary inverse mode")
        contains(asciiBinary, "IndexConverterMode(id: \"ascii\", label: \"文本→ASCII\")", "ASCII/binary must keep decimal ASCII encoding mode")
        contains(asciiBinary, "IndexConverterMode(id: \"deascii\", label: \"ASCII→文本\")", "ASCII/binary must expose the decimal ASCII inverse mode")
        contains(asciiBinary, "backfillModeTransition: { currentMode, newMode in", "ASCII/binary must use pair-aware backfill instead of global all-mode backfill")
        contains(asciiBinary, "case (\"bin\", \"debin\"),", "ASCII/binary must allow binary output to become binary decode input")
        contains(asciiBinary, "(\"debin\", \"bin\"),", "ASCII/binary must allow decoded binary text to become binary encode input")
        contains(asciiBinary, "(\"ascii\", \"deascii\"),", "ASCII/binary must allow decimal ASCII output to become ASCII decode input")
        contains(asciiBinary, "(\"deascii\", \"ascii\"):", "ASCII/binary must allow decoded ASCII text to become ASCII encode input")
        contains(asciiBinary, "ASCIIBinaryConversion.validatedASCIIToText(input)", "ASCII/binary must route ASCII decode through the strict Core helper")
        contains(asciiBinary, "outputPresentation: .nativeReadOnlyText", "ASCII/binary must use the native read-only surface for expanded large output")
        doesNotContain(unicode, "outputPresentation: .nativeReadOnlyText", "Unicode must keep the standard output surface until independently proven otherwise")
    }

    @Test func developmentTextWorkbenchesExposeOnlyTaskRelevantActions() throws {
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")
        doesNotContain(workbench, "IndexTextConversionFocusMode", "Shared workbench must not retain removed focus state")
        doesNotContain(workbench, "showsFocusControls", "Shared workbench must not expose pane enlargement controls")
        doesNotContain(workbench, "keyboardMonitor", "Removed focus mode must not retain an Escape monitor")
        contains(workbench, "var showsOutputSave = false", "Text saving must be opt-in so new callers cannot reintroduce the old default")
        contains(workbench, "if showsOutputSave", "HTML Markdown save must remain a shared opt-in capability")

        let copyOnlyPages = [
            "Sources/XTools/ToolPages/Development/JSONFormatterPage.swift",
            "Sources/XTools/ToolPages/Development/SQLPrettifyPage.swift",
            "Sources/XTools/ToolPages/Development/XMLFormatterPage.swift",
            "Sources/XTools/ToolPages/Development/YAMLPrettifyPage.swift",
            "Sources/XTools/ToolPages/Development/DockerRunToComposePage.swift"
        ]
        for path in copyOnlyPages {
            let page = try readSource(path)
            doesNotContain(page, "showsFocusControls", "\(path) must not configure removed pane enlargement controls")
            doesNotContain(page, "showsOutputSave", "\(path) must inherit the shared save-disabled default")
            doesNotContain(page, "outputFileName:", "\(path) must not retain an unreachable text save filename")
        }

        let markdown = try readSource("Sources/XTools/ToolPages/Development/HTMLToMarkdownPage.swift")
        contains(markdown, "showsOutputSave: true", "HTML to Markdown must retain Markdown file export")
        contains(markdown, "outputFileName: \"markdown-output.md\"", "HTML to Markdown must default to a Markdown extension")
        doesNotContain(markdown, "retainedState:", "HTML to Markdown must not retain removed focus state")
    }

    @Test func sharedTextConversionWorkbenchFoundationIsSettled() throws {
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")
        let converter = try readSource("Sources/XTools/ToolPages/Workbench/Converter/IndexConverterPage.swift")
        let asciiBinary = try readSource("Sources/XTools/ToolPages/Converter/ASCIIBinaryPage.swift")

        contains(workbench, "struct IndexTextConversionWorkbench", "Shared text conversion workbench must be a named foundation")
        doesNotContain(workbench, "enum IndexTextConversionFocusMode", "Workbench must not retain the removed focus mode")
        doesNotContain(workbench, "IndexTextConversionWorkbenchState", "Workbench must not retain removed focus state")
        doesNotContain(workbench, "retainedState:", "Workbench must not retain removed focus state bindings")
        contains(workbench, "var outputProcessingText: String? = nil", "Shared workbench must expose a stable output processing surface")
        contains(workbench, "var inputRenderingMode: IndexTextAreaRenderingMode? = nil", "Shared workbench must expose a narrow opt-in input renderer without changing unnamed callers")
        contains(workbench, "IndexTextConversionProcessingSurface(text: outputProcessingText)", "Shared workbench must replace mismatched output with real processing status")
        contains(workbench, "private var staticDivider: some View", "Workbench must use a noninteractive visual separator")
        contains(workbench, ".accessibilityHidden(true)", "The decorative divider must not expose an adjustable accessibility target")
        doesNotContain(workbench, "DragGesture", "The fixed pair must not install a divider drag gesture")
        doesNotContain(workbench, "resizeLeftRight", "The fixed pair must not advertise a horizontal resize cursor")
        contains(workbench, "staticDivider", "The fixed pair must always render the shared static separator")
        doesNotContain(workbench, "HSplitView", "Workbench must not expose a draggable horizontal divider")
        doesNotContain(workbench, "VSplitView", "Workbench must not switch to a draggable vertical layout")
        doesNotContain(workbench, "GeometryReader", "Workbench layout must not depend on width thresholds or split-ratio measurement")
        doesNotContain(workbench, "collapseWidth", "Workbench must not vertically collapse at the 960-point desktop window floor")
        doesNotContain(workbench, "splitRatio", "Workbench state and layout must not retain adjustable ratio behavior")
        doesNotContain(workbench, "resetSplitButton", "Workbench pane headers must not expose a reset split layout button")
        contains(workbench, "IndexWorkspaceTextArea(", "Workbench input must use the semantic text surface")
        contains(workbench, "inputRenderingMode: inputRenderingMode", "Workbench must pass its explicit input renderer opt-in to the semantic text surface")
        contains(workbench, "IndexWorkspaceOutputSurface(", "Workbench output must use the semantic output surface")
        contains(workbench, "IndexSaveTextButton", "Workbench must retain the explicit HTML Markdown save component")
        contains(workbench, "IndexInputHeaderAccessory(", "Workbench input actions must reuse the responsive header accessory")
        contains(workbench, "clearDisabled: isClearDisabled", "Responsive clear must preserve the complete workspace disabled state")
        contains(workbench, "inputCaretPlacementRequestToken: Int? = nil", "Workbench must expose an explicit one-shot caret placement seam")
        contains(workbench, "IndexCopyButton(text: output, iconOnly: true)", "Workbench output pane actions must stay compact so they do not squeeze the panel title")
        contains(workbench, "IndexSaveTextButton(text: output, fileName: outputFileName, iconOnly: true, saveClient: saveClient)", "Workbench save action must stay compact in the output panel header and use the save seam")
        doesNotContain(workbench, ".onExitCommand", "Removed focus mode must not retain an Escape command")
        doesNotContain(workbench, "IndexTextConversionKeyboardMonitoring", "Removed focus mode must not retain an AppKit key monitor")
        doesNotContain(workbench, "hiddenShortcutButton", "Removed focus/save shortcuts must not remain unreachable controls")
        contains(workbench, "protocol IndexTextConversionTextSaving", "Workbench must isolate save panel and file writes behind an adapter seam")
        contains(workbench, "enum IndexTextConversionSaveContentType", "Workbench save adapter must centralize filename-to-content-type mapping")
        contains(workbench, "UTType(filenameExtension: fileExtension)", "Workbench save adapter must derive the save-panel type from the requested filename extension")
        contains(workbench, "IndexTextConversionSaveContentType.contentType(for: fileName) ?? .plainText", "Workbench save panel must preserve structured output extensions while retaining a plain-text fallback")
        doesNotContain(workbench, "panel.allowedContentTypes = [.plainText]", "Workbench save panel must not force every structured output back to a .txt filename")
        doesNotContain(workbench, "Save Focused", "Removed generic text save must not retain the hidden Cmd-S path")
        contains(converter, "IndexTextConversionWorkbench(", "Shared converter must always render the settled copy-transform workbench")
        contains(converter, "inputError: workspace.error", "Shared converter must keep retained conversion errors inside the workbench")
        contains(converter, "onClear: workspace.clear", "Shared converter must keep clear inside the input pane header")
        contains(converter, "IndexActionBar {", "Shared converter must keep mode selection in the existing action bar without a primary convert button")
        contains(converter, "workspaceSemantic: .copyTransformWorkspace", "Shared converter must own the copy-transform workspace semantic")
        contains(converter, "workspace.changeMode(to: $0, backfillModeTransition: backfillModeTransition)", "Shared converter must route mode changes through the workspace execution model")
        contains(converter, "completedRequest == IndexConverterRequest(input: input, mode: mode)", "Shared converter must only backfill a completed result for the current request identity")
        contains(converter, "if clearsFailedInput {", "A failed request must clear its invalid input instead of executing it in the next mode")
        contains(converter, "inputCaretPlacementRequestToken: workspace.inputReplacementToken == 0 ? nil : workspace.inputReplacementToken", "Successful mode backfill must request caret placement through the shared editor seam")
        contains(converter, "inputByteCount > synchronousInputByteLimit", "Shared converter must classify large requests by UTF-8 input cost")
        contains(converter, "outputProcessingText: workspace.isProcessing ? \"正在转换…\" : nil", "Shared converter must expose real processing state through the existing workbench surface")
        contains(converter, "outputPresentation: outputPresentation", "Shared converter must pass an explicit per-tool output presentation into the workbench")
        doesNotContain(converter, ".onChange(of: workspace.input) { _ in validate() }", "Shared converter must not keep a View-local duplicate validation path")
        doesNotContain(converter, "ConverterModeBackfill.currentValidOutput", "Shared converter must not re-execute the previous conversion while backfilling a mode switch")
        doesNotContain(converter, "usesTextConversionWorkbench", "Shared converter must not retain the completed workbench migration flag")
        doesNotContain(converter, "IndexConverterTriggerRhythm", "Shared converter must not wrap live validation in a single-case trigger abstraction")
        doesNotContain(converter, "IndexIOPair(", "Shared converter must not retain the legacy IO-pair branch after all callers migrated")
        doesNotContain(converter, "IndexWorkbenchControlBar", "Shared converter must not retain the unused primary-convert-button branch")
        contains(asciiBinary, "isEmptyInputForMode: Self.isEmptyInput", "ASCII/binary must preserve whitespace text in encoding modes while keeping decode whitespace quiet")
    }

    @Test func allTextConversionToolsShareFixedHorizontalLayoutWithoutRatioPreferences() throws {
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")
        let store = try readSource("Sources/XTools/AppShell/ToolPreferenceStore.swift")

        let sharedConverterPages = [
            "Sources/XTools/ToolPages/Converter/Base64StringPage.swift",
            "Sources/XTools/ToolPages/Converter/URLCoderPage.swift",
            "Sources/XTools/ToolPages/Converter/ASCIIBinaryPage.swift",
            "Sources/XTools/ToolPages/Converter/UnicodePage.swift"
        ]
        for path in sharedConverterPages {
            contains(try readSource(path), "IndexConverterPage(", "\(path) must remain in the shared fixed-horizontal converter family")
        }

        let directWorkbenchPages = [
            "Sources/XTools/ToolPages/Crypto/TextEncryptionPage.swift",
            "Sources/XTools/ToolPages/Crypto/StringObfuscatorPage.swift"
        ]
        for path in directWorkbenchPages {
            contains(try readSource(path), "IndexTextConversionWorkbench(", "\(path) must remain in the shared fixed-horizontal workbench family")
        }
        // The structured formatter family stays fixed-horizontal through the
        // prototype workbench.
        for path in [
            "Sources/XTools/ToolPages/Development/JSONFormatterPage.swift",
            "Sources/XTools/ToolPages/Development/SQLPrettifyPage.swift",
            "Sources/XTools/ToolPages/Development/XMLFormatterPage.swift",
            "Sources/XTools/ToolPages/Development/YAMLPrettifyPage.swift",
            "Sources/XTools/ToolPages/Development/DockerRunToComposePage.swift",
            "Sources/XTools/ToolPages/Development/HTMLToMarkdownPage.swift"
        ] {
            contains(try readSource(path), "IndexFormatWorkbench", "\(path) must remain in the fixed-horizontal prototype family")
        }

        doesNotContain(workbench, "@Published var state", "Workbench must not retain removed focus state")
        doesNotContain(workbench, "IndexTextConversionWorkspaceModel", "Shared transform models must not construct a focus-only workbench")
        doesNotContain(workbench, "ToolPreferenceStore", "Workbench state must not know about cross-launch preferences")
        doesNotContain(store, "workbenchSplitRatio", "The preference surface must stop exposing per-tool split ratios")
        doesNotContain(store, "workbenchToolIDs", "The preference whitelist must not retain layout-only tool IDs")
        doesNotContain(store, "splitRatio.v1", "Legacy split defaults must become unread orphan keys")
    }

    @Test func romanNumeralPageNormalizesAndBackfills() throws {
        let source = try readSource("Sources/XTools/ToolPages/Converter/RomanNumeralPage.swift")

        contains(source, "Binding(get: { workspace.mode }, set: { changeMode(to: $0) })", "Roman numeral mode control must intercept mode changes for backfill")
        contains(source, "RomanNumeralConverter.validatedRoman(fromArabic:", "Roman numeral page must strictly validate Arabic input")
        contains(source, "RomanNumeralConverter.validatedNumber(fromRoman:", "Roman numeral page must strictly validate Roman input")
        doesNotContain(source, "RomanNumeralConverter.normalizedArabicInput", "Roman numeral page must not silently remove invalid Arabic characters")
        doesNotContain(source, "RomanNumeralConverter.normalizedRomanInput", "Roman numeral page must not silently remove invalid Roman characters")
        contains(source, "ConverterModeBackfill.currentValidOutput", "Roman numeral page must reuse current valid output when switching modes")
        contains(source, "IndexClearButton(isDisabled: workspace.input.isEmpty)", "Roman numeral clear action must remain in the input panel header")
    }

    @Test func htmlToMarkdownUsesSharedTextConversionWorkbench() throws {
        let source = try readSource("Sources/XTools/ToolPages/Development/HTMLToMarkdownPage.swift")
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")
        let prototypeWorkbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexFormatWorkbench.swift")
        let nativeOutput = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexReadOnlyTextSurface.swift")
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")

        contains(source, "workspaceSemantic: .structuredEditorTransform", "HTML to Markdown must use the editor-transform semantic that resolves the compact fixed page shell")
        contains(source, "IndexFormatWorkbench(", "HTML to Markdown must use the shared prototype workbench")
        contains(source, "ToolWorkspaceHost(key: HTMLToMarkdownToolWorkspaceModel.key)", "HTML to Markdown must delegate workflow state and cancellation to its session")
        contains(source, "session.fetchURL()", "HTML URL submit and button actions must use the same session operation")
        contains(source, "IndexProgressMotionLabel(", "HTML URL processing must use the shared indeterminate action label")
        contains(controls, "ProgressView()", "The shared HTML URL action label must show an indeterminate progress indicator")
        contains(source, "正在解析…", "HTML URL processing must expose the reference-matched loading copy")
        contains(source, "outputProcessingText: session.processingText", "HTML processing phases must replace stale STDOUT with a status surface")
        contains(source, "outputPresentation: .nativeReadOnlyText", "HTML Markdown output must opt into the large-text native surface")
        contains(source, "diagnostic: session.error ?? session.warning", "HTML to Markdown diagnostics must render inside the prototype workbench toolbar")
        contains(source, "outputFileName: \"markdown-output.md\"", "HTML to Markdown save action must use a stable Markdown file name")
        contains(source, "showsOutputSave: true", "HTML to Markdown keeps its save action in the prototype toolbar")
        contains(source, "leadingControl: {", "HTML URL fetch must ride the prototype toolbar's leading control slot")
        doesNotContain(source, "onFormat:", "HTML conversion is session-owned and must not grow an explicit format action")
        doesNotContain(source, "Label(\"转换\"", "HTML URL workflow must not require a second conversion button")
        doesNotContain(source, "suppressNextInputChange", "Programmatic cleaned HTML publication must be owned by the session instead of a page-local suppression flag")
        contains(workbench, "IndexTextConversionProcessingSurface", "Workbench must provide an in-pane processing state without covering output text")
        contains(prototypeWorkbench, "IndexTextConversionProcessingSurface(text: outputProcessingText)", "The prototype workbench must reuse the shared processing surface")
        contains(prototypeWorkbench, "case .nativeReadOnlyText", "The prototype workbench must expose the native large-text output path")
        contains(nativeOutput, "NSTextView", "Native large-text output must use AppKit text storage instead of SwiftUI Text layout")
        contains(nativeOutput, "textView.isEditable = false", "Native output must remain read-only")
        contains(nativeOutput, "textView.isSelectable = true", "Native output must preserve text selection")
    }

    @Test func structuredFormatterPagesUseEditorTransformWorkbenches() throws {
        let semantics = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexWorkspaceSemantics.swift")
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")
        let sharedComponents = try readSharedBagComponents()
        let textComponents = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let json = try readSource("Sources/XTools/ToolPages/Development/JSONFormatterPage.swift")
        let xml = try readSource("Sources/XTools/ToolPages/Development/XMLFormatterPage.swift")
        let yaml = try readSource("Sources/XTools/ToolPages/Development/YAMLPrettifyPage.swift")
        let docker = try readSource("Sources/XTools/ToolPages/Development/DockerRunToComposePage.swift")
        let html = try readSource("Sources/XTools/ToolPages/Development/HTMLToMarkdownPage.swift")
        let sql = try readSource("Sources/XTools/ToolPages/Development/SQLPrettifyPage.swift")

        contains(semantics, "enum IndexWorkspaceSemantic", "Shared workspaces must expose a domain-named semantic seam")
        contains(semantics, "case structuredOutputReading", "Workspace semantics must model structured output reading")
        contains(semantics, "case structuredEditorTransform", "Workspace semantics must model structured editor-transform workbenches")
        contains(semantics, "struct IndexWorkspaceBehaviorContract", "Workspace semantics must resolve to a stable behavior contract")
        contains(semantics, "struct IndexWorkspaceResolution", "Workspace semantics must resolve page shell and surface behavior through one interface")
        contains(semantics, "let pageShell: IndexWorkspacePageShell", "Workspace resolution must own page shell selection")
        contains(semantics, "let textArea: IndexWorkspaceTextAreaContract", "Workspace resolution must own text-area growth selection")
        contains(semantics, "let scrollOwnership: IndexWorkspaceScrollOwnership", "Workspace behavior must express scroll ownership")
        contains(semantics, "let inputGrowth: IndexWorkspaceInputGrowth", "Workspace behavior must express input growth")
        contains(semantics, "let fillBehavior: IndexWorkspaceFillBehavior", "Workspace behavior must express fill behavior")
        contains(semantics, "let outputScrolling: IndexWorkspaceOutputScrolling", "Workspace behavior must express output internal scrolling")
        contains(semantics, "let longTokenWrapping: IndexWorkspaceLongTokenWrapping", "Workspace behavior must express long-token wrapping")
        contains(semantics, "let defaultSafety: IndexWorkspaceDefaultSafety", "Workspace behavior must express default safety")
        contains(sharedComponents, "var workspaceSemantic: IndexWorkspaceSemantic = .unmigratedPageDefault", "Shared IO pairs must expose workspace semantics without migrating unnamed pages by default")
        contains(sharedComponents, "workspaceSemantic.behavior", "Shared IO pairs must derive standard IO behavior through the semantic seam")
        contains(sharedComponents, "struct IndexWorkspaceTextArea: View", "Structured IO inputs must use the shared semantic text input")
        contains(sharedComponents, "expandsWithContent: resolution.textArea.expandsWithContent", "Structured IO inputs must take growth from the resolved workspace contract")
        contains(sharedComponents, "struct IndexWorkspaceOutputSurface: View", "Structured IO outputs must use the shared semantic output surface")
        contains(sharedComponents, "scrollsInternally: behavior.outputScrollsInternally", "Structured IO outputs must take internal scrolling from the workspace behavior contract")
        contains(workbench, "struct IndexTextConversionWorkbench", "Structured formatter pages must use the shared text conversion workbench foundation")
        contains(workbench, "IndexWorkspaceTextArea(", "Workbench inputs must use the semantic text surface")
        contains(workbench, "IndexWorkspaceOutputSurface(", "Workbench outputs must use the semantic output surface")
        doesNotContain(workbench, "showsResetSplitButton", "Shared workbench pane headers must not expose a reset split override")
        doesNotContain(workbench, "resetSplitButton", "Input/output pane headers must keep only focus/restore from the split action group")
        doesNotContain(workbench, "IndexTextConversionFocusMode", "The fixed pair must not retain removed focus state")
        doesNotContain(workbench, "focusedPaneFrame", "The fixed pair must not collapse panes for a removed focus mode")
        doesNotContain(workbench, "allowsHitTesting(isVisible)", "The fixed pair must not retain hidden pane hit-testing branches")
        doesNotContain(workbench, "accessibilityHidden(!isVisible)", "The fixed pair must expose both panes consistently")
        contains(workbench, "staticDivider", "The fixed pair must keep its existing static separator")
        contains(textComponents, "var expandsWithContent = false", "Text areas must separate height filling from internal scrolling")
        contains(textComponents, "var scrollsInternally = true", "Output surfaces must keep internal scrolling as the default")
        contains(textComponents, "if scrollsInternally {\n                    ScrollView {", "Output surfaces must make the scroll container conditional")

        contains(json, "workspaceSemantic: .structuredEditorTransform", "JSON formatter must use the editor-transform semantic that resolves the compact fixed page shell")
        contains(xml, "workspaceSemantic: .structuredEditorTransform", "XML formatter must use the editor-transform semantic that resolves the compact fixed page shell")
        contains(yaml, "workspaceSemantic: .structuredEditorTransform", "YAML formatter must use the editor-transform semantic that resolves the compact fixed page shell")
        contains(docker, "workspaceSemantic: .structuredEditorTransform", "Docker Run to Compose must use the editor-transform semantic that resolves the compact fixed page shell")
        contains(html, "workspaceSemantic: .structuredEditorTransform", "HTML to Markdown must use the editor-transform semantic that resolves the compact fixed page shell")
        contains(json, "workspaceSemantic: .structuredEditorTransform", "JSON formatter must select the structured editor-transform semantic")
        contains(xml, "workspaceSemantic: .structuredEditorTransform", "XML formatter must select the structured editor-transform semantic")
        contains(yaml, "workspaceSemantic: .structuredEditorTransform", "YAML formatter must select the structured editor-transform semantic")
        contains(docker, "workspaceSemantic: .structuredEditorTransform", "Docker Run to Compose must select the structured editor-transform semantic")
        contains(html, "workspaceSemantic: .structuredEditorTransform", "HTML to Markdown must select the structured editor-transform semantic")
        contains(sql, "workspaceSemantic: .structuredEditorTransform", "SQL formatter must select the structured editor-transform semantic")
        for page in [json, xml, yaml, sql, docker] {
            contains(page, "outputLineNumbers: true", "Prototype family outputs keep the structured line-number gutter")
        }
        doesNotContain(html, "outputLineNumbers: true", "Markdown prose output must not spend width on a gutter")
        contains(json, "outputColorize: outputColorizer", "JSON formatter must route highlighting through a degradable output colorizer")
        contains(xml, "outputColorize: outputColorizer", "XML formatter must route highlighting through a degradable output colorizer")
        contains(yaml, "outputColorize: outputColorizer", "YAML formatter must route highlighting through a degradable output colorizer")
        contains(sql, "outputColorize: outputColorizer", "SQL formatter must route highlighting through a degradable output colorizer")
        contains(json, "if execution.binding.output.count > Self.maxHighlightedOutputCharacters", "JSON formatter must degrade highlighting before editor behavior on large output")
        contains(xml, "if execution.binding.output.count > Self.maxHighlightedOutputCharacters", "XML formatter must degrade highlighting before editor behavior on large output")
        contains(yaml, "if execution.binding.output.count > Self.maxHighlightedOutputCharacters", "YAML formatter must degrade highlighting before editor behavior on large output")
        contains(sql, "if execution.binding.output.count > Self.maxHighlightedOutputCharacters", "SQL formatter must degrade highlighting before editor behavior on large output")
        contains(docker, "outputColorize: outputColorizer", "Docker Run to Compose must route highlighting through a degradable output colorizer")
        contains(docker, "if execution.binding.output.count > Self.maxHighlightedOutputCharacters", "Docker Run to Compose must degrade highlighting before editor behavior on large output")
        for page in [json, xml, yaml, docker, sql] {
            doesNotContain(page, "outputFileName:", "Copy-only formatter pages must not retain unreachable text-save filenames")
        }
        contains(html, "outputFileName: \"markdown-output.md\"", "HTML to Markdown save action must use a stable Markdown file name")

        // The whole structured formatter family rides the prototype v3
        // single-panel workbench.
        let formatWorkbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexFormatWorkbench.swift")
        for page in [json, xml, yaml, docker, html, sql] {
            contains(page, "IndexFormatWorkbench", "Structured formatter pages must use the shared prototype workbench")
            doesNotContain(page, "IndexTextConversionWorkbench(", "Structured formatter pages must not keep the two-panel conversion workbench")
            doesNotContain(page, "showsResetSplitButton", "Structured formatter pages must rely on the fixed shared pane layout")
            doesNotContain(page, "IndexIOPair(", "Structured formatter pages must not keep the old shared IO pair after workbench migration")
        }
        contains(json, "workspaceSemantic: .structuredEditorTransform", "JSON formatter must express editor-transform behavior through the semantic seam")
        contains(formatWorkbench, "struct IndexFormatWorkbench", "The prototype workbench must be a shared component")
        contains(formatWorkbench, "embedsFlat: false", "Workbench panes must use carded editor surfaces")
        contains(formatWorkbench, "IndexBadge(\"STDIN\", tone: .accent, isCapsule: true)", "The workbench toolbar must carry the STDIN identity")
        contains(formatWorkbench, "IndexBadge(\"STDOUT\", tone: .accent, isCapsule: true)", "The workbench toolbar must carry the STDOUT identity")
        contains(formatWorkbench, "IndexPrimaryActionButton(title: actionTitle, hint: actionHint", "The primary format action must be the shared prototype button")
        contains(formatWorkbench, ".keyboardShortcut(.return, modifiers: .command)", "Format must be reachable through Command-Return")
        contains(formatWorkbench, ".toolErrorShake(trigger: errorShakeTrigger)", "A failed format must shake through the shared bounded shake")

        contains(formatWorkbench, "IndexWorkspaceTextArea(", "Workbench inputs must use the semantic text surface")
        contains(formatWorkbench, "var onFormat: (() -> Void)? = nil", "The prototype workbench must let session-owned converters (HTML) hide the primary action")
        doesNotContain(sql, "SQLFormatterEditorPair", "SQL formatter must not keep a page-local editor pair after workbench migration")
    }

    @Test func structuredFormatterTopControlsStayInPlace() throws {
        let json = try readSource("Sources/XTools/ToolPages/Development/JSONFormatterPage.swift")
        let sql = try readSource("Sources/XTools/ToolPages/Development/SQLPrettifyPage.swift")

        // Prototype v3: JSON owns one toolbar inside the workbench — no page
        // action bar, no key-sort switch; the indent control rides the toolbar.
        appearsBefore(json, "IndexPage(", "IndexFormatWorkbench(", "JSON formatter body must be the prototype workbench")
        contains(json, "IndexSegmentedControl(", "JSON indent must stay in the workbench toolbar")
        doesNotContain(json, "IndexActionBar {", "JSON must not keep a page-level action bar")
        contains(json, "IndexOptionSwitch(title: \"Key 排序\"", "JSON must provide the key-sort option in the workbench toolbar")
        doesNotContain(json, "IndexOptionPicker(", "JSON indent must use the toolbar segmented control")
        doesNotContain(json, "statsStrip", "JSON formatter must not keep the retired statistics strip")
        contains(json, "IndexPage(\"JSON 格式化\", subtitle: \"格式化、压缩和验证 JSON，支持自定义选项。\", workspaceSemantic: .structuredEditorTransform)", "JSON formatter must let the semantic resolve the compact fixed workbench page shell")
        contains(json, "execution.schedule(snapshot: snapshot, delay: .zero)", "Formatting must be explicit and still submit an immutable snapshot")
        doesNotContain(json, "workspace.seedEntryExampleIfNeeded()", "JSON must start with clean placeholder rather than seeding sample text")
        contains(json, "formatAttempt += 1", "Each format attempt must advance the shake generation")

        appearsBefore(sql, "IndexPage(", "IndexFormatWorkbench(", "SQL formatter body must be the prototype workbench")
        doesNotContain(sql, "IndexOptionLabel(\"关键字\")", "SQL formatter toolbar must keep keyword case control compact without a redundant label")
        contains(sql, "items: [(\"upper\", \"大写\"), (\"lower\", \"小写\")]", "SQL keyword-case must use the toolbar segmented control")
        contains(sql, "leadingControl: {", "SQL keyword-case controls must ride the workbench toolbar's leading slot")
        doesNotContain(sql, "IndexActionBar {", "SQL must not keep a page-level action bar")
        contains(sql, "execution.schedule(snapshot: snapshot, delay: .zero)", "SQL formatting must be explicit and still submit an immutable snapshot")
        contains(sql, "formatAttempt += 1", "Each SQL format attempt must advance the shake generation")
        contains(sql, "outputLineNumbers: true", "SQL formatter must keep syntax highlighting with a line-number gutter")
        contains(sql, "outputColorize: outputColorizer", "SQL formatter must keep structured output highlighting")
        contains(sql, "IndexPage(\"SQL 格式化\", subtitle: \"格式化 SQL，支持关键字大小写和基础校验。缩进固定2空格，逗号固定行尾。\", workspaceSemantic: .structuredEditorTransform)", "SQL formatter must let the semantic resolve the compact fixed workbench page shell")
        contains(sql, "workspaceSemantic: .structuredEditorTransform", "SQL formatter must express editor-transform behavior through the semantic seam")
        doesNotContain(sql, "expandsWithContent: true", "SQL formatter must not hand-assemble input growth for editor-transform behavior")
        doesNotContain(sql, "scrollsInternally: false", "SQL formatter must not hand-assemble output scrolling for editor-transform behavior")
        doesNotContain(sql, "IndexPairLayout(collapseWidth: 0, fillsHeight: true)", "SQL formatter must not keep the old page-local side-by-side pair")
    }

    @Test func copyTransformPagesKeepFixedInternalScrollAndWrapping() throws {
        let converter = try readSource("Sources/XTools/ToolPages/Workbench/Converter/IndexConverterPage.swift")
        let sharedComponents = try readSharedBagComponents()
        let textComponents = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let url = try readSource("Sources/XTools/ToolPages/Converter/URLCoderPage.swift")
        let base64 = try readSource("Sources/XTools/ToolPages/Converter/Base64StringPage.swift")
        let asciiBinary = try readSource("Sources/XTools/ToolPages/Converter/ASCIIBinaryPage.swift")
        let unicode = try readSource("Sources/XTools/ToolPages/Converter/UnicodePage.swift")
        let textStats = try readSource("Sources/XTools/ToolPages/Utility/TextStatisticsPage.swift")

        contains(converter, "IndexPage(title, subtitle: subtitle, workspaceSemantic: .copyTransformWorkspace)", "Shared converter must resolve page layout and chrome through the copy-transform semantic")
        contains(converter, "workspaceSemantic: .copyTransformWorkspace", "Shared converter must pass the same semantic into the text workbench")
        doesNotContain(converter, "layout: IndexPageLayout? = nil", "Shared converter must not retain unused explicit page-layout overrides")
        doesNotContain(converter, "chrome: IndexPageChrome? = nil", "Shared converter must not retain unused explicit page-chrome overrides")
        doesNotContain(converter, "workspaceSemantic: IndexWorkspaceSemantic", "Shared converter must own rather than expose its settled workspace semantic")
        contains(converter, "initialMode: String? = nil", "Shared text converter pages must support an explicit per-tool initial mode without changing existing callers")
        contains(converter, "Self.resolvedInitialMode(requested: initialMode, modes: modes)", "Shared text converter pages must validate requested initial modes and fall back safely")
        contains(sharedComponents, "var workspaceSemantic: IndexWorkspaceSemantic = .unmigratedPageDefault", "Shared IO pairs must keep unmigrated internal scrolling as the default")
        contains(sharedComponents, "var maxHeightRatio: CGFloat? = nil", "Semantic text areas must be able to express bounded mixed-workflow editors")
        contains(sharedComponents, "maxHeightRatio: maxHeightRatio", "Semantic text areas must pass bounded editor height through to the AppKit text area")
        contains(sharedComponents, "IndexWorkspaceTextArea(\n                    placeholder: placeholder,\n                    text: $input,\n                    fillsHeight: true,\n                    autoFocus: autoFocus,\n                    workspaceSemantic: workspaceSemantic", "Copy-transform inputs must stay fixed while wrapping according to the workspace contract")
        contains(sharedComponents, ".indexWorkspaceDiagnostic(inputError, tone: .error)", "Copy-transform input errors must stay attached to the input surface without covering editor text")
        contains(sharedComponents, "IndexWorkspaceOutputSurface(\n                    text: output,\n                    placeholder: IndexEmptyStateCopy.outputWillShowHere,\n                    fillsHeight: true,\n                    lineNumbers: outputLineNumbers,\n                    colorize: outputColorize,\n                    workspaceSemantic: workspaceSemantic", "Copy-transform outputs must scroll internally and wrap according to the workspace contract")
        contains(textComponents, "var lineBreakMode: NSLineBreakMode = .byCharWrapping", "Output surfaces must wrap long tokens by default while still allowing caller overrides")
        contains(textComponents, "Text(indexWrappingAttributedText(text, lineBreakMode: lineBreakMode))", "Plain output must apply explicit wrapping without changing copied text")
        contains(textComponents, "Text(indexWrappingAttributedText(line.isEmpty ? AttributedString(\" \") : colorize(line), lineBreakMode: lineBreakMode))", "Line-numbered colored output must preserve syntax highlighting while applying wrapping")
        contains(textComponents, "else if let colorize {\n            colorizedBody(colorize)", "Syntax-colored output must have a non-gutter rendering path")
        contains(textComponents, "private func colorizedBody(_ colorize: @escaping (String) -> AttributedString)", "The syntax-only output path must preserve dedicated colorized rendering without line numbers")
        contains(textComponents, "Text(indexWrappingAttributedText(combined, lineBreakMode: lineBreakMode))", "Syntax-only colorize path must render one Text from a combined AttributedString")
        doesNotContain(
            sourceSlice(textComponents, from: "private func colorizedBody(_ colorize: @escaping (String) -> AttributedString)", to: "private var gutteredBody"),
            "ForEach(Array(lines.enumerated())",
            "Syntax-only colorize path must not create one SwiftUI Text per line"
        )
        contains(textComponents, "textView.scrollRangeToVisible(clampedSelectedRange(for: textView))", "Fixed internal editors must reveal the current insertion point after large paste/edit operations")
        contains(textComponents, "guard !growsWithContent else { return }", "Insertion-point reveal must not interfere with naturally growing text areas")
        contains(
            sourceSlice(textComponents, from: "func measure(_ textView: NSTextView)", to: "private func configureUndoManager()"),
            "guard growsWithContent else { return }",
            "Fixed-height measured text areas must skip full-document height measurement"
        )
        contains(
            sourceSlice(textComponents, from: "func measure(_ textView: NSTextView)", to: "private func configureUndoManager()"),
            "IndexTextKitGeometry.measuredTextHeight(for: textView)",
            "Content-growing measured text areas must still compute document height"
        )
        doesNotContain(textComponents, "ScrollViewReader", "Output surfaces must not add programmatic scroll-to-bottom behavior")
        doesNotContain(textComponents, ".defaultScrollAnchor(.bottom)", "Output surfaces must not default generated output to the bottom")

        doesNotContain(url, "layout: .fill", "URL coder must not hand-assemble the fixed copy-transform page shell")
        doesNotContain(base64, "layout: .fill", "Base64 string converter must not hand-assemble the fixed copy-transform page shell")
        doesNotContain(asciiBinary, "layout: .fill", "ASCII/binary converter must not hand-assemble the fixed copy-transform page shell")
        doesNotContain(unicode, "layout: .fill", "Unicode converter must not hand-assemble the fixed copy-transform page shell")
        doesNotContain(url, "chrome: .compactWorkspace", "URL coder must not hand-assemble compact chrome")
        doesNotContain(base64, "chrome: .compactWorkspace", "Base64 string converter must not hand-assemble compact chrome")
        doesNotContain(asciiBinary, "chrome: .compactWorkspace", "ASCII/binary converter must not hand-assemble compact chrome")
        doesNotContain(unicode, "chrome: .compactWorkspace", "Unicode converter must not hand-assemble compact chrome")
        for page in [url, base64, asciiBinary, unicode] {
            doesNotContain(page, "workspaceSemantic:", "Copy-transform callers must not repeat the semantic owned by the shared module")
            doesNotContain(page, "usesTextConversionWorkbench:", "Copy-transform callers must not retain the completed migration flag")
            doesNotContain(page, "showsConvertButton:", "Copy-transform callers must not repeat the settled no-primary-button behavior")
        }
        doesNotContain(url, "outputFileName:", "URL coder must not retain an unreachable generic text-save filename")
        doesNotContain(base64, "outputFileName:", "Base64 string must not retain an unreachable generic text-save filename")
        contains(base64, "initialMode: \"dec\"", "Base64 string must open in the user-approved decode mode")
        doesNotContain(url, "initialMode:", "URL coder must keep its existing encode-first default")
        doesNotContain(asciiBinary, "initialMode:", "ASCII/binary must keep its existing text-to-binary default")
        doesNotContain(unicode, "initialMode:", "Unicode converter must keep its existing text-to-Unicode default")
        doesNotContain(asciiBinary, "outputFileName:", "ASCII/binary must not retain an unreachable generic text-save filename")
        doesNotContain(unicode, "outputFileName:", "Unicode must not retain an unreachable generic text-save filename")

        appearsBefore(url, "subtitle:", "modes: [", "URL coder must keep the same converter page structure and mode order")
        appearsBefore(base64, "subtitle:", "modes: [", "Base64 converter must keep the same converter page structure and mode order")
        appearsBefore(asciiBinary, "subtitle:", "modes: [", "ASCII/binary converter must keep the same converter page structure and mode order")
        appearsBefore(unicode, "subtitle:", "modes: [", "Unicode converter must keep the same converter page structure and mode order")
        contains(textStats, "IndexWorkspaceTextArea(\n                    placeholder: \"粘贴文本，实时统计…\",\n                    text: $workspace.text,\n                    minHeight: 160,\n                    fillsHeight: true,\n                    autoFocus: true,\n                    workspaceSemantic: .fixedInputWorkspace\n                )", "Text statistics must express its fixed internally scrolling input through the fixed-input workspace semantic")
    }

    @Test func largeStringMaskingOptsIntoViewportInputAndTextKit2Output() throws {
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")
        let stringObfuscator = try readSource("Sources/XTools/ToolPages/Crypto/StringObfuscatorPage.swift")
        let nativeOutput = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexReadOnlyTextSurface.swift")

        contains(stringObfuscator, "inputRenderingMode: .textKit2Viewport", "Large string masking input must explicitly use the shared TextKit 2 viewport")
        contains(stringObfuscator, "inputCountPresentation: .charactersOrUTF8Size(", "Large string masking must avoid a main-actor grapheme scan while retaining exact short-input counts")
        contains(stringObfuscator, "outputPresentation: workspace.usesNativeOutput ? .nativeReadOnlyText : .standard", "String masking must keep the existing short/native output split")
        contains(workbench, "var inputCountPresentation: IndexInputCountPresentation = .characters", "Ordinary workbench callers must retain exact character counts by default")
        contains(workbench, "inputCountPresentation.label(for: input)", "The workbench must evaluate its selected input metric only once per header update")
        doesNotContain(workbench, "count: input.count", "The workbench must not eagerly scan the input when a large-text metric is selected")
        contains(workbench, "case .nativeReadOnlyText", "The workbench must retain a dedicated native large-output presentation")
        contains(nativeOutput, "NSTextView(usingTextLayoutManager: true)", "Native large-text output must initialize TextKit 2 explicitly")
        contains(nativeOutput, "precondition(textView.textLayoutManager != nil)", "Native large-text output must verify that TextKit 2 remains active")
        doesNotContain(nativeOutput, "textView.layoutManager", "Native large-text output must not request the legacy layout manager")
        doesNotContain(nativeOutput, "ensureLayout(for:", "Native large-text output must not force full-document layout")
        doesNotContain(nativeOutput, "usedRect(for:", "Native large-text output must not measure full document geometry")
    }

    @Test func largeTextInputCountKeepsShortGraphemesAndBoundsLargeWork() {
        let presentation = IndexInputCountPresentation.charactersOrUTF8Size(
            largeTextByteLimit: 5
        )

        #expect(presentation.label(for: "A😀") == "2 字符")
        #expect(presentation.label(for: "abcdef") == "6 B UTF-8")
        #expect(IndexInputCountPresentation.characters.label(for: "👩🏽‍💻") == "1 字符")
    }

    @Test @MainActor func caretTextViewConformsToAsymmetricSurfaceAndEliminatesTrailingDeadZone() {
        let textView = IndexCaretTextView(frame: NSRect(x: 0, y: 0, width: 350, height: 200))
        #expect((textView as AnyObject) is IndexAsymmetricTextContainerSurface, "IndexCaretTextView must conform to IndexAsymmetricTextContainerSurface")

        // 1. With line numbers (gutter 44 + padding 13 = 57 inset)
        textView.textContainerInset = NSSize(width: IndexEditorLineNumberGutter.width + 13, height: 12)
        textView.textContainer?.lineFragmentPadding = 0

        IndexTextKitGeometry.synchronizeTextGeometry(
            for: textView,
            visibleWidth: 350,
            minimumHeight: 200,
            trailingReadingGuard: IndexTextKitGeometry.trailingWrapGuard
        )

        let rightMarginGutter = textView.bounds.width - (textView.textContainerOrigin.x + (textView.textContainer?.containerSize.width ?? 0))
        #expect(rightMarginGutter == IndexTextKitGeometry.trailingWrapGuard, "Gutter-backed editors must eliminate the 57pt dead zone and leave exactly trailingWrapGuard margin")

        // 2. Without line numbers (13 inset)
        textView.textContainerInset = NSSize(width: 13, height: 12)

        IndexTextKitGeometry.synchronizeTextGeometry(
            for: textView,
            visibleWidth: 350,
            minimumHeight: 200,
            trailingReadingGuard: IndexTextKitGeometry.trailingWrapGuard
        )

        let rightMarginPlain = textView.bounds.width - (textView.textContainerOrigin.x + (textView.textContainer?.containerSize.width ?? 0))
        #expect(rightMarginPlain == IndexTextKitGeometry.trailingWrapGuard, "Plain editors must also leave exactly trailingWrapGuard margin")
    }
}
