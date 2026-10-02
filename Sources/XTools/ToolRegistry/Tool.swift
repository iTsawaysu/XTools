import SwiftUI

typealias ToolPageFactory = @MainActor () -> AnyView

/// A named capability of a tool that search can surface as a match reason.
///
/// Hub tools merged several former tools into one (文本编码 = Base64 / URL /
/// ASCII / Unicode), so raw recall keywords like "percent" match without
/// telling the user WHY. An alias carries a display-worthy label (itself a
/// match surface), extra recall variants, and — when the tool is a segmented
/// hub — the segment to deep-link on activation. Matching variants must
/// absorb the keyword strings they replace verbatim so existing hits keep
/// their tier and score; aliases only make the reason visible.
struct ToolAlias: Hashable {
    let label: String
    let matching: [String]
    var segment: String? = nil

    init(
        _ label: String,
        matching: [String] = [],
        segment: String? = nil
    ) {
        self.label = label
        self.matching = matching
        self.segment = segment
    }
}

protocol Tool: Identifiable, Hashable {
    var id: ToolID { get }
    var title: String { get }
    var categoryID: ToolCategoryID { get }
    var systemImage: String { get }
    var keywords: [String] { get }
    var aliases: [ToolAlias] { get }
}

extension Tool {
    var aliases: [ToolAlias] { [] }
}

struct RegisteredTool: Tool {
    let id: ToolID
    let title: String
    let categoryID: ToolCategoryID
    let systemImage: String
    let keywords: [String]
    let aliases: [ToolAlias]
    private let pageFactory: ToolPageFactory

    init<Page: View>(
        id: ToolID,
        title: String,
        categoryID: ToolCategoryID,
        systemImage: String,
        keywords: [String],
        aliases: [ToolAlias] = [],
        @ViewBuilder page: @escaping @MainActor () -> Page
    ) {
        self.id = id
        self.title = title
        self.categoryID = categoryID
        self.systemImage = systemImage
        self.keywords = keywords
        self.aliases = aliases
        self.pageFactory = { AnyView(page()) }
    }

    @MainActor
    func makePage() -> AnyView {
        pageFactory()
    }

    static func == (lhs: RegisteredTool, rhs: RegisteredTool) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
