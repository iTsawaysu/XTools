// Adapted from MarkdownUI (https://github.com/gonzalezreal/swift-markdown-ui),
// The MIT License, Copyright (c) 2020 Guillermo Gonzalez.
// XTools 自有的 SwiftUI Markdown 渲染层：只实现 HTML→Markdown 预览需要的
// GFM 特性面，样式直接落在 Clay 设计令牌上（对应 vendored 2.4.1 的
// `.indexClay` 主题 + 默认主题）。相对上游的布局简化（均有依据）：
// - 边距折叠按静态边距表计算，不再走 PreferenceKey（样式固定，无运行时覆盖）；
// - tight/loose 列表在 Clay 边距表下渲染结果相同（列表项边距均为 0），故不区分；
// - 表格背景按整轨填充（Clay 下单元格底色 == 编辑器底色，与上游"贴内容"
//   的背景不可区分，整轨填充让 1pt 边框线保持整齐）；
// - 标题不再设置 `.id`（上游用 kebab-case id 支持锚点跳转，本预览不消费）。

import SwiftUI

/// 渲染入口：文档块列表 + 两个受控图片出口。
struct IndexMarkdownPreviewContent: View {
    let blocks: [MarkdownBlock]
    var imageProvider: MarkdownPreviewImageProvider = .unavailable
    var inlineImageProvider = MarkdownPreviewInlineImageProvider.unavailable

    var body: some View {
        IndexMarkdownBlockSequence(blocks: blocks)
            .environment(\.markdownBlockImageProvider, imageProvider)
            .environment(\.markdownInlineImageProvider, inlineImageProvider)
    }
}

// MARK: - Block sequence（边距折叠）

private struct IndexMarkdownBlockSequence: View {
    private let blocks: [MarkdownBlock]

    init(blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(self.blocks.enumerated()), id: \.offset) { index, block in
                block
                    .view()
                    .padding(.top, index == 0 ? 0 : self.spacing(before: block, after: self.blocks[index - 1]))
            }
        }
    }

    /// 与上游 BlockSequence 一致：取"当前块上边距"与"前一块下边距"的最大值，
    /// 未指定按 0 处理。
    private func spacing(before block: MarkdownBlock, after predecessor: MarkdownBlock) -> CGFloat {
        max(block.viewMargins.top ?? 0, predecessor.viewMargins.bottom ?? 0)
    }
}

private extension MarkdownBlock {
    /// Clay 边距表：indexClay 只覆盖 h1-h3、代码块与表格，其余块 0。
    var viewMargins: (top: CGFloat?, bottom: CGFloat?) {
        switch self {
        case .heading(1, _):
            return (20, 10)
        case .heading(2, _):
            return (16, 8)
        case .heading(3, _):
            return (12, 6)
        case .codeBlock:
            return (8, 8)
        case .table:
            return (8, 8)
        default:
            return (nil, nil)
        }
    }

    @MainActor
    @ViewBuilder
    func view() -> some View {
        switch self {
        case .blockquote(let children):
            // indexClay 未覆盖 blockquote，上游默认即原样呈现子块。
            IndexMarkdownBlockSequence(blocks: children)
        case .bulletedList(_, let items):
            IndexMarkdownBulletedListView(items: items)
        case .numberedList(_, let start, let items):
            IndexMarkdownNumberedListView(start: start, items: items)
        case .taskList(_, let items):
            IndexMarkdownTaskListView(items: items)
        case .codeBlock(_, let content):
            IndexMarkdownCodeBlockView(content: content)
        case .htmlBlock(let content):
            // 上游把原始 HTML 块按纯文本段落渲染（不执行）。
            IndexMarkdownParagraphView(content: [.text(Self.plainTextSource(content))])
        case .paragraph(let content):
            IndexMarkdownParagraphView(content: content)
        case .heading(let level, let content):
            IndexMarkdownHeadingView(level: level, content: content)
        case .table(let columnAlignments, let rows):
            IndexMarkdownTableView(columnAlignments: columnAlignments, rows: rows)
        case .thematicBreak:
            Divider()
        }
    }

    private static func plainTextSource(_ content: String) -> String {
        content.hasSuffix("\n") ? String(content.dropLast()) : content
    }
}

// MARK: - Paragraph / heading

private struct IndexMarkdownParagraphView: View {
    private let content: [MarkdownInline]

    init(content: [MarkdownInline]) {
        self.content = content
    }

    var body: some View {
        if let imageData = Self.singleImage(in: self.content) {
            IndexMarkdownImageView(imageData: imageData)
        } else if let flowItems = self.content.imageFlowItems {
            IndexMarkdownImageFlowLayout(items: flowItems)
        } else {
            IndexMarkdownInlineTextView(inlines: self.content)
        }
    }

    /// 段落只含一张图片（或一个只包图片的链接）→ 走块级图片出口。
    private static func singleImage(in inlines: [MarkdownInline]) -> MarkdownImageData? {
        guard inlines.count == 1, let imageData = inlines.first?.imageData else { return nil }
        return imageData
    }
}

private extension Array where Element == MarkdownInline {
    /// 段落/表格单元格只含图片与换行（可能多张）→ 流式排列；混入其他内容则
    /// 返回 nil，回退行内渲染。
    var imageFlowItems: [IndexMarkdownImageFlowItem]? {
        var items: [IndexMarkdownImageFlowItem] = []
        for inline in self {
            switch inline {
            case .text(let text) where text.isEmpty:
                continue
            case .softBreak:
                continue
            case .lineBreak:
                items.append(.lineBreak)
            case .image(let source, let children):
                items.append(.image(.init(source: source, alt: children.renderPlainText(), destination: nil)))
            case .link(let destination, let children) where children.count == 1:
                guard var imageData = children.first?.imageData else { return nil }
                imageData.destination = destination
                items.append(.image(imageData))
            default:
                return nil
            }
        }
        guard items.contains(where: \.isImage) else { return nil }
        return items
    }
}

private struct IndexMarkdownHeadingView: View {
    private let level: Int
    private let content: [MarkdownInline]

    init(level: Int, content: [MarkdownInline]) {
        self.level = level
        self.content = content
    }

    var body: some View {
        IndexMarkdownInlineTextView(inlines: self.content, baseFontOverride: Self.fontProperties(level: self.level))
    }

    private static func fontProperties(level: Int) -> MarkdownFontProperties {
        switch level {
        case 1:
            return .init(size: 20, weight: .semibold)
        case 2:
            return .init(size: 16, weight: .semibold)
        case 3:
            return .init(size: 14, weight: .semibold)
        default:
            // indexClay 未覆盖 h4-h6：与正文同字号、无边距。
            return .init(size: 13)
        }
    }
}

// MARK: - Inline text

private struct IndexMarkdownInlineTextView: View {
    private let inlines: [MarkdownInline]
    private let baseFontOverride: MarkdownFontProperties?
    @Environment(\.markdownInlineImageProvider) private var inlineImageProvider
    @State private var inlineImages: [String: Image] = [:]

    init(inlines: [MarkdownInline], baseFontOverride: MarkdownFontProperties? = nil) {
        self.inlines = inlines
        self.baseFontOverride = baseFontOverride
    }

    var body: some View {
        self.inlines
            .renderText(styleSet: IndexClayMarkdownStyle.inlineSet(base: self.baseFontOverride), images: self.inlineImages)
            .task(id: self.inlines) {
                self.inlineImages = (try? await self.loadInlineImages()) ?? [:]
            }
    }

    private func loadInlineImages() async throws -> [String: Image] {
        let images = Set(self.inlines.compactMap(\.imageData))
        guard !images.isEmpty else { return [:] }

        return try await withThrowingTaskGroup(of: (String, Image).self) { taskGroup in
            for image in images {
                guard let url = URL(string: image.source) else {
                    continue
                }
                taskGroup.addTask {
                    (image.source, try await self.inlineImageProvider.image(with: url, label: image.alt))
                }
            }

            var loaded: [String: Image] = [:]
            for try await result in taskGroup {
                loaded[result.0] = result.1
            }
            return loaded
        }
    }
}

// MARK: - Code block

private struct IndexMarkdownCodeBlockView: View {
    private let content: String

    init(content: String) {
        self.content = content.hasSuffix("\n") ? String(content.dropLast()) : content
    }

    var body: some View {
        Text(self.content)
            .font(ToolTypography.markdownCodeBlock)
            .foregroundStyle(IndexClayMarkdownStyle.textColor)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IndexClayMarkdownStyle.fieldColor)
            .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
    }
}

// MARK: - Lists

private struct IndexMarkdownBulletedListView: View {
    private let items: [MarkdownListItem]
    @Environment(\.markdownListLevel) private var listLevel

    init(items: [MarkdownListItem]) {
        self.items = items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(self.items.enumerated()), id: \.offset) { _, item in
                IndexMarkdownListItemView(item: item) {
                    IndexMarkdownListBullet(listLevel: self.listLevel + 1)
                }
                .environment(\.markdownListLevel, self.listLevel + 1)
            }
        }
    }
}

private struct IndexMarkdownNumberedListView: View {
    private let start: Int
    private let items: [MarkdownListItem]
    @Environment(\.markdownListLevel) private var listLevel
    @State private var markerWidth: CGFloat?

    init(start: Int, items: [MarkdownListItem]) {
        self.start = start
        self.items = items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(self.items.enumerated()), id: \.offset) { index, item in
                IndexMarkdownListItemView(item: item, markerWidth: self.markerWidth) {
                    Text("\(self.start + index).")
                        .monospacedDigit()
                        .frame(minWidth: IndexClayMarkdownStyle.markerMinWidth, alignment: .trailing)
                        .readListMarkerWidth(column: 0)
                }
                .environment(\.markdownListLevel, self.listLevel + 1)
            }
        }
        .onPreferenceChange(ListMarkerWidthPreference.self) { widths in
            self.markerWidth = widths[0]
        }
    }
}

private struct IndexMarkdownTaskListView: View {
    private let items: [MarkdownTaskListItem]
    @Environment(\.markdownListLevel) private var listLevel

    init(items: [MarkdownTaskListItem]) {
        self.items = items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(self.items.enumerated()), id: \.offset) { _, item in
                IndexMarkdownListItemView(taskItem: item) {
                    Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                        .symbolRenderingMode(.hierarchical)
                        .imageScale(.small)
                        .frame(minWidth: IndexClayMarkdownStyle.markerMinWidth, alignment: .trailing)
                }
                .environment(\.markdownListLevel, self.listLevel + 1)
            }
        }
    }
}

private struct IndexMarkdownListItemView<Marker: View>: View {
    private let children: [MarkdownBlock]
    private let markerWidth: CGFloat?
    @ViewBuilder private let marker: () -> Marker

    init(
        item: MarkdownListItem,
        markerWidth: CGFloat? = nil,
        @ViewBuilder marker: @escaping () -> Marker
    ) {
        self.children = item.children
        self.markerWidth = markerWidth
        self.marker = marker
    }

    init(
        taskItem: MarkdownTaskListItem,
        markerWidth: CGFloat? = nil,
        @ViewBuilder marker: @escaping () -> Marker
    ) {
        self.children = taskItem.children
        self.markerWidth = markerWidth
        self.marker = marker
    }

    var body: some View {
        Label {
            IndexMarkdownBlockSequence(blocks: self.children)
        } icon: {
            self.marker()
                .font(ToolTypography.markdownProse)
                .foregroundStyle(IndexClayMarkdownStyle.textColor)
                .frame(width: self.markerWidth, alignment: .trailing)
        }
        .labelStyle(.titleAndIcon)
    }
}

/// 上游 discCircleSquare：按嵌套层级在实心圆/空心圆/实心方块间切换。
private struct IndexMarkdownListBullet: View {
    private let listLevel: Int

    init(listLevel: Int) {
        self.listLevel = listLevel
    }

    var body: some View {
        let symbol = switch self.listLevel {
        case ...1: "circle.fill"
        case 2: "circle"
        default: "square.fill"
        }
        Image(systemName: symbol)
            .font(.system(size: round(13 / 3)))
            .frame(minWidth: IndexClayMarkdownStyle.markerMinWidth, alignment: .trailing)
    }
}

private struct ListMarkerWidthPreference: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]

    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

private extension View {
    func readListMarkerWidth(column: Int) -> some View {
        self.background(
            GeometryReader { proxy in
                Color.clear.preference(key: ListMarkerWidthPreference.self, value: [column: proxy.size.width])
            }
        )
    }
}

// MARK: - Table

private struct IndexMarkdownTableView: View {
    private let columnAlignments: [MarkdownTableColumnAlignment]
    private let rows: [MarkdownTableRow]

    init(columnAlignments: [MarkdownTableColumnAlignment], rows: [MarkdownTableRow]) {
        self.columnAlignments = columnAlignments
        self.rows = rows
    }

    var body: some View {
        // 单元格整轨填充底色，1pt 间隙透出边框色形成网格线；外圈 1pt 内边距
        // 形成外边框（等价上游 allBorders 1pt secondary 线 + alternatingRows 底色）。
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            ForEach(Array(self.rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { columnIndex, cell in
                        IndexMarkdownTableCellView(
                            content: cell.content,
                            alignment: Self.horizontalAlignment(self.columnAlignments[columnIndex])
                        )
                    }
                }
            }
        }
        .padding(1)
        .background(IndexClayMarkdownStyle.borderColor)
    }

    private static func horizontalAlignment(_ alignment: MarkdownTableColumnAlignment) -> HorizontalAlignment {
        switch alignment {
        case .none, .left:
            return .leading
        case .center:
            return .center
        case .right:
            return .trailing
        }
    }
}

private struct IndexMarkdownTableCellView: View {
    private let content: [MarkdownInline]
    private let alignment: HorizontalAlignment

    init(content: [MarkdownInline], alignment: HorizontalAlignment) {
        self.content = content
        self.alignment = alignment
    }

    var body: some View {
        Group {
            if let flowItems = self.content.imageFlowItems {
                IndexMarkdownImageFlowLayout(items: flowItems)
            } else {
                IndexMarkdownInlineTextView(inlines: self.content)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .init(horizontal: self.alignment, vertical: .center))
        .background(IndexClayMarkdownStyle.fieldColor)
    }
}

// MARK: - Images

private enum IndexMarkdownImageFlowItem {
    case image(MarkdownImageData)
    case lineBreak

    var isImage: Bool {
        guard case .image = self else { return false }
        return true
    }
}

private struct IndexMarkdownImageView: View {
    private let imageData: MarkdownImageData
    @Environment(\.markdownBlockImageProvider) private var imageProvider

    init(imageData: MarkdownImageData) {
        self.imageData = imageData
    }

    var body: some View {
        self.imageProvider
            .makeImage(url: URL(string: self.imageData.source))
            .link(destination: self.imageData.destination)
            .accessibilityLabel(self.imageData.alt)
    }
}

private extension View {
    /// 上游 LinkModifier：块级图片被 `[![](src)](href)` 包裹时整块可点。
    func link(destination: String?) -> some View {
        self.modifier(IndexMarkdownImageLinkModifier(destination: destination))
    }
}

private struct IndexMarkdownImageLinkModifier: ViewModifier {
    @Environment(\.openURL) private var openURL
    let destination: String?

    func body(content: Content) -> some View {
        if let url = self.destination.flatMap(URL.init(string:)) {
            Button {
                self.openURL(url)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// 上游 FlowLayout：段落内多张图片 + 硬换行的流式排列。
private struct IndexMarkdownImageFlowLayout: View {
    private let items: [IndexMarkdownImageFlowItem]
    private static let spacing: CGFloat = 4

    init(items: [IndexMarkdownImageFlowItem]) {
        self.items = items
    }

    var body: some View {
        IndexMarkdownFlowLayout(horizontalSpacing: Self.spacing, verticalSpacing: Self.spacing) {
            ForEach(Array(self.items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .image(let imageData):
                    IndexMarkdownImageView(imageData: imageData)
                case .lineBreak:
                    Spacer()
                }
            }
        }
    }
}

private struct IndexMarkdownFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = self.computeLayout(for: proposal, subviews: subviews)
        return Self.sizeThatFits(rows: rows, verticalSpacing: self.verticalSpacing)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let rows = self.computeLayout(for: proposal, subviews: subviews)
        var position = bounds.origin

        for row in rows {
            for item in row.items {
                // 底边对齐（与上游一致）。
                let itemBounds = CGRect(origin: position, size: item.size)
                    .offsetBy(dx: 0, dy: row.size.height - item.size.height)
                subviews[item.index].place(at: itemBounds.origin, proposal: .init(itemBounds.size))
                position.x += item.size.width + self.horizontalSpacing
            }
            position.x = bounds.origin.x
            position.y += row.size.height + self.verticalSpacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var size: CGSize = .zero
        var items: [Item] = []
    }

    private func computeLayout(for proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()

        for (index, view) in zip(subviews.indices, subviews) {
            // 低优先级视图（硬换行 Spacer）拿剩余宽度，其余拿全宽。
            let proposedWidth =
                view.priority < 0 ? proposal.width.map { $0 - currentRow.size.width } : proposal.width
            let item = Item(
                index: index,
                size: view.sizeThatFits(.init(width: proposedWidth, height: nil))
            )

            if currentRow.size.width > 0,
                currentRow.size.width + item.size.width > (proposal.width ?? .infinity)
            {
                currentRow.size.width -= self.horizontalSpacing
                rows.append(currentRow)
                currentRow = Row()
            }

            currentRow.items.append(item)
            currentRow.size.width += item.size.width + self.horizontalSpacing
            currentRow.size.height = max(item.size.height, currentRow.size.height)
        }

        if !currentRow.items.isEmpty {
            currentRow.size.width -= self.horizontalSpacing
            rows.append(currentRow)
        }

        return rows
    }

    private static func sizeThatFits(rows: [Row], verticalSpacing: CGFloat) -> CGSize {
        zip(rows.indices, rows).reduce(CGSize.zero) { size, tuple in
            let (index, row) = tuple
            let spacing = index < rows.endIndex - 1 ? verticalSpacing : 0
            return CGSize(
                width: max(size.width, row.size.width),
                height: size.height + row.size.height + spacing
            )
        }
    }
}

// MARK: - Environment

private struct MarkdownBlockImageProviderKey: EnvironmentKey {
    static var defaultValue: MarkdownPreviewImageProvider { .unavailable }
}

private struct MarkdownInlineImageProviderKey: EnvironmentKey {
    static var defaultValue: MarkdownPreviewInlineImageProvider { .unavailable }
}

private struct MarkdownListLevelKey: EnvironmentKey {
    static let defaultValue = 0
}

private extension EnvironmentValues {
    var markdownBlockImageProvider: MarkdownPreviewImageProvider {
        get { self[MarkdownBlockImageProviderKey.self] }
        set { self[MarkdownBlockImageProviderKey.self] = newValue }
    }

    var markdownInlineImageProvider: MarkdownPreviewInlineImageProvider {
        get { self[MarkdownInlineImageProviderKey.self] }
        set { self[MarkdownInlineImageProviderKey.self] = newValue }
    }

    var markdownListLevel: Int {
        get { self[MarkdownListLevelKey.self] }
        set { self[MarkdownListLevelKey.self] = newValue }
    }
}

// MARK: - Clay 样式令牌

@MainActor
private enum IndexClayMarkdownStyle {
    static let textColor = ToolTheme.textPrimary
    static let fieldColor = ToolTheme.editorBackground
    static let borderColor = ToolTheme.border
    static let markerMinWidth: CGFloat = round(13 * 1.5)

    /// indexClay 行内样式：13pt 正文、12pt mono 行内代码（编辑器底色）、
    /// accent 实线下划线链接、semibold 强调。`base` 供标题覆盖基础字号/字重。
    static func inlineSet(base override: MarkdownFontProperties? = nil) -> MarkdownInlineStyleSet {
        var styleSet = MarkdownInlineStyleSet(
            baseFont: .init(size: 13),
            baseForegroundColor: textColor,
            code: .init(
                fontProperties: .init(size: 12, design: .monospaced),
                backgroundColor: fieldColor
            ),
            emphasis: .init(fontProperties: .init(italic: true)),
            strong: .init(fontProperties: .init(weight: .semibold)),
            strikethrough: .init(strikethroughStyle: .single),
            link: .init(
                foregroundColor: ToolTheme.accent,
                underlineStyle: Text.LineStyle(pattern: .solid)
            )
        )
        if let override {
            styleSet.baseFont = override
        }
        return styleSet
    }
}
