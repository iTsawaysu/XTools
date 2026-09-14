import Foundation

public struct HTTPStatusEntry: Equatable, Sendable, Identifiable {
    public let code: Int
    public let name: String
    public let meaning: String
    public let detail: String
    public let family: Int

    public var id: Int { code }

    public init(code: Int, name: String, meaning: String, detail: String, family: Int) {
        self.code = code
        self.name = name
        self.meaning = meaning
        self.detail = detail
        self.family = family
    }
}

public enum HTTPStatusCatalog {
    public static let categories = [
        "全部", "1xx 信息", "2xx 成功", "3xx 重定向", "4xx 客户端错误", "5xx 服务器错误",
    ]

    /// 族编号 → 族名。1…5 之外一律归入 5xx 文案（与页面原行为一致）。
    public static func familyName(_ family: Int) -> String {
        switch family {
        case 1: return "1xx 信息"
        case 2: return "2xx 成功"
        case 3: return "3xx 重定向"
        case 4: return "4xx 客户端错误"
        default: return "5xx 服务器错误"
        }
    }

    public static func entries(matching query: String, category: String) -> [HTTPStatusEntry] {
        var result = entries

        if category != "全部" {
            result = result.filter { familyName($0.family) == category }
        }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            result = result.filter {
                String($0.code).contains(q)
                    || $0.name.lowercased().contains(q)
                    || $0.meaning.contains(q)
                    || $0.detail.contains(q)
            }
        }

        return result
    }
}
