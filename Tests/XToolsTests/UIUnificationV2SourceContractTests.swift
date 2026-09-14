import Foundation
import Testing

@testable import XTools

/// UI 统一重构 2.0（Clay Warmth）的防回潮契约。
///
/// 十一条规则对应 `docs/ui-unification-v2-master-plan.md` §六 R5；每条都是
/// 「单一真相源」的编译外看门：令牌/共享组件之外的位置不允许再出现旧写法。
struct UIUnificationV2SourceContractTests {
    private let categoryDirs = [
        "Sources/XTools/ToolPages/Converter/",
        "Sources/XTools/ToolPages/Crypto/",
        "Sources/XTools/ToolPages/Development/",
        "Sources/XTools/ToolPages/Image/",
        "Sources/XTools/ToolPages/Time/",
        "Sources/XTools/ToolPages/Utility/",
        "Sources/XTools/ToolPages/Web/",
    ]

    // MARK: 1. 面板单一密度

    @Test func rule1_panelStaysSingleDensity() throws {
        let pageShell = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexPageShell.swift")
        doesNotContain(pageShell, "chromeDensity", "IndexPanel must stay single-density — no standard/workbench fork may return")
    }

    // MARK: 2. 圆角字面量归零

    @Test func rule2_cornerRadiusLiteralsAreGone() throws {
        for (path, source) in try allSources() {
            let matches = Self.matches(in: source, pattern: "cornerRadius: *[0-9]")
            expectEmpty(matches, path, "must use ToolMetrics.CornerRadius tokens")
        }
    }

    // MARK: 3. 裸数字字体归零

    @Test func rule3_rawPointSizesOnlyLiveInTypography() throws {
        // Typography 与其 AppKit 镜像之外禁止裸数字字号（IconSize 令牌除外）。
        for (path, source) in try allSources(excluding: ["Sources/XTools/Shared/ToolTypography.swift"]) {
            let matches = Self.matches(in: source, pattern: #"\.system\(size: *[0-9]"#)
            expectEmpty(matches, path, "must size fonts through ToolTypography/ToolMetrics.IconSize")
        }
    }

    // MARK: 4. 系统语义色归零（暖调 text* 令牌单一真相源）

    @Test func rule4_systemSemanticColorsAreGone() throws {
        for (path, source) in try allSources() {
            let matches = Self.matches(
                in: source,
                pattern: #"\.foregroundStyle\(\.(secondary|primary|tertiary)\)|Color\.(secondary|primary)\b"#
            )
            expectEmpty(matches, path, "must use ToolTheme.text* tokens instead of system semantic colors")
        }
    }

    // MARK: 5. 处理中指示单一入口

    @Test func rule5_progressViewsLiveOnlyInTheProgressComponents() throws {
        let allowed = [
            "Sources/XTools/ToolPages/Workbench/Controls/IndexProgressLabel.swift",
            "Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift",
        ]
        for (path, source) in try allSources() {
            guard !allowed.contains(path) else { continue }
            #expect(
                !source.contains("ProgressView("),
                Comment(rawValue: "\(path) must use IndexProgressLabel/IndexProgressSpinner/IndexProgressMotionLabel instead of a bare ProgressView")
            )
        }
    }

    // MARK: 6. 空态文案走 IndexEmptyStateCopy

    @Test func rule6_emptyStateCopyUsesTheCanonicalTable() throws {
        let emptyState = try readSource("Sources/XTools/Shared/Components/IndexEmptyState.swift")
        contains(emptyState, "enum IndexEmptyStateCopy", "Empty-state copy must keep one canonical table")
        let basicAuth = try readSource("Sources/XTools/ToolPages/Web/BasicAuthGeneratorPage.swift")
        let userAgent = try readSource("Sources/XTools/ToolPages/Web/UserAgentParserPage.swift")
        let password = try readSource("Sources/XTools/ToolPages/Crypto/PasswordGeneratorPage.swift")
        let token = try readSource("Sources/XTools/ToolPages/Crypto/TokenGeneratorPage.swift")
        contains(basicAuth, "title: IndexEmptyStateCopy.noParsedResult", "Basic Auth must use canonical parsed-result copy")
        contains(basicAuth, "message: IndexEmptyStateCopy.autoParse(\"Basic Auth 请求头或 Base64 凭据\")", "Basic Auth must use canonical parse copy")
        contains(userAgent, "title: IndexEmptyStateCopy.noParsedResult", "User-Agent must use canonical parsed-result copy")
        contains(password, "IndexEmptyStateCopy.autoGenerate(\"字符集\")", "Password generation must use canonical empty copy")
        contains(token, "IndexEmptyStateCopy.autoGenerate(\"格式\")", "Token generation must use canonical empty copy")
        for (path, source) in try allSources(excluding: ["Sources/XTools/Shared/Components/IndexEmptyState.swift"]) {
            let matches = Self.matches(in: source, pattern: "输入文本后自动显示|暂无生成结果\"|输出将显示在这里\"")
            expectEmpty(matches, path, "must pull canonical empty-state copy from IndexEmptyStateCopy")
        }
    }

    // MARK: 7. .buttonStyle(.plain) 收归共享组件

    @Test func rule7_plainButtonStyleLivesInSharedComponents() throws {
        for dir in categoryDirs {
            let urls = try FileManager.default.contentsOfDirectory(atPath: dir)
                .filter { $0.hasSuffix(".swift") }
            for file in urls {
                let source = try readSource(dir + file)
                #expect(
                    !source.contains(".buttonStyle(.plain)"),
                    Comment(rawValue: "\(dir)\(file) must use Index* button styles or IndexBareButtonStyle for page-local custom chrome")
                )
            }
        }
    }

    // MARK: 8. 成功反馈文案单一真相源

    @Test func rule8_successCopyLivesInOneTable() throws {
        for (path, source) in try allSources(excluding: ["Sources/XTools/Shared/ToolFeedbackCopy.swift"]) {
            let matches = Self.matches(
                in: source,
                pattern: "已复制到剪贴板|完整输出已复制|图片已保存|五个部署文件已保存"
            )
            expectEmpty(matches, path, "must pull success copy from ToolFeedbackCopy")
        }
    }

    // MARK: 9. 禁止同步模态文件对话框

    @Test func rule9_runModalIsBanned() throws {
        for (path, source) in try allSources() {
            #expect(
                !source.contains("runModal"),
                Comment(rawValue: "\(path) must use the sheet-based FileInputPanel/FileOutputPanel clients instead of a synchronous modal loop")
            )
        }
    }

    // MARK: 10. 工具页不得停留在未迁移默认语义

    @Test func rule10_pagesMustDeclareRealWorkspaceSemantics() throws {
        let semantics = try readSource("Sources/XTools/ToolPages/Workbench/PageChrome/IndexWorkspaceSemantics.swift")
        contains(semantics, "case unmigratedPageDefault", "The protective default must exist as the shared component default")
        for dir in categoryDirs {
            let urls = try FileManager.default.contentsOfDirectory(atPath: dir)
                .filter { $0.hasSuffix(".swift") }
            for file in urls {
                let source = try readSource(dir + file)
                #expect(
                    !source.contains("unmigratedPageDefault"),
                    Comment(rawValue: "\(dir)\(file) must declare a real workspace semantic instead of the unmigrated default")
                )
            }
        }
    }

    // MARK: 阴影配方单一真相源

    @Test func shadowsFlowThroughTheRecipeTokens() throws {
        for (path, source) in try allSources() {
            let matches = Self.matches(in: source, pattern: #"\.shadow\(\s*color:"#)
            expectEmpty(matches, path, "must use .toolShadow(ToolTheme.Shadow...) recipes instead of raw shadow calls")
        }
    }

    @Test func workbenchUsesNamedControlsAndOwnsItsSession() throws {
        let dashboard = try readSource("Sources/XTools/AppShell/DashboardView.swift")
        let workbench = try readSource("Sources/XTools/AppShell/HomeContentWorkbench.swift")
        let session = try readSource("Sources/XTools/AppShell/HomeContentSession.swift")

        contains(dashboard, "ToolWorkspaceHost(key: HomeContentSession.key)", "Workbench input must stay in the window-scoped session repository")
        contains(dashboard, "ToolMetrics.Workbench.mainMaxWidth", "Workbench layout must use the approved named geometry tokens")
        contains(dashboard, "Shortcut(id: \"json-formatter\"", "Workbench must expose real registered shortcut identifiers")
        contains(dashboard, "Shortcut(id: \"color-picker\"", "Workbench must keep all six approved default shortcuts")
        doesNotContain(dashboard, "DashboardWaterfall", "Retired waterfall rendering must not remain in the V3 workbench")
        doesNotContain(dashboard, "showsLayoutEditor", "V3 workbench must not retain card-layout editing")
        contains(workbench, "IndexTextArea(", "Workbench input must use the shared native text surface")
        contains(workbench, "IndexCopyButton(", "Workbench result copy must use the shared feedback control")
        contains(workbench, "HomeContentAction.allCases", "Workbench must derive its action menu from the approved Core action set")
        contains(workbench, "WorkbenchSecondaryButton(title: \"粘贴\"", "Clipboard input must have one explicit paste control")
        contains(workbench, "private func paste()", "Clipboard reading must stay owned by the explicit paste action")
        doesNotContain(session, "NSPasteboard", "Home session must not import or monitor clipboard content")
    }

    // MARK: - Helpers

    private func allSources(excluding: [String] = []) throws -> [(path: String, source: String)] {
        let roots = ["Sources/XTools"]
        var results: [(String, String)] = []
        let fileManager = FileManager.default
        for root in roots {
            let enumerator = fileManager.enumerator(atPath: root)
            while let next = enumerator?.nextObject() as? String {
                guard next.hasSuffix(".swift") else { continue }
                let path = "\(root)/\(next)"
                guard !excluding.contains(path) else { continue }
                results.append((path, try readSource(path)))
            }
        }
        return results
    }

    private static func matches(in source: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { result in
            guard let range = Range(result.range, in: source) else { return nil }
            return String(source[range])
        }
    }

    private func readSource(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func contains(_ source: String, _ needle: String, _ message: String) {
        #expect(source.contains(needle), Comment(rawValue: message))
    }

    private func doesNotContain(_ source: String, _ needle: String, _ message: String) {
        #expect(!source.contains(needle), Comment(rawValue: message))
    }

    private func expectEmpty(_ matches: [String], _ path: String, _ message: String) {
        #expect(matches.isEmpty, Comment(rawValue: "\(path): \(message) found \(matches)"))
    }
}
