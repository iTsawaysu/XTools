import XToolsCore
import SwiftUI

@MainActor
final class HTTPStatusToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<HTTPStatusToolWorkspaceModel>(toolID: "http-status-codes") { _ in
        HTTPStatusToolWorkspaceModel()
    }

    @Published var query = ""
    @Published var category = "全部"

    func clearSearch() {
        query = ""
    }
}

struct IndexHTTPStatusPage: View {
    var body: some View {
        ToolWorkspaceHost(key: HTTPStatusToolWorkspaceModel.key) { workspace, _ in
            IndexHTTPStatusWorkspaceContent(workspace: workspace)
        }
    }
}

private struct IndexHTTPStatusWorkspaceContent: View {
    @ObservedObject var workspace: HTTPStatusToolWorkspaceModel

    private var categories: [String] { HTTPStatusCatalog.categories }

    private var filtered: [HTTPStatusEntry] {
        HTTPStatusCatalog.entries(matching: workspace.query, category: workspace.category)
    }

    var body: some View {
        IndexPage("HTTP 状态码", subtitle: "查询 HTTP 状态码及其含义。", workspaceSemantic: .queryListWorkspace) {
            IndexActionBar {
                IndexSearchInput(
                    placeholder: "搜索状态码、名称或描述…",
                    text: $workspace.query,
                    autoFocus: true,
                    clearTitle: "清空状态码搜索",
                    onClear: workspace.clearSearch
                )
                .frame(maxWidth: 320)
            }
            IndexPanel("分类筛选") {
                IndexFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(categories, id: \.self) { name in
                        let isActive = workspace.category == name
                        IndexBadge(name, isSelected: isActive) {
                            workspace.category = name
                        }
                    }
                }
            }
            .withoutDiagnosticStatusSlot()
            // SPEC §P6：长状态码列表在面板内部滚动，整页不滚。
            IndexPanel("状态码（\(filtered.count)）") {
                if filtered.isEmpty {
                    emptyState
                } else {
                    List(filtered) { row in
                        IndexHTTPStatusRow(row: row)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.visible)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .verticallyFilling()
            .withoutDiagnosticStatusSlot()
        }
    }

    private var emptyState: some View {
        IndexEmptyState(
            title: "无匹配结果",
            systemImage: "magnifyingglass",
            message: "没有匹配的状态码"
        )
        .frame(maxWidth: .infinity, minHeight: 72)
    }
}

private struct IndexHTTPStatusRow: View {
    let row: HTTPStatusEntry

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IndexBadge("\(row.code)", tone: statusTone(row.family), fixedWidth: 64)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(ToolTypography.monoValueMedium)
                    Text(row.meaning)
                        .font(ToolTypography.compactBody)
                        .foregroundStyle(ToolTheme.textSecondary)
                }
                Text(row.detail)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            IndexCopyButton(
                text: "\(row.code) \(row.name) \(row.meaning)\n\(row.detail)",
                title: "复制 \(row.code) 状态码",
                iconOnly: true
            )
        }
        .padding(.vertical, 10)
        .background(isHovering ? ToolTheme.hoverFill : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withToolAnimation(ToolMotion.Preset.controlFeedback) { isHovering = hovering }
        }
    }

    private func statusTone(_ family: Int) -> IndexBadgeTone {
        switch family {
        case 2: return .success
        case 4: return .warning
        case 5: return .error
        default: return .accent
        }
    }
}
