import AppKit
import SwiftUI
import Testing
@testable import XTools
@testable import XToolsCore

struct CodeViewerSurfaceTests {
    // MARK: - Syntax Highlighting Conversion Tests

    @Test func jsonHighlightingConvertsToNSAttributedStringWithColors() {
        let line = #"  "name": "XTools", "count": 42, "active": true"#
        let attributed = JSONSyntaxHighlighter.highlight(line: line)
        let nsAttr = NSAttributedString(attributed)

        #expect(nsAttr.length == (line as NSString).length)

        // Verify that attributes exist and foregroundColor is assigned
        var colorFound = false
        nsAttr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: nsAttr.length)) { value, range, _ in
            if value != nil {
                colorFound = true
            }
        }
        #expect(colorFound, "NSAttributedString converted from JSON highlight must retain foreground colors")
    }

    @Test func sqlHighlightingConvertsToNSAttributedStringWithColors() {
        let line = "SELECT id, name FROM users WHERE active = true"
        let attributed = StructuredSyntaxHighlighter.sql(line: line)
        let nsAttr = NSAttributedString(attributed)

        #expect(nsAttr.length == (line as NSString).length)

        var colorFound = false
        nsAttr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: nsAttr.length)) { value, range, _ in
            if value != nil {
                colorFound = true
            }
        }
        #expect(colorFound, "NSAttributedString converted from SQL highlight must retain foreground colors")
    }

    @Test func sqlHighlightingHandlesRepeatedKeywordsOnSameLine() {
        let line = "SELECT id, (SELECT count(*) FROM orders) as total FROM users"
        let attributed = StructuredSyntaxHighlighter.sql(line: line)
        let nsAttr = NSAttributedString(attributed)

        var firstColor: Any?
        var secondColor: Any?

        nsAttr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: nsAttr.length)) { value, range, _ in
            if range.location <= 0 && range.upperBound >= 6 { firstColor = value }
            if range.location <= 12 && range.upperBound >= 18 { secondColor = value }
        }

        #expect(firstColor != nil, "First SELECT must be highlighted")
        #expect(secondColor != nil, "Second SELECT on same line must also be highlighted")
    }

    @Test func yamlHighlightingConvertsToNSAttributedStringWithColors() {
        let line = "database_host: 'localhost'"
        let attributed = StructuredSyntaxHighlighter.yaml(line: line)
        let nsAttr = NSAttributedString(attributed)

        #expect(nsAttr.length == (line as NSString).length)

        var colorFound = false
        nsAttr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: nsAttr.length)) { value, range, _ in
            if value != nil { colorFound = true }
        }
        #expect(colorFound, "YAML highlight must convert with colors")
    }

    @Test func xmlHighlightingConvertsToNSAttributedStringWithColors() {
        let line = #"<user id="123" role="admin">Alice</user>"#
        let attributed = StructuredSyntaxHighlighter.xml(line: line)
        let nsAttr = NSAttributedString(attributed)

        #expect(nsAttr.length == (line as NSString).length)

        var colorFound = false
        nsAttr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: nsAttr.length)) { value, range, _ in
            if value != nil { colorFound = true }
        }
        #expect(colorFound, "XML highlight must convert with colors")
    }

    // MARK: - Real-World Payload Formatting & View Model Tests

    @Test func realWorldComplexJSONFormatsAndColors() throws {
        let complexJSON = """
        {
          "store": {
            "book": [
              {
                "category": "reference",
                "author": "Nigel Rees",
                "title": "Sayings of the Century",
                "price": 8.95
              },
              {
                "category": "fiction",
                "author": "Evelyn Waugh",
                "title": "Sword of Honour",
                "price": 12.99
              }
            ],
            "bicycle": {
              "color": "red",
              "price": 19.95,
              "available": true,
              "discount": null
            }
          }
        }
        """

        let formatted = try JSONFormatting.format(complexJSON, sortKeys: true, indentWidth: 2)
        #expect(!formatted.isEmpty)

        // Test each line through highlighter
        for line in formatted.components(separatedBy: "\n") {
            let highlighted = JSONSyntaxHighlighter.highlight(line: line)
            let nsAttr = NSAttributedString(highlighted)
            #expect(nsAttr.string == line)
        }
    }

    @Test func realWorldComplexSQLFormatsAndColors() throws {
        let complexSQL = """
        with recursive subordinates as (
            select employee_id, manager_id, full_name
            from employees
            where employee_id = 1
            union all
            select e.employee_id, e.manager_id, e.full_name
            from employees e
            inner join subordinates s on s.employee_id = e.manager_id
        )
        select employee_id, full_name
        from subordinates
        order by employee_id desc
        """

        let formatted = try SQLFormatting.format(complexSQL, options: .init(keywordCase: .upper, indentWidth: 2))
        #expect(!formatted.isEmpty)
        #expect(formatted.contains("WITH"))
        #expect(formatted.contains("SELECT"))

        for line in formatted.components(separatedBy: "\n") {
            let highlighted = StructuredSyntaxHighlighter.sql(line: line)
            let nsAttr = NSAttributedString(highlighted)
            #expect(nsAttr.string == line)
        }
    }

    @Test func realWorldYAMLFormatsAndColors() throws {
        let complexYAML = """
        version: "3.8"
        services:
          web:
            image: nginx:alpine
            ports:
              - "80:80"
            environment:
              NODE_ENV: production
              DEBUG: false
            restart: always
        """

        let formatted = try YAMLPrettifier.formatValidated(complexYAML)
        #expect(!formatted.isEmpty)

        for line in formatted.components(separatedBy: "\n") {
            let highlighted = StructuredSyntaxHighlighter.yaml(line: line)
            let nsAttr = NSAttributedString(highlighted)
            #expect(nsAttr.string == line)
        }
    }

    @Test func realWorldXMLFormatsAndColors() throws {
        let complexXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <configuration>
            <server port="8080" host="0.0.0.0">
                <ssl enabled="true" certificate="/etc/ssl/cert.pem"/>
            </server>
            <database>
                <driver>postgresql</driver>
                <url>jdbc:postgresql://localhost:5432/mydb</url>
                <credentials>
                    <username>admin</username>
                    <password>secret</password>
                </credentials>
            </database>
        </configuration>
        """

        let formatted = try XMLFormatting.format(complexXML, indentWidth: 2)
        #expect(!formatted.isEmpty)
        #expect(formatted.contains("<?xml"))
        #expect(formatted.contains("<server port=\"8080\""))

        for line in formatted.components(separatedBy: "\n") {
            let highlighted = StructuredSyntaxHighlighter.xml(line: line)
            let nsAttr = NSAttributedString(highlighted)
            #expect(nsAttr.string == line)
        }
    }

    @MainActor
    @Test func jsonFormatterInitializesWithCleanEmptyState() {
        let defaults = UserDefaults(suiteName: "CodeViewerSurfaceTests.\(UUID().uuidString)")!
        let store = ToolPreferenceStore(defaults: defaults)
        let model = JSONFormatterToolWorkspaceModel(preferences: store)
        #expect(model.input.isEmpty, "JSON formatter input must start empty without pre-seeded sample text")
        #expect(model.output.isEmpty, "JSON formatter output must start empty")
        #expect(model.error == nil)
        #expect(model.warning == nil)
    }

    @MainActor
    @Test func jsonFormatterPageMountsWithCleanEmptyStateInHostingView() {
        let defaults = UserDefaults(suiteName: "CodeViewerSurfaceTests.Mount.\(UUID().uuidString)")!
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let view = IndexJSONFormatterPage().environmentObject(repository)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        hostingView.layoutSubtreeIfNeeded()

        let key = JSONFormatterToolWorkspaceModel.key
        let model = repository.model(for: key)
        #expect(model.input.isEmpty, "JSON input must be completely empty on initial mount")
        #expect(model.output.isEmpty, "JSON output must be completely empty on initial mount")
    }

    @MainActor
    @Test func jsonFormatterEditorViewportsFitMinimumRootWindowDetailWidth() {
        let defaults = UserDefaults(suiteName: "CodeViewerSurfaceTests.Layout.\(UUID().uuidString)")!
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let view = IndexJSONFormatterPage().environmentObject(repository)
        let hostingView = NSHostingView(rootView: view)
        let rootWidth: CGFloat = 960
        let sidebarWidth: CGFloat = 220
        let detailWidth = rootWidth - sidebarWidth
        let container = NSView(frame: NSRect(x: 0, y: 0, width: rootWidth, height: 640))
        container.addSubview(hostingView)
        hostingView.frame = NSRect(x: sidebarWidth, y: 0, width: detailWidth, height: 640)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: rootWidth, height: 640),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer { window.close() }

        window.orderFront(nil)
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        #expect(window.contentView?.bounds.width == rootWidth)
        #expect(hostingView.bounds.width == detailWidth)

        let textViews = Self.findAllDescendants(of: hostingView, type: NSTextView.self)
        #expect(textViews.count >= 2, "JSON page must expose native input and output editors")
        for textView in textViews {
            guard let contentView = textView.enclosingScrollView?.contentView else {
                Issue.record("JSON editor must be hosted by a native scroll view")
                continue
            }
            let viewport = contentView.convert(contentView.bounds, to: hostingView)
            #expect(viewport.width > 0 && viewport.height > 0)
            #expect(viewport.minX >= -1 && viewport.maxX <= hostingView.bounds.maxX + 1,
                    "Editor viewport must remain inside the derived detail coordinate space")
        }
    }

    @MainActor
    @Test func textDiffEditorViewportsFitMinimumRootWindowDetailWidth() {
        let defaults = UserDefaults(suiteName: "CodeViewerSurfaceTests.Layout.Diff.\(UUID().uuidString)")!
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let view = IndexTextDiffPage().environmentObject(repository)
        let hostingView = NSHostingView(rootView: view)
        let rootWidth: CGFloat = 960
        let detailWidth: CGFloat = rootWidth - 220
        let container = NSView(frame: NSRect(x: 0, y: 0, width: rootWidth, height: 640))
        container.addSubview(hostingView)
        hostingView.frame = NSRect(x: 220, y: 0, width: detailWidth, height: 640)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: rootWidth, height: 640),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer { window.close() }
        window.orderFront(nil)
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        #expect(window.contentView?.bounds.width == rootWidth)
        #expect(hostingView.bounds.width == detailWidth)
        let textViews = Self.findAllDescendants(of: hostingView, type: NSTextView.self)
        #expect(textViews.count >= 2, "Diff page must expose at least two native editors")
        for textView in textViews {
            guard let contentView = textView.enclosingScrollView?.contentView else {
                Issue.record("Diff editor must be hosted by a native scroll view")
                continue
            }
            let viewport = contentView.convert(contentView.bounds, to: hostingView)
            #expect(viewport.width > 0 && viewport.height > 0)
            #expect(viewport.minX >= -1 && viewport.maxX <= hostingView.bounds.maxX + 1)
        }
    }

    @MainActor
    @Test func codeViewerSurfaceDynamicallyAdaptsTextContainerWidthOnFrameChange() {
        let view = IndexCodeViewerSurface(
            text: "<root><item>Very long line of formatted xml text that needs to wrap properly</item></root>",
            lineNumbers: true,
            fillsHeight: true
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 350, height: 400)
        hostingView.layoutSubtreeIfNeeded()

        guard let textView = Self.findDescendant(of: hostingView, type: NSTextView.self),
              let textContainer = textView.textContainer else {
            Issue.record("Expected NSTextView inside IndexCodeViewerSurface")
            return
        }

        let initialContainerWidth = textContainer.containerSize.width
        #expect(initialContainerWidth > 200 && initialContainerWidth < 350, "Initial container width should fit 350pt view")

        // Resize hosting view to wider container
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 400)
        hostingView.layoutSubtreeIfNeeded()

        let expandedContainerWidth = textContainer.containerSize.width
        #expect(expandedContainerWidth > 750, "Container width must expand past 750pt when resized to 900pt, not stuck at 300-400pt: was \(expandedContainerWidth)")

        // Shrink hosting view to narrower container
        hostingView.frame = NSRect(x: 0, y: 0, width: 250, height: 400)
        hostingView.layoutSubtreeIfNeeded()

        let shrunkContainerWidth = textContainer.containerSize.width
        #expect(shrunkContainerWidth < 200, "Container width must shrink below 200pt when resized to 250pt: was \(shrunkContainerWidth)")
    }

    @MainActor
    @Test func codeViewerKeepsExactFormatterOutputAcrossCanonicalEquivalentUpdates() throws {
        let options = SQLFormatting.Options(minify: true)
        let composed = try SQLFormatting.format("SELECT 'café' FROM users", options: options)
        let decomposed = try SQLFormatting.format("SELECT 'cafe\u{301}' FROM users", options: options)
        #expect(composed == decomposed)
        #expect(!composed.utf8.elementsEqual(decomposed.utf8))

        let model = ViewerModel(text: composed, syntax: .sql)
        let hostingView = NSHostingView(rootView: ViewerProbe(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 640, height: 260)
        hostingView.layoutSubtreeIfNeeded()
        guard let textView = Self.findDescendant(of: hostingView, type: NSTextView.self) else {
            Issue.record("Expected native code viewer")
            return
        }
        #expect(textView.string.utf8.elementsEqual(composed.utf8))

        model.text = decomposed
        let updated = Self.waitForViewerUpdate(hostingView) {
            textView.string.utf8.elementsEqual(decomposed.utf8)
        }
        #expect(updated)
        #expect(Self.findDescendant(of: hostingView, type: NSTextView.self) === textView,
                "The update must reuse the same representable and coordinator")
        #expect(textView.string.utf8.elementsEqual(decomposed.utf8),
                "The native viewer must keep the formatter's exact Unicode representation")

        model.text = composed
        #expect(Self.waitForViewerUpdate(hostingView) {
            textView.string.utf8.elementsEqual(composed.utf8)
        })
        #expect(Self.findDescendant(of: hostingView, type: NSTextView.self) === textView)
    }

    @MainActor
    @Test func codeViewerBatchesVisibleTokenEditsAndPreservesAttributes() {
        let text = "{" + Array(repeating: #""key":1"#, count: 2_000).joined(separator: ",") + "}"
        let model = ViewerModel(text: text, syntax: nil)
        let hostingView = NSHostingView(rootView: ViewerProbe(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 260)
        hostingView.layoutSubtreeIfNeeded()
        guard let textView = Self.findDescendant(of: hostingView, type: NSTextView.self),
              let storage = textView.textStorage else {
            Issue.record("Expected native text storage")
            return
        }

        textView.setSelectedRange(NSRange(location: 2, length: 3))
        let editCounter = TextStorageEditCounter()
        NotificationCenter.default.addObserver(
            editCounter,
            selector: #selector(TextStorageEditCounter.didProcessEditing(_:)),
            name: NSTextStorage.didProcessEditingNotification,
            object: storage
        )
        defer { NotificationCenter.default.removeObserver(editCounter) }

        model.syntax = .json
        let highlighted = Self.waitForViewerUpdate(hostingView) {
            storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
                == IndexSyntaxToken.Kind.key.nsColor
        }
        #expect(highlighted)

        #expect(editCounter.count > 0)
        #expect(editCounter.count <= 5,
                "Thousands of visible tokens should produce one color edit transaction")
        #expect(textView.string.utf8.elementsEqual(text.utf8))
        #expect(textView.selectedRange() == NSRange(location: 2, length: 3))
        #expect(storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
                == IndexSyntaxToken.Kind.key.nsColor)
        #expect(storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont != nil)
        #expect(storage.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle != nil)

        model.syntax = nil
        let reset = Self.waitForViewerUpdate(hostingView) {
            storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
                != IndexSyntaxToken.Kind.key.nsColor
        }
        #expect(reset)
        #expect(storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
                != IndexSyntaxToken.Kind.key.nsColor)

        let editsBeforeRehighlight = editCounter.count
        model.syntax = .json
        let highlightedAgain = Self.waitForViewerUpdate(hostingView) {
            storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
                == IndexSyntaxToken.Kind.key.nsColor
        }
        #expect(highlightedAgain)
        #expect(editCounter.count - editsBeforeRehighlight <= 5)

        model.text = ""
        #expect(Self.waitForViewerUpdate(hostingView) { textView.string.isEmpty })
        #expect(textView.string.isEmpty)
        #expect(storage.length == 0)
    }

    @MainActor
    @Test func codeViewerHighlightsNewlyVisibleLinesAfterScroll() async {
        let text = (0..<200).map { #"{"key":\#($0)}"# }.joined(separator: "\n")
        let model = ViewerModel(text: text, syntax: .json)
        let hostingView = NSHostingView(rootView: ViewerProbe(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer { window.close() }
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        guard let textView = Self.findDescendant(of: hostingView, type: NSTextView.self),
              let storage = textView.textStorage,
              let scrollView = textView.enclosingScrollView else {
            Issue.record("Expected scrollable native viewer")
            return
        }

        #expect(await Self.waitForAsyncHighlight(hostingView) {
            storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
                == IndexSyntaxToken.Kind.key.nsColor
        }, "The initial viewport must be highlighted before testing a distant line")
        let target = (text as NSString).range(of: #"{"key":199}"#).location + 2
        #expect(target > 2)
        #expect(storage.attribute(.foregroundColor, at: target, effectiveRange: nil) as? NSColor
                != IndexSyntaxToken.Kind.key.nsColor)

        textView.scrollRangeToVisible(NSRange(location: target, length: 1))
        let scrolledAndHighlighted = await Self.waitForAsyncHighlight(hostingView) {
            scrollView.contentView.bounds.minY > 0
                && storage.attribute(.foregroundColor, at: target, effectiveRange: nil) as? NSColor
                    == IndexSyntaxToken.Kind.key.nsColor
        }
        #expect(scrolledAndHighlighted,
                "viewport=\(scrollView.contentView.bounds), document=\(textView.frame), targetColor=\(String(describing: storage.attribute(.foregroundColor, at: target, effectiveRange: nil))), firstColor=\(String(describing: storage.attribute(.foregroundColor, at: 2, effectiveRange: nil)))")
        #expect(textView.string.utf8.elementsEqual(text.utf8))
    }

    @MainActor
    @Test func xmlFormatPagePanesExpandResponsivelyWithoutFixedDeadZones() {
        let defaults = UserDefaults(suiteName: "CodeViewerSurfaceTests.XMLResponsive.\(UUID().uuidString)")!
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let view = IndexXMLFormatPage().environmentObject(repository)
        let hostingView = NSHostingView(rootView: view)

        hostingView.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        hostingView.layoutSubtreeIfNeeded()

        let textViews = Self.findAllDescendants(of: hostingView, type: NSTextView.self)
        #expect(textViews.count >= 2, "Expected input and output NSTextViews in XML format page")

        // Resize to widescreen
        hostingView.frame = NSRect(x: 0, y: 0, width: 1400, height: 700)
        hostingView.layoutSubtreeIfNeeded()

        for tv in textViews {
            if let container = tv.textContainer {
                #expect(container.containerSize.width > 500, "Each split pane container width should exceed 500pt on 1400pt wide window, got \(container.containerSize.width)")
            }
        }
    }

    @MainActor
    private static func findDescendant<T: NSView>(of view: NSView, type: T.Type) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = findDescendant(of: subview, type: type) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private static func findAllDescendants<T: NSView>(of view: NSView, type: T.Type) -> [T] {
        var results: [T] = []
        if let match = view as? T { results.append(match) }
        for subview in view.subviews {
            results.append(contentsOf: findAllDescendants(of: subview, type: type))
        }
        return results
    }

    @MainActor
    private static func waitForViewerUpdate(
        _ hostingView: NSView,
        until condition: () -> Bool
    ) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        repeat {
            hostingView.layoutSubtreeIfNeeded()
            if condition() { return true }
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return condition()
    }

    @MainActor
    private static func waitForAsyncHighlight(
        _ hostingView: NSView,
        until condition: () -> Bool
    ) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        repeat {
            hostingView.layoutSubtreeIfNeeded()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return condition()
    }
}

@MainActor
private final class ViewerModel: ObservableObject {
    @Published var text: String
    @Published var syntax: IndexSyntaxKind?

    init(text: String, syntax: IndexSyntaxKind?) {
        self.text = text
        self.syntax = syntax
    }
}

private struct ViewerProbe: View {
    @ObservedObject var model: ViewerModel

    var body: some View {
        IndexCodeViewerSurface(text: model.text, lineNumbers: false, syntax: model.syntax)
    }
}

@MainActor
private final class TextStorageEditCounter: NSObject {
    private(set) var count = 0

    @objc func didProcessEditing(_ notification: Notification) {
        count += 1
    }
}
