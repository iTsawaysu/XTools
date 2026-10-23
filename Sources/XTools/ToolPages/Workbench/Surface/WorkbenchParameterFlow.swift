import SwiftUI
import XToolsDesign

// MARK: - 换行规划纯数学（design.md §2 / §9）

/// 参数区换行规划的纯数值契约：给定可用宽度与各控件的理想宽度，产出
/// 行分组。规则与承载渲染的 `IndexFlowLayout` 完全一致（放不下就换行、
/// 行内间距计入、恰好占满不换行、超宽控件独占一行不丢弃），供
/// `WorkbenchParameterFlowPlanningTests` 锚定数学；纯值、无 SwiftUI 宿主。
enum WorkbenchParameterFlowPlanning {
    /// 把理想宽度序列分组为行（返回下标区间，按输入顺序连续覆盖）。
    static func rows(
        idealWidths: [CGFloat],
        availableWidth: CGFloat,
        spacing: CGFloat
    ) -> [Range<Int>] {
        guard !idealWidths.isEmpty else { return [] }

        var rows: [Range<Int>] = []
        var rowStart = 0
        var rowWidth: CGFloat = 0
        for (index, width) in idealWidths.enumerated() {
            if rowWidth > 0, rowWidth + spacing + width > availableWidth {
                rows.append(rowStart..<index)
                rowStart = index
                rowWidth = width
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + width
            }
        }
        rows.append(rowStart..<idealWidths.count)
        return rows
    }
}

// MARK: - 弹性参数区（design.md §2）

/// 弹性参数区：取代固定 44pt 纸头的参数承载（根治 head:/headControls/
/// 横向滚动三个逃生口）。自然高度、按组组织、随内容换行。
///
/// 组成件（ViewBuilder 泛型组合，无 AnyView 逃生口）：
/// - `WorkbenchParameterGroup`：可选 caption 组标签 + 控件流（换行）；
/// - `WorkbenchParameterGroupSeparator`：组间 hairline 分隔线；
/// - `WorkbenchParameterDisclosure`：占满宽度的展开披露。
///
/// 硬规则（PRD AC）：任何参数放不下时换行，禁止横向滚动与折叠后门。
/// 内边距归属：本组件只拥有组间纵向节奏（lg 16）；纸内边距
/// （paperInset 横向 + sm 上下 + 参数带最小高度）由 `WorkbenchSurface`
/// 的参数带容器统一持有，避免双重 padding。
struct WorkbenchParameterFlow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.lg) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - 参数组

/// 一个参数组：可选 caption 组标签（caption 字号、tertiary 墨色）+
/// `IndexFlowLayout` 承载的控件流。行内横向间距 md(12)、行间 sm(8)
/// （design.md §2）；控件统一 `Control.row` 高由 `WorkbenchParameterItem`
/// 负责，混合高度在行中线上对齐（IndexFlowLayout 内建）。
struct WorkbenchParameterGroup<Items: View>: View {
    let label: String?
    private let items: Items

    init(label: String? = nil, @ViewBuilder items: () -> Items) {
        self.label = label
        self.items = items()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xs) {
            if let label {
                Text(label)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textTertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            IndexFlowLayout(spacing: ToolMetrics.Spacing.md, lineSpacing: ToolMetrics.Spacing.sm) {
                items
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - 组间分隔线

/// 组间 hairline 分隔线（design.md §2：组间分隔线 + 组标签构成组边界）。
/// 与组标签二选一或并用，由宿主按参数语义选择。
struct WorkbenchParameterGroupSeparator: View {
    var body: some View {
        Rectangle()
            .fill(ToolTheme.border)
            .frame(height: ToolMetrics.Spacing.hairline)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

// MARK: - 单个参数项

/// 单个参数控件包装：标签在左、控件在右（Raycast Form 规范），可选 help
/// 悬停说明挂在自身命中区；统一 `Control.row` 行高，使流式换行后的每一
/// 行共享同一视觉轴线。
///
/// 只放「影响当下计算」的即时参数；全局偏好在阶段③进设置页（design.md §2）。
struct WorkbenchParameterItem<Control: View>: View {
    let label: String?
    let help: String?
    private let control: Control

    init(
        _ label: String? = nil,
        help: String? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.label = label
        self.help = help
        self.control = control()
    }

    var body: some View {
        HStack(spacing: ToolMetrics.Spacing.fine) {
            if let label {
                Text(label)
                    .font(ToolTypography.label)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            control
        }
        .modifier(WorkbenchParameterItemHelp(help: help))
        .frame(height: ToolMetrics.Control.row)
    }
}

/// 条件 help：有说明才挂悬停，无说明不干预（说明挂在项自身命中区）。
private struct WorkbenchParameterItemHelp: ViewModifier {
    let help: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let help {
            content.help(help)
        } else {
            content
        }
    }
}

// MARK: - 参数区展开披露

/// 参数区展开披露：复用 `IndexDisclosure` 的 inline 样式语言（阶段① 唯一
/// 披露入口），占满参数区宽度；展开体仍是参数流（组/项）。
///
/// 默认展开策略由宿主持有；RegexTester 试点要求参数默认全展开、无折叠
/// 后门（design.md §10），披露仅用于真正的低频高级参数。
struct WorkbenchParameterDisclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    var collapsedSummary: String? = nil
    private let content: Content

    init(
        title: String,
        isExpanded: Binding<Bool>,
        collapsedSummary: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.collapsedSummary = collapsedSummary
        self.content = content()
    }

    var body: some View {
        IndexDisclosure(
            title: title,
            isExpanded: $isExpanded,
            collapsedSummary: collapsedSummary
        ) {
            content
        }
        .inline()
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
