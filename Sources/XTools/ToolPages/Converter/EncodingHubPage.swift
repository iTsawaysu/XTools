import SwiftUI

@MainActor
final class EncodingHubWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<EncodingHubWorkspaceModel>(toolID: "text-encoding") { preferences in
        EncodingHubWorkspaceModel(preferences: preferences)
    }

    /// Hub 分段：rawValue 即 IndexSegmentedControl 的 item id，
    /// 顺序 Base64 | URL | ASCII/二进制 | Unicode（合并前注册表顺序）。
    enum Segment: String, CaseIterable, Sendable, HubSegmentIdentifier {
        case base64
        case url
        case ascii
        case unicode

        var label: String {
            switch self {
            case .base64: return "Base64"
            case .url: return "URL"
            case .ascii: return "ASCII/二进制"
            case .unicode: return "Unicode"
            }
        }

        /// 页面副标题沿用合并前四工具的文案，随分段切换。
        var subtitle: String {
            switch self {
            case .base64: return "在纯文本与 Base64 之间互转，支持 UTF-8。"
            case .url: return "对路径片段、查询参数值等 URL 组件进行百分号编码与解码。"
            case .ascii: return "文本与 ASCII 码、二进制串之间互转。"
            case .unicode: return "文本与 Unicode 转义序列互转。"
            }
        }
    }

    /// 当前分段；切换即写入偏好，重启后回到上次使用的分段（全新用户默认 Base64）。
    @Published var segment: Segment {
        didSet {
            guard segment != oldValue else { return }
            preferences.set(segment.rawValue, for: TextDevelopmentToolPreferenceKeys.encodingSegment)
        }
    }

    private let preferences: ToolPreferenceStore

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        segment = Segment(rawValue: preferences.value(for: TextDevelopmentToolPreferenceKeys.encodingSegment)) ?? .base64
    }
}

struct IndexEncodingHubPage: View {
    var body: some View {
        ToolWorkspaceHost(key: EncodingHubWorkspaceModel.key) { workspace, _ in
            IndexEncodingHubContent(workspace: workspace)
        }
    }
}

/// 「文本编码」Hub：单一 IndexPage 外壳 + 顶部 Base64|URL|ASCII/二进制|Unicode
/// 四段切换。各分段的输入、模式与输出由 ToolWorkspaceRepository 按 (toolID, slot)
/// 保活（key 沿用合并前 base64-string/url-encoder-decoder/text-to-ascii-binary/
/// text-to-unicode），切换分段或离开再回来不丢内容。
private struct IndexEncodingHubContent: View {
    @ObservedObject var workspace: EncodingHubWorkspaceModel

    var body: some View {
        HubSegmentPage(
            title: "文本编码",
            toolID: "text-encoding",
            workspaceSemantic: .copyTransformWorkspace,
            segment: $workspace.segment
        ) { segment in
            switch segment {
            case .base64: IndexBase64StringSegment()
            case .url: IndexURLCoderSegment()
            case .ascii: IndexASCIIBinarySegment()
            case .unicode: IndexUnicodeSegment()
            }
        }
    }
}
