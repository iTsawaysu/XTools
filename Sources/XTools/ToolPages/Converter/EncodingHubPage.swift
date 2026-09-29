import SwiftUI

@MainActor
final class EncodingHubWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<EncodingHubWorkspaceModel>(toolID: "text-encoding") { preferences in
        EncodingHubWorkspaceModel(preferences: preferences)
    }

    /// Hub 分段：rawValue 即 IndexSegmentedControl 的 item id，
    /// 顺序 Base64 | URL | ASCII/二进制 | Unicode（合并前注册表顺序）。
    enum Segment: String, CaseIterable, Sendable {
        case base64
        case url
        case ascii
        case unicode

        var id: String { rawValue }
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
    @EnvironmentObject var entryHint: HubSegmentEntryHint

    var body: some View {
        IndexPage("文本编码", subtitle: workspace.segment.subtitle, workspaceSemantic: .copyTransformWorkspace) {
            IndexSegmentedControl(
                items: EncodingHubWorkspaceModel.Segment.allCases.map { ($0.id, $0.label) },
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
                guard let newSegment = EncodingHubWorkspaceModel.Segment(rawValue: value) else { return }
                workspace.segment = newSegment
            }
        )
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch workspace.segment {
        case .base64: IndexBase64StringSegment()
        case .url: IndexURLCoderSegment()
        case .ascii: IndexASCIIBinarySegment()
        case .unicode: IndexUnicodeSegment()
        }
    }

    /// SmartPaste 深链（剪贴板 URL 编码文本/Base64 建议）：进入本工具或工具
    /// 已打开时一次性消费分段提示（先清 request 再设分段，避免滞留覆盖后续
    /// 手动切换；仅消费指向本工具的请求，其余 Hub 的请求原样保留）。
    private func consumeEntryHintIfNeeded() {
        guard let request = entryHint.request, request.toolID == "text-encoding" else { return }
        entryHint.request = nil
        guard let segment = EncodingHubWorkspaceModel.Segment(rawValue: request.segment) else { return }
        workspace.segment = segment
    }
}
