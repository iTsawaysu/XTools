@testable import XTools
import AppKit
import Foundation
import Testing

struct IconSemanticContractTests {
    // Audited against SFSafeSymbols cb2e670a213ff42ae08528ee2c401bfb1d799675.
    // Every entry is available before or with SF Symbols 4.0 (macOS 13).
    private let reviewedMacOS13Symbols: Set<String> = [
        "01.square",
        "app.badge",
        "exclamationmark.triangle",
        "minus",
        "plus",
        "arrow.clockwise",
        "arrow.counterclockwise",
        "arrow.down.doc",
        "arrow.down.right.and.arrow.up.left",
        "arrow.left.arrow.right",
        "arrow.left.arrow.right.square",
        "arrow.left.circle",
        "arrow.right.circle",
        "barcode",
        "building.columns",
        "calendar",
        "calendar.badge.clock",
        "camera.filters",
        "chart.bar.doc.horizontal",
        "checkmark",
        "checkmark.circle.fill",
        "checkmark.shield",
        "checkmark.square.fill",
        "checklist",
        "chevron.down",
        "chevron.left",
        "chevron.left.forwardslash.chevron.right",
        "chevron.right",
        "chevron.up",
        "circle.lefthalf.filled",
        "clock",
        "clock.arrow.circlepath",
        "curlybraces",
        "curlybraces.square",
        "cylinder",
        "desktopcomputer",
        "doc",
        "doc.badge.gearshape",
        "doc.badge.plus",
        "doc.fill",
        "doc.on.doc",
        "doc.plaintext",
        "doc.questionmark",
        "doc.text.magnifyingglass",
        "exclamationmark.triangle.fill",
        "eye",
        "eye.slash",
        "eyedropper",
        "face.smiling",
        "function",
        "gearshape",
        "globe",
        "globe.americas",
        "hammer",
        "info.circle",
        "info.circle.fill",
        "key",
        "keyboard",
        "lightbulb",
        "link",
        "list.bullet.indent",
        "lock",
        "lock.rectangle",
        "lock.shield",
        "magnifyingglass",
        "moon.fill",
        "network",
        "number",
        "paintpalette",
        "pause.fill",
        "photo",
        "photo.on.rectangle.angled",
        "play.fill",
        "rectangle.and.text.magnifyingglass",
        "server.rack",
        "shippingbox",
        "shuffle",
        "sidebar.left",
        "square",
        "square.and.arrow.down",
        "square.grid.3x3",
        "square.split.2x1",
        "star",
        "star.fill",
        "sun.max.fill",
        "terminal",
        "text.badge.checkmark",
        "text.below.photo",
        "text.justify.left",
        "text.magnifyingglass",
        "text.quote",
        "textformat",
        "textformat.abc",
        "textformat.size",
        "ticket",
        "timer",
        "trash",
        "wrench.and.screwdriver",
        "xmark",
        "xmark.circle",
        "xmark.circle.fill",
    ]

    private let reviewedDynamicSymbols: Set<String> = [
        "checkmark",
        "checkmark.circle.fill",
        "checkmark.square.fill",
        "exclamationmark.triangle.fill",
        "eye",
        "eye.slash",
        "info.circle",
        "info.circle.fill",
        "pause.fill",
        "play.fill",
        "square",
        "star",
        "star.fill",
        "xmark.circle.fill",
    ]

    private let approvedToolIcons: [ToolID: String] = [
        "base64-file-converter": "doc",
        "base64-string": "text.quote",
        "url-encoder-decoder": "link",
        "text-to-ascii-binary": "01.square",
        "text-to-unicode": "textformat",
        "integer-base-converter": "arrow.left.arrow.right.square",
        "roman-numeral-converter": "building.columns",
        "case-converter": "textformat.size",
        "hash-text": "number",
        "text-encryption": "lock",
        "string-obfuscator": "eye.slash",
        "token-generator": "shuffle",
        "uuid-generator": "barcode",
        "password-generator": "lock.rectangle",
        "json-formatter": "curlybraces.square",
        "sql-prettify": "cylinder",
        "xml-formatter": "chevron.left.forwardslash.chevron.right",
        "yaml-prettify": "list.bullet.indent",
        "json-diff": "curlybraces",
        "text-diff": "square.split.2x1",
        "regex-tester": "text.magnifyingglass",
        "docker-run-to-docker-compose-converter": "shippingbox",
        "html-to-markdown": "doc.plaintext",
        "crontab-generator": "clock.arrow.circlepath",
        "random-port-generator": "server.rack",
        "chmod-calculator": "terminal",
        "jwt-parser": "ticket",
        "basic-auth-generator": "key",
        "http-status-codes": "network",
        "useragent-parser": "rectangle.and.text.magnifyingglass",
        "keycode-info": "keyboard",
        "image-converter": "photo.on.rectangle.angled",
        "image-compressor": "arrow.down.right.and.arrow.up.left",
        "image-watermark": "text.below.photo",
        "image-grayscale": "circle.lefthalf.filled",
        "favicon-generator": "app.badge",
        "color-picker": "paintpalette",
        "date-time-converter": "calendar",
        "timezone-viewer": "globe.americas",
        "date-calculator": "calendar.badge.clock",
        "chronometer": "timer",
        "device-information": "desktopcomputer",
        "file-type-detector": "doc.questionmark",
        "math-evaluator": "function",
        "text-statistics": "chart.bar.doc.horizontal",
        "emoji-picker": "face.smiling",
    ]

    @Test func defaultRegistryUsesApprovedToolIdentityIcons() throws {
        let registry = ToolRegistry.default

        for (toolID, systemImage) in approvedToolIcons {
            #expect(try #require(registry.tool(for: toolID)).systemImage == systemImage)
        }

        #expect(registry.toolCount == approvedToolIcons.count)
    }

    @Test func navigationProjectionCarriesApprovedIconsToEveryConsumer() throws {
        let registry = ToolRegistry.default
        let projection = ToolNavigationProjection(
            registry: registry,
            favoriteIDs: [],
            selectedToolID: "case-converter",
            query: ""
        )
        let sidebarIcons = Dictionary(
            uniqueKeysWithValues: projection.sidebarGroups
                .flatMap(\.items)
                .map { ($0.id, $0.systemImage) }
        )
        let commandPaletteIcons = Dictionary(
            uniqueKeysWithValues: projection.commandPaletteEntries
                .map { ($0.toolID, $0.systemImage) }
        )

        for (toolID, systemImage) in approvedToolIcons {
            #expect(sidebarIcons[toolID] == systemImage)
            #expect(commandPaletteIcons[toolID] == systemImage)
        }

        #expect(projection.selectedTool?.systemImage == "textformat.size")
    }

    @Test func sharedFeedbackTonesUseConventionalSeverityIcons() {
        #expect(ToolFeedbackTone.success.systemImage == "checkmark.circle.fill")
        #expect(ToolFeedbackTone.error.systemImage == "xmark.circle.fill")
        #expect(ToolFeedbackTone.warning.systemImage == "exclamationmark.triangle.fill")
        #expect(ToolFeedbackTone.info.systemImage == "info.circle.fill")
    }

    @Test func sharedActionVocabularySeparatesClearRemoveResetRefreshAndSave() {
        #expect(IndexActionSymbol.clear == "xmark.circle")
        #expect(IndexActionSymbol.searchClear == "xmark.circle.fill")
        #expect(IndexActionSymbol.removeResource == "trash")
        #expect(IndexActionSymbol.reset == "arrow.counterclockwise")
        #expect(IndexActionSymbol.refresh == "arrow.clockwise")
        #expect(IndexActionSymbol.save == "square.and.arrow.down")
        #expect(IndexActionSymbol.copy == "doc.on.doc")
        #expect(Set([
            IndexActionSymbol.clear,
            IndexActionSymbol.searchClear,
            IndexActionSymbol.removeResource,
            IndexActionSymbol.reset,
            IndexActionSymbol.refresh,
            IndexActionSymbol.save,
            IndexActionSymbol.copy,
        ]).count == 7)
    }

    @Test func actionConsumersUseTheApprovedVocabulary() throws {
        let generateParse = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexGenerateParseMode.swift")
        let controls = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift")
        let textComponents = try readSource("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        let chronometer = try readSource("Sources/XTools/ToolPages/Time/ChronometerPage.swift")
        let base64File = try readSource("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        let randomPort = try readSource("Sources/XTools/ToolPages/Development/RandomPortPage.swift")

        contains(generateParse, #"Label("清空", systemImage: IndexActionSymbol.clear)"#, "Generate/parse workspaces must treat clearing drafts as content clearing")
        contains(controls, "Image(systemName: IndexActionSymbol.clear)", "Shared icon-only clear controls must use the clear symbol owner")
        contains(controls, "Label(title, systemImage: IndexActionSymbol.clear)", "Shared labeled clear controls must use the clear symbol owner")
        occurrenceCount(controls, #"copied ? "checkmark" : IndexActionSymbol.copy"#, 2, "Shared copy controls must use the copy symbol owner before success feedback")
        contains(textComponents, "systemImage: IndexActionSymbol.searchClear", "Shared search fields must use the familiar filled clear symbol")
        contains(chronometer, #"Label("重置", systemImage: IndexActionSymbol.reset)"#, "Chronometer reset must remain distinct from refresh and regeneration")

        contains(base64File, "IndexClearButton(", "Base64 content clearing must use the shared clear button component")
        contains(base64File, "systemImage: IndexActionSymbol.copy", "Base64 full-output copying must use the shared copy symbol owner")
        occurrenceCount(base64File, "systemImage: IndexActionSymbol.save", 2, "Base64 encoded and decoded file saves must use the shared save symbol owner")
        let base64FilenameReset = sourceSlice(
            base64File,
            from: "private var resetOutputFileNameButton: some View",
            to: "@ViewBuilder\n    private var reversePreview: some View"
        )
        let usesSharedResetSymbol =
            base64FilenameReset.contains("Image(systemName: IndexActionSymbol.reset)") ||
            base64FilenameReset.contains(#"Label("重置文件名", systemImage: IndexActionSymbol.reset)"#)
        #expect(usesSharedResetSymbol, "Base64 filename reset must use the shared reset symbol owner")
        if base64FilenameReset.contains("Image(systemName: IndexActionSymbol.reset)") {
            contains(base64FilenameReset, #".accessibilityLabel("重置文件名")"#, "Base64 icon-only filename reset must keep its accessible action name")
        }
        contains(randomPort, #"Label("重新生成", systemImage: IndexActionSymbol.refresh)"#, "Random Port regeneration must use the shared refresh symbol owner")

        contains(
            try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexGenerateBar.swift"),
            "systemImage: IndexActionSymbol.refresh",
            "The shared generator bar must own the refresh symbol"
        )
        let refreshConsumers = [
            "Sources/XTools/ToolPages/Utility/DeviceInformationPage.swift",
        ]
        for path in refreshConsumers {
            contains(try readSource(path), "systemImage: IndexActionSymbol.refresh", "\(path) must use the shared refresh symbol")
        }

        let imageResourceConsumers = [
            "Sources/XTools/ToolPages/Image/FaviconGeneratorPage.swift",
            "Sources/XTools/ToolPages/Image/ImageCompressorPage.swift",
            "Sources/XTools/ToolPages/Image/ImageConverterPage.swift",
            "Sources/XTools/ToolPages/Image/ImageGrayscalePage.swift",
            "Sources/XTools/ToolPages/Image/ImageWatermarkPage.swift",
        ]
        for path in imageResourceConsumers {
            let source = try readSource(path)
            contains(source, "systemImage: IndexActionSymbol.removeResource", "\(path) must reserve trash for removing the selected image resource")
            contains(source, "systemImage: IndexActionSymbol.save", "\(path) must use the shared file-save symbol")
        }
    }

    @Test func appShellUsesAppearanceAndLeftSidebarSemantics() throws {
        let sidebar = try readSource("Sources/XTools/AppShell/SidebarView.swift")
        let titlebar = try readSource("Sources/XTools/AppShell/TitlebarView.swift")

        contains(sidebar, "SidebarFooterButton(title: themeTitle, systemImage: themeIcon", "Theme toggle must project the current appearance preference state")
        doesNotContain(sidebar, #"SidebarFooterButton(title: "切换主题", systemImage: "sun.max""#, "Theme toggle must not describe only light appearance")
        contains(titlebar, #"Image(systemName: "sidebar.left")"#, "Sidebar control must identify the controlled left sidebar")
        doesNotContain(titlebar, "Image(systemName: selectedTool.systemImage)", "Titlebar must not project a selected-tool breadcrumb identity icon")
        doesNotContain(titlebar, #"isSidebarVisible ? "sidebar.left" : "sidebar.right""#, "Hidden left sidebar must not be represented as a right sidebar")
        contains(titlebar, ".toolMotionIconSwap(id: isSidebarVisible)", "Sidebar visibility feedback must retain its existing motion lifecycle")
        contains(titlebar, ".accessibilityLabel(presentation.title)", "Sidebar control must retain its state-specific accessible name")
    }

    @Test func iconOnlyDateAndFavoriteControlsExposeDiscoverableActions() throws {
        let datePicker = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexDatePicker.swift")
        let sidebar = try readSource("Sources/XTools/AppShell/SidebarView.swift")

        let trigger = sourceSlice(
            datePicker,
            from: "var body: some View",
            to: "// MARK: - IndexCalendarView"
        )
        contains(trigger, #".help("选择日期")"#, "Date trigger must explain its action on hover")
        contains(trigger, #".accessibilityLabel("选择日期")"#, "Date trigger must expose an action name instead of reading only its icon")
        contains(trigger, ".accessibilityValue(formatted(selection))", "Date trigger must expose the selected date as its value")

        let monthNavigation = sourceSlice(
            datePicker,
            from: "private struct IndexCalendarNavButton: View",
            to: "/// Single day cell"
        )
        contains(monthNavigation, #".help(help)"#, "Previous/next-month icons must have discoverable help")
        contains(monthNavigation, #".accessibilityLabel(help)"#, "Previous/next-month icons must have an accessible action name")
        contains(datePicker, #"help: "上一个月""#, "Previous-month call site must name its action")
        contains(datePicker, #"help: "下一个月""#, "Next-month call site must name its action")

        let favorite = sourceSlice(
            sidebar,
            from: "// Favorite toggle:",
            to: ".opacity(isFavorite || hoverState.isHovered ? 1 : 0)"
        )
        contains(favorite, #".help(isFavorite ? "取消收藏" : "加入收藏")"#, "Sidebar favorite icon must retain dynamic hover help")
        contains(favorite, #".accessibilityLabel(isFavorite ? "取消收藏\(title)" : "收藏\(title)")"#, "Sidebar favorite icon must name both the current action and target tool")
    }

    @Test func directProductionSymbolsStayInsideTheMacOS13ReviewSet() throws {
        let regex = try NSRegularExpression(
            pattern: #"(?:systemImage|systemName)\s*:\s*"([^"]+)""#
        )
        var references: [String: Set<String>] = [:]

        for source in try productionSwiftSources() {
            let range = NSRange(source.contents.startIndex..<source.contents.endIndex, in: source.contents)
            for match in regex.matches(in: source.contents, range: range) {
                guard let symbolRange = Range(match.range(at: 1), in: source.contents) else { continue }
                references[String(source.contents[symbolRange]), default: []].insert(source.path)
            }
        }

        let directSymbols = Set(references.keys)
        let unreviewed = directSymbols.subtracting(reviewedMacOS13Symbols)
        #expect(
            unreviewed.isEmpty,
            "Direct production SF Symbols need a macOS 13 review: \(unreviewed.sorted())"
        )
        #expect(directSymbols.count >= 70, "The recursive audit must keep covering the complete production icon surface")
    }

    @Test func dynamicStateSymbolsStayExplicitAndReviewed() throws {
        let chronometer = try readSource("Sources/XTools/ToolPages/Time/ChronometerPage.swift")
        let dateCalculator = try readSource("Sources/XTools/ToolPages/Time/DateCalculatorPage.swift")
        let titlebar = try readSource("Sources/XTools/AppShell/TitlebarView.swift")
        let sidebar = try readSource("Sources/XTools/AppShell/SidebarView.swift")
        let timezone = try readSource("Sources/XTools/ToolPages/Time/TimezoneViewerPage.swift")
        let jwt = try readSource("Sources/XTools/ToolPages/Web/JWTParserPage.swift")

        contains(chronometer, #"chronometer.isRunning ? "pause.fill" : "play.fill""#, "Chronometer must keep distinct pause and start state symbols")
        contains(dateCalculator, #"isOn ? "checkmark.square.fill" : "square""#, "Date options must keep checked and unchecked state symbols")
        contains(titlebar, #"isFavorite ? "star.fill" : "star""#, "Toolbar favorite state must keep filled and unfilled symbols")
        contains(sidebar, #"isFavorite ? "star.fill" : "star""#, "Sidebar favorite state must keep filled and unfilled symbols")
        contains(timezone, #"isFavorite ? "star.fill" : "star""#, "Timezone favorite state must keep filled and unfilled symbols")
        occurrenceCount(jwt, #"return ("checkmark.circle.fill""#, 3, "JWT status mappings must keep the approved success symbol")
        occurrenceCount(jwt, #"return ("xmark.circle.fill""#, 3, "JWT status mappings must keep the approved failure symbol")
        #expect(reviewedDynamicSymbols.isSubset(of: reviewedMacOS13Symbols))
    }

    @Test func removedWorkbenchZoomAndGenericSaveActionsStayAbsent() throws {
        let workbenchPath = "Sources/XTools/ToolPages/Workbench/Text/IndexTextConversionWorkbench.swift"
        let workbench = try readSource(workbenchPath)
        let sources = try productionSwiftSources()
        let combinedSource = sources.map(\.contents).joined(separator: "\n")

        doesNotContain(workbench, "IndexTextConversionFocusMode", "Text workbenches must not restore removed pane enlargement state")
        doesNotContain(workbench, "keyboardMonitor", "Text workbenches must not restore the hidden Escape listener")
        doesNotContain(combinedSource, "arrow.up.left.and.arrow.down.right", "The removed workbench enlargement action symbol must stay absent")
        #expect(
            combinedSource.components(separatedBy: #"systemImage: "arrow.down.right.and.arrow.up.left""#).count - 1 == 1,
            "The inward-arrow symbol must remain only the Image Compressor tool identity"
        )

        let explicitTextSaveConsumers = sources
            .filter { $0.contents.contains("showsOutputSave: true") }
            .map(\.path)
        #expect(
            explicitTextSaveConsumers == ["Sources/XTools/ToolPages/Development/HTMLToMarkdownPage.swift"],
            "Only HTML to Markdown may opt into text-workbench file saving"
        )
    }

    @Test func allReviewedSymbolsResolveOnTheCurrentRuntime() {
        let contractSymbols = Set(approvedToolIcons.values).union([
            IndexActionSymbol.clear,
            IndexActionSymbol.searchClear,
            IndexActionSymbol.removeResource,
            IndexActionSymbol.reset,
            IndexActionSymbol.refresh,
            IndexActionSymbol.save,
            IndexActionSymbol.copy,
            "checkmark.circle.fill",
            "xmark.circle.fill",
            "exclamationmark.triangle.fill",
            "info.circle.fill",
            "circle.lefthalf.filled",
            "sidebar.left",
        ])
        #expect(contractSymbols.isSubset(of: reviewedMacOS13Symbols))

        for symbol in reviewedMacOS13Symbols {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil)
        }
    }

    private func productionSwiftSources() throws -> [(path: String, contents: String)] {
        let root = try sourcePackageRoot()
        let sourcesRoot = root.appendingPathComponent("Sources/XTools")
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(domain: "IconSemanticContractTests", code: 1)
        }

        var sources: [(path: String, contents: String)] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            sources.append((
                path: relativePath,
                contents: try String(contentsOf: fileURL, encoding: .utf8)
            ))
        }
        return sources.sorted { $0.path < $1.path }
    }
}
