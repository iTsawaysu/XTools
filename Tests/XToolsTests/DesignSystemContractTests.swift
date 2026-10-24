import Foundation
import Testing

/// design-foundation 防再生产合同（design.md §6，Batch E）。
///
/// 五条合同全部是源码结构探针：对 Sources/ 做注释剥离后按正则扫描，与
/// 硬编码白名单做逐文件精确计数断言；不镜像任何实现。与
/// `tools/ui-lint.py` 的分工——ui-lint 管 ToolPages（除 Workbench）的逐文件
/// ratchet（`UILintContractTests` 已把它接进 swift test）；本合同把 Batch
/// B/C 收编后的基线冻结到整个 Sources 树（含 Workbench/Shared/AppShell/
/// XToolsDesign），并锁住组件族唯一性。
///
/// 白名单即合同：新增条目必须带豁免理由注释；条目失效（实际命中归零）
/// 同样报错，防止白名单静默腐烂。
struct DesignSystemContractTests {

    // MARK: - 合同 1：mono 12.5 唯一构造点

    @Test func monospacedCodeFontSizeStaysInTheAppKitMirror() throws {
        try expectExactCounts(
            pattern: #"monospacedSystemFont\(ofSize:\s*12\.5"#,
            scanning: ["Sources"],
            expected: [
                // AppKitMirror.codeBody()：SwiftUI 侧 ToolTypography.codeBody
                // token 的 NSFont 镜像，mono 12.5 的唯一合法构造点。
                "Sources/XToolsDesign/ToolTypography.swift": 1,
            ],
            because: "mono 12.5 只允许出现在 AppKitMirror.codeBody 定义本体，AppKit 调用侧一律引用镜像（design.md §6.1）"
        )
    }

    // MARK: - 合同 2：tone 描边透明度孤儿值白名单

    @Test func toneBorderOpacityOrphansStayWhitelisted() throws {
        try expectExactCounts(
            pattern: #"\.opacity\(0\.(?:25|26|34|45|55|7)\)"#,
            scanning: ["Sources/XTools"],
            expected: [
                // 0.55：alpha 滑杆的棋盘格功能纹理（读 controlBackgroundColor），
                // 非 tone 描边——tone 描边一律走 ToolTheme.*Border 双模式 token。
                "Sources/XTools/ToolPages/Workbench/Controls/IndexSliderAndNumberInput.swift": 1,
                // 0.7：禁用态字形压暗（前景色，基于已低档的 textTertiary；
                // 套 opacityDisabled 0.40 会双重压暗）。
                "Sources/XTools/ToolPages/Workbench/Controls/IndexControls.swift": 1,
            ],
            because: "0.25/0.26/0.34/0.45/0.55/0.7 是收编前的 tone 描边自造透明度（design.md §6.2）；重新出现即为体系外字面量"
        )
    }

    // MARK: - 合同 3：裸 cornerRadius 数值

    @Test func cornerRadiusNumericLiteralsStayWhitelisted() throws {
        try expectExactCounts(
            pattern: #"\.cornerRadius\(\s*[0-9]|cornerRadius:\s*[0-9]|\w*[Cc]ornerRadius:\s*CGFloat\s*=\s*[0-9]"#,
            scanning: ["Sources"],
            expected: [
                // washCornerRadius 2：LocatingWash token 定义本体——命名圆角
                // 常量的唯一合法形式就是 token 定义点。
                "Sources/XToolsDesign/ToolMotion.swift": 1,
                // SidebarMetrics.rowCornerRadius 7（S14）已随阶段③原生侧栏
                // 迁移删除：行级圆角交给系统 List(.sidebar)，白名单条目同步
                // 移除，7pt 侧栏行圆角不得复活。
            ],
            because: "圆角必须走 ToolMetrics.CornerRadius / IndexSurfaceShape 阶梯（design.md §6.3）；命名常量仅允许 token 定义点"
        )
    }

    // MARK: - 合同 4：组件族唯一性

    @Test func buttonStyleFamilyStaysAtExactlyFourStyles() throws {
        let declared = try Self.captureGroups(
            pattern: #"(?:struct|final class|class|enum|extension)\s+(\w+)\s*:[^{}]{0,120}?ButtonStyle\b"#,
            directories: ["Sources"]
        )
        // design.md §3.1：hover/press 收敛为共享实现后，全库仅此四种。
        let survivors = [
            "IndexButtonStyle",
            "IndexIconActionButtonStyle",
            "IndexQuietChromeStyle",
            "ToolInteractionFeedbackStyle",
        ]
        var problems: [String] = []
        if Set(declared) != Set(survivors) {
            problems.append(
                "ButtonStyle 声明集合 \(declared.sorted()) ≠ 合同四样式 \(survivors.sorted())"
            )
        }
        // 被 C1/C2 合并掉的样式名不得复活（注释里的历史说明经剥离后不计）。
        let merged = [
            "IndexSmallButtonStyle",
            "IndexBareButtonStyle",
            "IndexOptionsMenuTriggerStyle",
            "IndexOptionsMenuRowStyle",
            "IndexOptionPressableButtonStyle",
            "SidebarChromeButtonStyle",
            "QuietTitlebarButtonStyle",
            "CommandTriggerButtonStyle",
        ]
        for name in merged {
            let hits = try Self.scan(pattern: "\\b\(name)\\b", directories: ["Sources"])
            if !hits.isEmpty {
                problems.append("已合并样式 \(name) 复活：\(Self.describe(hits))")
            }
        }
        #expect(problems.isEmpty, Comment(rawValue: problems.sorted().joined(separator: "\n")))
    }

    @Test func readOnlyOutputSurfaceStaysASingleImplementation() throws {
        // 唯一实现：IndexOutputSurface（AppKit 底座，plain/code 两种呈现，C3 合并）。
        try expectExactCounts(
            pattern: #"(?:struct|final class|class|enum)\s+IndexOutputSurface\b"#,
            scanning: ["Sources"],
            expected: [
                "Sources/XTools/ToolPages/Workbench/Text/IndexOutputSurface.swift": 1,
            ],
            because: "只读输出面仅允许一套实现（design.md §3.2，C3 合并）"
        )
        // 纯转发门面与旧只读面不得复活。
        try expectExactCounts(
            pattern: #"\bIndexWorkspaceOutputSurface\b"#,
            scanning: ["Sources"],
            expected: [:],
            because: "IndexWorkspaceOutputSurface（纯转发门面）已在 C3 删除，不得复活"
        )
        try expectExactCounts(
            pattern: #"\bIndexReadOnlyTextSurface\b"#,
            scanning: ["Sources"],
            expected: [:],
            because: "IndexReadOnlyTextSurface 已并入 IndexOutputSurface 的 plain 呈现（C3），不得复活"
        )
        // IndexCodeViewerSurface 仅允许以指向统一面的迁移期 typealias 存在。
        try expectExactCounts(
            pattern: #"\bIndexCodeViewerSurface\b"#,
            scanning: ["Sources"],
            expected: [
                // 迁移期别名（阶段④清理）：旧名唯一允许的残留形式。
                "Sources/XTools/ToolPages/Workbench/Text/IndexOutputSurface.swift": 1,
            ],
            because: "IndexCodeViewerSurface 能力已平移进 IndexOutputSurface 的 code 呈现（C3），独立实现不得复活"
        )
        try expectExactCounts(
            pattern: #"typealias\s+IndexCodeViewerSurface\s*=\s*IndexOutputSurface"#,
            scanning: ["Sources"],
            expected: [
                "Sources/XTools/ToolPages/Workbench/Text/IndexOutputSurface.swift": 1,
            ],
            because: "IndexCodeViewerSurface 只能以指向 IndexOutputSurface 的 typealias 过渡形式存在"
        )
    }

    @Test func emptyStateStaysASingleEntryPoint() throws {
        try expectExactCounts(
            pattern: #"(?:struct|final class|class|enum)\s+IndexEmptyState\b"#,
            scanning: ["Sources"],
            expected: [
                "Sources/XTools/Shared/Components/IndexEmptyState.swift": 1,
            ],
            because: "空态唯一入口 IndexEmptyState（design.md §3.3，C4 收敛），新空态不得另起炉灶"
        )
        try expectExactCounts(
            pattern: #"enum\s+IndexEmptyStateCopy\b"#,
            scanning: ["Sources"],
            expected: [
                "Sources/XTools/Shared/Components/IndexEmptyState.swift": 1,
            ],
            because: "空态文案家族 IndexEmptyStateCopy 与唯一入口同点定义"
        )
    }

    // MARK: - 合同 5：裸 padding/spacing 字面量冻结为 0

    @Test func barePaddingAndSpacingLiteralsStayFrozenAtZero() throws {
        // 空白名单 = Batch B 收编后全树冻结（含 ui-lint 不扫的 Workbench/
        // Shared/AppShell 与 XToolsDesign；ToolPages 部分由 ui-lint ratchet
        // 另行把关）。确需豁免：在本字典加条目并写理由注释。三元/表达式
        // 字面量（如 `spacing: cond ? 8 : 12`）与 ui-lint 口径一致，不计数
        //（implement.md Batch A+B 白名单第 7 条）。
        let frozen: [String: Int] = [:]
        try expectExactCounts(
            pattern: #"\.padding\(\s*(?:\.(?:horizontal|vertical|top|leading|trailing|bottom|all)\s*,\s*)?[0-9]"#,
            scanning: ["Sources/XTools", "Sources/XToolsDesign"],
            expected: frozen,
            because: "裸 padding 数值 = 0（design.md §6.5，Batch B 收编后冻结；新增需改白名单并说明理由）"
        )
        try expectExactCounts(
            pattern: #"\bspacing:\s*[1-9][0-9]*"#,
            scanning: ["Sources/XTools", "Sources/XToolsDesign"],
            expected: frozen,
            because: "裸 spacing 非零数值 = 0（design.md §6.5；`spacing: 0` 显式紧凑合法保留）"
        )
    }
}

// MARK: - Scanner（与 LocalizationSourceContractTests 同型的结构探针）

private extension DesignSystemContractTests {
    struct ScanShapeError: Error {}

    static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func swiftFiles(under directories: [String]) throws -> [URL] {
        let root = packageRoot()
        var files: [URL] = []
        for directory in directories {
            let url = root.appendingPathComponent(directory)
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
                throw ScanShapeError()
            }
            files += (enumerator.allObjects as? [URL] ?? [])
                .filter { $0.pathExtension == "swift" && !$0.lastPathComponent.hasPrefix(".") }
        }
        return files.sorted { $0.path < $1.path }
    }

    /// 逐行计数：注释剥离后每行首次命中记一次（与 ui-lint 的逐行口径一致，
    /// 行号保留用于失败信息）。
    static func scan(pattern: String, directories: [String]) throws -> [String: [Int]] {
        let regex = try NSRegularExpression(pattern: pattern)
        let root = packageRoot().path + "/"
        var hits: [String: [Int]] = [:]
        for file in try swiftFiles(under: directories) {
            let key = file.path.replacingOccurrences(of: root, with: "")
            let stripped = stripComments(try String(contentsOf: file, encoding: .utf8))
            for (index, line) in stripped.components(separatedBy: "\n").enumerated() {
                guard regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else {
                    continue
                }
                hits[key, default: []].append(index + 1)
            }
        }
        return hits
    }

    /// 整文件捕获第 1 组：用于类型名声明收集（协议列表可跨行）。
    static func captureGroups(pattern: String, directories: [String]) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        return try swiftFiles(under: directories).flatMap { file in
            let stripped = stripComments(try String(contentsOf: file, encoding: .utf8))
            let range = NSRange(stripped.startIndex..., in: stripped)
            return regex.matches(in: stripped, range: range).compactMap { match in
                Range(match.range(at: 1), in: stripped).map { String(stripped[$0]) }
            }
        }
    }

    /// 与 LocalizationSourceContractTests 同型的注释剥离（// 与 /* */，
    /// 字符串感知）；额外保留块注释内的换行，行号与原文件对齐。
    static func stripComments(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var inString = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if inString {
                out.append(c)
                if c == "\\", text.index(after: i) < text.endIndex {
                    out.append(text[text.index(after: i)])
                    i = text.index(after: text.index(after: i))
                    continue
                }
                if c == "\"" {
                    inString = false
                }
                i = text.index(after: i)
                continue
            }
            if c == "\"" {
                inString = true
                out.append(c)
                i = text.index(after: i)
                continue
            }
            if c == "/", text.index(after: i) < text.endIndex {
                let next = text[text.index(after: i)]
                if next == "/" {
                    while i < text.endIndex, text[i] != "\n" {
                        i = text.index(after: i)
                    }
                    continue
                }
                if next == "*" {
                    i = text.index(after: text.index(after: i))
                    while i < text.endIndex {
                        if text[i] == "*", text.index(after: i) < text.endIndex,
                           text[text.index(after: i)] == "/" {
                            i = text.index(after: text.index(after: i))
                            break
                        }
                        if text[i] == "\n" {
                            out.append("\n")
                        }
                        i = text.index(after: i)
                    }
                    continue
                }
            }
            out.append(c)
            i = text.index(after: i)
        }
        return out
    }

    static func describe(_ hits: [String: [Int]]) -> String {
        hits.sorted(by: { $0.key < $1.key })
            .map { "\($0.key):\($0.value.map(String.init).joined(separator: ","))" }
            .joined(separator: " ")
    }

    /// 白名单双向精确匹配：多于允许值报「体系外字面量」，少于允许值报
    /// 「条目失效」，两边都必须显式改合同。
    func expectExactCounts(
        pattern: String,
        scanning directories: [String],
        expected: [String: Int],
        because reason: String
    ) throws {
        let hits = try Self.scan(pattern: pattern, directories: directories)
        var problems: [String] = []
        for (file, lines) in hits {
            let allowed = expected[file] ?? 0
            if lines.count > allowed {
                problems.append(
                    "\(file)：命中 \(lines.count) 处（行 \(lines.map(String.init).joined(separator: ", "))），白名单允许 \(allowed)——改用 token，确需豁免先在白名单加理由注释"
                )
            } else if lines.count < allowed {
                problems.append("\(file)：白名单允许 \(allowed) 但实际 \(lines.count) 处——收编有进展，请同步下调白名单")
            }
        }
        for (file, allowed) in expected where hits[file] == nil {
            problems.append("\(file)：白名单允许 \(allowed) 但扫描 0 命中——条目已失效，请删除")
        }
        #expect(
            problems.isEmpty,
            Comment(rawValue: reason + "\n" + problems.sorted().joined(separator: "\n"))
        )
    }
}
