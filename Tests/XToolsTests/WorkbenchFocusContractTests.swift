import AppKit
import SwiftUI
import Testing
@testable import XTools

/// 阶段③ Batch C 焦点契约（workbenchFocusToken，design.md §4 / PRD 需求 5）。
///
/// 源码结构探针锁锚点（壳注入 / 组件族消费 / 试点页声明），真窗口行为
/// 用例验证 makeFirstResponder 通道：声明首位输入在请求到达时取焦、
/// inactive 请求不抢焦、token 更新可再聚焦（重试纪律同 palette
/// searchFocusToken：请求恒等门控 + 有界补试，成功后不再抢回）。
@Suite(.serialized)
struct WorkbenchFocusContractTests {
    private struct ScanShapeError: Error {}

    // MARK: - 源码锚点

    @Test func focusContractAnchors() throws {
        let focus = try Self.read("Sources/XTools/ToolPages/Workbench/Surface/WorkbenchFocus.swift")
        #expect(focus.contains("struct WorkbenchFocusRequest"))
        #expect(focus.contains("var workbenchFocusRequest: WorkbenchFocusRequest"))
        #expect(focus.contains("var workbenchFocusTarget: Bool"))
        #expect(focus.contains("func workbenchFocusTarget()"))

        let surface = try Self.read("Sources/XTools/ToolPages/Workbench/Surface/WorkbenchSurface.swift")
        #expect(surface.contains("var focusRequestToken: Int? = nil"), "壳必须有 focusTarget 声明槽")
        #expect(
            surface.contains(".environment(\\.workbenchFocusRequest, workbenchFocusRequest)"),
            "壳必须把聚焦请求经环境下发"
        )

        let field = try Self.read("Sources/XTools/ToolPages/Workbench/Text/IndexTextComponents.swift")
        #expect(field.contains("func requestFocus(_ textField: NSTextField, request: WorkbenchFocusRequest)"))
        #expect(field.contains("func requestFocus(_ textView: NSTextView, request: WorkbenchFocusRequest)"))
        let segment = try Self.read("Sources/XTools/ToolPages/Workbench/Controls/IndexControlledSegmentInput.swift")
        #expect(segment.contains("func requestFocus(_ textField: NSTextField, request: WorkbenchFocusRequest)"))
        for file in [field, segment] {
            #expect(
                Self.occurrences(of: "@Environment(\\.workbenchFocusRequest)", in: file) >= 1,
                "组件族必须经环境消费聚焦请求"
            )
        }
    }

    @Test func pilotPagesDeclareFirstInput() throws {
        // 4 试点页中 3 个有文本输入的页面声明首位输入；UUIDGenerator 无文本
        // 输入（stepper/分段），无首位输入可声明（聚焦契约空实现，见
        // WorkbenchSurface 声明槽注释）。
        let dateTime = try Self.read("Sources/XTools/ToolPages/Time/DateTimeConverterPage.swift")
        #expect(dateTime.contains(".workbenchFocusTarget()"), "DateTimeConverter 首输入 = 时间戳字段")
        let regex = try Self.read("Sources/XTools/ToolPages/Development/RegexTesterPage.swift")
        #expect(regex.contains(".workbenchFocusTarget()"), "RegexTester 首输入 = 表达式字段")
        let base64 = try Self.read("Sources/XTools/ToolPages/Converter/Base64FilePage.swift")
        #expect(base64.contains(".workbenchFocusTarget()"), "Base64File 首输入 = 解码输入区")
        #expect(base64.contains("focusRequestToken: firstInputFocusToken"), "useAsInput 走壳声明槽")
        #expect(base64.contains("firstInputFocusToken += 1"), "「用作输入」递增契约 token")
    }

    // MARK: - 真窗口行为

    @MainActor
    @Test func declaredFirstInputTakesFirstResponderWhenRequestArrives() async throws {
        let fixture = try FocusFixture(view: Self.field(probe: .init(generation: 1, token: 0)))
        defer { fixture.close() }

        try await Self.waitUntil("字段编辑器接管 firstResponder") {
            fixture.firstTextFieldEditor != nil
        }
        #expect(fixture.isFieldEditorFirstResponder)
    }

    @MainActor
    @Test func inactiveRequestLeavesFirstResponderAlone() async throws {
        let fixture = try FocusFixture(view: Self.field(probe: .inactive))
        defer { fixture.close() }
        fixture.settle()

        try? await Task.sleep(for: .milliseconds(150))
        fixture.settle()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(!fixture.isFieldEditorFirstResponder, "generation 0（停靠/未声明）不得抢焦")
    }

    @MainActor
    @Test func tokenUpdateRefocusesAfterUserMovesFocus() async throws {
        var request = WorkbenchFocusRequest(generation: 1, token: 0)
        let fixture = try FocusFixture(view: Self.field(probe: request))
        defer { fixture.close() }
        try await Self.waitUntil("首次聚焦") { fixture.isFieldEditorFirstResponder }

        // 用户移焦后，token 更新（同一代际）触发再聚焦；旧请求不重放。
        fixture.window.makeFirstResponder(nil)
        fixture.settle()
        #expect(!fixture.isFieldEditorFirstResponder)

        request = WorkbenchFocusRequest(generation: 1, token: 1)
        fixture.rootView = AnyView(Self.field(probe: request))
        fixture.settle()
        try await Self.waitUntil("token 更新后再聚焦") { fixture.isFieldEditorFirstResponder }
    }

    @MainActor
    @Test func declaredTextAreaTakesFirstResponderWhenRequestArrives() async throws {
        let fixture = try FocusFixture(view:
            IndexTextArea(placeholder: "焦点区域", text: .constant(""), minHeight: 80)
                .workbenchFocusTarget()
                .environment(\.workbenchFocusRequest, WorkbenchFocusRequest(generation: 1, token: 0))
                .frame(width: 320, height: 120)
        )
        defer { fixture.close() }

        try await Self.waitUntil("文本视图接管 firstResponder") {
            fixture.isTextViewFirstResponder
        }
        #expect(fixture.isTextViewFirstResponder)
    }

    // MARK: - helpers

    private static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func read(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ScanShapeError()
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: needle, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<text.endIndex
        }
        return count
    }

    // MARK: - fixtures

    @MainActor
    private static func field(probe request: WorkbenchFocusRequest) -> some View {
        IndexTextInput(placeholder: "焦点输入", text: .constant(""))
            .workbenchFocusTarget()
            .environment(\.workbenchFocusRequest, request)
            .frame(width: 300, height: 44)
    }

    @MainActor
    private final class FocusFixture {
        let window: NSWindow
        let hostingView: NSHostingView<AnyView>
        private let suiteName = "WorkbenchFocusContractTests.\(UUID().uuidString)"

        init(view: some View) throws {
            hostingView = NSHostingView(rootView: AnyView(
                view.environment(\._accessibilityReduceMotion, true)
            ))
            hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 160)
            window = NSWindow(
                contentRect: hostingView.frame,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hostingView
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeKey()
            settle()
        }

        var rootView: AnyView {
            get { hostingView.rootView }
            set {
                hostingView.rootView = newValue
                settle()
            }
        }

        func settle() {
            hostingView.layoutSubtreeIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()
        }

        func close() {
            window.resignKey()
            window.orderOut(nil)
            window.contentView = nil
        }

        private var textViews: [NSTextView] {
            Self.descendants(of: hostingView).compactMap { $0 as? NSTextView }
        }

        private var textFields: [NSTextField] {
            Self.descendants(of: hostingView).compactMap { $0 as? NSTextField }
        }

        var firstTextFieldEditor: NSText? {
            textFields.first?.currentEditor()
        }

        var isFieldEditorFirstResponder: Bool {
            guard let editor = firstTextFieldEditor else { return false }
            return window.firstResponder === editor
        }

        var isTextViewFirstResponder: Bool {
            // 区分 textarea 本体与字段编辑器：textarea 自身是 NSTextView。
            textViews.contains { window.firstResponder === $0 && !$0.isFieldEditor }
        }

        static func descendants(of view: NSView) -> [NSView] {
            var result: [NSView] = []
            for child in view.subviews {
                result.append(child)
                result.append(contentsOf: descendants(of: child))
            }
            return result
        }
    }

    @MainActor
    private static func waitUntil(
        _ label: String,
        timeout: TimeInterval = 3,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        Issue.record("等待超时：\(label)")
    }
}
