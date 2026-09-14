import XToolsCore
import Testing

struct HTTPStatusCatalogTests {
    @Test func catalogHoldsAllEntriesAcrossFiveFamilies() {
        let entries = HTTPStatusCatalog.entries
        #expect(entries.count == 62)

        // 每个族都有成员，且 family 编号落在 1…5。
        let families = Set(entries.map(\.family))
        #expect(families == [1, 2, 3, 4, 5])
    }

    @Test func emptyQueryAndAllCategoryReturnsEverything() {
        let result = HTTPStatusCatalog.entries(matching: "", category: "全部")
        #expect(result.count == HTTPStatusCatalog.entries.count)
    }

    @Test func categoryFilterKeepsOnlyThatFamily() {
        let result = HTTPStatusCatalog.entries(matching: "", category: "4xx 客户端错误")
        #expect(!result.isEmpty)
        #expect(result.allSatisfy { $0.family == 4 })
    }

    @Test func codeSubstringMatchIsIntentionallyLoose() {
        // 「40」按子串匹配 code，命中 400/401/404/406… 与 500-range 无关项。
        // 记录原页面的宽松行为，不是修 bug。
        let result = HTTPStatusCatalog.entries(matching: "40", category: "全部")
        let codes = Set(result.map(\.code))
        #expect(codes.contains(400))
        #expect(codes.contains(404))
        #expect(codes.contains(406))
        // 200-range 里的 200…208 不含「40」子串，不应命中。
        #expect(!codes.contains(200))
    }

    @Test func nameMatchIsCaseInsensitive() {
        let lower = HTTPStatusCatalog.entries(matching: "not found", category: "全部")
        let upper = HTTPStatusCatalog.entries(matching: "NOT FOUND", category: "全部")
        #expect(lower.map(\.code) == upper.map(\.code))
        #expect(lower.contains { $0.code == 404 })
    }

    @Test func meaningAndDetailAreSearchable() {
        // meaning 命中：「重定向」出现在 3xx 的多个 meaning/detail 中。
        let byMeaning = HTTPStatusCatalog.entries(matching: "永久重定向", category: "全部")
        #expect(byMeaning.contains { $0.code == 301 })

        // detail 命中：「茶壶」只在 418 的 detail 里。
        let byDetail = HTTPStatusCatalog.entries(matching: "茶壶", category: "全部")
        #expect(byDetail.map(\.code) == [418])
    }

    @Test func currentRegistryNamesAndLifecycleBoundariesAreRepresented() {
        let contentTooLarge = HTTPStatusCatalog.entries.first { $0.code == 413 }
        #expect(contentTooLarge?.name == "Content Too Large")
        #expect(contentTooLarge?.meaning == "请求内容过大")

        let unprocessableContent = HTTPStatusCatalog.entries.first { $0.code == 422 }
        #expect(unprocessableContent?.name == "Unprocessable Content")
        #expect(unprocessableContent?.meaning == "无法处理的内容")

        let teapot = HTTPStatusCatalog.entries.first { $0.code == 418 }
        #expect(teapot?.name == "I'm a Teapot")
        #expect(teapot?.detail.contains("unused（未使用）") == true)
        #expect(teapot?.detail.contains("RFC 2324") == true)

        let notExtended = HTTPStatusCatalog.entries.first { $0.code == 510 }
        #expect(notExtended?.name == "Not Extended")
        #expect(notExtended?.detail.contains("obsolete（已废弃）") == true)
        #expect(notExtended?.detail.contains("RFC 2774") == true)
    }

    @Test func currentRegistryNamesAndLifecycleBoundariesAreSearchable() {
        #expect(HTTPStatusCatalog.entries(matching: "Content Too Large", category: "全部").map(\.code) == [413])
        #expect(HTTPStatusCatalog.entries(matching: "Unprocessable Content", category: "全部").map(\.code) == [422])
        #expect(HTTPStatusCatalog.entries(matching: "unused", category: "全部").map(\.code) == [418])
        #expect(HTTPStatusCatalog.entries(matching: "obsolete", category: "全部").map(\.code) == [510])
    }

    @Test func categoryAndQueryCombine() {
        // 先按 5xx 过滤，再搜「网关」——只应剩 502/504。
        let result = HTTPStatusCatalog.entries(matching: "网关", category: "5xx 服务器错误")
        let codes = Set(result.map(\.code))
        #expect(codes == [502, 504])
    }

    @Test func noMatchReturnsEmpty() {
        let result = HTTPStatusCatalog.entries(matching: "这不是任何状态码文案xyz", category: "全部")
        #expect(result.isEmpty)
    }

    @Test func familyNameFallsBackToServerErrorText() {
        #expect(HTTPStatusCatalog.familyName(1) == "1xx 信息")
        #expect(HTTPStatusCatalog.familyName(5) == "5xx 服务器错误")
        // 越界 family 归入 5xx 文案（与页面原行为一致）。
        #expect(HTTPStatusCatalog.familyName(9) == "5xx 服务器错误")
    }
}
