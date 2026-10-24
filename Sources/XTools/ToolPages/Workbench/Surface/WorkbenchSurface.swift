import SwiftUI
import XToolsDesign

// MARK: - 主操作声明（design.md §6）

/// 壳级主操作声明：工具声明后壳在标题行渲染主按钮（⌘↩ 键帽提示）并
/// 注册 ⌘↩（页面级、`toolPageEntryGeneration` 门控：停靠失活自动注销）。
/// 实时计算类工具（无运行按钮）不声明、不注册。
struct WorkbenchPrimaryAction {
    let title: String
    let help: String
    let perform: () -> Void

    init(title: String, help: String, perform: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.perform = perform
    }
}

// MARK: - 内容区形态（design.md §1）

/// 内容区四种形态之一：
/// - `.inputOutput`：对等双栏（`WorkbenchIOPair`，宽分窄堆、数学参数化）；
/// - `.result`：单结果（`IndexResultSurface` 5 内容形态直接复用）；
/// - `.generator`：生成器行列表（`IndexGeneratedValueRowList` 直接复用）；
/// - `.canvas`：自定义画布（diff/图片等任意 SwiftUI 内容）。
enum WorkbenchContentShape: Sendable, Equatable {
    case inputOutput
    case result
    case generator
    case canvas
}

// MARK: - 统一壳（design.md §1）

/// 统一工作台壳：一张纸覆盖此前 10 个壳的全部合法用例。结构自上而下：
/// 可选标题行 → 弹性参数区（自然高度、可分组）→ 诊断单轨 → 内容区。
///
/// 壳本体只写一次「纸背景 → 0.5 描边 → toolErrorTint → clipShape →
/// toolAnimation → 诊断 preference 消费」（消灭旧壳六连抄，
/// workbench-audit ④-1）；诊断三件套（payload/presentation/toastCenter）
/// 由壳私有持有。诊断只走 preference 单轨：内容面用
/// `.indexWorkspaceDiagnostic(...)` 发布，壳聚合成纸顶 banner + 变化才
/// 播报的 toast；参数注入轨（`diagnostic: String?` 直传）不进入本壳。
///
/// 纸几何合同（workbench-audit ⑤-2，数值不松）：纸内边距 paperInset(14)；
/// 可读最大宽 paperMaxWidth(1080) 仍由 `IndexPage` 页壳持有（本壳不重复
/// 约束）；paperHeadHeight(44) 退役为参数带单行最小高度（控件行高
/// Control.row(36) + 上下 sm(8)）。
///
/// 键盘契约（design.md §6）：⌘↩ 经 `primaryAction` 声明后由壳注册；
/// ⇧⌘C 由 `WorkbenchActionBar` 的首个 copy 动作持有；两者均以
/// `toolPageEntryGeneration` 门控（停靠失活注销）。
struct WorkbenchSurface<
    TitleAccessory: View,
    Parameters: View,
    Content: View
>: View {
    var title: String? = nil
    var primaryAction: WorkbenchPrimaryAction? = nil
    let shape: WorkbenchContentShape
    /// `.result` / `.generator` 形态的内容区底部操作条（design.md §5）；
    /// `.inputOutput` 形态的操作条挂输出 pane（经 `WorkbenchIOPair` 的
    /// trailingActions）；`.canvas` 形态由宿主自行嵌入。
    var actions: [WorkbenchActionBarAction] = []
    /// 首个输入聚焦声明槽（阶段③ C3 焦点契约，design.md §4）：页面持有
    /// `@State` 请求计数并在需要聚焦时递增（Base64File「用作输入」；⌘K
    /// 「别名+空格」直达在 Batch D 接同一 token）。nil = 页面无首位文本输入
    /// （如 UUID 生成器），壳不注入活跃请求。
    var focusRequestToken: Int? = nil

    private let titleAccessory: TitleAccessory
    private let parameters: Parameters
    private let content: Content
    private let hasTitleAccessory: Bool
    private let hasParameters: Bool

    // 诊断单轨三件套（壳私有持有，调用侧不再各自复制）。
    @State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?
    @State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()
    @Environment(\.toolToastCenter) private var toastCenter
    @Environment(\.toolPageEntryGeneration) private var entryGeneration
    // 壳层直达载荷（Batch D）：校验 toolID 归属后并入焦点请求。
    @Environment(\.workbenchEntryPayload) private var workbenchEntryPayload
    @Environment(\.toolPageEntryTraceContext) private var entryTraceContext

    private init(
        title: String?,
        primaryAction: WorkbenchPrimaryAction?,
        shape: WorkbenchContentShape,
        actions: [WorkbenchActionBarAction],
        focusRequestToken: Int?,
        titleAccessory: TitleAccessory,
        hasTitleAccessory: Bool,
        parameters: Parameters,
        hasParameters: Bool,
        content: () -> Content
    ) {
        self.title = title
        self.primaryAction = primaryAction
        self.shape = shape
        self.actions = actions
        self.focusRequestToken = focusRequestToken
        self.titleAccessory = titleAccessory
        self.hasTitleAccessory = hasTitleAccessory
        self.parameters = parameters
        self.hasParameters = hasParameters
        self.content = content()
    }

    init(
        title: String?,
        primaryAction: WorkbenchPrimaryAction?,
        shape: WorkbenchContentShape,
        actions: [WorkbenchActionBarAction] = [],
        focusRequestToken: Int? = nil,
        @ViewBuilder titleAccessory: () -> TitleAccessory,
        @ViewBuilder parameters: () -> Parameters,
        content: () -> Content
    ) {
        self.init(
            title: title,
            primaryAction: primaryAction,
            shape: shape,
            actions: actions,
            focusRequestToken: focusRequestToken,
            titleAccessory: titleAccessory(),
            hasTitleAccessory: true,
            parameters: parameters(),
            hasParameters: true,
            content: content
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            parameterBand
            diagnosticTrack
            contentArea
        }
        .background(
            ToolTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: ToolMetrics.Spacing.hairline)
        }
        .toolErrorTint(active: workspaceDiagnostic?.tone == .error, cornerRadius: ToolMetrics.CornerRadius.panel)
        .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous))
        .toolAnimation(ToolMotion.Preset.diagnostic, value: workspaceDiagnostic != nil)
        .onPreferenceChange(IndexWorkspaceDiagnosticPreferenceKey.self) { diagnostic in
            if let announcement = diagnosticPresentation.update(to: diagnostic) {
                toastCenter?.show(announcement.text, tone: announcement.tone)
            }
            workspaceDiagnostic = diagnostic
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 页面级快捷键的统一挂载点（unified-workbench 排查修复）：⇧⌘C 等由
        // ActionBar 深嵌在 pane 内（GeometryReader 固定高分栏 + IndexWorkbenchPane
        // 双层容器），实测事件分发在该位置不稳定（真窗口矩阵：同 gen 同动作，
        // IndexPage 直系层零尺寸代理可触发而 pane 内按钮不触发）。统一上移到
        // 壳直系层挂零尺寸代理钮，视觉仍由 ActionBar 呈现（代理钮 opacity 0）。
        // 门控语义不变：entryGeneration=0（停靠/失活）传 nil 注销。
        .overlay { pageLevelShortcuts }
        // 焦点契约下发（阶段③ C3）：值 = 页面代际 + 页内 token；页面经
        // `.workbenchFocusTarget()` 声明的首个输入在请求变化时消费聚焦。
        .environment(\.workbenchFocusRequest, workbenchFocusRequest)
    }

    /// 焦点契约请求值（C3 + Batch D 直达载荷）：页面声明了首位输入
    /// （focusRequestToken 非 nil）才注入活跃请求；停靠/失活（代际 0）与
    /// 未声明页面都收敛到 inactive，组件族的请求消费在入口处被压住。
    /// 壳层直达载荷（⌘K 直达 / SmartPaste 建议 / deeplink）在页面活跃且
    /// 归属本工具时并入请求——entry 变化即为一次新的「写文本 + 聚焦」
    /// 外部请求，载荷随选择变化由 ShellNavigationModel 作废（一次性）。
    private var workbenchFocusRequest: WorkbenchFocusRequest {
        guard let focusRequestToken else { return .inactive }
        var request = WorkbenchFocusRequest(generation: entryGeneration, token: focusRequestToken)
        if entryGeneration > 0,
           let payload = workbenchEntryPayload,
           payload.toolID == entryTraceContext?.toolID {
            request.entry = payload.id
            request.entryText = payload.text
        }
        return request
    }

    /// 页面级快捷键代理（design.md §5-6 的实现位）：每个持快捷键的动作在此
    /// 挂一个隐藏 Button；可见按钮照常渲染、其自身不再挂 keyboardShortcut。
    /// 形制沿用 RootView 隐藏快捷键按钮组的成熟先例：真实文字标题 +
    /// opacity(0)（EmptyView 标签的按钮不产生平台视图，快捷键不注册）。
    @ViewBuilder
    private var pageLevelShortcuts: some View {
        if entryGeneration > 0 {
            ForEach(Array(pageShortcutActions.enumerated()), id: \.offset) { index, shortcut in
                Button(shortcut.title) {
                    shortcut.perform()
                }
                .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
                .opacity(0)
                .frame(width: .zero, height: .zero)
                .accessibilityHidden(true)
            }
        }
    }

    /// 壳持有的页面级快捷键清单：⇧⌘C（首个 copy）与 ⌘↩（primaryAction）。
    /// 動作执行委托回 ActionBar 动作闭包；copy 的成功 toast 复用
    /// IndexCopyButton 同路径（拷贝 + 播报）。
    private var pageShortcutActions: [WorkbenchPageShortcut] {
        var shortcuts: [WorkbenchPageShortcut] = []
        if let primaryAction {
            shortcuts.append(WorkbenchPageShortcut(
                title: primaryAction.title,
                key: .return,
                modifiers: .command,
                perform: primaryAction.perform
            ))
        }
        if let copy = firstCopyAction {
            shortcuts.append(WorkbenchPageShortcut(
                title: copy.copyTitle,
                key: "c",
                modifiers: [.command, .shift],
                perform: { copy.performCopyViaToastCenter(toastCenter) }
            ))
        }
        return shortcuts
    }

    private var firstCopyAction: WorkbenchActionBarAction? {
        actions.first { if case .copy = $0.kind { return true } else { return false } }
    }

    // MARK: - 标题行（可选）

    private var showsTitleRow: Bool {
        title != nil || primaryAction != nil || hasTitleAccessory
    }

    @ViewBuilder
    private var titleRow: some View {
        if showsTitleRow {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                if let title {
                    Text(title)
                        .font(ToolTypography.panelTitle)
                        .foregroundStyle(ToolTheme.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Spacer(minLength: ToolMetrics.Spacing.sm)
                titleAccessory
                if let primaryAction {
                    primaryActionButton(primaryAction)
                }
            }
            .padding(.horizontal, ToolMetrics.Workbench.paperInset)
            .frame(height: ToolMetrics.Control.thumb)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { hairline }
        }
    }

    private func primaryActionButton(_ action: WorkbenchPrimaryAction) -> some View {
        IndexPrimaryActionButton(
            title: action.title,
            hint: "⌘↩",
            help: action.help,
            action: action.perform
        )
        // 页面级 ⌘↩（design.md §6）：entryGeneration 为 0（停靠/失活）时
        // 传 nil 注销。
        .keyboardShortcut(
            entryGeneration > 0 ? KeyboardShortcut(.return, modifiers: .command) : nil
        )
    }

    // MARK: - 弹性参数区容器（design.md §1-2）

    /// 参数带：自然高度（随内容换行增高），单行下限 =
    /// Control.row(36) + 上下 sm(8)——paperHeadHeight 的退役语义。内边距
    /// 在此统一持有（`WorkbenchParameterFlow` 只拥有组间节奏，避免双重
    /// padding）。放不下就换行，永不横向滚动。
    @ViewBuilder
    private var parameterBand: some View {
        if hasParameters {
            parameters
                .padding(.horizontal, ToolMetrics.Workbench.paperInset)
                .padding(.vertical, ToolMetrics.Spacing.sm)
                .frame(
                    minHeight: WorkbenchSurfaceMetrics.parameterBandMinHeight,
                    alignment: .topLeading
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { hairline }
        }
    }

    // MARK: - 诊断单轨（design.md §4）

    /// 纸顶诊断槽：preference 聚合结果渲染为 banner（36pt 有界轨道）；
    /// 变化才播报 toast（`IndexWorkspaceDiagnosticPresentationState` 门控）。
    private var diagnosticTrack: some View {
        IndexDiagnosticStatusSlot(isActive: workspaceDiagnostic != nil) {
            if let diagnostic = workspaceDiagnostic {
                IndexDiagnosticBanner(
                    diagnostic: nil,
                    message: diagnostic.text,
                    tone: diagnostic.tone
                )
            }
        }
    }

    // MARK: - 内容区容器（design.md §1）

    @ViewBuilder
    private var contentArea: some View {
        switch shape {
        case .inputOutput:
            // 双栏：WorkbenchIOPair 自持纸内边距与 pane 几何，容器只给满幅。
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .result, .generator:
            // 单结果/生成器：内容复用 IndexResultSurface /
            // IndexGeneratedValueRowList，操作条挂内容区底部（design.md §5）。
            VStack(spacing: ToolMetrics.Spacing.sm) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if !actions.isEmpty {
                    WorkbenchActionBar(actions: actions)
                }
            }
            .padding(ToolMetrics.Workbench.paperInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .canvas:
            // 画布：任意 SwiftUI 内容（diff/图片），统一纸内边距；满幅与否
            // 由画布内容自决。
            content
                .padding(ToolMetrics.Workbench.paperInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(ToolTheme.border)
            .frame(height: ToolMetrics.Spacing.hairline)
            .accessibilityHidden(true)
    }
}

// MARK: - 壳几何常量

private enum WorkbenchSurfaceMetrics {
    /// 参数带单行最小高度（design.md §1）：paperHeadHeight(44) 退役后的
    /// 语义——控件行高 Control.row(36) + 上下 sm(8)，全部由 token 组合。
    static let parameterBandMinHeight: CGFloat = ToolMetrics.Control.row + ToolMetrics.Spacing.sm * 2
}

// MARK: - 便捷入口（缺席槽位 == EmptyView，调用侧 API 形状不变）

extension WorkbenchSurface where TitleAccessory == EmptyView {
    /// 无标题行次级动作的入口。
    init(
        title: String?,
        primaryAction: WorkbenchPrimaryAction? = nil,
        shape: WorkbenchContentShape,
        actions: [WorkbenchActionBarAction] = [],
        focusRequestToken: Int? = nil,
        @ViewBuilder parameters: () -> Parameters,
        content: () -> Content
    ) {
        self.init(
            title: title,
            primaryAction: primaryAction,
            shape: shape,
            actions: actions,
            focusRequestToken: focusRequestToken,
            titleAccessory: EmptyView(),
            hasTitleAccessory: false,
            parameters: parameters(),
            hasParameters: true,
            content: content
        )
    }
}

extension WorkbenchSurface where Parameters == EmptyView {
    /// 无参数区的入口（简单工具：无即时参数）。
    init(
        title: String?,
        primaryAction: WorkbenchPrimaryAction? = nil,
        shape: WorkbenchContentShape,
        actions: [WorkbenchActionBarAction] = [],
        focusRequestToken: Int? = nil,
        @ViewBuilder titleAccessory: () -> TitleAccessory,
        content: () -> Content
    ) {
        self.init(
            title: title,
            primaryAction: primaryAction,
            shape: shape,
            actions: actions,
            focusRequestToken: focusRequestToken,
            titleAccessory: titleAccessory(),
            hasTitleAccessory: true,
            parameters: EmptyView(),
            hasParameters: false,
            content: content
        )
    }
}

extension WorkbenchSurface where TitleAccessory == EmptyView, Parameters == EmptyView {
    /// 最小入口：无标题行动作、无参数区（试点 UUIDGenerator/DateTime
    /// Converter 的目标形态，样板量下限）。
    init(
        title: String?,
        primaryAction: WorkbenchPrimaryAction? = nil,
        shape: WorkbenchContentShape,
        actions: [WorkbenchActionBarAction] = [],
        focusRequestToken: Int? = nil,
        content: () -> Content
    ) {
        self.init(
            title: title,
            primaryAction: primaryAction,
            shape: shape,
            actions: actions,
            focusRequestToken: focusRequestToken,
            titleAccessory: EmptyView(),
            hasTitleAccessory: false,
            parameters: EmptyView(),
            hasParameters: false,
            content: content
        )
    }
}
