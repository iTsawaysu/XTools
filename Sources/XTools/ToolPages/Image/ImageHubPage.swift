import SwiftUI

@MainActor
final class ImageHubWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<ImageHubWorkspaceModel>(toolID: "image-tools") { preferences in
        ImageHubWorkspaceModel(preferences: preferences)
    }

    /// Hub 分段：rawValue 即 IndexSegmentedControl 的 item id，
    /// 顺序 格式转换 | 压缩 | 灰度 | 水印 | Favicon（前三段为重编码工作流，
    /// 水印为图层合成工作流，Favicon 为部署产物生成器）。
    enum Segment: String, CaseIterable, Sendable, HubSegmentIdentifier {
        case convert
        case compress
        case grayscale
        case watermark
        case favicon

        var label: String {
            switch self {
            case .convert: return "格式转换"
            case .compress: return "压缩"
            case .grayscale: return "灰度"
            case .watermark: return "水印"
            case .favicon: return "Favicon"
            }
        }

        /// 页面副标题沿用合并前各工具的文案，随分段切换。
        var subtitle: String {
            switch self {
            case .convert: return "把图片另存为不同格式；不用于压缩体积。"
            case .compress: return "自动优化图片体积，可按偏好和尺寸限制调整输出。"
            case .grayscale: return "将彩色图片转为灰度图。"
            case .watermark: return "为图片添加黑色或白色文字水印，并保持原格式与尺寸。"
            case .favicon: return "上传图片，生成可直接放入站点根目录的五文件 Favicon 部署包。"
            }
        }
    }

    /// 当前分段；切换即写入偏好，重启后回到上次使用的分段（全新用户默认格式转换）。
    @Published var segment: Segment {
        didSet {
            guard segment != oldValue else { return }
            preferences.set(segment.rawValue, for: TextDevelopmentToolPreferenceKeys.imageSegment)
        }
    }

    private let preferences: ToolPreferenceStore

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        segment = Segment(rawValue: preferences.value(for: TextDevelopmentToolPreferenceKeys.imageSegment)) ?? .convert
    }
}

struct IndexImageHubPage: View {
    var body: some View {
        ToolWorkspaceHost(key: ImageHubWorkspaceModel.key) { workspace, _ in
            IndexImageHubContent(workspace: workspace)
        }
    }
}

/// 「图片处理」Hub：单一 IndexPage 外壳 + 顶部
/// 格式转换|压缩|灰度|水印|Favicon 五段切换。五段的源图与结果由
/// ToolWorkspaceRepository 按 (toolID, slot) 保活（key 已重挂
/// toolID "image-tools" + 各自 slot），切换分段或离开再回来不丢输入与结果；
/// 离开 Hub 时五个会话的重载荷按 toolID 一并驱逐（ToolWorkspacePayloadEvicting）。
private struct IndexImageHubContent: View {
    @ObservedObject var workspace: ImageHubWorkspaceModel

    var body: some View {
        HubSegmentPage(
            title: "图片处理",
            toolID: "image-tools",
            workspaceSemantic: .imagePreviewStage,
            segment: $workspace.segment
        ) { segment in
            switch segment {
            case .convert: IndexImageConverterSegment()
            case .compress: IndexImageCompressorSegment()
            case .grayscale: IndexImageGrayscaleSegment()
            case .watermark: IndexImageWatermarkSegment()
            case .favicon: IndexImageFaviconSegment()
            }
        }
    }
}
