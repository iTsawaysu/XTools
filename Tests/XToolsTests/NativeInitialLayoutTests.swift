import AppKit
import SwiftUI
import Testing
@testable import XTools
@testable import XToolsCore

@MainActor
@Suite(.serialized)
struct NativeInitialLayoutTests {
    @Test func diffInitialHeightDoesNotTypesetEntireMultilineDocument() throws {
        let text = String(repeating: "line 0123456789\n", count: 100_000)
        let view = IndexDiffTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        view.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude)
        view.string = text
        let manager = try #require(view.layoutManager)
        let before = view.undoManager
        let height = IndexDiffTextLayoutGeometry.documentHeight(for: view)
        #expect(height > 400)
        #expect(manager.firstUnlaidCharacterIndex() < (text as NSString).length / 10,
                "Initial height must not synchronously lay out the full document")
        #expect(view.string.utf8.elementsEqual(text.utf8))
        #expect(view.undoManager === before)
    }

    @Test func codeViewerFirstViewportDoesNotTypesetEntireMultilineDocument() throws {
        let text = String(repeating: "{\"value\":1}\n", count: 100_000)
        let host = NSHostingView(rootView: IndexCodeViewerSurface(text: text, syntax: .json))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        host.layoutSubtreeIfNeeded()
        let view = try #require(findTextView(in: host))
        let manager = try #require(view.layoutManager)
        #expect(manager.firstUnlaidCharacterIndex() < (text as NSString).length / 10,
                "Read-only first viewport must leave offscreen paragraphs unlaid")
        #expect(view.string.utf8.elementsEqual(text.utf8))
        view.selectAll(nil)
        #expect(view.selectedRange().length == (text as NSString).length)
    }

    @Test func previewKeepsSafeUnicodePrefixAndFullTextIsExplicit() {
        let limit = IndexSyntaxHighlightBudget.maximumLineUTF16
        let samples = [
            String(repeating: "x", count: limit - 3) + "👩🏽‍💻" + String(repeating: "z", count: limit),
            String(repeating: "x", count: limit - 2) + "e" + String(repeating: "\u{301}", count: limit),
            "e" + String(repeating: "\u{301}", count: limit * 2)
        ]
        for text in samples {
            let plan = IndexCodePreviewPlan.make(text: text, permitsFullText: false)
            #expect(plan.previewCharacterCount != nil)
            #expect((plan.displayedText as NSString).length < limit)
            #expect(text.utf8.starts(with: plan.displayedText.utf8))
            // A prefix of whole source Characters must agree byte for byte.
            #expect(String(text.prefix(plan.displayedText.count)).utf8.elementsEqual(plan.displayedText.utf8))
            let full = IndexCodePreviewPlan.make(text: text, permitsFullText: true)
            #expect(full.previewCharacterCount == nil)
            #expect(full.displayedText.utf8.elementsEqual(text.utf8))
        }
        #expect(IndexCodePreviewPlan.make(text: samples[2], permitsFullText: false).displayedText.isEmpty)
        let multiline = String(repeating: "short line\n", count: 10_000)
        #expect(IndexCodePreviewPlan.make(text: multiline, permitsFullText: false).previewCharacterCount == nil)
        let softLines = String(repeating: "short\u{2028}", count: 10_000)
        #expect(IndexCodePreviewPlan.make(text: softLines, permitsFullText: false).previewCharacterCount != nil,
                "Soft line separators must not hide one oversized TextKit paragraph")
        let paragraphs = String(repeating: "short\u{2029}", count: 10_000)
        #expect(IndexCodePreviewPlan.make(text: paragraphs, permitsFullText: false).previewCharacterCount == nil)
    }

    @Test func giantCodeViewerUsesExplicitBoundedNativePreviewAndKeepsEditorAcrossSourceChange() throws {
        let text = String(repeating: "x", count: 1_000_000)
        let host = NSHostingView(rootView: IndexCodeViewerSurface(text: text, syntax: .json))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        host.layoutSubtreeIfNeeded()
        let view = try #require(findTextView(in: host))
        let expected = IndexCodePreviewPlan.make(text: text, permitsFullText: false)
        #expect(view.string == expected.displayedText)
        view.selectAll(nil)
        #expect(view.selectedRange().length == (expected.displayedText as NSString).length)
        host.rootView = IndexCodeViewerSurface(text: "e\u{301}", syntax: .json)
        host.layoutSubtreeIfNeeded()
        let updated = try #require(findTextView(in: host))
        #expect(updated === view)
        #expect(updated.string.utf8.elementsEqual("e\u{301}".utf8))
    }

    @Test func previewNoticeAndActionsKeepAccessibleNamesInsideLabeledOutput() async throws {
        let text = String(repeating: "x", count: 40_000)
        let plan = IndexCodePreviewPlan.make(text: text, permitsFullText: false)
        let previewCount = try #require(plan.previewCharacterCount)
        let host = NSHostingView(rootView: IndexCodeViewerSurface(text: text, syntax: .json)
            .accessibilityLabel("输出")
            .environment(\.accessibilityEnabled, true))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        func waitUntil(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(2)
            repeat {
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                window.displayIfNeeded()
                CATransaction.flush()
                if condition() { return }
                try await Task.sleep(for: .milliseconds(10))
            } while ContinuousClock.now < deadline
            let tree = previewAccessibilityElements(in: window).map {
                "\($0.role ?? "nil"):\($0.label ?? ""):\(($0.value ?? "").prefix(80))"
            }.joined(separator: " | ")
            try #require(condition(), "Preview accessibility did not publish its expected state: \(tree)")
        }
        try await waitUntil {
            previewAccessibilityElements(in: window).filter {
                $0.role == NSAccessibility.Role.button.rawValue
                    && ["输出", "复制全文", "载入全文"].contains($0.label ?? "")
            }.count == 2
                && findTextView(in: host)?.string == plan.displayedText
        }
        let editor = try #require(findTextView(in: host))
        let elements = previewAccessibilityElements(in: window)
        let notices = elements.flatMap { [$0.label, $0.value].compactMap { $0 } }
        #expect(notices.contains {
            $0.contains("选择与查找仅限预览")
                && $0.replacingOccurrences(of: ",", with: "").contains(String(previewCount))
        }, "The output label must not hide the preview range and selection/find limitation")
        let buttons = elements.filter { $0.role == NSAccessibility.Role.button.rawValue }
        #expect(buttons.contains { $0.label == "复制全文" })
        let load = try #require(buttons.first { $0.label == "载入全文" })
        #expect(!buttons.contains { $0.label == "输出" })
        #expect(load.press())
        try await waitUntil { editor.string.utf8.elementsEqual(text.utf8) }
        #expect(findTextView(in: host) === editor,
                "The accessible full-load action must preserve the native editor")
        editor.selectAll(nil)
        #expect(editor.selectedRange().length == (text as NSString).length)
        try await waitUntil {
            !previewAccessibilityElements(in: window).contains { $0.label == "载入全文" }
        }
    }

    @Test func lazyDocumentCanRevealLastSourceRangeAndKeepStableRepeatedGeometry() throws {
        let text = String(repeating: "line 0123456789\n", count: 10_000) + "END_👩🏽‍💻\n"
        let view = IndexDiffTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        view.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude)
        IndexNativeViewportLayout.configure(view)
        view.string = text
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        scroll.documentView = view
        func synchronize() {
            IndexDiffTextLayoutGeometry.synchronizeTextGeometry(for: view, visibleWidth: 500,
                minimumHeight: 300, trailingReadingGuard: 16)
        }
        synchronize()
        let target = (text as NSString).range(of: "END_👩🏽‍💻")
        view.setSelectedRange(target)
        view.scrollRangeToVisible(target)
        synchronize()
        let manager = try #require(view.layoutManager)
        let container = try #require(view.textContainer)
        let glyphs = manager.glyphRange(forCharacterRange: target, actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
        #expect(rect.intersects(scroll.documentVisibleRect))
        let initialOrigin = scroll.contentView.bounds.origin
        for _ in 0..<5 { synchronize() }
        #expect(scroll.contentView.bounds.origin == initialOrigin)
        #expect(view.selectedRange() == target)
        #expect(view.string.utf8.elementsEqual(text.utf8))
        // A far Diff target deliberately completes the preceding layout so
        // both panes retain exact source-line Y positions.
        #expect(!manager.allowsNonContiguousLayout)
        let end = (text as NSString).length
        view.setSelectedRange(NSRange(location: end, length: 0))
        view.scrollRangeToVisible(NSRange(location: end, length: 0))
        synchronize()
        let visibleBlocks = IndexDiffTextLayoutGeometry.lineBlockRects(for: view,
            visibleRect: scroll.documentVisibleRect)
        let terminal = try #require(visibleBlocks[10_002])
        #expect(terminal.intersects(scroll.documentVisibleRect),
                "The terminal empty LF line must remain reachable without full layout")
    }

    @Test func indexedLineRangesRetainAllExistingNewlineSemantics() {
        for separator in ["\r\n", "\r", "\n", "\u{85}", "\u{2028}", "\u{2029}"] {
            let text = "👩🏽‍💻" + separator + "e\u{301}" + separator
            let ranges = DiffSourceText.lineRanges(in: text)
            let source = text as NSString
            let lines = ranges.map { source.substring(with: $0) }
            if separator == "\r" || separator == "\n" {
                #expect(lines == ["👩🏽‍💻", "e\u{301}", ""])
            } else if separator == "\r\n" {
                // CRLF is one Swift Character: the existing hasSuffix checks
                // do not append the terminal empty entry for this separator.
                #expect(lines == ["👩🏽‍💻", "e\u{301}"])
            } else {
                // Preserve the pre-existing Core contract: only CR/LF are
                // stripped from ranges, although NSString recognizes others.
                #expect(lines == ["👩🏽‍💻" + separator, "e\u{301}" + separator])
            }
        }
        #expect(DiffSourceText.lineRanges(in: "") == [NSRange(location: 0, length: 0)])
    }

    @Test func realDiffOuterHostKeepsLazyFirstFrameAndCanNavigateBothWrappedTails() async throws {
        let count = 10_000
        let shared = (1..<count).map { "shared line \($0)" }
        let leftTail = "LEFT_END_👩🏽‍💻 " + String(repeating: "wrap ", count: 35)
        let rightTail = "RIGHT_END_👩🏽‍💻 " + String(repeating: "wrap ", count: 70)
        let left = (shared + [leftTail]).joined(separator: "\n")
        let right = (shared + [rightTail]).joined(separator: "\n")
        let rows = (1...count).map { number in
            DiffAlignedRow(kind: number == count ? .changed : .unchanged,
                left: DiffAlignedCell(lineNumber: number,
                    text: number == count ? leftTail : shared[number - 1], indent: 0),
                right: DiffAlignedCell(lineNumber: number,
                    text: number == count ? rightTail : shared[number - 1], indent: 0))
        }
        func root(request: DiffDifferenceNavigationRequest? = nil) -> IndexEditableDiffMergeView {
            IndexEditableDiffMergeView(left: .constant(left), right: .constant(right),
                leftPlaceholder: "Left", rightPlaceholder: "Right",
                leftAccessibilityLabel: "Left", rightAccessibilityLabel: "Right",
                leftDisplayText: nil, rightDisplayText: nil, rows: rows, syntax: .plain,
                foldUnchanged: false, differenceNavigationRequest: request)
        }
        let host = NSHostingView(rootView: root())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 500),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let editors = descendants(in: host, type: IndexDiffTextView.self)
        #expect(editors.count == 2)
        let outer = try #require(descendants(in: host, type: NSScrollView.self).first {
            $0.hasVerticalScroller && !($0.documentView is NSTextView)
        })
        let document = try #require(outer.documentView)
        for editor in editors {
            let manager = try #require(editor.layoutManager)
            #expect(manager.firstUnlaidCharacterIndex() < editor.textStorage!.length / 2,
                    "The real Diff host, row decoration and wrapping must stay lazy")
        }
        host.rootView = root(request: DiffDifferenceNavigationRequest(id: 1, forward: true))
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(outer.contentView.bounds.minY > 0)
        var tailOrigins: [CGFloat] = []
        for (editor, tail) in zip(editors, [leftTail, rightTail]) {
            let manager = try #require(editor.layoutManager)
            let container = try #require(editor.textContainer)
            let range = (editor.string as NSString).range(of: tail)
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
            let documentRect = editor.convert(rect, to: document)
            tailOrigins.append(documentRect.minY)
            #expect(documentRect.maxY <= document.bounds.maxY + 1,
                    "The shared document must include the longer wrapped side")
            #expect(documentRect.intersects(outer.documentVisibleRect),
                    "Both final difference cells must be reachable in the outer viewport")
        }
        #expect(abs(tailOrigins[0] - tailOrigins[1]) <= 1,
                "Identical source prefixes must put the same tail row at the same Y")
        let origin = outer.contentView.bounds.origin
        for _ in 0..<5 { host.layoutSubtreeIfNeeded() }
        #expect(outer.contentView.bounds.origin == origin)
        #expect(editors[0].string.utf8.elementsEqual(left.utf8))
        #expect(editors[1].string.utf8.elementsEqual(right.utf8))
        // A resize must preserve the actual native editors and full sources.
        window.setContentSize(NSSize(width: 760, height: 500))
        host.layoutSubtreeIfNeeded()
        let resized = descendants(in: host, type: IndexDiffTextView.self)
        #expect(zip(editors, resized).allSatisfy { $0 === $1 })
    }

    private func descendants<T: NSView>(in view: NSView, type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(in: $0, type: type) }
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        for child in view.subviews {
            if let found = findTextView(in: child) { return found }
        }
        return nil
    }

    private func previewAccessibilityElements(in window: NSWindow) -> [PreviewAccessibilityElement] {
        var pending = [PreviewAccessibilityElement(object: window)]
        var result: [PreviewAccessibilityElement] = []
        var visited = Set<ObjectIdentifier>()
        while let element = pending.popLast(), result.count < 2_000 {
            guard visited.insert(ObjectIdentifier(element.object)).inserted else { continue }
            result.append(element)
            pending.append(contentsOf: element.children)
        }
        return result
    }
}

/// SwiftUI semantic nodes expose public AX selectors without consistently
/// declaring NSAccessibilityProtocol; preserve their actual runtime types.
@MainActor
private struct PreviewAccessibilityElement {
    let object: NSObject
    private var dynamic: AnyObject { object }
    var role: String? { dynamic.accessibilityRole?()?.rawValue ?? attribute("AXRole") as? String }
    var label: String? {
        dynamic.accessibilityLabel?() ?? attribute("AXDescription") as? String ?? attribute("AXTitle") as? String
    }
    var value: String? {
        let selector = NSSelectorFromString("accessibilityValue")
        let value = object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
        return value as? String ?? attribute("AXValue") as? String
    }
    var children: [PreviewAccessibilityElement] {
        let children = dynamic.accessibilityChildren?() ?? attribute("AXChildren") as? [Any] ?? []
        return children.compactMap { ($0 as? NSObject).map(PreviewAccessibilityElement.init) }
    }
    func press() -> Bool {
        if let result = dynamic.accessibilityPerformPress?() { return result }
        let names = NSSelectorFromString("accessibilityActionNames")
        let action = NSSelectorFromString("accessibilityPerformAction:")
        guard object.responds(to: names), object.responds(to: action),
              let actions = object.perform(names)?.takeUnretainedValue() as? [String],
              actions.contains("AXPress") else { return false }
        object.perform(action, with: "AXPress")
        return true
    }
    private func attribute(_ name: String) -> Any? {
        let selector = NSSelectorFromString("accessibilityAttributeValue:")
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector, with: name)?.takeUnretainedValue()
    }
}
