import Foundation

/// SmartPaste 深链的一次性分段提示：横幅点击时写入目标工具与分段，经
/// environmentObject 注入，目标 Hub 出现时校验 toolID 后消费并清空（工具
/// 已打开再点建议时经 onChange 立即生效），「格式化」「文本编码」等
/// 分段式 Hub 共用。
@MainActor
final class HubSegmentEntryHint: ObservableObject {
    struct Request: Equatable {
        let toolID: ToolID
        let segment: String
    }

    @Published var request: Request?
}
