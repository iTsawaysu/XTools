import SwiftUI

@MainActor
final class GeneratorHubWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<GeneratorHubWorkspaceModel>(toolID: "generator") { preferences in
        GeneratorHubWorkspaceModel(preferences: preferences)
    }

    /// Hub 分段：rawValue 即 IndexSegmentedControl 的 item id，
    /// 顺序 Token | UUID | 密码（用户确认顺序，亦为合并前注册表顺序）。
    enum Segment: String, CaseIterable, Sendable, HubSegmentIdentifier {
        case token
        case uuid
        case password

        var label: String {
            switch self {
            case .token: return "Token"
            case .uuid: return "UUID"
            case .password: return "密码"
            }
        }

        /// 页面副标题沿用合并前三工具的文案，随分段切换。
        var subtitle: String {
            switch self {
            case .token: return "使用系统安全随机数生成 Base64url、Hex 或字符集 Token。"
            case .uuid: return "批量生成 UUID v4 或按时间排序的 UUID v7，支持单个复制与全部复制。"
            case .password: return "生成网站兼容的随机密码，可设置长度与字符类别。"
            }
        }
    }

    /// 当前分段；切换即写入偏好，重启后回到上次使用的分段（全新用户默认 Token）。
    @Published var segment: Segment {
        didSet {
            guard segment != oldValue else { return }
            preferences.set(segment.rawValue, for: TextDevelopmentToolPreferenceKeys.generatorSegment)
        }
    }

    private let preferences: ToolPreferenceStore

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        segment = Segment(rawValue: preferences.value(for: TextDevelopmentToolPreferenceKeys.generatorSegment)) ?? .token
    }
}

struct IndexGeneratorHubPage: View {
    var body: some View {
        ToolWorkspaceHost(key: GeneratorHubWorkspaceModel.key) { workspace, _ in
            IndexGeneratorHubContent(workspace: workspace)
        }
    }
}

/// 「生成器」Hub：单一 IndexPage 外壳 + 顶部 Token|UUID|密码 三段切换。三分段的
/// 配方与已生成值由 ToolWorkspaceRepository 按 (toolID, slot) 保活（key 沿用
/// 合并前 token-generator/uuid-generator/password-generator），切换分段或离开
/// 再回来不丢配方与结果。
private struct IndexGeneratorHubContent: View {
    @ObservedObject var workspace: GeneratorHubWorkspaceModel

    var body: some View {
        HubSegmentPage(
            title: "生成器",
            toolID: "generator",
            workspaceSemantic: .queryListWorkspace,
            segment: $workspace.segment
        ) { segment in
            switch segment {
            case .token: IndexTokenGeneratorSegment()
            case .uuid: IndexUUIDGeneratorSegment()
            case .password: IndexPasswordGeneratorSegment()
            }
        }
    }
}
