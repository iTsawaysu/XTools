import Foundation
import AppKit
@testable import XTools
import Testing

/// Symbol-level and structural contracts for query/list pages and utility pages.
///
/// Anchors assert workspace semantics, shared component usage, bounded IO,
/// and forbidden regressions (internal scroll containers on short-result
/// pages, page-level synchronous IO, CryptoSwift re-entry). Multi-line
/// indentation-sensitive needles, full subtitle/title literals, and
/// row-by-row copy anchors were retired.
struct QueryListAndUtilitySourceContractTests {
    @Test func queryListPagesKeepInternalScrollWithoutWrappingEmptyResults() throws {
        let deviceInfo = try readSource("Sources/XTools/ToolPages/Utility/DeviceInformationPage.swift")
        let httpStatus = try readSource("Sources/XTools/ToolPages/Web/HTTPStatusCodesPage.swift")
        let timezone = try readSource("Sources/XTools/ToolPages/Time/TimezoneViewerPage.swift")
        let emoji = try readSource("Sources/XTools/ToolPages/Utility/EmojiPickerPage.swift")
        let emojiCollection = try readSource("Sources/XTools/ToolPages/Utility/EmojiCollectionView.swift")

        contains(deviceInfo, "workspaceSemantic: .queryListWorkspace", "Device information must use the query-list page shell")
        contains(httpStatus, "IndexPanel(\"状态码（\\(filtered.count)）\")", "HTTP status must keep its count-titled result panel")
        contains(httpStatus, ".listStyle(.plain)", "HTTP status must use the native plain list virtualization path")
        doesNotContain(httpStatus, "LazyVStack(spacing: 0)", "HTTP status must not eagerly materialize every status row through the nested lazy stack path")
        contains(timezone, "workspaceSemantic: .queryListWorkspace", "Timezone viewer must use the query-list page shell")
        contains(emoji, "IndexEmojiCollectionView(", "Emoji non-empty browse/search results must use the panel-local native collection renderer")
        contains(emojiCollection, "static func sectioned(sections: [EmojiSection]", "Emoji special-symbol browse mode must project catalog sections into native collection sections")
        doesNotContain(emoji, "ToolDisclosureBody", "Emoji special-symbol browse mode must not add collapsible section state for the MVP")
        for (name, page) in [("Device information", deviceInfo), ("HTTP status", httpStatus), ("Timezone viewer", timezone), ("Emoji", emoji)] {
            contains(page, ".verticallyFilling()", "\(name) query/list panel must fill the available workspace")
            doesNotContain(page, "IndexWorkspaceResultSurface(workspaceSemantic: .naturalHeightShortResultPanel)", "\(name) must not be reclassified as natural-height short result panels")
            doesNotContain(page, "IndexShortResultKV(", "\(name) must not reuse short-result KV semantics")
            doesNotContain(page, "IndexShortResultCardList(", "\(name) must not reuse short-result card semantics")
        }
    }

    @Test func deviceInformationKeepsSnapshotProjectionArchitecture() throws {
        let page = try readSource("Sources/XTools/ToolPages/Utility/DeviceInformationPage.swift")
        let query = try readSource("Sources/XTools/ToolPages/Utility/DeviceInformationQuery.swift")
        let collector = try readSource("Sources/XTools/ToolPages/Utility/MacDeviceInformationCollector.swift")
        let session = try readSource("Sources/XTools/ToolPages/Utility/DeviceInformationSession.swift")

        contains(page, "IndexKV(rows: rows, emptyText: \"加载设备信息中…\", copyable: true)", "Device information rows must expose per-row copy actions")
        contains(page, "@StateObject private var session = DeviceInformationSession()", "Device information page must hold one refreshable query session")
        contains(page, "DeviceInformationProjection.fields(from: session.snapshot)", "Device information page must render the pure snapshot projection")
        contains(page, "NSApplication.didChangeScreenParametersNotification", "Device information must refresh when the display configuration changes")
        contains(page, "session.refresh()", "Device information screen-change wiring must refresh the query session")
        doesNotContain(page, "NSScreen.main", "Device information page must not label the keyboard-focus screen as the primary display")
        doesNotContain(page, "NSScreen.screens", "Device information page must render a captured display snapshot")
        doesNotContain(page, "CGDisplay", "Device information page must not own CoreGraphics display projection")
        doesNotContain(page, "sysctlbyname", "Device information page must not own platform C queries")
        doesNotContain(page, "ProcessInfo.processInfo", "Device information page must render a snapshot instead of collecting process facts")
        doesNotContain(page, "DeviceInspector", "Device information page must not own network collection")

        contains(collector, "let screens = NSScreen.screens", "Device information collector must capture one consistent display array")
        doesNotContain(collector, "NSScreen.main", "Device information collector must not use the keyboard-focus screen as the primary display")
        contains(query, "snapshot.displays.first?.pixelSize", "Device information must derive the primary summary from the first display in the captured screen order")
        contains(collector, "localNetworkAddress(family: .ipv4)", "Device information must let the core selector choose the best local IPv4 interface")
        contains(query, "DeviceInfoFormatter.formatLocalNetworkAddress", "Device information must format network addresses through the Core formatter")
        doesNotContain(query, "import SwiftUI", "Device information snapshot and projection must stay UI-neutral")
        doesNotContain(query, "import AppKit", "Device information snapshot and projection must not expose platform UI types")
        contains(session, "@Published private(set) var snapshot: DeviceInformationSnapshot", "Device information session must expose a read-only snapshot")
        contains(session, "func refresh()", "Device information session must expose one explicit refresh command")
    }

    @Test func utilityPagesDelegateToCoreLogicAndBoundRendering() throws {
        let math = try readSource("Sources/XTools/ToolPages/Utility/MathEvaluatorPage.swift")
        let textStats = try readSource("Sources/XTools/ToolPages/Utility/TextStatisticsPage.swift")
        let textStatsModel = try readSource("Sources/XTools/ToolPages/Utility/TextStatisticsWorkspaceModel.swift")
        let emoji = try readSource("Sources/XTools/ToolPages/Utility/EmojiPickerPage.swift")
        let emojiCollection = try readSource("Sources/XTools/ToolPages/Utility/EmojiCollectionView.swift")
        let fileType = try readSource("Sources/XTools/ToolPages/Utility/FileTypeDetectorPage.swift")
        let fileTypeSession = try readSource("Sources/XTools/ToolPages/Utility/FileTypeDetectorSession.swift")

        contains(math, "MathExpressionEvaluator.evaluateLiveInput(input)", "Math page must delegate short live expression classification to Core")
        contains(math, ".indexWorkspaceDiagnostic(diagnosticText)", "Math page diagnostics must use the shared non-displacing workspace anchor")
        doesNotContain(math, "NSExpression", "Math page must not evaluate expressions through Foundation's dynamic expression engine")
        doesNotContain(math, "JavaScriptCore", "Math page must not evaluate expressions through a script engine")

        doesNotContain(textStats, "TextStatistics.analyze(", "Text statistics View body must not run Unicode-aware analysis on the main actor")
        contains(textStatsModel, "TextStatistics.analyze(input, shouldCancel: shouldCancel)", "Text statistics background model must delegate cancellable Unicode-aware counting to Core")
        contains(textStatsModel, "SupersedingExecutionSession(cancelInFlight: true)", "Text statistics analysis must use the shared serial latest-wins worker")
        contains(textStats, "workspaceSemantic: .fixedInputWorkspace", "Text statistics must preserve the fixed-input workspace semantic")
        contains(textStats, "valueMotion: .immediate", "Text statistics values must remain immediate rather than animating each completion")

        contains(fileTypeSession, "FileTypeDetector.inspect(", "File type session must delegate evidence resolution, size, and header interpretation to Core")
        contains(fileTypeSession, "read(upToCount: maxByteCount)", "File type reader must keep file reads bounded to the detector prefix limit supplied by the session")
        contains(fileTypeSession, "maxByteCount: FileTypeDetector.leadingByteLimit", "File type session must request only the Core detector prefix limit")
        doesNotContain(fileType, "FileTypeDetector.inspect(", "File type page must leave report construction in the session")
        doesNotContain(fileType, "FileHandle(forReadingFrom:", "File type page must not read selected files on the main actor")

        contains(emoji, "private static let displayLimit = 200", "Emoji page must cap broad search rendering for predictable grid performance")
        contains(emoji, "EmojiCatalog.search(matching: query, limit: Self.displayLimit)", "Emoji search must use Core's structured capped result")
        contains(emojiCollection, "EmojiCatalog.apply(tone: tone, to: entry)", "Emoji renderer must delegate skin-tone application to Core")
        contains(emoji, "entries.contains(where: \\.skinToneCapable)", "Emoji tone visibility must follow current result capability rather than a category-name whitelist")
    }

    @Test func customLiveValidationPagesSurfaceInvalidInputThroughWorkspaceDiagnostics() throws {
        let math = try readSource("Sources/XTools/ToolPages/Utility/MathEvaluatorPage.swift")
        let color = try readSource("Sources/XTools/ToolPages/Image/ColorPickerPage.swift")
        let userAgent = try readSource("Sources/XTools/ToolPages/Web/UserAgentParserPage.swift")
        let basicAuth = try readSource("Sources/XTools/ToolPages/Web/BasicAuthGeneratorPage.swift")

        contains(math, "MathExpressionEvaluator.evaluateLiveInput(input)", "Math live validation must stay in Core")
        contains(math, ".indexWorkspaceDiagnostic(diagnosticText)", "Math invalid-expression diagnostics must use the non-displacing workspace anchor")

        contains(color, "@Published private(set) var state = CSSColorWorkspaceState()", "Color page must retain one canonical draft/result snapshot")
        contains(color, "CSSColorWorkspaceReducer.reduce(state: &next, action: action)", "Color page must route every edit through the Core reducer")
        contains(color, ".indexWorkspaceDiagnostic(workspace.state.diagnostic?.message)", "Color diagnostics must use the non-displacing workspace anchor")
        contains(color, "IndexTextInput(", "Color page must keep a directly editable general CSS color input")
        contains(color, "@State private var showsSystemColorPicker = false", "Color page must keep system ColorPicker behind an explicit on-demand state")
        contains(color, ".popover(isPresented: $showsSystemColorPicker", "Color page must mount the system ColorPicker only when the picker popover is requested")
        contains(color, "IndexDisclosure(", "Advanced color spaces must stay bounded behind the shared disclosure component")
        doesNotContain(color, "DisclosureGroup(", "Color disclosure must not regress to the arrow-only system hit target")
        doesNotContain(color, "suppressNextHexSync", "The canonical reducer must not retain the old one-shot feedback-loop flag")

        contains(userAgent, "UserAgentParser.validationIssue(trimmed)", "UserAgent page must distinguish empty input from structurally invalid input")
        contains(userAgent, ".indexWorkspaceDiagnostic(workspace.error)", "UserAgent retained errors must use the non-displacing workspace anchor")
        appearsBefore(userAgent, ".indexWorkspaceDiagnostic(workspace.error)", "IndexPanel(\"解析结果\")", "UserAgent errors must belong to the input panel rather than the result panel")

        let basicAuthSession = try readSource("Sources/XToolsCore/Web/BasicAuthWorkspaceSession.swift")
        contains(basicAuthSession, "public var outputDiagnostic: String?", "Basic Auth must promote invalid credential states to a persistent diagnostic in the Core session")
        contains(basicAuth, ".indexWorkspaceDiagnostic(session.outputDiagnostic)", "Basic Auth invalid credentials must use the non-displacing workspace anchor")
    }

    @Test func regexTesterMapsErrorsAndUsesCompactFlagMenu() throws {
        let page = try readSource("Sources/XTools/ToolPages/Development/RegexTesterPage.swift")
        let components = try readSource("Sources/XTools/ToolPages/Development/RegexTesterComponents.swift")
        let executionSession = try readSource("Sources/XTools/ToolPages/Development/RegexExecutionSession.swift")

        contains(page, "private var flagMenu: some View", "Regex tester must keep supported flags in one compact, width-stable control")
        doesNotContain(page, "showsAdvancedFlags", "Regex tester must not keep a second raw-flag editing surface for the same five supported flags")
        doesNotContain(page, "IndexOptionSwitch(", "Regex tester must not lay out variable-width flag switches that scramble at narrow widths")
        contains(page, ".onChange(of: workspaceInput)", "Regex tester must schedule one coordinated snapshot instead of three independent field observers")
        doesNotContain(page, ".onChange(of: workspace.pattern)", "Regex preset application must not fan out through a pattern-only observer")
        doesNotContain(page, ".onChange(of: workspace.flags)", "Regex preset application must not fan out through a flags-only observer")
        doesNotContain(page, ".onChange(of: workspace.text)", "Regex preset application must not fan out through a text-only observer")
        contains(page, "let execution = RegexExecutionSession()", "Regex tester must delegate matching state to the asynchronous execution session")
        contains(executionSession, "workGate.runDetached", "Regex tester must execute ICU matching through the shared detached work gate")
        contains(try readSource("Sources/XToolsCore/Utility/AsyncWorkGate.swift"), "Task.detached(priority: .userInitiated)", "AsyncWorkGate.runDetached must leave the main actor for ICU/regex work")
        contains(executionSession, "catch let error as RegexMatcher.MatcherError", "Regex execution session must catch matcher errors explicitly")
        doesNotContain(executionSession, "localizedDescription", "Regex tester must not surface raw matcher localizedDescription text")
        contains(page, "let debouncer = IndexDebouncer()", "Regex tester must keep debounced matching for large input")
        contains(page, "RegexMatcher.summaryText(for: report)", "Regex tester copied summary must include captures and named groups through the tested formatter")
        for (name, source) in [("page", page), ("components", components)] {
            doesNotContain(source, "替换", "Regex tester \(name) P0 must not add replace UI")
            doesNotContain(source, "Replace", "Regex tester \(name) P0 must not add replace UI")
        }
    }

    @Test func sharedSwitchesUseNativeToggleSemantics() throws {
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexOptionControls.swift")

        contains(controls, "struct IndexOptionSwitch: View", "Shared switches must keep one named switch surface")
        contains(controls, "private struct IndexOptionSwitchToggleStyle: ToggleStyle", "The switch family must share one custom ToggleStyle")
        contains(controls, ".accessibilityValue(isOn ? \"已开启\" : \"已关闭\")", "Shared switches must announce their current state")
        doesNotContain(controls, "struct IndexSwitch: View", "The retired IndexSwitch thin shell must not return; use IndexOptionSwitch(style: .standalone)")
    }

    @Test func regexResultWorkspaceExpandsNaturallyWithoutInternalScroll() throws {
        let page = try readSource("Sources/XTools/ToolPages/Development/RegexTesterPage.swift")
        let components = try readSource("Sources/XTools/ToolPages/Development/RegexTesterComponents.swift")

        contains(page, "workspaceSemantic: .regexResultWorkspace", "Regex tester must name the page-level natural-height workspace semantic")
        occurrenceCount(page, "IndexPanel(", 2, "Regex tester must keep only the pattern and test-text panels")
        doesNotContain(page, "IndexPanel(\"匹配结果\")", "Regex tester must not repeat the whole test text in a third result panel")
        contains(page, "temporaryHighlights: temporaryHighlights", "Regex matches must be rendered directly in the editable test text")
        contains(page, "execution.reportSourceText", "Regex highlights must use the exact text snapshot that produced the report")
        contains(page, "IndexTextAreaCharacterRangeProjection.utf16Ranges", "Regex Character offsets must be projected to AppKit UTF-16 ranges")
        contains(page, "RegexResultStatus(", "Regex execution state must remain visible below the editable test text")
        contains(page, "RegexResultSummary(stats: stats(for: report))", "Regex statistics must stay below the editable test text")
        contains(page, "RegexMatchList(matches: report.matches, valueMotion: .immediate,", "Regex match details must remain grouped and update without high-frequency animation")
        contains(page, "IndexPairLayout(collapseWidth: 720, fillsHeight: true, leading: {", "Regex tester must present pattern details and test text as a side-by-side pair on wide windows")
        doesNotContain(page, "RegexHighlightedPreview", "Regex must not retain a second read-only copy of the test text")
        doesNotContain(page, "IndexWorkspaceResultSurface", "Regex feedback must stay in the test-text panel rather than a detached result surface")
        doesNotContain(page, "IndexStatGrid(", "Regex result workspace must not reserve the tall generic statistics grid")
        doesNotContain(page, ".animation(", "Regex high-frequency updates must not add page-local animation")
        doesNotContain(page, ".transition(", "Regex high-frequency updates must not add page-local transitions")

        contains(components, "struct RegexResultStatus: View", "Regex state messaging must live in a named compact component")
        contains(components, "struct RegexResultSummary: View", "Regex result metrics must live in a named compact component")
        contains(components, "ViewThatFits(in: .horizontal)", "Regex result metrics must switch to a deliberate narrow-width fallback instead of wrapping unpredictably")
        contains(components, "LazyVStack(spacing: 8)", "Regex match details must use lazy grouped rendering")
        contains(components, "struct RegexMatchList: View", "Regex match details must be a named grouped result component")
        doesNotContain(components, "ScrollView {", "Regex details must rely on the page scroll owner")
    }

    @Test func jwtPageKeepsBidirectionalMixedWorkspaceSemantics() throws {
        let source = try readSource("Sources/XTools/ToolPages/Web/JWTParserPage.swift")
        let session = try readSource("Sources/XToolsCore/JWT/JWTWorkspaceSession.swift")
        let sharedComponents = try readSharedBagComponents()

        contains(source, "ToolWorkspaceHost(key: JWTToolWorkspaceModel.key)", "JWT page must resolve its retained per-tool workspace")
        contains(source, "IndexGenerateParseModeContent(", "JWT must render mode-specific structured workflows through the shared transition container")
        contains(source, "layout: .scroll", "JWT must retain page-level scrolling for its mixed workspace")
        doesNotContain(source, "IndexConverterPage(", "JWT must not be forced into the symmetric string converter shell")
        doesNotContain(source, "@AppStorage", "JWT must not persist token or secret drafts")
        doesNotContain(source, "@SceneStorage", "JWT must not persist token or secret drafts")

        contains(source, "IndexWorkspaceTextArea(", "JWT inputs must use workspace semantic text surfaces")
        contains(source, "workspaceSemantic: .longTextNaturalInput", "JWT inputs must use natural page-scrolled input behavior")
        occurrenceCount(source, "IndexWorkspaceOutputSurface(", 4, "JWT generation and parsing must use semantic output surfaces")
        occurrenceCount(source, "workspaceSemantic: .structuredOutputReading", 4, "JWT long outputs must keep structured reading semantics")
        contains(source, "IndexWorkspaceResultSurface(workspaceSemantic: .naturalHeightShortResultPanel)", "JWT verification result must keep the natural-height short-result semantic")

        contains(source, "IndexSecureInput(", "JWT shared secret field must use the shared secure input")
        doesNotContain(source, "IndexPanel(\"高级 Header（可选）\")", "JWT generation must expose only one Header surface")
        contains(source, ".indexWorkspaceDiagnostic(session.generationHeaderError)", "The single Header preview must own Header diagnostics")
        contains(session, "JWTSigner.sign(config:", "JWT generation must delegate signing to Core codecs")
        contains(session, "JWTVerifier.verify(", "JWT verification must delegate to Core codecs")
        contains(session, "public mutating func clearGenerate()", "JWT full reset must clear generate state in the session")
        contains(session, "public mutating func clearParse()", "JWT full reset must clear parse state in the session")
        contains(source, "session.clearAll()", "JWT page clear must delegate to the Core session")
        contains(source, "IndexDisclosure(", "JWT local check must use the shared disclosure component")
        doesNotContain(source, "验证通过", "JWT page must not claim application-level validity")
        doesNotContain(source, "验证失败", "JWT page must not claim application-level validity")

        contains(sharedComponents, "struct IndexWorkspaceResultSurface", "Short result panels must have a semantic result surface")
        contains(sharedComponents, "workspaceSemantic: IndexWorkspaceSemantic = .naturalHeightShortResultPanel", "Short result surface must default to the natural-height short result semantic")
    }

    @Test func naturalHeightShortResultEntrypointsStaySeparateFromScrollableLists() throws {
        let sharedComponents = try readSharedBagComponents()

        contains(sharedComponents, "struct IndexShortResultKV: View", "Shared UI must expose a natural-height KV entry for short results and file metadata")
        contains(sharedComponents, "var valueLineBreakMode: NSLineBreakMode = .byCharWrapping", "Short-result KV values must wrap long tokens by default")
        contains(sharedComponents, "var workspaceSemantic: IndexWorkspaceSemantic = .naturalHeightShortResultPanel", "Short-result entries must default to the natural-height short result semantic")
        contains(sharedComponents, "struct IndexShortResultCardList: View", "Shared UI must expose a natural-height result-card entry for bounded derived results")
        contains(sharedComponents, "struct IndexScrollableKV: View", "Scrollable KV must remain available for explicit query/list exceptions")
        contains(sharedComponents, ".fixedSize(horizontal: false, vertical: true)", "Result card values must expand vertically instead of hiding wrapped lines")
    }

    @Test func shortResultPagesAvoidLockingLegacyInternalScrollContracts() throws {
        let userAgent = try readSource("Sources/XTools/ToolPages/Web/UserAgentParserPage.swift")
        let caseConverter = try readSource("Sources/XTools/ToolPages/Converter/CaseConverterPage.swift")
        let hashText = try readSource("Sources/XTools/ToolPages/Crypto/HashTextPage.swift")
        let hashWorkspace = try readSource("Sources/XTools/ToolPages/Crypto/HashTextWorkspaceModel.swift")
        let base64File = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        let basicAuth = try readSource("Sources/XTools/ToolPages/Web/BasicAuthGeneratorPage.swift")

        contains(userAgent, "layout: .scroll", "UserAgent parser must keep page-level scrolling")
        contains(userAgent, "IndexWorkspaceTextArea(", "UserAgent input must use a workspace semantic input surface")
        contains(userAgent, "workspaceSemantic: .longTextNaturalInput", "UserAgent input must grow with long content through the long-text semantic instead of hand-assembled flags")
        doesNotContain(userAgent, "IndexTextArea(", "UserAgent input must not bypass the workspace semantic input surface")
        contains(userAgent, "IndexWorkspaceResultSurface {", "UserAgent short result rows must use the natural-height result surface")
        doesNotContain(userAgent, "ScrollView {", "UserAgent result rows must not create an internal scroll container")
        doesNotContain(userAgent, ".verticallyFilling()", "UserAgent result panel must not fill the viewport like a query/list workspace")

        contains(caseConverter, "workspaceSemantic: .longTextNaturalInput", "Case converter must use the long-text semantic page shell")
        contains(caseConverter, "IndexWorkspaceTextArea(", "Case converter input must use a workspace semantic input surface")
        doesNotContain(caseConverter, "IndexTextArea(", "Case converter input must not bypass the workspace semantic input surface")
        contains(caseConverter, "renderer: @escaping CaseConversionStyleRenderer = CaseConversion.styles,", "Case converter must derive all case rows from the core helper inside the workspace model")
        contains(caseConverter, "IndexShortResultKV(", "Case converter results must use the natural-height short-result KV entry")
        doesNotContain(caseConverter, "IndexScrollableKV(rows: rows", "Case converter results must not create an internal scroll container")
        doesNotContain(caseConverter, ".verticallyFilling()", "Case converter result panel must not fill the viewport like a query/list workspace")

        contains(hashText, "workspaceSemantic: .boundedLongTextInput", "Hash text page must select the bounded long-text semantic for its page shell and input viewport")
        contains(hashText, "IndexWorkspaceTextArea(", "Hash text input must use the shared semantic input surface")
        doesNotContain(hashText, "workspaceSemantic: .longTextNaturalInput", "Hash text input must not retain the unbounded natural-growth semantic")
        contains(hashText, "private var inputViewportHeight: CGFloat", "Hash text must keep a stable responsive input viewport independent of content length")
        contains(hashText, "private var resultItems: [IndexResultCardItem]", "Hash digest results must keep named copyable result data")
        contains(hashText, "workspace.computeExplicitly", "Large Hash input must expose a stable explicit calculation action")
        contains(hashWorkspace, "static let realtimeUTF8ByteLimit = 64 * 1_024", "Hash realtime policy must retain the benchmark-calibrated UTF-8 byte limit")
        contains(hashWorkspace, "SupersedingExecutionSession(cancelInFlight: true)", "Hash workspace must use the shared superseding detached worker")
        contains(hashWorkspace, "HashDigestPipeline.compute(bytes, shouldCancel: shouldCancel)", "Hash workspace must delegate the eight-algorithm pipeline to Core")
        let pipeline = try readSource("Sources/XToolsCore/Crypto/HashDigestPipeline.swift")
        contains(pipeline, "public enum HashDigestAlgorithm", "Core hash pipeline must expose typed algorithm descriptors")
        contains(pipeline, "RIPEMD160.hash", "Core hash pipeline must keep RIPEMD-160")
        contains(pipeline, "Array(Insecure.MD5.hash", "Core hash pipeline must use the platform MD5 implementation")
        doesNotContain(pipeline, "Digest.md5", "Core hash pipeline must not keep common digests on the slower CryptoSwift path")
        contains(hashText, "IndexCopyButton(text: allDigestsText", "Hash digest copy behavior must stay in the result panel header")
        contains(hashText, "IndexShortResultCardList(items: resultItems", "Hash digest results must use the natural-height derived result card entry")
        doesNotContain(hashText, ".verticallyFilling()", "Hash digest result panel must not fill the viewport like a query/list workspace")

        occurrenceCount(base64File, "Base64DecodedMetadataList(", 1, "Base64 file page must keep one decoded short-result surface")
        contains(base64File, "Base64DecodedMetadataList(rows: metadataRows(projection.reverseRows))", "Base64 decoded metadata must use natural-height prototype-aligned rows")
        doesNotContain(base64File, "selectedFileRows", "Base64 selected-file metadata must stay inside the compact picker instead of a second result surface")
        doesNotContain(base64File, "IndexScrollableKV(rows: reverseRows", "Base64 decoded metadata must not create an internal scroll container")
        doesNotContain(base64File, "emptyFilePickerHeight", "Base64 empty state must not use a taller picker that shifts the workflow")
        doesNotContain(base64File, "selectedFilePickerHeight", "Base64 selected state must not use a second picker height")
        contains(base64File, "maxUTF8Bytes: Base64FileWorkflowSession.editableReverseInputByteLimit", "Base64 reverse pasted input must keep oversized text out of the editable AppKit path")

        contains(basicAuth, "IndexWorkspaceOutputSurface(", "Basic Auth output must use a semantic output surface")
        contains(basicAuth, "workspaceSemantic: .naturalHeightShortResultPanel", "Basic Auth output must select the natural-height short-result semantic")
        doesNotContain(basicAuth, "IndexOutputSurface(text: output", "Basic Auth output must not use the legacy internally scrolling output surface")
        doesNotContain(basicAuth, ".verticallyFilling()", "Basic Auth output panel must not fill the viewport like a query/list workspace")
    }

    @Test func repositorySourcesAndManifestStayFreeOfCryptoSwift() throws {
        // CryptoSwift 已由平台实现 + 本地 Rabbit/SHA3（RFC 4503 / FIPS 202）取代；
        // 此契约防止依赖回流：Sources 与 Tests 的所有 Swift 文件以及
        // Package.swift 都不得再出现该依赖字样。
        let packageRoot = try sourcePackageRoot()
        let fileManager = FileManager.default

        var swiftFilePaths: [String] = []
        for relativeDirectory in ["Sources", "Tests"] {
            guard let enumerator = fileManager.enumerator(
                at: packageRoot.appendingPathComponent(relativeDirectory),
                includingPropertiesForKeys: nil
            ) else {
                #expect(false, Comment(rawValue: "Source directory must be enumerable: \(relativeDirectory)"))
                continue
            }
            // 注意不能写 while-let 附加条件：首个非 Swift 元素会终止整个循环。
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                swiftFilePaths.append(url.path)
            }
        }

        // 枚举必须真实生效，避免目录名改动后契约静默空转。
        #expect(swiftFilePaths.count > 100, Comment(rawValue: "Source enumeration must find the repository's Swift files"))

        // 行首锚定 import 断言：注释与契约字符串里讨论该依赖（含本契约自身的
        // 字面量）不构成依赖回流，只有真正的 import 语句才算。
        let importRegex = try NSRegularExpression(
            pattern: "^[[:space:]]*(@preconcurrency[[:space:]]+)?import CryptoSwift[[:space:]]*$",
            options: [.anchorsMatchLines]
        )
        for path in swiftFilePaths {
            let source = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            #expect(
                importRegex.firstMatch(in: source, options: [], range: range) == nil,
                Comment(rawValue: "CryptoSwift import must stay removed from \(path)")
            )
        }

        let manifest = try String(contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(
            !manifest.contains("CryptoSwift"),
            Comment(rawValue: "Package.swift must not declare the CryptoSwift dependency")
        )
    }

    @Test func fileTypeDetectorUsesNaturalHeightShortResultPanel() throws {
        let page = try readSource("Sources/XTools/ToolPages/Utility/FileTypeDetectorPage.swift")
        let session = try readSource("Sources/XTools/ToolPages/Utility/FileTypeDetectorSession.swift")
        let dropZone = try readSource("Sources/XTools/Shared/Components/IndexDropZone.swift")

        contains(page, "IndexWorkspaceResultSurface(workspaceSemantic: .naturalHeightShortResultPanel)", "File type detector results must explicitly select the natural-height short result semantic")
        appearsBefore(page, "IndexPanel(\"上传文件\")", "IndexPanel(\"检测结果\")", "File type detector must keep the upload panel before the result panel")
        doesNotContain(page, "ScrollView {", "File type detector results must not use an internal vertical scroll container")
        doesNotContain(page, ".verticallyFilling()", "File type detector result panel must not fill the remaining viewport like a query/list workspace")
        doesNotContain(page, ".queryListWorkspace", "File type detector must not be classified as a query/list workspace")
        doesNotContain(page, "IndexScrollableKV", "File type detector results must not use the scrollable KV query/list helper")
        doesNotContain(page, "IndexScrollableResultCardList", "File type detector results must not use the scrollable card-list helper")

        contains(session, "FileHandle(forReadingFrom: url)", "File type reader must open the selected file through a handle")
        contains(session, "read(upToCount: maxByteCount)", "File type reader must read only the requested bounded prefix")
        contains(session, "maxByteCount: FileTypeDetector.leadingByteLimit", "File type session must use the Core prefix limit for bounded content and header detection")
        doesNotContain(page, "Data(contentsOf: url)", "File type detector must not load the entire selected file into memory")
        doesNotContain(page, "FileHandle(forReadingFrom:", "File type page must not perform synchronous prefix IO")
        doesNotContain(page, "resourceValues(forKeys:", "File type page must not perform synchronous metadata IO")

        contains(page, "@Environment(\\.fileInputPanelClient) private var fileInputPanelClient", "File type page must receive the shared window-scoped input panel client")
        contains(page, "ToolWorkspaceHost(key: FileTypeDetectorSession.workspaceKey)", "File type page state and async work must resolve from the retained detector session")
        contains(page, "session.selectFile(filePanel: fileInputPanelClient)", "File type click selection must use the shared panel client")
        contains(page, ".indexDropZone(", "File type upload surface must accept local single-file drops through the shared drop zone")
        contains(dropZone, ".dropDestination(for: URL.self)", "The shared drop zone must own the native drop destination for local single-file drops")
        contains(dropZone, "SingleFileDropResolver.resolve(urls)", "File type drops must use the shared single-file batch resolver")
        contains(page, "onFile: { session.inspect($0) }", "Dropped files must enter the shared detector session handler")
        contains(session, "self.inspect(url)", "Panel-selected and dropped URLs must enter the same detector session handler")
        contains(page, "session.rejectMultipleFileDrop()", "File type drops must reject an entire multi-file batch")
        contains(page, ".indexWorkspaceDiagnostic(session.error)", "File selection and metadata failures must stay on the upload panel that owns the input")
        contains(page, ".indexWorkspaceDiagnostic(session.warning, tone: .warning)", "Prefix-read warnings must stay on the result panel that owns the partial report")
        doesNotContain(page, "session.error ?? session.warning", "Input failures and result warnings must not be collapsed into one sibling-panel diagnostic")
        doesNotContain(page, "NSOpenPanel()", "File type page must not construct its own input panel")
        doesNotContain(page, "runModal()", "File type input must not start a synchronous modal event loop")

        contains(session, "workGate.runDetached", "File type metadata and prefix reads must run off the main actor through AsyncWorkGate")
        contains(session, "workGate.isCurrent(generation)", "File type session must suppress stale background completions")
        contains(session, "case success(FileTypeReport, warning: String?)", "File type prefix warnings must remain separate from metadata failures")
        doesNotContain(page, "魔数", "File type UI must not describe every displayed header byte as a magic number")
    }

    @Test func crontabCoreOwnsDayFieldSemantics() throws {
        let cron = try readSource("Sources/XTools/ToolPages/Development/CrontabGeneratorPage.swift")
        let cronCore = try readSource("Sources/XToolsCore/Utility/CronScheduler.swift")

        contains(cron, "CronScheduler.dayMatchingExplanation(workspace.expression)", "Crontab page must render Core's Unix day-field OR explanation")
        contains(cronCore, "日与星期字段同时受限时，任一字段匹配即运行", "Cron Core must own the user-facing Unix day-field OR semantics")
        contains(cron, "TimeZone.current.identifier", "Crontab next-run preview must expose the timezone used for calculation")
    }

    @Test func chmodPageKeepsBidirectionalInputAndSpecialBitsCompact() throws {
        let source = try readSource("Sources/XTools/ToolPages/Development/ChmodCalculatorPage.swift")

        contains(source, "IndexTextInput(placeholder: \"644 或 4755\"", "Chmod page must accept direct octal input")
        contains(source, "IndexOptionSwitch(title: \"setuid\", style: .standalone", "Chmod page must expose setuid")
        contains(source, "IndexOptionSwitch(title: \"setgid\", style: .standalone", "Chmod page must expose setgid")
        contains(source, "IndexOptionSwitch(title: \"sticky\", style: .standalone", "Chmod page must expose sticky")
        contains(source, ".indexWorkspaceDiagnostic(workspace.error)", "Invalid chmod input must use the workspace diagnostic surface")
        doesNotContain(source, "capabilityWarning", "Chmod no longer needs a warning that special bits are unsupported")
    }

    @Test func randomPortPageDisclosesRangeAndDisablesEmptyCopy() throws {
        let source = try readSource("Sources/XTools/ToolPages/Development/RandomPortPage.swift")
        let heroStat = try readSource("Sources/XTools/Shared/Components/IndexHeroStat.swift")

        contains(source, "IndexHeroStat(", "Random-port results must render through the shared hero stat")
        contains(heroStat, "IndexCopyButton(text: value, iconOnly: true)", "The shared hero stat must own the copy action through the shared copy button")
        doesNotContain(source, "AvailableTCPPortAllocator", "Random-port page must not probe a socket")
    }

    @Test func crontabUsesScrollablePageLayout() throws {
        let source = try readSource("Sources/XTools/ToolPages/Development/CrontabGeneratorPage.swift")

        contains(source, "workspaceSemantic: .naturalHeightShortResultPanel", "Crontab page must use the natural-height short-result shell")
        occurrenceCount(source, "IndexPanel(", 2, "Crontab must keep exactly the expression panel and the merged result panel")
        doesNotContain(source, "IndexPanel(\"常用预设\")", "Crontab presets must stay inside the expression panel instead of a standalone preset panel")
        doesNotContain(source, "IndexPanel(\"说明\")", "Crontab field explanations must live inside the merged result panel")
        doesNotContain(source, "IndexPanel(\"下次运行时间\")", "Crontab next runs must live inside the merged result panel")
        contains(source, "CronScheduler.expressionSummary(workspace.expression)", "Crontab must lead the result panel with Core's plain-language schedule summary")
        contains(source, "CronScheduler.fieldExplanations(workspace.expression)", "Crontab must render per-field explanations from Core's structured rows")
        contains(source, "fieldSegmentBar(fields)", "Crontab must present fields as a five-segment bar beside the expression, not stacked table rows")
    }
}

extension QueryListAndUtilitySourceContractTests {
    @Test func queryPagesUseSharedShellAndStaticPanelContracts() throws {
        let pages: [(String, String)] = [
            ("HTTP status", try readSource("Sources/XTools/ToolPages/Web/HTTPStatusCodesPage.swift")),
            ("Device information", try readSource("Sources/XTools/ToolPages/Utility/DeviceInformationPage.swift")),
            ("Timezone viewer", try readSource("Sources/XTools/ToolPages/Time/TimezoneViewerPage.swift"))
        ]

        for (name, source) in pages {
            contains(source, "workspaceSemantic: .queryListWorkspace", "\(name) must use the shared query-list page shell")
            contains(source, ".withoutDiagnosticStatusSlot()", "\(name) static panels must opt out of the diagnostic reserve")
            doesNotContain(source, ".buttonStyle(.bordered", "\(name) must not introduce native bordered button chrome")
            doesNotContain(source, "ProgressView(", "\(name) must use shared progress/empty owners instead of a bare progress view")
        }
    }
}
