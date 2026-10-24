import SwiftUI
import XToolsDesign

// MARK: - 对等双栏分栏策略（design.md §3）

/// 双栏分栏策略：把 `IndexFileWorkbench` 壳内烧死的两套布局数学
/// （workbench-audit ④-8）提升为可注入参数。两种策略都由共享 internal
/// 纯数值类型承载（`IndexPairWorkbenchLayoutPolicy` /
/// `IndexFileWorkbenchLayoutPolicy`，仍在 IndexFileWorkbench.swift 中定
/// 义、旧壳与本项目引用同一定义），默认值与旧常量完全一致：
/// - `.pairEqual`（等宽）：≥720pt 等宽分栏、行高最小 280（Regex/文本
///   转换旧 pair 契约）——试点统一用它（design.md §3）；
/// - `.fileAsymmetric`（文件）：≥900pt `1 : 1.05` 分栏、行高最小 398、
///   窄窗堆叠每 pane 最小 280（Base64File 旧 file 契约，留给阶段④ 按
///   工具微调）。
enum WorkbenchIOPairSplitPolicy: Equatable {
    case pairEqual(threshold: CGFloat)
    case fileAsymmetric

    /// 默认策略：等宽 1:1、阈值取旧 pair 契约常量 720pt。
    static let `default` = WorkbenchIOPairSplitPolicy.pairEqual(
        threshold: IndexPairWorkbenchLayoutPolicy.defaultThreshold
    )

    /// 策略到纯数值 pair 契约的投影（file 契约返回 nil）。
    var pairPolicy: IndexPairWorkbenchLayoutPolicy? {
        switch self {
        case let .pairEqual(threshold):
            return IndexPairWorkbenchLayoutPolicy(threshold: threshold)
        case .fileAsymmetric:
            return nil
        }
    }

    /// 策略到纯数值 file 契约的投影（pair 契约返回 nil）。
    var filePolicy: IndexFileWorkbenchLayoutPolicy? {
        switch self {
        case .pairEqual:
            return nil
        case .fileAsymmetric:
            return IndexFileWorkbenchLayoutPolicy()
        }
    }
}

// MARK: - 对等双栏（design.md §3）

/// 对等双栏内容区：输入/输出两个地位对等的 workspace 窗格，宽屏分栏、
/// 窄窗堆叠（布局数学见 `WorkbenchIOPairSplitPolicy`）。每 pane 复用
/// `IndexWorkbenchPane`（44pt 标题头 + 可拉伸内容 + footer 槽）；操作条
/// 挂 pane 内容底部（design.md §5 ActionBar 位置），会话派生的状态行
/// （`IndexWorkbenchFooter`）经 `leadingFooter`/`trailingFooter` 走 pane
/// 的 footer 槽，与操作条并存时位于其下。
///
/// 与旧 `IndexFileWorkbench` 的几何逐项一致：等宽契约的分栏/堆叠、文件
/// 契约的 398pt 行高与堆叠外层 ScrollView（保证两 pane 完整可达）。
/// 宽/窄切换不挂动画（最小窗宽合同：连续 resize 的分栏重排即时更新）。
struct WorkbenchIOPair<
    LeadingAccessory: View,
    LeadingContent: View,
    TrailingAccessory: View,
    TrailingContent: View
>: View {
    let leadingTitle: String
    let trailingTitle: String
    var splitPolicy: WorkbenchIOPairSplitPolicy = .default

    @Environment(\.toolPageEntryGeneration) private var entryGeneration
    @Environment(\.toolToastCenter) private var toastCenter

    /// 输入 pane 尾部动作（通常为空；输入侧操作如清空按需声明）。
    var leadingActions: [WorkbenchActionBarAction] = []
    /// 输出 pane 尾部动作（ ActionBar 的标准挂载点：copy/save/swap…）。
    var trailingActions: [WorkbenchActionBarAction] = []
    /// 会话派生的 pane 状态行（`IndexWorkbenchFooter`：状态点 + 状态文本 +
    /// 尾部提示）。文件类工作台（Base64File）四个 pane 各有一条；缺席时
    /// pane 内容自闭合（`IndexWorkbenchPane` 的既有几何）。操作条与状态行
    /// 并存时顺序为：内容 → 操作条 → 状态行。
    var leadingFooter: IndexWorkbenchFooter? = nil
    var trailingFooter: IndexWorkbenchFooter? = nil

    private let leadingAccessory: LeadingAccessory
    private let leadingContent: LeadingContent
    private let trailingAccessory: TrailingAccessory
    private let trailingContent: TrailingContent

    init(
        leadingTitle: String,
        trailingTitle: String,
        splitPolicy: WorkbenchIOPairSplitPolicy = .default,
        leadingActions: [WorkbenchActionBarAction] = [],
        trailingActions: [WorkbenchActionBarAction] = [],
        leadingFooter: IndexWorkbenchFooter? = nil,
        trailingFooter: IndexWorkbenchFooter? = nil,
        @ViewBuilder leadingAccessory: () -> LeadingAccessory,
        @ViewBuilder leading: () -> LeadingContent,
        @ViewBuilder trailingAccessory: () -> TrailingAccessory,
        @ViewBuilder trailing: () -> TrailingContent
    ) {
        self.leadingTitle = leadingTitle
        self.trailingTitle = trailingTitle
        self.splitPolicy = splitPolicy
        self.leadingActions = leadingActions
        self.trailingActions = trailingActions
        self.leadingFooter = leadingFooter
        self.trailingFooter = trailingFooter
        self.leadingAccessory = leadingAccessory()
        self.leadingContent = leading()
        self.trailingAccessory = trailingAccessory()
        self.trailingContent = trailing()
    }

    var body: some View {
        GeometryReader { proxy in
            if let pairPolicy = splitPolicy.pairPolicy {
                pairBody(policy: pairPolicy, proxy: proxy)
            } else if let filePolicy = splitPolicy.filePolicy {
                fileBody(policy: filePolicy, proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 页面级 ⇧⌘C 代理（page-rollout Batch A 发现的缺口）：双栏页的主输出
        // copy 声明在 trailingActions 上，宿主壳的 pageLevelShortcuts 只聚合
        // 壳自身 `actions`，看不到这里——IOPair 在自己根部挂同款隐藏代理钮
        //（形制同壳：真实标题 + opacity(0)；RootView 隐藏按钮组成熟先例）。
        // 门控同壳：entryGeneration=0（停靠/失活）不挂载。
        .overlay { pageLevelShortcuts }
    }

    /// 双栏动作的页面级快捷键代理：首个 copy 取 trailingActions 优先（输出
    /// pane 即主输出），退而 leadingActions。执行语义与可见复制钮一致；
    /// `copyEnabled` 门控同可见钮（Batch B 格式化族 isOutputFresh——旧页
    /// 禁用按钮的快捷键不触发，代理同样注销）。
    @ViewBuilder
    private var pageLevelShortcuts: some View {
        if entryGeneration > 0, let copy = primaryCopyAction, copy.copyEnabled {
            Button(copy.copyTitle) {
                copy.performCopyViaToastCenter(toastCenter)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .opacity(0)
            .frame(width: .zero, height: .zero)
            .accessibilityHidden(true)
        }
    }

    private var primaryCopyAction: WorkbenchActionBarAction? {
        (trailingActions + leadingActions).first { if case .copy = $0.kind { return true } else { return false } }
    }

    // MARK: - 等宽契约（旧 IndexPairWorkbenchLayoutPolicy 几何平移）

    @ViewBuilder
    private func pairBody(policy: IndexPairWorkbenchLayoutPolicy, proxy: GeometryProxy) -> some View {
        let paneHeight = max(
            IndexPairWorkbenchLayoutPolicy.minimumPaneHeight,
            proxy.size.height - ToolMetrics.Spacing.panelInset
        )
        if policy.mode(for: proxy.size.width) == .horizontal {
            HStack(spacing: IndexPairWorkbenchLayoutPolicy.columnSpacing) {
                leadingPane
                    .frame(width: policy.paneWidth(for: proxy.size.width), height: paneHeight, alignment: .topLeading)
                trailingPane
                    .frame(width: policy.paneWidth(for: proxy.size.width), height: paneHeight, alignment: .topLeading)
            }
            .padding(.horizontal, ToolMetrics.Spacing.panelInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: IndexPairWorkbenchLayoutPolicy.columnSpacing) {
                leadingPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                trailingPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, ToolMetrics.Spacing.panelInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - 文件契约（旧 IndexFileWorkbenchLayoutPolicy 几何平移）

    /// GeometryReader 拥有剩余页高：横向模式吃满（min 398pt）；堆叠模式
    /// 保留一层外 ScrollView 让两个完整 pane 都可达（ScrollView 单独提不出
    /// 有限高度，旧壳注释的经验原样保留）。
    @ViewBuilder
    private func fileBody(policy: IndexFileWorkbenchLayoutPolicy, proxy: GeometryProxy) -> some View {
        let horizontalHeight = max(
            IndexFileWorkbenchLayoutPolicy.minimumHorizontalHeight,
            proxy.size.height - ToolMetrics.Spacing.panelInset
        )
        if let widths = policy.columnWidths(for: proxy.size.width) {
            HStack(spacing: IndexFileWorkbenchLayoutPolicy.columnSpacing) {
                leadingPane
                    .frame(width: widths.leading, height: horizontalHeight, alignment: .topLeading)
                trailingPane
                    .frame(width: widths.trailing, height: horizontalHeight, alignment: .topLeading)
            }
            .padding(.horizontal, ToolMetrics.Spacing.panelInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                VStack(spacing: IndexFileWorkbenchLayoutPolicy.columnSpacing) {
                    leadingPane
                        .frame(
                            maxWidth: .infinity,
                            minHeight: IndexFileWorkbenchLayoutPolicy.minimumStackedPaneHeight,
                            alignment: .topLeading
                        )
                    trailingPane
                        .frame(
                            maxWidth: .infinity,
                            minHeight: IndexFileWorkbenchLayoutPolicy.minimumStackedPaneHeight,
                            alignment: .topLeading
                        )
                }
                .padding(.horizontal, ToolMetrics.Spacing.panelInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.automatic)
        }
    }

    // MARK: - pane 组装（IndexWorkbenchPane 复用）

    private var leadingPane: some View {
        IndexWorkbenchPane(title: leadingTitle, footer: leadingFooter) {
            leadingAccessory
        } content: {
            paneBody(leadingContent, actions: leadingActions)
        }
    }

    private var trailingPane: some View {
        IndexWorkbenchPane(title: trailingTitle, footer: trailingFooter) {
            trailingAccessory
        } content: {
            paneBody(trailingContent, actions: trailingActions)
        }
    }

    /// pane 内容 + 尾部动作条：内容拉伸吃满 pane，操作条钉在 pane 底缘
    /// （design.md §5「输出 pane footer」位置）。
    @ViewBuilder
    private func paneBody<Content: View>(_ content: Content, actions: [WorkbenchActionBarAction]) -> some View {
        VStack(spacing: ToolMetrics.Spacing.sm) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if !actions.isEmpty {
                WorkbenchActionBar(actions: actions)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 无 pane 头附件的便捷入口

extension WorkbenchIOPair where LeadingAccessory == EmptyView, TrailingAccessory == EmptyView {
    init(
        leadingTitle: String,
        trailingTitle: String,
        splitPolicy: WorkbenchIOPairSplitPolicy = .default,
        leadingActions: [WorkbenchActionBarAction] = [],
        trailingActions: [WorkbenchActionBarAction] = [],
        leadingFooter: IndexWorkbenchFooter? = nil,
        trailingFooter: IndexWorkbenchFooter? = nil,
        @ViewBuilder leading: () -> LeadingContent,
        @ViewBuilder trailing: () -> TrailingContent
    ) {
        self.init(
            leadingTitle: leadingTitle,
            trailingTitle: trailingTitle,
            splitPolicy: splitPolicy,
            leadingActions: leadingActions,
            trailingActions: trailingActions,
            leadingFooter: leadingFooter,
            trailingFooter: trailingFooter,
            leadingAccessory: { EmptyView() },
            leading: leading,
            trailingAccessory: { EmptyView() },
            trailing: trailing
        )
    }
}
