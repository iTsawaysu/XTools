import Foundation
import Testing

/// 阶段③ Batch B 原生侧栏合同（design.md §1 / app-shell-performance §1.3）。
///
/// 三条源码结构探针，与 DesignSystemContractTests 同型的防再生产合同：
/// 1. 自绘侧栏链（Coordinator/TrackView/Layout/Entry/ScrollIndicator…）零残留；
/// 2. 收藏与折叠观察住在侧栏之下——RootView 不持有两者的 StateObject，
///    收藏切换/Section 折叠不重估壳层（rootBody=0 契约的侧栏半边）；
/// 3. 原生侧栏锚点：`List(.sidebar)` + `scrollContentBackground(.hidden)` +
///    整列系统 sidebar 材质（B0 决策：材质一块铺满、List 只画行）。
struct SidebarNativeShellContractTests {
    private struct ScanShapeError: Error {}

    @Test func retiredFlatSidebarChainStaysOutOfSources() throws {
        // 退役即退役：类型名不得在 Sources 代码中复活（注释里的历史说明经
        // 剥离后不计——与 DesignSystemContractTests 的 merged 样式同一口径）。
        let pattern = "SidebarNavigationList|SidebarNavigationTrack|SidebarNavigationLayout|SidebarNavigationEntry|SidebarScrollIndicator|SidebarSelectionIndicator|SidebarNavigationScrollAnchor|SidebarNavigationDocumentView"
        let hits = try Self.scanCode(pattern: pattern, directories: ["Sources"])
        #expect(hits.isEmpty, Comment(rawValue: "自绘侧栏链残留：\(Self.describe(hits))"))
    }

    @Test func sidebarObservationStaysBelowRootView() throws {
        // RootView 刻意不订阅收藏/折叠（B4：收藏切换只触发侧栏局部重估）；
        // 观察下沉在 SidebarNativeList。所有权经 init 透传（paletteRecents
        // 先例），Batch D 多窗口时升级为环境注入共享单例。
        let rootView = try Self.read("Sources/XTools/AppShell/RootView.swift")
        #expect(
            !rootView.contains("@StateObject private var favorites"),
            "RootView 不得以 StateObject 订阅 FavoritesStore（收藏切换会重估壳层）"
        )
        #expect(
            !rootView.contains("@StateObject private var sidebarSections"),
            "RootView 不得以 StateObject 订阅 SidebarSectionExpansionStore（折叠切换会重估壳层）"
        )
        #expect(
            !rootView.contains("isFavorite: selectedTool"),
            "工具栏收藏态不得在 RootView body 里求值（改由 FavoriteToolbarLabel 自行观察）"
        )

        let nativeList = try Self.read("Sources/XTools/AppShell/SidebarNativeList.swift")
        #expect(nativeList.contains("@ObservedObject var favorites"))
        #expect(nativeList.contains("@ObservedObject var sidebarSections"))
    }

    @Test func nativeListUsesSystemSidebarChrome() throws {
        let nativeList = try Self.read("Sources/XTools/AppShell/SidebarNativeList.swift")
        #expect(nativeList.contains("List(selection:"), "侧栏必须由原生 List(selection:) 承载")
        #expect(nativeList.contains(".listStyle(.sidebar)"), "侧栏必须使用系统 sidebar 列表样式")
        #expect(
            nativeList.contains(".scrollContentBackground(.hidden)"),
            "B0 决策：List 自带材质隐藏，整列由 SidebarMaterialBackground 铺一块全高系统材质"
        )
        #expect(nativeList.contains("NSVisualEffectView"), "材质铺底必须走 NSVisualEffectView(.sidebar)")
        #expect(
            nativeList.contains(".onMove(perform: onMoveFavorites)"),
            "拖拽排序仅收藏区启用（.onMove 不得出现在其他 Section）"
        )

        // S14：7pt 侧栏行圆角常量不得复活（注释剥离后判定）。
        let metrics = Self.stripComments(try Self.read("Sources/XTools/AppShell/SidebarMetrics.swift"))
        #expect(!metrics.contains("rowCornerRadius"))
    }
}

private extension SidebarNativeShellContractTests {
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

    static func swiftFiles(under directory: String) throws -> [URL] {
        let url = packageRoot().appendingPathComponent(directory)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
            throw ScanShapeError()
        }
        return (enumerator.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.path < $1.path }
    }

    /// 注释剥离（// 与 /* */，字符串感知）后按正则扫描，命中返回文件相对路径。
    static func scanCode(pattern: String, directories: [String]) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        let root = packageRoot().path + "/"
        var hits: [String] = []
        for file in try directories.flatMap({ try swiftFiles(under: $0) }) {
            let stripped = stripComments(try String(contentsOf: file, encoding: .utf8))
            let range = NSRange(stripped.startIndex..., in: stripped)
            if regex.firstMatch(in: stripped, range: range) != nil {
                hits.append(file.path.replacingOccurrences(of: root, with: ""))
            }
        }
        return hits
    }

    /// 与 DesignSystemContractTests 同型的注释剥离（// 与 /* */，字符串感知）。
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

    static func describe(_ hits: [String]) -> String {
        hits.sorted().joined(separator: ", ")
    }
}
