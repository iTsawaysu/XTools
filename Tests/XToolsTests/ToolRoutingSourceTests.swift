@testable import XTools
import SwiftUI
import Testing

struct ToolRoutingSourceTests {
    @Test func defaultRegistryHasConsistentRegistrations() {
        let registry = ToolRegistry.default
        let groups = registry.categoryGroups()
        let categoryIDs = Set(groups.map(\.category.id))
        let tools = groups.flatMap(\.tools)
        let toolIDs = tools.map(\.id)

        #expect(!tools.isEmpty)
        #expect(registry.toolCount == tools.count)
        #expect(Set(toolIDs).count == toolIDs.count)

        for tool in tools {
            #expect(categoryIDs.contains(tool.categoryID))
            #expect(registry.tool(for: tool.id) == tool)
            #expect(registry.category(for: tool.categoryID) != nil)
            #expect(registry.categoryTitle(for: tool.categoryID) != nil)
            #expect(!tool.title.isEmpty)
            #expect(!tool.systemImage.isEmpty)
        }
    }

    @Test func defaultRegistryPreservesRequestedCategoryToolOrder() throws {
        let groups = ToolRegistry.default.categoryGroups()

        #expect(groups.map(\.category.title) == [
            "编码与转换",
            "加密与生成",
            "开发",
            "Web",
            "图像与颜色",
            "时间与日期",
            "辅助工具"
        ])

        #expect(try #require(groups.first { $0.category.id == .converter }?.tools).map(\.title) == [
            "Base64 文件",
            "Base64 字符串",
            "URL 编解码",
            "ASCII / 二进制",
            "Unicode 转换",
            "进制转换",
            "罗马数字",
            "大小写转换"
        ])
        #expect(try #require(groups.first { $0.category.id == .crypto }?.tools).map(\.title) == [
            "Hash 文本",
            "文本加密",
            "字符串遮蔽",
            "Token 生成器",
            "UUID 生成器",
            "密码生成器"
        ])
        #expect(try #require(groups.first { $0.category.id == .development }?.tools).map(\.title) == [
            "JSON 格式化",
            "SQL 格式化",
            "XML 格式化",
            "YAML 格式化",
            "JSON 对比",
            "文本对比",
            "正则测试",
            "Docker Run → Compose",
            "HTML → Markdown",
            "Crontab 生成",
            "随机端口",
            "Chmod 计算器"
        ])
        #expect(try #require(groups.first { $0.category.id == .web }?.tools).map(\.title) == [
            "JWT",
            "Basic Auth",
            "HTTP 状态码",
            "User-Agent 解析",
            "键盘事件"
        ])
        #expect(try #require(groups.first { $0.category.id == .image }?.tools).map(\.title) == [
            "图片格式转换",
            "智能压缩图片",
            "图片水印",
            "图片灰阶生成器",
            "Favicon 生成器",
            "颜色转换"
        ])
        #expect(try #require(groups.first { $0.category.id == .time }?.tools).map(\.title) == [
            "时间戳转换",
            "时区查看器",
            "日期计算",
            "计时器"
        ])
        #expect(try #require(groups.first { $0.category.id == .utility }?.tools).map(\.title) == [
            "设备信息",
            "文件类型探测器",
            "数学计算",
            "文本统计",
            "Emoji 与符号"
        ])
    }

    @Test func registryQueriesPreserveCategoryOrderForDefaultTool() {
        let registry = ToolRegistry(
            categories: [
                ToolCategory(id: .emptySearchCategory, title: "Empty", systemImage: "tray"),
                ToolCategory(id: .searchCategory, title: "Development", systemImage: "hammer")
            ],
            tools: [
                Self.tool(.searchPrefixTool, title: "JSON Formatter", categoryID: .searchCategory, keywords: [])
            ]
        )

        #expect(registry.firstToolIDInCategoryOrder() == .searchPrefixTool)
    }

    @Test func registrySearchUsesTitleKeywordRankingAndStableTies() {
        let registry = ToolRegistry(
            categories: [
                ToolCategory(id: .searchCategory, title: "Development", systemImage: "hammer")
            ],
            tools: [
                Self.tool(.searchContainsTool, title: "Pretty JSON", categoryID: .searchCategory, keywords: []),
                Self.tool(.searchKeywordTool, title: "Beautifier", categoryID: .searchCategory, keywords: ["json"]),
                Self.tool(.searchPrefixTool, title: "JSON Formatter", categoryID: .searchCategory, keywords: [])
            ]
        )

        #expect(registry.matchRank(for: registry.tool(for: .searchPrefixTool)!, query: "json") == .titlePrefix)
        #expect(registry.matchRank(for: registry.tool(for: .searchContainsTool)!, query: "json") == .titleContains)
        #expect(registry.matchRank(for: registry.tool(for: .searchKeywordTool)!, query: "json") == .keyword)
        #expect(registry.matchingTools(query: " json ").map(\.id) == [
            .searchPrefixTool,
            .searchContainsTool,
            .searchKeywordTool
        ])
    }

    @Test func registrySearchIsCaseAndDiacriticInsensitive() {
        let registry = ToolRegistry(
            categories: [
                ToolCategory(id: .searchCategory, title: "Development", systemImage: "hammer")
            ],
            tools: [
                Self.tool(.searchPrefixTool, title: "Cafe Menu", categoryID: .searchCategory, keywords: [])
            ]
        )

        #expect(registry.matchingTools(query: "CAFÉ").map(\.id) == [.searchPrefixTool])
    }

    @Test func stringMaskingSearchKeepsPlainKeywordsWithoutAliasInfrastructure() {
        let registry = ToolRegistry.default

        for query in ["遮蔽", "混淆", "mask", "redact"] {
            #expect(registry.matchingTools(query: query).map(\.id).contains("string-obfuscator"))
        }
    }

    @Test func userAgentRegistrationKeepsStableIDAndSearchAliases() throws {
        let registry = ToolRegistry.default
        let tool = try #require(registry.tool(for: "useragent-parser"))

        #expect(tool.title == "User-Agent 解析")
        for query in ["useragent", "user agent"] {
            #expect(registry.matchingTools(query: query).map(\.id).contains("useragent-parser"))
        }
    }

    @MainActor
    @Test func registeredToolsAssemblePages() {
        let registry = ToolRegistry.default

        for tool in registry.categoryGroups().flatMap(\.tools) {
            _ = tool.makePage()
        }
    }

    private static func tool(
        _ id: ToolID,
        title: String,
        categoryID: ToolCategoryID,
        keywords: [String]
    ) -> RegisteredTool {
        RegisteredTool(
            id: id,
            title: title,
            categoryID: categoryID,
            systemImage: "gear",
            keywords: keywords
        ) {
            EmptyView()
        }
    }
}

private extension ToolCategoryID {
    static let emptySearchCategory = ToolCategoryID(rawValue: "empty-search-category")
    static let searchCategory = ToolCategoryID(rawValue: "search-category")
}

private extension ToolID {
    static let searchPrefixTool = ToolID(rawValue: "search-prefix-tool")
    static let searchContainsTool = ToolID(rawValue: "search-contains-tool")
    static let searchKeywordTool = ToolID(rawValue: "search-keyword-tool")
}
