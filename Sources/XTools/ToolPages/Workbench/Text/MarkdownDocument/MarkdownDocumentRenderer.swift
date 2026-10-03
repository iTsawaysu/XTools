// Adapted from MarkdownUI (https://github.com/gonzalezreal/swift-markdown-ui),
// The MIT License, Copyright (c) 2020 Guillermo Gonzalez.
// 文档模型 → cmark C AST → 官方渲染器的出口。HTMLToMarkdownConverterTests 以
// `cmark_render_html` 的输出为独立 oracle 验证 HTML→Markdown 转换，因此这条
// 路径的输出必须与 vendored 2.4.1 快照逐字节一致；renderPlainText 会像
// MarkdownContent.renderPlainText 一样剥掉单个结尾换行。

import cmark_gfm
import cmark_gfm_extensions
import Foundation

extension Array where Element == MarkdownBlock {
    func renderPlainText() -> String {
        let result = makeDocument { document in
            String(cString: cmark_render_plaintext(document, CMARK_OPT_DEFAULT, 0))
        } ?? ""
        return result.hasSuffix("\n") ? String(result.dropLast()) : result
    }

    func renderHTML() -> String {
        makeDocument { document in
            String(cString: cmark_render_html(document, CMARK_OPT_DEFAULT, nil))
        } ?? ""
    }

    /// 与预览共用的行内渲染器出口：把第一个文本块渲染成 AttributedString，
    /// 供回归测试在不进 SwiftUI 的前提下锁定行内渲染行为（HTML 注释不可见、
    /// 邮箱不得变成 mailto 链接）。
    func renderFirstTextBlockAttributedString() -> AttributedString? {
        guard let block = first else { return nil }
        let inlines: [MarkdownInline]
        switch block {
        case .paragraph(let content), .heading(_, let content):
            inlines = content
        default:
            return nil
        }

        return inlines.reduce(into: AttributedString()) { result, inline in
            result += inline.renderAttributedString(styleSet: .plain)
        }
    }

    private func makeDocument<ResultType>(
        body: (UnsafeMutablePointer<cmark_node>) throws -> ResultType
    ) rethrows -> ResultType? {
        cmark_gfm_core_extensions_ensure_registered()
        guard let document = cmark_node_new(CMARK_NODE_DOCUMENT) else { return nil }
        compactMap(UnsafeNode.make).forEach { cmark_node_append_child(document, $0) }

        defer { cmark_node_free(document) }
        return try body(document)
    }
}

private typealias UnsafeNode = UnsafeMutablePointer<cmark_node>

private extension UnsafeNode {
    static func make(_ block: MarkdownBlock) -> UnsafeNode? {
        switch block {
        case .blockquote(let children):
            guard let node = cmark_node_new(CMARK_NODE_BLOCK_QUOTE) else { return nil }
            children.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
            return node
        case .bulletedList(let isTight, let items):
            guard let node = cmark_node_new(CMARK_NODE_LIST) else { return nil }
            cmark_node_set_list_type(node, CMARK_BULLET_LIST)
            cmark_node_set_list_tight(node, isTight ? 1 : 0)
            items.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
            return node
        case .numberedList(let isTight, let start, let items):
            guard let node = cmark_node_new(CMARK_NODE_LIST) else { return nil }
            cmark_node_set_list_type(node, CMARK_ORDERED_LIST)
            cmark_node_set_list_tight(node, isTight ? 1 : 0)
            cmark_node_set_list_start(node, Int32(start))
            items.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
            return node
        case .taskList(let isTight, let items):
            guard let node = cmark_node_new(CMARK_NODE_LIST) else { return nil }
            cmark_node_set_list_type(node, CMARK_BULLET_LIST)
            cmark_node_set_list_tight(node, isTight ? 1 : 0)
            items.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
            return node
        case .codeBlock(let fenceInfo, let content):
            guard let node = cmark_node_new(CMARK_NODE_CODE_BLOCK) else { return nil }
            if let fenceInfo {
                cmark_node_set_fence_info(node, fenceInfo)
            }
            cmark_node_set_literal(node, content)
            return node
        case .htmlBlock(let content):
            guard let node = cmark_node_new(CMARK_NODE_HTML_BLOCK) else { return nil }
            cmark_node_set_literal(node, content)
            return node
        case .paragraph(let content):
            guard let node = cmark_node_new(CMARK_NODE_PARAGRAPH) else { return nil }
            content.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
            return node
        case .heading(let level, let content):
            guard let node = cmark_node_new(CMARK_NODE_HEADING) else { return nil }
            cmark_node_set_heading_level(node, Int32(level))
            content.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
            return node
        case .table(let columnAlignments, let rows):
            guard let table = cmark_find_syntax_extension("table"),
                let node = cmark_node_new_with_ext(ExtensionNodeTypes.shared.CMARK_NODE_TABLE, table)
            else {
                return nil
            }
            cmark_gfm_extensions_set_table_columns(node, UInt16(columnAlignments.count))
            var alignments = columnAlignments.map { $0.rawValue.asciiValue! }
            cmark_gfm_extensions_set_table_alignments(node, UInt16(columnAlignments.count), &alignments)
            rows.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
            if let header = cmark_node_first_child(node) {
                cmark_gfm_extensions_set_table_row_is_header(header, 1)
            }
            return node
        case .thematicBreak:
            guard let node = cmark_node_new(CMARK_NODE_THEMATIC_BREAK) else { return nil }
            return node
        }
    }

    static func make(_ item: MarkdownListItem) -> UnsafeNode? {
        guard let node = cmark_node_new(CMARK_NODE_ITEM) else { return nil }
        item.children.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
        return node
    }

    static func make(_ item: MarkdownTaskListItem) -> UnsafeNode? {
        guard let tasklist = cmark_find_syntax_extension("tasklist"),
            let node = cmark_node_new_with_ext(CMARK_NODE_ITEM, tasklist)
        else {
            return nil
        }
        cmark_gfm_extensions_set_tasklist_item_checked(node, item.isCompleted)
        item.children.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
        return node
    }

    static func make(_ tableRow: MarkdownTableRow) -> UnsafeNode? {
        guard let table = cmark_find_syntax_extension("table"),
            let node = cmark_node_new_with_ext(ExtensionNodeTypes.shared.CMARK_NODE_TABLE_ROW, table)
        else {
            return nil
        }
        tableRow.cells.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
        return node
    }

    static func make(_ tableCell: MarkdownTableCell) -> UnsafeNode? {
        guard let table = cmark_find_syntax_extension("table"),
            let node = cmark_node_new_with_ext(ExtensionNodeTypes.shared.CMARK_NODE_TABLE_CELL, table)
        else {
            return nil
        }
        // 重建的单元格必须显式设置 span：calloc 默认 0 会被 table 扩展当作
        // "填充格"跳过，HTML 输出丢失 th/td 标签（vendored 同路径存在同样问题，
        // 只是没有用例把表格走 renderHTML，故从未暴露）。
        cmark_gfm_extensions_set_table_cell_colspan(node, 1)
        cmark_gfm_extensions_set_table_cell_rowspan(node, 1)
        // 已知限制：cmark-gfm 未导出 cell_index 的设置 API，重建单元格的对齐
        // 属性会全部读到第 0 列的取值。预览的对齐来自文档模型（正确）；oracle
        // 路径只被转换器的文本级断言消费，不涉及表格对齐。
        tableCell.content.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
        return node
    }

    static func make(_ inline: MarkdownInline) -> UnsafeNode? {
        switch inline {
        case .text(let content):
            guard let node = cmark_node_new(CMARK_NODE_TEXT) else { return nil }
            cmark_node_set_literal(node, content)
            return node
        case .softBreak:
            return cmark_node_new(CMARK_NODE_SOFTBREAK)
        case .lineBreak:
            return cmark_node_new(CMARK_NODE_LINEBREAK)
        case .code(let content):
            guard let node = cmark_node_new(CMARK_NODE_CODE) else { return nil }
            cmark_node_set_literal(node, content)
            return node
        case .html(let content):
            guard let node = cmark_node_new(CMARK_NODE_HTML_INLINE) else { return nil }
            cmark_node_set_literal(node, content)
            return node
        case .emphasis(let children):
            guard let node = cmark_node_new(CMARK_NODE_EMPH) else { return nil }
            children.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
            return node
        case .strong(let children):
            guard let node = cmark_node_new(CMARK_NODE_STRONG) else { return nil }
            children.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
            return node
        case .strikethrough(let children):
            guard let strikethrough = cmark_find_syntax_extension("strikethrough"),
                let node = cmark_node_new_with_ext(
                    ExtensionNodeTypes.shared.CMARK_NODE_STRIKETHROUGH, strikethrough)
            else {
                return nil
            }
            children.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
            return node
        case .link(let destination, let children):
            guard let node = cmark_node_new(CMARK_NODE_LINK) else { return nil }
            cmark_node_set_url(node, destination)
            children.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
            return node
        case .image(let source, let children):
            guard let node = cmark_node_new(CMARK_NODE_IMAGE) else { return nil }
            cmark_node_set_url(node, source)
            children.compactMap(UnsafeNode.make).forEach { cmark_node_append_child(node, $0) }
            return node
        }
    }
}

/// 表格/删除线等扩展节点类型不在 `cmark_gfm_extensions` 头文件里导出，
/// 需要从符号表取（与上游 MarkdownParser.swift 同一手法）。
private struct ExtensionNodeTypes: @unchecked Sendable {
    let CMARK_NODE_TABLE: cmark_node_type
    let CMARK_NODE_TABLE_ROW: cmark_node_type
    let CMARK_NODE_TABLE_CELL: cmark_node_type
    let CMARK_NODE_STRIKETHROUGH: cmark_node_type

    static let shared = ExtensionNodeTypes()

    private init() {
        func findNodeType(_ name: String, in handle: UnsafeMutableRawPointer!) -> cmark_node_type? {
            guard let symbol = dlsym(handle, name) else {
                return nil
            }
            return symbol.assumingMemoryBound(to: cmark_node_type.self).pointee
        }

        let handle = dlopen(nil, RTLD_LAZY)

        self.CMARK_NODE_TABLE = findNodeType("CMARK_NODE_TABLE", in: handle) ?? CMARK_NODE_NONE
        self.CMARK_NODE_TABLE_ROW = findNodeType("CMARK_NODE_TABLE_ROW", in: handle) ?? CMARK_NODE_NONE
        self.CMARK_NODE_TABLE_CELL =
            findNodeType("CMARK_NODE_TABLE_CELL", in: handle) ?? CMARK_NODE_NONE
        self.CMARK_NODE_STRIKETHROUGH =
            findNodeType("CMARK_NODE_STRIKETHROUGH", in: handle) ?? CMARK_NODE_NONE

        dlclose(handle)
    }
}
