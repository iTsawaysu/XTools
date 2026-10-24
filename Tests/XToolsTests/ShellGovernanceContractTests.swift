import Foundation
import Testing

/// 阶段③ Batch C 壳层治理合同（design.md §3：RootView 分家 + 外观链收敛）。
///
/// 源码结构探针，与 SidebarNativeShellContractTests 同型的防再生产合同：
/// 1. 导航 5 状态 + 持久化 didSet 全部住在 `ShellNavigationModel`，RootView
///    只组合（无 @Published、无偏好键写入、StateObject 清单冻结）；
/// 2. 外观链四挂点收敛：`AppThemeEnvironment` 唯一解析位且内聚
///    `WindowAppearanceOwner` 单应用器，RootView / 偏好设置 sheet 只消费
///    单挂点，RootView 不再有第二处 colorScheme 解析。
struct ShellGovernanceContractTests {
    private struct ScanShapeError: Error {}

    // MARK: - C1 导航分家

    @Test func navigationStatesLiveInShellNavigationModel() throws {
        let model = try Self.read("Sources/XTools/AppShell/ShellNavigationModel.swift")
        for state in [
            "selectedToolID",
            "searchText",
            "pageTransitionIntent",
            "autoResumeLastTool",
            "sidebarVisibility",
        ] {
            #expect(
                model.contains("@Published var \(state)"),
                Comment(rawValue: "导航状态 \(state) 必须下沉 ShellNavigationModel")
            )
        }

        let rootView = Self.stripComments(try Self.read("Sources/XTools/AppShell/RootView.swift"))
        #expect(!rootView.contains("@Published"), "RootView 不得持有导航状态本体（只组合）")
        #expect(!rootView.contains("AppShellPreferenceKeys."), "shell 偏好持久化必须住在 ShellNavigationModel 的 didSet")
        #expect(!rootView.contains("RootViewModel"), "RootViewModel 已分家退役，不得复活")
        #expect(
            rootView.contains("@StateObject private var navigation: ShellNavigationModel"),
            "RootView 经单一 StateObject 持有导航模型"
        )
    }

    @Test func shellPersistenceKeysStayUnchanged() throws {
        // 持久化键全部不变（tools.shell.*.v1 语义原样平移，RootViewPersistenceTests 做行为断言）。
        let keys = Self.stripComments(try Self.read("Sources/XTools/Shared/ToolPreferenceStore.swift"))
        for key in [
            "tools.shell.autoResumeLastTool.v1",
            "tools.shell.selectedToolID.v1",
            "tools.shell.sidebarVisibility.v1",
        ] {
            #expect(keys.contains(key), Comment(rawValue: "shell 持久化键不得变更：\(key)"))
        }
    }

    @Test func rootViewStateObjectInventoryIsPinned() throws {
        // 分家后的 RootView StateObject 清单（分家前 9 项 → 分家后 9 项 →
        // Batch D +1：clipboardSuggestions（Smart Detection「为你建议」，
        // 低频采样观察面）；workspaceRepository 引用自 ShellSharedStores
        // 共享单例（D4），仍以 StateObject 包装、观察面不变）。
        let rootView = try Self.read("Sources/XTools/AppShell/RootView.swift")
        let expected = [
            "@StateObject private var navigation: ShellNavigationModel",
            "@StateObject private var toastCenter = ToolToastCenter()",
            "@StateObject private var fileInputPanelCoordinator = FileInputPanelCoordinator()",
            "@StateObject private var fileOutputPanelCoordinator = FileOutputPanelCoordinator()",
            "@StateObject private var workspaceRepository: ToolWorkspaceRepository",
            "@StateObject private var dashboardStore: DashboardStore",
            "@StateObject private var smartPaste = SmartPasteMonitor()",
            "@StateObject private var hubSegmentEntryHint = HubSegmentEntryHint()",
            "@StateObject private var clipboardSuggestions = ClipboardSuggestionModel()",
            "@StateObject private var systemAppearanceSource: SystemAppearanceSource",
        ]
        for line in expected {
            #expect(rootView.contains(line), Comment(rawValue: "RootView StateObject 清单漂移：缺 \(line)"))
        }
        #expect(
            Self.occurrences(of: "@StateObject", in: rootView) == expected.count,
            "RootView StateObject 数量必须与冻结清单一致（发现多余观察面）"
        )
    }

    // MARK: - C2 外观链收敛

    @Test func appearanceChainConvergesToSingleResolverAndApplier() throws {
        let owner = Self.stripComments(try Self.read("Sources/XTools/AppShell/WindowAppearanceOwner.swift"))
        // 唯一应用器挂点内聚在 AppThemeEnvironment 本体。
        #expect(
            owner.contains(".background(WindowAppearanceOwner(preference: preference))"),
            "AppThemeEnvironment 必须内聚 WindowAppearanceOwner 单应用器"
        )

        let rootView = Self.stripComments(try Self.read("Sources/XTools/AppShell/RootView.swift"))
        let sheet = Self.stripComments(try Self.read("Sources/XTools/AppShell/RootPreferencesSheet.swift"))
        #expect(
            Self.occurrences(of: "appThemeEnvironment(preference:", in: rootView) == 1,
            "RootView 外观挂点必须收敛为单处 AppThemeEnvironment"
        )
        #expect(
            Self.occurrences(of: "appThemeEnvironment(preference:", in: sheet) == 1,
            "偏好设置 sheet（独立窗口）只经单挂点消费外观链"
        )
        #expect(!rootView.contains("WindowAppearanceOwner(preference:"), "RootView 不得直挂窗口应用器")
        #expect(!sheet.contains("WindowAppearanceOwner(preference:"), "sheet 不得直挂窗口应用器")
        #expect(
            !rootView.contains("resolvedColorScheme"),
            "RootView 的第二处 colorScheme 解析已退役（工具栏经解析输入消费同一函数）"
        )
        #expect(
            Self.stripComments(try Self.read("Sources/XTools/AppShell/TitlebarView.swift"))
                .contains("SystemAppearanceSource.resolvedColorScheme("),
            "工具栏与 AppThemeEnvironment 消费同一唯一解析函数"
        )
    }

    // MARK: - helpers（与 SidebarNativeShellContractTests 同口径）

    static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func read(_ relativePath: String) throws -> String {
        let url = packageRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ScanShapeError()
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func occurrences(of needle: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: needle, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<text.endIndex
        }
        return count
    }

    /// 注释剥离（// 与 /* */，字符串感知）——只用于挂点计数，防止注释里的
    /// 历史说明干扰判定。
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
                        i = text.index(after: text.index(after: i))
                    }
                    continue
                }
            }
            out.append(c)
            i = text.index(after: i)
        }
        return out
    }
}
