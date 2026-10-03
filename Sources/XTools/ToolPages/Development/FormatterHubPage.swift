import SwiftUI

/// JSON/XML/SQL 格式化分段共用的缩进模式分段：2 空格 | 4 空格 | 压缩。
/// rawValue 即偏好存储键值与 IndexSegmentedControl 的 item id。
enum FormatterIndentMode: String, CaseIterable, Sendable {
    case two = "2"
    case four = "4"
    case compact = "compact"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .two: return "2"
        case .four: return "4"
        case .compact: return "压缩"
        }
    }
}

@MainActor
final class FormatterHubWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<FormatterHubWorkspaceModel>(toolID: "formatter") { preferences in
        FormatterHubWorkspaceModel(preferences: preferences)
    }

    /// Hub 分段：rawValue 即 IndexSegmentedControl 的 item id，
    /// 顺序 JSON | XML | YAML | SQL（用户原始表述顺序）。
    enum Segment: String, CaseIterable, Sendable, HubSegmentIdentifier {
        case json
        case xml
        case yaml
        case sql

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

    var body: some View {
        HubSegmentPage(
            title: "格式化",
            toolID: "formatter",
            workspaceSemantic: .structuredEditorTransform,
            segment: $workspace.segment
        ) { segment in
            switch segment {
            case .json: IndexJSONFormatterSegment()
            case .xml: IndexXMLFormatterSegment()
            case .yaml: IndexYAMLPrettifySegment()
            case .sql: IndexSQLPrettifySegment()
            }
        }
    }
}
