import XToolsCore
import SwiftUI
import XToolsDesign

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

/// 统一壳装配（page-rollout A0）：搜索框 + List 过滤形态的标准配方——
/// 搜索字段与分类徽章是筛选参数，归弹性参数区；动态结果计数移标题行
/// （UUID meta 同款 title 槽投影）；列表为 .result 内容（行内复制、
/// 行 hover（indexRowHoverBackground 范式）原样保留；列表过滤动画旧账
/// 留阶段⑤）。
private struct IndexHTTPStatusWorkspaceContent: View {
    @ObservedObject var workspace: HTTPStatusToolWorkspaceModel

    private var categories: [String] { HTTPStatusCatalog.categories }

    private var filtered: [HTTPStatusEntry] {
        HTTPStatusCatalog.entries(matching: workspace.query, category: workspace.category)
    }

    var body: some View {
        IndexPage("HTTP 状态码", subtitle: "查询 HTTP 状态码及其含义。", workspaceSemantic: .queryListWorkspace) {
            WorkbenchSurface(title: "状态码（\(filtered.count)）", shape: .result, parameters: { parameterFlow }) {
                Group {
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
            }
        }
    }

    /// 弹性参数区：搜索字段独占行（参数区统一轴线 36pt），分类徽章随窗宽
    /// 换行（行距从旧 6 收敛到参数区统一 sm 档）。
    private var parameterFlow: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterItem {
                IndexSearchInput(
                    placeholder: "搜索状态码、名称或描述…",
                    text: $workspace.query,
                    height: ToolMetrics.Control.row,
                    autoFocus: true,
                    clearTitle: "清空状态码搜索",
                    onClear: workspace.clearSearch
                )
                .frame(maxWidth: ToolMetrics.Control.readingNarrow)
                .workbenchFocusTarget()
            }
            WorkbenchParameterGroup {
                ForEach(categories, id: \.self) { name in
                    let isActive = workspace.category == name
                    IndexBadge(name, isSelected: isActive) {
                        workspace.category = name
                    }
                }
            }
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
        HStack(alignment: .top, spacing: ToolMetrics.Spacing.md) {
            IndexBadge("\(row.code)", tone: statusTone(row.family), fixedWidth: 64)

            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xs) {
                HStack(spacing: ToolMetrics.Spacing.sm) {
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
        .padding(.vertical, ToolMetrics.Spacing.compact)
        .indexRowHoverBackground(isHovering)
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
