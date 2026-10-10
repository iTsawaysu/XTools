import Foundation
import AppKit
@testable import XTools
import Testing

/// Symbol-level and structural contracts for the shared text workbench family.
///
/// Anchors assert component existence, workspace semantics, and forbidden
/// regressions (removed focus modes, legacy IO pairs, split ratios, copy-only
/// pages leaking save actions). Multi-line indentation-sensitive needles and
/// copy/value-duplicate anchors were retired.
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
        doesNotContain(integerBase, ".onChange(of: workspace.input)", "Input changes must be owned by the workspace model rather than a second View validation path")
        doesNotContain(integerBase, "private func validate()", "Base converter must not retain a duplicate full-conversion validation path")
    }

    @Test func formatterAndDockerInputsDelegateToThePrototypeWorkbench() throws {
        let sql = try readSource("Sources/XTools/ToolPages/Development/SQLPrettifyPage.swift")
        let shared = try readSharedBagComponents()

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
        contains(shared, "struct IndexInputCountLabel", "Shared components must define the input character count label")
    }

    @Test func formatterErrorsUseInputPanelWorkspaceDiagnostics() throws {
        let json = try readSource("Sources/XTools/ToolPages/Development/JSONFormatterPage.swift")
        let docker = try readSource("Sources/XTools/ToolPages/Development/DockerRunToComposePage.swift")
        let shared = try readSharedBagComponents()
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")

        contains(shared, "struct IndexWorkspaceDiagnostic: View", "Shared components must provide a persistent non-displacing diagnostic")
        contains(shared, "struct IndexWorkspaceDiagnosticRegion", "Shared components must provide a safe diagnostic region outside editor text")
        contains(workbench, "var inputError: String? = nil", "Shared text conversion workbench must accept an optional input-panel error")
        contains(workbench, "IndexDiagnosticStatusSlot(isActive: hasDiagnostic)", "Shared text conversion workbench must attach errors and warnings through the shared status slot")
        contains(json, "diagnostic: execution.binding.error ?? execution.binding.warning", "JSON formatter diagnostics must render inside the prototype workbench toolbar")
        contains(docker, "diagnostic: execution.binding.error ?? execution.binding.warning", "Docker diagnostics must render inside the prototype workbench toolbar")
        for (name, fileName) in [("XML", "XMLFormatterPage"), ("YAML", "YAMLPrettifyPage"), ("SQL", "SQLPrettifyPage")] {
            let source = try readSource("Sources/XTools/ToolPages/Development/\(fileName).swift")
            contains(source, "diagnostic: execution.binding.error", "\(name) formatter errors must render inside the prototype workbench toolbar")
            doesNotContain(source, ".indexFloatingError(error)", "\(name) formatter errors must not use the old floating-error API")
        }
        doesNotContain(workbench, "IndexInputErrorLine(", "Workbench errors must not use an inline row that resizes the panel")
        doesNotContain(json, ".indexFloatingError(error)", "JSON formatter errors must not use the old floating-error API")
        doesNotContain(docker, ".indexFloatingError(error)", "Docker errors must not use the old floating-error API")
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
            "Sources/XTools/ToolPages/Development/DiffHubPage.swift",
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

    @Test func diffHubShellCarriesSegmentedDiffWorkbenches() throws {
        let diffHub = try readSource("Sources/XTools/ToolPages/Development/DiffHubPage.swift")
        let jsonDiff = try readSource("Sources/XTools/ToolPages/Development/JSONDiffPage.swift")
        let textDiff = try readSource("Sources/XTools/ToolPages/Development/TextDiffPage.swift")

        // JSON 与文本对比合并为单入口「对比」后，IndexPage 页面壳统一
        // 上移到共享 HubSegmentPage 骨架；两分段只保留各自的对比工作台。
        contains(diffHub, "HubSegmentPage(", "Diff hub must compose the shared hub segment skeleton")
        contains(diffHub, "IndexJSONDiffSegment()", "Diff hub must mount the JSON diff segment")
        contains(diffHub, "IndexTextDiffSegment()", "Diff hub must mount the text diff segment")
        contains(diffHub, "workspaceSemantic: .editableDiffWorkspace", "Diff hub must let the semantic resolve the editable diff workspace page shell")
        for segment in [jsonDiff, textDiff] {
            contains(segment, "IndexEditableDiffWorkspace(", "Diff segments must keep delegating their panes to the shared diff workbench")
            doesNotContain(segment, "IndexPage(", "Diff segments must not nest a second page shell inside the hub")
        }
    }

    @Test func generatorHubShellCarriesSegmentedGeneratorWorkbenches() throws {
        let hub = try readSource("Sources/XTools/ToolPages/Crypto/GeneratorHubPage.swift")
        let token = try readSource("Sources/XTools/ToolPages/Crypto/TokenGeneratorPage.swift")
        let uuid = try readSource("Sources/XTools/ToolPages/Crypto/UUIDGeneratorPage.swift")
        let password = try readSource("Sources/XTools/ToolPages/Crypto/PasswordGeneratorPage.swift")

        // Token/UUID/密码生成器合并为单入口「生成器」后，IndexPage 页面壳统一
        // 上移到共享 HubSegmentPage 骨架；三分段只保留各自的生成工作台。
        contains(hub, "HubSegmentPage(", "Generator hub must compose the shared hub segment skeleton")
        contains(hub, "IndexTokenGeneratorSegment()", "Generator hub must mount the token segment")
        contains(hub, "IndexUUIDGeneratorSegment()", "Generator hub must mount the UUID segment")
        contains(hub, "IndexPasswordGeneratorSegment()", "Generator hub must mount the password segment")
        contains(hub, "workspaceSemantic: .queryListWorkspace", "Generator hub must let the semantic resolve the query-list workspace page shell")
        for segment in [token, uuid, password] {
            contains(segment, "IndexGeneratedValueRowList(", "Generator segments must keep delegating their results to the shared value row list")
            doesNotContain(segment, "IndexPage(", "Generator segments must not nest a second page shell inside the hub")
        }
    }

    @Test func imageHubShellCarriesSegmentedImageWorkbenches() throws {
        let hub = try readSource("Sources/XTools/ToolPages/Image/ImageHubPage.swift")
        let converter = try readSource("Sources/XTools/ToolPages/Image/ImageConverterPage.swift")
        let compressor = try readSource("Sources/XTools/ToolPages/Image/ImageCompressorPage.swift")
        let grayscale = try readSource("Sources/XTools/ToolPages/Image/ImageGrayscalePage.swift")
        let watermark = try readSource("Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift")
        let favicon = try readSource("Sources/XTools/ToolPages/Image/FaviconGeneratorPage.swift")

        // 格式转换/压缩/灰度/水印/Favicon 合并为单入口「图片处理」后，IndexPage 页面壳统一
        // 上移到共享 HubSegmentPage 骨架；五分段只保留各自的图片工作台（会话仍按 slot 独立保活）。
        contains(hub, "HubSegmentPage(", "Image hub must compose the shared hub segment skeleton")
        contains(hub, "IndexImageConverterSegment()", "Image hub must mount the converter segment")
        contains(hub, "IndexImageCompressorSegment()", "Image hub must mount the compressor segment")
        contains(hub, "IndexImageGrayscaleSegment()", "Image hub must mount the grayscale segment")
        contains(hub, "IndexImageWatermarkSegment()", "Image hub must mount the watermark segment")
        contains(hub, "IndexImageFaviconSegment()", "Image hub must mount the favicon segment")
        contains(hub, "workspaceSemantic: .imagePreviewStage", "Image hub must let the semantic resolve the image preview stage page shell")
        for segment in [converter, compressor, grayscale, watermark, favicon] {
            contains(segment, "ToolWorkspaceHost(key:", "Image segments must keep resolving their repository-retained workspace sessions")
            doesNotContain(segment, "IndexPage(", "Image segments must not nest a second page shell inside the hub")
        }
    }

    @Test func encodingHubShellCarriesSegmentedConverterWorkbenches() throws {
        let hub = try readSource("Sources/XTools/ToolPages/Converter/EncodingHubPage.swift")
        let base64 = try readSource("Sources/XTools/ToolPages/Converter/Base64StringPage.swift")
        let url = try readSource("Sources/XTools/ToolPages/Converter/URLCoderPage.swift")
        let asciiBinary = try readSource("Sources/XTools/ToolPages/Converter/ASCIIBinaryPage.swift")
        let unicode = try readSource("Sources/XTools/ToolPages/Converter/UnicodePage.swift")

        // Base64/URL/ASCII/Unicode 合并为单入口「文本编码」后，IndexPage 页面壳
        // 统一上移到共享 HubSegmentPage 骨架；四分段经 IndexConverterPage(embedsPageShell: false)
        // 只保留各自的转换工作台（会话仍按合并前四页的 key 保活）。
        contains(hub, "HubSegmentPage(", "Encoding hub must compose the shared hub segment skeleton")
        contains(hub, "IndexBase64StringSegment()", "Encoding hub must mount the Base64 segment")
        contains(hub, "IndexURLCoderSegment()", "Encoding hub must mount the URL coder segment")
        contains(hub, "IndexASCIIBinarySegment()", "Encoding hub must mount the ASCII/binary segment")
        contains(hub, "IndexUnicodeSegment()", "Encoding hub must mount the Unicode segment")
        contains(hub, "workspaceSemantic: .copyTransformWorkspace", "Encoding hub must let the semantic resolve the copy-transform workspace page shell")
        for segment in [base64, url, asciiBinary, unicode] {
            contains(segment, "IndexConverterPage(", "Encoding segments must keep delegating their panes to the shared converter workbench")
            doesNotContain(segment, "IndexPage(", "Encoding segments must not nest a second page shell inside the hub")
        }
    }

    @Test func urlCoderReusesAutomaticConverterShell() throws {
        let source = try readSource("Sources/XTools/ToolPages/Converter/URLCoderPage.swift")

        contains(source, "IndexConverterPage(", "URL coder must keep using the shared copy-transform module")
        #expect(source.components(separatedBy: "IndexConverterMode(").count - 1 == 2, "URL coder must keep exactly the encode and decode modes")
        contains(source, "backfillsOutputOnModeChange: true", "URL coder must backfill the current valid output when switching direction")
        doesNotContain(source, "showsConvertButton:", "URL coder must inherit the settled no-primary-button behavior")
        doesNotContain(source, "usesTextConversionWorkbench:", "URL coder must not retain the completed workbench migration flag")
        doesNotContain(source, "outputFileName:", "URL coder must not retain an unreachable generic text-save filename")
    }

    @Test func unicodeAndAsciiBinaryUseRoundTripBackfillContracts() throws {
        let asciiBinary = try readSource("Sources/XTools/ToolPages/Converter/ASCIIBinaryPage.swift")
        let unicode = try readSource("Sources/XTools/ToolPages/Converter/UnicodePage.swift")

        contains(unicode, "backfillsOutputOnModeChange: true", "Unicode conversion must backfill the current valid output when switching direction")

        contains(asciiBinary, "IndexConverterMode(id: \"bin\"", "ASCII/binary must keep an explicit text-to-binary mode")
        contains(asciiBinary, "IndexConverterMode(id: \"debin\"", "ASCII/binary must expose the binary inverse mode")
        contains(asciiBinary, "backfillModeTransition: { currentMode, newMode in", "ASCII/binary must use pair-aware backfill instead of global all-mode backfill")
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

        contains(workbench, "struct IndexTextConversionWorkbench", "Shared text conversion workbench must be a named foundation")
        contains(workbench, "var outputProcessingText: String? = nil", "Shared workbench must expose a stable output processing surface")
        contains(workbench, "IndexTextConversionProcessingSurface(text: outputProcessingText)", "Shared workbench must replace mismatched output with real processing status")
        contains(workbench, "var inputRenderingMode: IndexTextAreaRenderingMode? = nil", "Shared workbench must expose a narrow opt-in input renderer without changing unnamed callers")
        contains(workbench, "staticDivider", "The fixed pair must always render the shared static separator")
        contains(workbench, "IndexWorkspaceTextArea(", "Workbench input must use the semantic text surface")
        contains(workbench, "IndexWorkspaceOutputSurface(", "Workbench output must use the semantic output surface")
        contains(workbench, "protocol IndexTextConversionTextSaving", "Workbench must isolate save panel and file writes behind an adapter seam")
        contains(workbench, "enum IndexTextConversionSaveContentType", "Workbench save adapter must centralize filename-to-content-type mapping")
        contains(workbench, "UTType(filenameExtension: fileExtension)", "Workbench save adapter must derive the save-panel type from the requested filename extension")
        doesNotContain(workbench, "panel.allowedContentTypes = [.plainText]", "Workbench save panel must not force every structured output back to a .txt filename")

        doesNotContain(workbench, "IndexTextConversionWorkbenchState", "Workbench must not retain removed focus state")
        doesNotContain(workbench, "retainedState:", "Workbench must not retain removed focus state bindings")
        doesNotContain(workbench, "DragGesture", "The fixed pair must not install a divider drag gesture")
        doesNotContain(workbench, "HSplitView", "Workbench must not expose a draggable horizontal divider")
        doesNotContain(workbench, "VSplitView", "Workbench must not switch to a draggable vertical layout")
        doesNotContain(workbench, "GeometryReader", "Workbench layout must not depend on width thresholds or split-ratio measurement")
        doesNotContain(workbench, "splitRatio", "Workbench state and layout must not retain adjustable ratio behavior")
        doesNotContain(workbench, ".onExitCommand", "Removed focus mode must not retain an Escape command")
        doesNotContain(workbench, "IndexTextConversionKeyboardMonitoring", "Removed focus mode must not retain an AppKit key monitor")
        doesNotContain(workbench, "hiddenShortcutButton", "Removed focus/save shortcuts must not remain unreachable controls")
        doesNotContain(workbench, "Save Focused", "Removed generic text save must not retain the hidden Cmd-S path")

        contains(converter, "IndexFormatWorkbench(", "Shared converter must render the unified prototype workbench (same component as the formatter family)")
        contains(converter, "diagnostic: workspace.error", "Shared converter must keep retained conversion errors inside the workbench diagnostic slot")
        contains(converter, "workspaceSemantic: .copyTransformWorkspace", "Shared converter must own the copy-transform workspace semantic")
        contains(converter, "workspace.changeMode(to: $0, backfillModeTransition: backfillModeTransition)", "Shared converter must route mode changes through the workspace execution model")
        doesNotContain(converter, "IndexActionBar {", "Shared converter must not keep a page-level action bar; mode selection rides the workbench toolbar")
        doesNotContain(converter, "IndexIOPair(", "Shared converter must not retain the legacy IO-pair branch after all callers migrated")
        doesNotContain(converter, "IndexWorkbenchControlBar", "Shared converter must not retain the unused primary-convert-button branch")
        doesNotContain(converter, "usesTextConversionWorkbench", "Shared converter must not retain the completed workbench migration flag")
    }

    @Test func allTextConversionToolsShareFixedHorizontalLayoutWithoutRatioPreferences() throws {
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")
        let store = try readSource("Sources/XTools/Shared/ToolPreferenceStore.swift")

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
    }

    @Test func romanNumeralPageNormalizesAndBackfills() throws {
        let source = try readSource("Sources/XTools/ToolPages/Converter/RomanNumeralPage.swift")

        contains(source, "Binding(get: { workspace.mode }, set: { changeMode(to: $0) })", "Roman numeral mode control must intercept mode changes for backfill")
        contains(source, "RomanNumeralConverter.validatedRoman(fromArabic:", "Roman numeral page must strictly validate Arabic input")
        contains(source, "RomanNumeralConverter.validatedNumber(fromRoman:", "Roman numeral page must strictly validate Roman input")
        doesNotContain(source, "RomanNumeralConverter.normalizedArabicInput", "Roman numeral page must not silently remove invalid Arabic characters")
        doesNotContain(source, "RomanNumeralConverter.normalizedRomanInput", "Roman numeral page must not silently remove invalid Roman characters")
        contains(source, "ConverterModeBackfill.currentValidOutput", "Roman numeral page must reuse current valid output when switching modes")
        contains(source, "IndexClearButton(", "Roman numeral clear action must remain in the input panel header")
    }

    @Test func htmlToMarkdownUsesSharedTextConversionWorkbench() throws {
        let source = try readSource("Sources/XTools/ToolPages/Development/HTMLToMarkdownPage.swift")
        let nativeOutput = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexReadOnlyTextSurface.swift")

        contains(source, "workspaceSemantic: .structuredEditorTransform", "HTML to Markdown must use the editor-transform semantic that resolves the compact fixed page shell")
        contains(source, "IndexFormatWorkbench(", "HTML to Markdown must use the shared prototype workbench")
        contains(source, "ToolWorkspaceHost(key: HTMLToMarkdownToolWorkspaceModel.key)", "HTML to Markdown must delegate workflow state and cancellation to its session")
        contains(source, "session.fetchURL()", "HTML URL submit and button actions must use the same session operation")
        contains(source, "IndexProgressMotionLabel(", "HTML URL processing must use the shared indeterminate action label")
        contains(source, "outputFileName: \"markdown-output.md\"", "HTML to Markdown save action must use a stable Markdown file name")
        contains(source, "showsOutputSave: true", "HTML to Markdown keeps its save action in the prototype toolbar")
        doesNotContain(source, "onFormat:", "HTML conversion is session-owned and must not grow an explicit format action")
        doesNotContain(source, "suppressNextInputChange", "Programmatic cleaned HTML publication must be owned by the session instead of a page-local suppression flag")
        contains(nativeOutput, "NSTextView", "Native large-text output must use AppKit text storage instead of SwiftUI Text layout")
        contains(nativeOutput, "textView.isEditable = false", "Native output must remain read-only")
        contains(nativeOutput, "textView.isSelectable = true", "Native output must preserve text selection")
    }

    @Test func structuredFormatterPagesUseEditorTransformWorkbenches() throws {
        let semantics = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexWorkspaceSemantics.swift")
        let sharedComponents = try readSharedBagComponents()
        let textComponents = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let outputSurface = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexOutputSurface.swift")
        let json = try readSource("Sources/XTools/ToolPages/Development/JSONFormatterPage.swift")
        let xml = try readSource("Sources/XTools/ToolPages/Development/XMLFormatterPage.swift")
        let yaml = try readSource("Sources/XTools/ToolPages/Development/YAMLPrettifyPage.swift")
        let docker = try readSource("Sources/XTools/ToolPages/Development/DockerRunToComposePage.swift")
        let html = try readSource("Sources/XTools/ToolPages/Development/HTMLToMarkdownPage.swift")
        let sql = try readSource("Sources/XTools/ToolPages/Development/SQLPrettifyPage.swift")
        // 四个格式化页面合并为单入口「格式化」后，IndexPage 页面壳统一
        // 上移到 Hub；semantic 壳断言改锚 Hub 文件。
        let formatterHub = try readSource("Sources/XTools/ToolPages/Development/FormatterHubPage.swift")

        contains(semantics, "enum IndexWorkspaceSemantic", "Shared workspaces must expose a domain-named semantic seam")
        contains(semantics, "case structuredEditorTransform", "Workspace semantics must model structured editor-transform workbenches")
        contains(semantics, "struct IndexWorkspaceBehaviorContract", "Workspace semantics must resolve to a stable behavior contract")
        contains(semantics, "struct IndexWorkspaceResolution", "Workspace semantics must resolve page shell and surface behavior through one interface")
        contains(semantics, "let pageShell: IndexWorkspacePageShell", "Workspace resolution must own page shell selection")
        contains(sharedComponents, "var workspaceSemantic: IndexWorkspaceSemantic = .unmigratedPageDefault", "Shared IO pairs must expose workspace semantics without migrating unnamed pages by default")
        contains(sharedComponents, "struct IndexWorkspaceTextArea: View", "Structured IO inputs must use the shared semantic text input")
        contains(sharedComponents, "struct IndexWorkspaceOutputSurface: View", "Structured IO outputs must use the shared semantic output surface")
        contains(textComponents, "var expandsWithContent = false", "Text areas must separate height filling from internal scrolling")
        contains(outputSurface, "var scrollsInternally = true", "Output surfaces must keep internal scrolling as the default")

        contains(formatterHub, "workspaceSemantic: .structuredEditorTransform", "Formatter hub must let the semantic resolve the compact fixed workbench page shell")
        contains(docker, "workspaceSemantic: .structuredEditorTransform", "Docker Run to Compose must use the editor-transform semantic that resolves the compact fixed page shell")
        contains(html, "workspaceSemantic: .structuredEditorTransform", "HTML to Markdown must use the editor-transform semantic that resolves the compact fixed page shell")
        for page in [json, xml, yaml, sql, docker] {
            contains(page, "outputLineNumbers: true", "Prototype family outputs keep the structured line-number gutter")
            doesNotContain(page, "maxHighlightedOutputCharacters", "Viewport highlighting must replace per-page highlight budgets")
            doesNotContain(page, "outputFileName:", "Copy-only formatter pages must not retain unreachable text-save filenames")
        }
        doesNotContain(html, "outputLineNumbers: true", "Markdown prose output must not spend width on a gutter")
        contains(json, "outputSyntax: .json", "JSON formatter must declare its syntax for the viewport-lazy viewer highlighter")
        contains(xml, "outputSyntax: .xml", "XML formatter must declare its syntax for the viewport-lazy viewer highlighter")
        contains(yaml, "outputSyntax: .yaml", "YAML formatter must declare its syntax for the viewport-lazy viewer highlighter")
        contains(sql, "outputSyntax: .sql", "SQL formatter must declare its syntax for the viewport-lazy viewer highlighter")
        contains(docker, "outputSyntax: workspace.direction == .runToCompose ? .yaml : nil", "Docker Run to Compose must declare YAML syntax only for compose-direction output")
        contains(html, "outputFileName: \"markdown-output.md\"", "HTML to Markdown save action must use a stable Markdown file name")
        // Viewport highlighting in the shared code viewer replaces the old
        // per-page character budgets: large output keeps full highlighting.
        let codeViewer = try readSource("Sources/XTools/Shared/Components/IndexCodeViewerSurface.swift")
        contains(codeViewer, "IndexViewportHighlighting", "The shared code viewer must own viewport-lazy highlighting")
        contains(codeViewer, "syntax.tokens(line: line)", "The viewer must colorize from per-line tokens inside the visible span only")

        // The whole structured formatter family rides the prototype v3
        // single-panel workbench.
        let formatWorkbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexFormatWorkbench.swift")
        for page in [json, xml, yaml, docker, html, sql] {
            contains(page, "IndexFormatWorkbench", "Structured formatter pages must use the shared prototype workbench")
            doesNotContain(page, "IndexTextConversionWorkbench(", "Structured formatter pages must not keep the two-panel conversion workbench")
            doesNotContain(page, "IndexIOPair(", "Structured formatter pages must not keep the old shared IO pair after workbench migration")
        }
        contains(formatWorkbench, "struct IndexFormatWorkbench", "The prototype workbench must be a shared component")
        contains(formatWorkbench, "IndexPrimaryActionButton(title: actionTitle, hint: actionHint", "The primary format action must be the shared prototype button")
        contains(formatWorkbench, ".keyboardShortcut(.return, modifiers: .command)", "Format must be reachable through Command-Return")
        contains(formatWorkbench, "var onFormat: (() -> Void)? = nil", "The prototype workbench must let session-owned converters (HTML) hide the primary action")
        doesNotContain(sql, "SQLFormatterEditorPair", "SQL formatter must not keep a page-local editor pair after workbench migration")
    }

    @Test func structuredFormatterTopControlsStayInPlace() throws {
        let json = try readSource("Sources/XTools/ToolPages/Development/JSONFormatterPage.swift")
        let sql = try readSource("Sources/XTools/ToolPages/Development/SQLPrettifyPage.swift")
        let formatterHub = try readSource("Sources/XTools/ToolPages/Development/FormatterHubPage.swift")

        // Prototype v3: JSON owns one toolbar inside the workbench — no page
        // action bar, no key-sort switch; the indent control rides the toolbar.
        // 页面壳合并后由共享 HubSegmentPage 骨架承载：分段控件挂在页面壳
        // 之内，四个分段挂在同一个 switch 下。
        contains(formatterHub, "HubSegmentPage(", "Formatter hub must compose the shared hub segment skeleton")
        contains(formatterHub, "IndexJSONFormatterSegment()", "Formatter hub must mount the JSON formatter segment")
        contains(formatterHub, "IndexXMLFormatterSegment()", "Formatter hub must mount the XML formatter segment")
        contains(formatterHub, "IndexYAMLPrettifySegment()", "Formatter hub must mount the YAML formatter segment")
        contains(formatterHub, "IndexSQLPrettifySegment()", "Formatter hub must mount the SQL formatter segment")
        contains(formatterHub, "workspaceSemantic: .structuredEditorTransform", "Formatter hub must let the semantic resolve the compact fixed workbench page shell")
        contains(json, "IndexSegmentedControl(", "JSON indent must stay in the workbench toolbar")
        doesNotContain(json, "IndexActionBar {", "JSON must not keep a page-level action bar")
        doesNotContain(json, "IndexOptionPicker(", "JSON indent must use the toolbar segmented control")
        doesNotContain(json, "statsStrip", "JSON formatter must not keep the retired statistics strip")
        doesNotContain(json, "formatAttempt", "The retired per-attempt feedback counter must not return to the JSON formatter")

        contains(sql, "IndexFormatWorkbench(", "SQL formatter segment body must be the prototype workbench")
        contains(sql, "leadingControl: {", "SQL keyword-case controls must ride the workbench toolbar's leading slot")
        doesNotContain(sql, "IndexActionBar {", "SQL must not keep a page-level action bar")
        doesNotContain(sql, "formatAttempt", "The retired per-attempt feedback counter must not return to the SQL formatter")
    }

    @Test func copyTransformPagesKeepFixedInternalScrollAndWrapping() throws {
        let converter = try readSource("Sources/XTools/ToolPages/Workbench/Converter/IndexConverterPage.swift")
        let sharedComponents = try readSharedBagComponents()
        let textComponents = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let outputSurface = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexOutputSurface.swift")
        let scrollGeometry = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextScrollGeometry.swift")
        let url = try readSource("Sources/XTools/ToolPages/Converter/URLCoderPage.swift")
        let base64 = try readSource("Sources/XTools/ToolPages/Converter/Base64StringPage.swift")
        let asciiBinary = try readSource("Sources/XTools/ToolPages/Converter/ASCIIBinaryPage.swift")
        let unicode = try readSource("Sources/XTools/ToolPages/Converter/UnicodePage.swift")

        contains(converter, "workspaceSemantic: .copyTransformWorkspace", "Shared converter must resolve page layout and chrome through the copy-transform semantic")
        doesNotContain(converter, "layout: IndexPageLayout? = nil", "Shared converter must not retain unused explicit page-layout overrides")
        doesNotContain(converter, "chrome: IndexPageChrome? = nil", "Shared converter must not retain unused explicit page-chrome overrides")
        doesNotContain(converter, "workspaceSemantic: IndexWorkspaceSemantic", "Shared converter must own rather than expose its settled workspace semantic")
        contains(sharedComponents, "var workspaceSemantic: IndexWorkspaceSemantic = .unmigratedPageDefault", "Shared IO pairs must keep unmigrated internal scrolling as the default")
        contains(textComponents, "var lineBreakMode: NSLineBreakMode = .byCharWrapping", "Output surfaces must wrap long tokens by default while still allowing caller overrides")
        contains(outputSurface, "indexWrappingAttributedText", "Plain and colorized output must apply explicit wrapping without changing copied text")
        contains(textComponents, "textView.scrollRangeToVisible(clampedSelectedRange(for: textView))", "Fixed internal editors must reveal the current insertion point after large paste/edit operations")
        contains(scrollGeometry, "guard !growsWithContent else { return }", "Insertion-point reveal must not interfere with naturally growing text areas")
        doesNotContain(textComponents, "ScrollViewReader", "Output surfaces must not add programmatic scroll-to-bottom behavior")
        doesNotContain(textComponents, ".defaultScrollAnchor(.bottom)", "Output surfaces must not default generated output to the bottom")

        for (name, page) in [("URL", url), ("Base64", base64), ("ASCII/binary", asciiBinary), ("Unicode", unicode)] {
            doesNotContain(page, "layout: .fill", "\(name) converter must not hand-assemble the fixed copy-transform page shell")
            doesNotContain(page, "chrome: .compactWorkspace", "\(name) converter must not hand-assemble compact chrome")
            doesNotContain(page, "workspaceSemantic:", "\(name) converter must not repeat the semantic owned by the shared module")
            doesNotContain(page, "usesTextConversionWorkbench:", "\(name) converter must not retain the completed migration flag")
            doesNotContain(page, "outputFileName:", "\(name) converter must not retain an unreachable generic text-save filename")
        }
        contains(base64, "initialMode: \"dec\"", "Base64 string must open in the user-approved decode mode")
        doesNotContain(url, "initialMode:", "URL coder must keep its existing encode-first default")
        doesNotContain(asciiBinary, "initialMode:", "ASCII/binary must keep its existing text-to-binary default")
        doesNotContain(unicode, "initialMode:", "Unicode converter must keep its existing text-to-Unicode default")
    }

    @Test func largeStringMaskingOptsIntoViewportInputAndTextKit2Output() throws {
        let workbench = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift")
        let stringObfuscator = try readSource("Sources/XTools/ToolPages/Crypto/StringObfuscatorPage.swift")
        let nativeOutput = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexReadOnlyTextSurface.swift")

        contains(stringObfuscator, "inputRenderingMode: .textKit2Viewport", "Large string masking input must explicitly use the shared TextKit 2 viewport")
        contains(stringObfuscator, "inputCountPresentation: .charactersOrUTF8Size(", "Large string masking must avoid a main-actor grapheme scan while retaining exact short-input counts")
        contains(stringObfuscator, "outputPresentation: workspace.usesNativeOutput ? .nativeReadOnlyText : .standard", "String masking must keep the existing short/native output split")
        contains(workbench, "var inputCountPresentation: IndexInputCountPresentation = .characters", "Ordinary workbench callers must retain exact character counts by default")
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
