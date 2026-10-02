import SwiftUI

@MainActor
final class DiffHubWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<DiffHubWorkspaceModel>(toolID: "diff") { preferences in
        DiffHubWorkspaceModel(preferences: preferences)
    }

    /// Hub 分段：rawValue 即 IndexSegmentedControl 的 item id，
    /// 顺序 JSON | 文本（用户原始表述顺序，亦为合并前注册表顺序）。
    enum Segment: String, CaseIterable, Sendable {
        case json
        case text

        var id: String { rawValue }
        var label: String {
            switch self {
            case .json: return "JSON"
            case .text: return "文本"
            }
        }

        /// 页面副标题沿用合并前两工具的文案，随分段切换。
        var subtitle: String {
            switch self {
            case .json: return "对比两段 JSON，以左右对齐视图显示差异。"
            case .text: return "逐行对比两段文本的差异。"
            }
        }
    }

    /// 当前分段；切换即写入偏好，重启后回到上次使用的分段（全新用户默认 JSON）。
    @Published var segment: Segment {
        didSet {
            guard segment != oldValue else { return }
            preferences.set(segment.rawValue, for: TextDevelopmentToolPreferenceKeys.diffSegment)
        }
    }

    private let preferences: ToolPreferenceStore

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        segment = Segment(rawValue: preferences.value(for: TextDevelopmentToolPreferenceKeys.diffSegment)) ?? .json
    }
}

struct IndexDiffHubPage: View {
    var body: some View {
        ToolWorkspaceHost(key: DiffHubWorkspaceModel.key) { workspace, _ in
            IndexDiffHubContent(workspace: workspace)
        }
    }
}

/// 「对比」Hub：单一 IndexPage 外壳 + 顶部 JSON|文本 两段切换。两分段的输入与
/// 执行状态由 ToolWorkspaceRepository 按 (toolID, slot) 保活（key 沿用
/// 合并前 json-diff/text-diff），切换分段或离开再回来不丢输入与结果。
private struct IndexDiffHubContent: View {
    @ObservedObject var workspace: DiffHubWorkspaceModel
    @EnvironmentObject var entryHint: HubSegmentEntryHint

    var body: some View {
        IndexPage("对比", subtitle: workspace.segment.subtitle, workspaceSemantic: .editableDiffWorkspace) {
            IndexSegmentedControl(
                items: DiffHubWorkspaceModel.Segment.allCases.map { ($0.id, $0.label) },
                selection: segmentSelection,
                density: .regular
            )
            segmentContent
        }
        .onAppear { consumeEntryHintIfNeeded() }
        .onChange(of: entryHint.request) { _ in consumeEntryHintIfNeeded() }
    }

    private var segmentSelection: Binding<String> {
        Binding(
            get: { workspace.segment.rawValue },
            set: { value in
                guard let newSegment = DiffHubWorkspaceModel.Segment(rawValue: value) else { return }
                workspace.segment = newSegment
            }
        )
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch workspace.segment {
        case .json: IndexJSONDiffSegment()
        case .text: IndexTextDiffSegment()
        }
    }

    /// 深链分段提示（⌘K 关键词命中本 Hub 别名时写入；SmartPaste 同通道）：
    /// 进入本工具或工具已打开时一次性消费（先清 request 再设分段，避免滞留
    /// 覆盖后续手动切换；仅消费指向本工具的请求，其余 Hub 的请求原样保留）。
    private func consumeEntryHintIfNeeded() {
        guard let request = entryHint.request, request.toolID == "diff" else { return }
        entryHint.request = nil
        guard let segment = DiffHubWorkspaceModel.Segment(rawValue: request.segment) else { return }
        workspace.segment = segment
    }
}
