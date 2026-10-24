import Foundation

/// ⌘K「别名 + 空格」直达模式（阶段③ Batch D，design.md §6）：query 以
/// 「别名 + 一个尾随空格」命中某工具的 `ToolAlias`（label 或 matching
/// 变体，大小写/变音折叠后精确比较）时，面板切换为该工具的直达列表——
/// 列表只含该工具（分段 Hub 额外列出各 segment 行），回车经
/// `launchFromPalette` 打开并触发焦点契约；Esc 退回普通搜索。
///
/// 解析规则：
/// - query 恰有一个尾随空格且去尾后非空；别名本体允许内部空格（如
///   "Data URL" 的 "data url" 变体）。
/// - 同一别名命中多个工具时取注册表顺序第一个（registry 序即产品意图
///   顺序：formatter 先于 diff）；未命中返回 nil，面板保持普通搜索。
/// - 无别名语义的普通查询（无尾随空格）永不触发。
struct CommandPaletteDirectEntry: Equatable {
    let tool: RegisteredTool
    /// 命中的别名展示标签（直达提示行用）。
    let aliasLabel: String
    /// 分段 Hub 的 segment 行（该工具别名声明过的 segment 去重保序）。
    let segmentRows: [SegmentRow]

    struct SegmentRow: Equatable {
        let label: String
        let segment: String
    }

    /// 别名折叠语义与 ToolSearchText 一致（大小写 + 变音不敏感）；别名
    /// 全部是 ASCII/中文字面量，折叠只影响大小写与变体拼写。
    private static func foldedAlias(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    static func parse(query: String, registry: ToolRegistry) -> CommandPaletteDirectEntry? {
        guard query.hasSuffix(" ") else { return nil }
        let body = String(query.dropLast())
        guard !body.isEmpty else { return nil }
        // 尾随空格是「进入直达」的键；换行/制表符结尾不是别名语义。
        guard !query.contains("\n"), !query.contains("\t") else { return nil }

        let foldedQuery = foldedAlias(body)
        for tool in registry.allTools() {
            for alias in tool.aliases {
                let labelHit = foldedAlias(alias.label) == foldedQuery
                let variantHit = !labelHit && alias.matching.contains {
                    foldedAlias($0) == foldedQuery
                }
                guard labelHit || variantHit else { continue }

                var seenSegments = Set<String>()
                var segmentRows: [SegmentRow] = []
                for candidate in tool.aliases {
                    guard let segment = candidate.segment,
                          seenSegments.insert(segment).inserted else { continue }
                    segmentRows.append(SegmentRow(label: candidate.label, segment: segment))
                }
                return CommandPaletteDirectEntry(
                    tool: tool,
                    aliasLabel: alias.label,
                    segmentRows: segmentRows
                )
            }
        }
        return nil
    }
}
