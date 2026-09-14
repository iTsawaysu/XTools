import SwiftUI

typealias ToolPageFactory = @MainActor () -> AnyView

protocol Tool: Identifiable, Hashable {
    var id: ToolID { get }
    var title: String { get }
    var categoryID: ToolCategoryID { get }
    var systemImage: String { get }
    var keywords: [String] { get }
}

struct RegisteredTool: Tool {
    let id: ToolID
    let title: String
    let categoryID: ToolCategoryID
    let systemImage: String
    let keywords: [String]
    private let pageFactory: ToolPageFactory

    init<Page: View>(
        id: ToolID,
        title: String,
        categoryID: ToolCategoryID,
        systemImage: String,
        keywords: [String],
        @ViewBuilder page: @escaping @MainActor () -> Page
    ) {
        self.id = id
        self.title = title
        self.categoryID = categoryID
        self.systemImage = systemImage
        self.keywords = keywords
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
