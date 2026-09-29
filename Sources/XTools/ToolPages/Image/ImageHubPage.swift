import SwiftUI

@MainActor
final class ImageHubWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<ImageHubWorkspaceModel>(toolID: "image-tools") { preferences in
        ImageHubWorkspaceModel(preferences: preferences)
    }

    /// Hub 分段：rawValue 即 IndexSegmentedControl 的 item id，
    /// 顺序 格式转换 | 压缩 | 灰度 | Favicon（用户确认顺序，亦为合并前注册表顺序）。
    enum Segment: String, CaseIterable, Sendable {
        case convert
        case compress
        case grayscale
        case favicon

        var id: String { rawValue }
        var label: String {
            switch self {
            case .convert: return "格式转换"
            case .compress: return "压缩"
            case .grayscale: return "灰度"
            case .favicon: return "Favicon"
            }
        }

        /// 页面副标题沿用合并前四工具的文案，随分段切换。
        var subtitle: String {
            switch self {
            case .convert: return "把图片另存为不同格式；不用于压缩体积。"
            case .compress: return "自动优化图片体积，可按偏好和尺寸限制调整输出。"
            case .grayscale: return "将彩色图片转为灰度图。"
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

/// 「图片处理」Hub：单一 IndexPage 外壳 + 顶部 格式转换|压缩|灰度|Favicon 四段切换。
/// 四段的源图与结果由 ToolWorkspaceRepository 按 (toolID, slot) 保活（key 已重挂
/// toolID "image-tools" + 各自 slot），切换分段或离开再回来不丢输入与结果；离开
/// Hub 时四个会话的重载荷按 toolID 一并驱逐（ToolWorkspacePayloadEvicting）。
private struct IndexImageHubContent: View {
    @ObservedObject var workspace: ImageHubWorkspaceModel

    var body: some View {
        IndexPage("图片处理", subtitle: workspace.segment.subtitle, workspaceSemantic: .imagePreviewStage) {
            IndexSegmentedControl(
                items: ImageHubWorkspaceModel.Segment.allCases.map { ($0.id, $0.label) },
                selection: segmentSelection,
                density: .regular
            )
            segmentContent
        }
    }

    private var segmentSelection: Binding<String> {
        Binding(
            get: { workspace.segment.rawValue },
            set: { value in
                guard let newSegment = ImageHubWorkspaceModel.Segment(rawValue: value) else { return }
                workspace.segment = newSegment
            }
        )
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch workspace.segment {
        case .convert: IndexImageConverterSegment()
        case .compress: IndexImageCompressorSegment()
        case .grayscale: IndexImageGrayscaleSegment()
        case .favicon: IndexFaviconGeneratorSegment()
        }
    }
}
