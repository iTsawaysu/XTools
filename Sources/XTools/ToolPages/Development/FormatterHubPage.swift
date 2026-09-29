import SwiftUI

@MainActor
final class FormatterHubWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<FormatterHubWorkspaceModel>(toolID: "formatter") { preferences in
        FormatterHubWorkspaceModel(preferences: preferences)
    }

    /// Hub 分段：rawValue 即 IndexSegmentedControl 的 item id，
    /// 顺序 JSON | XML | YAML | SQL（用户原始表述顺序）。
    enum Segment: String, CaseIterable, Sendable {
        case json
        case xml
        case yaml
        case sql

        var id: String { rawValue }
        var label: String {
            switch self {
            case .json: return "JSON"
            case .xml: return "XML"
            case .yaml: return "YAML"
            case .sql: return "SQL"
            }
        }

        /// 页面副标题沿用合并前各工具的文案，随分段切换。
        var subtitle: String {
            switch self {
            case .json: return "格式化、压缩和验证 JSON，支持自定义选项。"
            case .xml: return "格式化与压缩 XML，支持 2/4 空格缩进与 Minify。"
            case .yaml: return "规整 YAML 空白与键值间距，支持 Key 排序。"
            case .sql: return "格式化与压缩 SQL，支持关键字大小写和缩进选项。"
            }
        }
    }

    /// 当前分段；切换即写入偏好，重启后回到上次使用的分段（全新用户默认 JSON）。
    @Published var segment: Segment {
        didSet {
            guard segment != oldValue else { return }
            preferences.set(segment.rawValue, for: TextDevelopmentToolPreferenceKeys.formatterSegment)
        }
    }

    private let preferences: ToolPreferenceStore

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        segment = Segment(rawValue: preferences.value(for: TextDevelopmentToolPreferenceKeys.formatterSegment)) ?? .json
    }
}

struct IndexFormatterHubPage: View {
    var body: some View {
        ToolWorkspaceHost(key: FormatterHubWorkspaceModel.key) { workspace, _ in
            IndexFormatterHubContent(workspace: workspace)
        }
    }
}

/// 「格式化」Hub：单一 IndexPage 外壳 + 顶部四段切换。各分段的输入与
/// 执行状态由 ToolWorkspaceRepository 按 (toolID, slot) 保活（key 沿用
/// 合并前各工具 id），切换分段或离开再回来不丢输入与输出。
private struct IndexFormatterHubContent: View {
    @ObservedObject var workspace: FormatterHubWorkspaceModel
    @EnvironmentObject var entryHint: HubSegmentEntryHint

    var body: some View {
        IndexPage("格式化", subtitle: workspace.segment.subtitle, workspaceSemantic: .structuredEditorTransform) {
            IndexSegmentedControl(
                items: FormatterHubWorkspaceModel.Segment.allCases.map { ($0.id, $0.label) },
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
                guard let newSegment = FormatterHubWorkspaceModel.Segment(rawValue: value) else { return }
                workspace.segment = newSegment
            }
        )
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch workspace.segment {
        case .json: IndexJSONFormatterSegment()
        case .xml: IndexXMLFormatterSegment()
        case .yaml: IndexYAMLPrettifySegment()
        case .sql: IndexSQLPrettifySegment()
        }
    }

    /// SmartPaste 深链（剪贴板 JSON/XML 建议）：进入本工具或工具已打开时
    /// 一次性消费分段提示（先清 request 再设分段，避免滞留覆盖后续手动
    /// 切换；仅消费指向本工具的请求，其余 Hub 的请求原样保留）。
    private func consumeEntryHintIfNeeded() {
        guard let request = entryHint.request, request.toolID == "formatter" else { return }
        entryHint.request = nil
        guard let segment = FormatterHubWorkspaceModel.Segment(rawValue: request.segment) else { return }
        workspace.segment = segment
    }
}
