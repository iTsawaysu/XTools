import SwiftUI

/// Hub 分段枚举的共享契约：rawValue 即 IndexSegmentedControl 的 item id
/// 与偏好存储键值，label 供分段控件展示，subtitle 随分段切换写入页面壳。
protocol HubSegmentIdentifier: Hashable, RawRepresentable, CaseIterable, Sendable
where RawValue == String {
    var id: String { get }
    var label: String { get }
    var subtitle: String { get }
}

extension HubSegmentIdentifier {
    var id: String { rawValue }
}

/// 分段式 Hub 的共享骨架：单一 IndexPage 页面壳 + 顶部 IndexSegmentedControl
/// 分段切换 + 深链分段提示一次性消费。各 Hub 保留 Segment 枚举（偏好读写）
/// 与分段内容，仅声明标题、工作区语义与每段的视图；分段持久化仍由各
/// Hub 的 workspace model 负责（切换即写偏好，重启回到上次分段）。
struct HubSegmentPage<Segment: HubSegmentIdentifier, Content: View>: View {
    @EnvironmentObject private var entryHint: HubSegmentEntryHint

    private let title: String
    private let toolID: ToolID
    private let workspaceSemantic: IndexWorkspaceSemantic
    @Binding private var segment: Segment
    private let content: (Segment) -> Content

    init(
        title: String,
        toolID: ToolID,
        workspaceSemantic: IndexWorkspaceSemantic,
        segment: Binding<Segment>,
        @ViewBuilder content: @escaping (Segment) -> Content
    ) {
        self.title = title
        self.toolID = toolID
        self.workspaceSemantic = workspaceSemantic
        self._segment = segment
        self.content = content
    }

    var body: some View {
        IndexPage(title, subtitle: segment.subtitle, workspaceSemantic: workspaceSemantic) {
            IndexSegmentedControl(
                items: Segment.allCases.map { ($0.id, $0.label) },
                selection: segmentSelection,
                density: .regular
            )
            content(segment)
        }
        .onAppear { consumeEntryHintIfNeeded() }
        .onChange(of: entryHint.request) { _ in consumeEntryHintIfNeeded() }
    }

    private var segmentSelection: Binding<String> {
        Binding(
            get: { segment.rawValue },
            set: { value in
                guard let newSegment = Segment(rawValue: value) else { return }
                segment = newSegment
            }
        )
    }

    /// 深链分段提示（⌘K 关键词命中本 Hub 别名时写入；SmartPaste 同通道）：
    /// 进入本工具或工具已打开时一次性消费（先清 request 再设分段，避免滞留
    /// 覆盖后续手动切换；仅消费指向本工具的请求，其余 Hub 的请求原样保留）。
    private func consumeEntryHintIfNeeded() {
        guard let request = entryHint.request, request.toolID == toolID else { return }
        entryHint.request = nil
        guard let newSegment = Segment(rawValue: request.segment) else { return }
        segment = newSegment
    }
}
