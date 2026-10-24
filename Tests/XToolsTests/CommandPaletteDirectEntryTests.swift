@testable import XTools
import Foundation
import Testing

/// 阶段③ Batch D 命令面板增强的行为测试：
/// 1. 「别名+空格」直达模式解析（label / matching 变体 / 折叠 / 多命中取
///    注册表序第一个 / segment 行展开）；
/// 2. ⌘↑/⌘↓ 跨分组跳转（落地页与过滤态 sections 语义、边界不动）；
/// 3. 直达快照的行模型与 deepLink segment 通道；
/// 4. 「为你建议」落地页置顶与缓存键（suggestion 变化重建）。
@MainActor
struct CommandPaletteDirectEntryTests {
    // MARK: - 别名解析

    @Test func aliasWithTrailingSpaceEntersDirectMode() throws {
        let entry = try #require(CommandPaletteDirectEntry.parse(query: "json ", registry: .default))
        #expect(entry.tool.id == "formatter")
        #expect(entry.aliasLabel == "JSON")
        // formatter 是分段 Hub：直达列表应展开全部 segment 行。
        let segments = entry.segmentRows.map(\.segment)
        #expect(segments == ["json", "xml", "yaml", "sql"])
    }

    @Test func aliasMatchingVariantsAndCaseFoldingResolve() throws {
        // matching 变体（url/percent）与大小写折叠。
        let url = try #require(CommandPaletteDirectEntry.parse(query: "url ", registry: .default))
        #expect(url.tool.id == "text-encoding")
        #expect(url.segmentRows.map(\.segment) == ["base64", "url", "ascii", "unicode"])

        let percent = try #require(CommandPaletteDirectEntry.parse(query: "percent ", registry: .default))
        #expect(percent.tool.id == "text-encoding")

        let upper = try #require(CommandPaletteDirectEntry.parse(query: "BASE64 ", registry: .default))
        #expect(upper.tool.id == "text-encoding")
    }

    @Test func nonSegmentToolsYieldNoSegmentRows() throws {
        // 进制转换的别名（hex）不带 segment。
        let entry = try #require(CommandPaletteDirectEntry.parse(query: "hex ", registry: .default))
        #expect(entry.tool.id == "integer-base-converter")
        #expect(entry.segmentRows.isEmpty)
    }

    @Test func ambiguousAliasTakesFirstRegistryHit() throws {
        // "json " 同时命中 formatter 与 diff 的 JSON 别名：注册表序 formatter 在前。
        let entry = try #require(CommandPaletteDirectEntry.parse(query: "json ", registry: .default))
        #expect(entry.tool.id == "formatter")
    }

    @Test func plainQueriesNeverTriggerDirectMode() {
        #expect(CommandPaletteDirectEntry.parse(query: "json", registry: .default) == nil) // 无尾随空格
        #expect(CommandPaletteDirectEntry.parse(query: "json  ", registry: .default) == nil) // 双空格（主体含空格且不匹配别名）
        #expect(CommandPaletteDirectEntry.parse(query: " ", registry: .default) == nil) // 空主体
        #expect(CommandPaletteDirectEntry.parse(query: "nosuchalias ", registry: .default) == nil)
        #expect(CommandPaletteDirectEntry.parse(query: "json\n", registry: .default) == nil)
    }

    @Test func internalWhitespaceAliasResolves() throws {
        // "Data URL" 别名的内部空格变体（"data url"）。
        let entry = try #require(CommandPaletteDirectEntry.parse(query: "data url ", registry: .default))
        #expect(entry.tool.id == "base64-file-converter")
    }

    // MARK: - 直达快照

    @Test func directSnapshotContainsToolRowAndSegmentRowsWithDeepLinks() throws {
        let model = CommandPaletteSessionModel(registry: .default, actions: [])
        #expect(model.setQuery("json "))
        let direct = try #require(model.directEntry)

        let snapshot = model.snapshot
        // 无空行兜底：行 = sectionTitle + 工具行 + 4 个 segment 行。
        #expect(direct.tool.id == "formatter")
        let ids = snapshot.rows.map(\.id)
        #expect(ids.contains("tool.formatter"))
        for segment in direct.segmentRows.map(\.segment) {
            #expect(ids.contains("direct.formatter.\(segment)"))
            let row = try #require(snapshot.rows.first { $0.id == "direct.formatter.\(segment)" })
            #expect(snapshot.deepLinkSegment(for: row) == segment, "segment 行经 deepLink 通道打开对应分段")
        }
        // 工具行本身不带 segment。
        let toolRow = try #require(snapshot.rows.first { $0.id == "tool.formatter" })
        #expect(snapshot.deepLinkSegment(for: toolRow) == nil)
        #expect(snapshot.selectableCount == 5)
        #expect(snapshot.sectionCountsByTitle["直达"] == 5)
    }

    @Test func leavingDirectQueryRestoresFilteredProjection() throws {
        let model = CommandPaletteSessionModel(registry: .default, actions: [])
        #expect(model.setQuery("json "))
        #expect(model.directEntry != nil)
        #expect(model.setQuery("json"))
        #expect(model.directEntry == nil)
        // 普通过滤态恢复「动作 + 工具」结构。
        #expect(model.snapshot.rows.contains { $0.id == "title.工具" })
    }

    // MARK: - ⌘↑/⌘↓ 跨分组（过滤态 sections：动作/工具）

    @Test func sectionJumpLandsOnNeighborSectionFirstRowInFilteredState() throws {
        let registry = ToolRegistry.default
        let model = CommandPaletteSessionModel(registry: registry, actions: [])
        #expect(model.setQuery("base"))
        var state = model.navigationState

        // 过滤态 sections = 动作（0 行,被跳过）+ 工具：单 section,⌘↓ 不动。
        let bounds = model.snapshot.selectableSectionBounds()
        #expect(bounds.count == 1)
        let jumpedAtSingleSection = state.jumpActiveAcrossSections(by: 1, in: model.snapshot)
        #expect(!jumpedAtSingleSection)

        // 用动作命中的查询构造两 section（动作/工具）。
        let model2 = CommandPaletteSessionModel(registry: registry, actions: [
            CommandActionEntry(
                id: .copyGeneratedUUID,
                title: "生成并复制 UUID",
                subtitle: nil,
                systemImage: "barcode"
            )
        ])
        #expect(model2.setQuery("uuid"))
        let twoBounds = model2.snapshot.selectableSectionBounds()
        #expect(twoBounds.count == 2, "命中动作与工具时应构成 动作/工具 两 section")
        var state2 = model2.navigationState

        // ⌘↓：从工具区跳到动作区首行。
        let firstToolIndex = twoBounds[1].lowerBound
        state2.setActiveSelectableIndex(firstToolIndex, in: model2.snapshot)
        let jumpedAtLastSection = state2.jumpActiveAcrossSections(by: 1, in: model2.snapshot)
        #expect(!jumpedAtLastSection, "已是最末 section,⌘↓ 不动")
        let jumpedBackToActions = state2.jumpActiveAcrossSections(by: -1, in: model2.snapshot)
        #expect(jumpedBackToActions)
        #expect(state2.activeRowID(in: model2.snapshot) == "command.copyGeneratedUUID")

        // ⌘↑：从动作区首行再往上——已是最前 section,不动。
        let jumpedBeforeFirstSection = state2.jumpActiveAcrossSections(by: -1, in: model2.snapshot)
        #expect(!jumpedBeforeFirstSection)
    }

    @Test func sectionJumpLandsOnNeighborSectionFirstRowInLandingState() {
        // 落地页 sections = 动作（4 条 shell 命令,与 RootView.commandBaseActions
        // 同形）+ 分类×7（最近使用为空被跳过）。
        let actions = CommandActionID.allCases.map { id in
            CommandActionEntry(id: id, title: id.rawValue, subtitle: nil, systemImage: "circle")
        }
        let model = CommandPaletteSessionModel(registry: .default, actions: actions)
        var state = model.navigationState

        let bounds = model.snapshot.selectableSectionBounds()
        #expect(bounds.count == 8)
        #expect(bounds.first?.count == 4, "动作 section：4 条 shell 命令")

        // 激活第 2 section（第一个分类）首行,⌘↑ 应回动作 section 首行。
        state.setActiveSelectableIndex(bounds[1].lowerBound, in: model.snapshot)
        let actionFirstID = state.activeRowID(in: model.snapshot)
        state.setActiveSelectableIndex(bounds[2].lowerBound, in: model.snapshot)
        let jumpedToNeighbor = state.jumpActiveAcrossSections(by: -1, in: model.snapshot)
        #expect(jumpedToNeighbor)
        #expect(state.activeRowID(in: model.snapshot) == actionFirstID)

        // 最末 section ⌘↓ 不动。
        state.setActiveSelectableIndex(bounds[7].lowerBound, in: model.snapshot)
        let jumpedPastLastSection = state.jumpActiveAcrossSections(by: 1, in: model.snapshot)
        #expect(!jumpedPastLastSection)
    }

    // MARK: - 「为你建议」（落地页置顶 + 缓存）

    @Test func suggestionSectionLeadsTheLandingPageAndInvalidatesCache() throws {
        let model = CommandPaletteSessionModel(registry: .default, actions: [])
        let before = model.snapshot

        let suggestion = ClipboardSuggestionModel.Suggestion(
            kind: .json,
            toolID: "formatter",
            toolTitle: "格式化",
            systemImage: "curlybraces.square",
            message: "剪贴板中有 JSON",
            segment: "json"
        )
        model.updateSuggestions(suggestion)

        let after = model.snapshot
        #expect(after.rows.first?.id == "title.为你建议")
        let suggestionRow = try #require(after.rows.first { $0.id == "suggestion.json" })
        #expect(suggestionRow.toolID == "formatter")
        #expect(after.selectableCount == before.selectableCount + 1)

        // 移除建议：落地页恢复,且无残留建议行。
        model.updateSuggestions(nil)
        #expect(model.snapshot.rows.first?.id != "title.为你建议")
        #expect(!model.snapshot.rows.contains { $0.id == "suggestion.json" })
    }

    @Test func suggestionDoesNotAppearInFilteredState() throws {
        let model = CommandPaletteSessionModel(registry: .default, actions: [])
        let suggestion = ClipboardSuggestionModel.Suggestion(
            kind: .json,
            toolID: "formatter",
            toolTitle: "格式化",
            systemImage: "curlybraces.square",
            message: "剪贴板中有 JSON",
            segment: "json"
        )
        #expect(model.setQuery("base"))
        model.updateSuggestions(suggestion)
        // 过滤态不展示建议区（仅落状态）。
        #expect(!model.snapshot.rows.contains { $0.id == "suggestion.json" })
        // 清空查询回落地页后出现。
        #expect(model.setQuery(""))
        #expect(model.snapshot.rows.first?.id == "title.为你建议")
    }
}
