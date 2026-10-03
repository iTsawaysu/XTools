// Adapted from MarkdownUI (https://github.com/gonzalezreal/swift-markdown-ui),
// The MIT License, Copyright (c) 2020 Guillermo Gonzalez.
// XTools 改动：只保留 cmark C AST → 文档模型的解析方向；未知的 C 节点类型
// 从 fatalError 降级为"跳过该节点"（阅读器不应因新版 cmark 的节点类型而崩溃，
// 与上游块级 init 对未处理类型的 assertionFailure+nil 策略一致）。

import cmark_gfm
import cmark_gfm_extensions
import Foundation

/// GFM（table/tasklist/strikethrough/autolink/tagfilter 扩展）解析入口。
/// 输出与 vendored MarkdownUI 2.4.1 快照逐节点等价的文档模型。
enum MarkdownDocument {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let blocks = UnsafeNode.parseMarkdown(markdown) { document in
            document.children.compactMap(MarkdownBlock.init(unsafeNode:))
        }
        return blocks ?? []
    }
}

extension MarkdownBlock {
    fileprivate init?(unsafeNode: UnsafeNode) {
        switch unsafeNode.knownNodeType {
        case .blockquote:
            self = .blockquote(children: unsafeNode.children.compactMap(MarkdownBlock.init(unsafeNode:)))
        case .list:
            if unsafeNode.children.contains(where: \.isTaskListItem) {
                self = .taskList(
                    isTight: unsafeNode.isTightList,
                    items: unsafeNode.children.map(MarkdownTaskListItem.init(unsafeNode:))
                )
            } else {
                switch unsafeNode.listType {
                case CMARK_BULLET_LIST:
                    self = .bulletedList(
                        isTight: unsafeNode.isTightList,
                        items: unsafeNode.children.map(MarkdownListItem.init(unsafeNode:))
                    )
                case CMARK_ORDERED_LIST:
                    self = .numberedList(
                        isTight: unsafeNode.isTightList,
                        start: unsafeNode.listStart,
                        items: unsafeNode.children.map(MarkdownListItem.init(unsafeNode:))
                    )
                default:
                    assertionFailure("cmark reported a list node without a list type.")
                    return nil
                }
            }
        case .codeBlock:
            self = .codeBlock(fenceInfo: unsafeNode.fenceInfo, content: unsafeNode.literal ?? "")
        case .htmlBlock:
            self = .htmlBlock(content: unsafeNode.literal ?? "")
        case .paragraph:
            self = .paragraph(content: unsafeNode.children.compactMap(MarkdownInline.init(unsafeNode:)))
        case .heading:
            self = .heading(
                level: unsafeNode.headingLevel,
                content: unsafeNode.children.compactMap(MarkdownInline.init(unsafeNode:))
            )
        case .table:
            self = .table(
                columnAlignments: unsafeNode.tableAlignments,
                rows: unsafeNode.children.map(MarkdownTableRow.init(unsafeNode:))
            )
        case .thematicBreak:
            self = .thematicBreak
        default:
            assertionFailure("Unhandled node type '\(unsafeNode.nodeTypeString)' in MarkdownBlock.")
            return nil
        }
    }
}

extension MarkdownListItem {
    fileprivate init(unsafeNode: UnsafeNode) {
        guard unsafeNode.knownNodeType == .item else {
            assertionFailure("Expected a list item but got a '\(unsafeNode.nodeTypeString)' instead.")
            self.init(children: [])
            return
        }
        self.init(children: unsafeNode.children.compactMap(MarkdownBlock.init(unsafeNode:)))
    }
}

extension MarkdownTaskListItem {
    fileprivate init(unsafeNode: UnsafeNode) {
        guard unsafeNode.knownNodeType == .taskListItem || unsafeNode.knownNodeType == .item else {
            assertionFailure("Expected a list item but got a '\(unsafeNode.nodeTypeString)' instead.")
            self.init(isCompleted: false, children: [])
            return
        }
        self.init(
            isCompleted: unsafeNode.isTaskListItemChecked,
            children: unsafeNode.children.compactMap(MarkdownBlock.init(unsafeNode:))
        )
    }
}

extension MarkdownTableRow {
    fileprivate init(unsafeNode: UnsafeNode) {
        guard unsafeNode.knownNodeType == .tableRow || unsafeNode.knownNodeType == .tableHead else {
            assertionFailure("Expected a table row but got a '\(unsafeNode.nodeTypeString)' instead.")
            self.init(cells: [])
            return
        }
        self.init(cells: unsafeNode.children.map(MarkdownTableCell.init(unsafeNode:)))
    }
}

extension MarkdownTableCell {
    fileprivate init(unsafeNode: UnsafeNode) {
        guard unsafeNode.knownNodeType == .tableCell else {
            assertionFailure("Expected a table cell but got a '\(unsafeNode.nodeTypeString)' instead.")
            self.init(content: [])
            return
        }
        self.init(content: unsafeNode.children.compactMap(MarkdownInline.init(unsafeNode:)))
    }
}

extension MarkdownInline {
    fileprivate init?(unsafeNode: UnsafeNode) {
        switch unsafeNode.knownNodeType {
        case .text:
            self = .text(unsafeNode.literal ?? "")
        case .softBreak:
            self = .softBreak
        case .lineBreak:
            self = .lineBreak
        case .code:
            self = .code(unsafeNode.literal ?? "")
        case .html:
            self = .html(unsafeNode.literal ?? "")
        case .emphasis:
            self = .emphasis(children: unsafeNode.children.compactMap(MarkdownInline.init(unsafeNode:)))
        case .strong:
            self = .strong(children: unsafeNode.children.compactMap(MarkdownInline.init(unsafeNode:)))
        case .strikethrough:
            self = .strikethrough(children: unsafeNode.children.compactMap(MarkdownInline.init(unsafeNode:)))
        case .link:
            self = .link(
                destination: unsafeNode.url ?? "",
                children: unsafeNode.children.compactMap(MarkdownInline.init(unsafeNode:))
            )
        case .image:
            self = .image(
                source: unsafeNode.url ?? "",
                children: unsafeNode.children.compactMap(MarkdownInline.init(unsafeNode:))
            )
        default:
            assertionFailure("Unhandled node type '\(unsafeNode.nodeTypeString)' in MarkdownInline.")
            return nil
        }
    }
}

private typealias UnsafeNode = UnsafeMutablePointer<cmark_node>

private extension UnsafeNode {
    /// 未知类型字符串返回 nil 并跳过节点：cmark 升级后新增节点类型时，
    /// 预览允许丢失该节点，不允许崩溃。
    var knownNodeType: NodeType? {
        guard let nodeType = NodeType(rawValue: nodeTypeString) else {
            assertionFailure("Unknown node type '\(nodeTypeString)' found.")
            return nil
        }
        return nodeType
    }

    var nodeTypeString: String {
        String(cString: cmark_node_get_type_string(self))
    }

    var children: UnsafeNodeSequence {
        .init(cmark_node_first_child(self))
    }

    var literal: String? {
        cmark_node_get_literal(self).map(String.init(cString:))
    }

    var url: String? {
        cmark_node_get_url(self).map(String.init(cString:))
    }

    var isTaskListItem: Bool {
        knownNodeType == .taskListItem
    }

    var listType: cmark_list_type {
        cmark_node_get_list_type(self)
    }

    var listStart: Int {
        Int(cmark_node_get_list_start(self))
    }

    var isTaskListItemChecked: Bool {
        cmark_gfm_extensions_get_tasklist_item_checked(self)
    }

    var isTightList: Bool {
        cmark_node_get_list_tight(self) != 0
    }

    var fenceInfo: String? {
        cmark_node_get_fence_info(self).map(String.init(cString:))
    }

    var headingLevel: Int {
        Int(cmark_node_get_heading_level(self))
    }

    private var tableColumns: Int {
        Int(cmark_gfm_extensions_get_table_columns(self))
    }

    var tableAlignments: [MarkdownTableColumnAlignment] {
        (0..<self.tableColumns).map { column in
            let ascii = cmark_gfm_extensions_get_table_alignments(self)[column]
            let scalar = UnicodeScalar(ascii)
            let character = Character(scalar)
            return .init(rawValue: character) ?? .none
        }
    }

    static func parseMarkdown<ResultType>(
        _ markdown: String,
        body: (UnsafeNode) throws -> ResultType
    ) rethrows -> ResultType? {
        cmark_gfm_core_extensions_ensure_registered()

        let parser = cmark_parser_new(CMARK_OPT_DEFAULT)
        defer { cmark_parser_free(parser) }

        let extensionNames: Set<String> = ["autolink", "strikethrough", "tagfilter", "tasklist", "table"]

        for extensionName in extensionNames {
            guard let syntaxExtension = cmark_find_syntax_extension(extensionName) else {
                continue
            }
            cmark_parser_attach_syntax_extension(parser, syntaxExtension)
        }

        cmark_parser_feed(parser, markdown, markdown.utf8.count)

        guard let document = cmark_parser_finish(parser) else {
            return nil
        }

        defer { cmark_node_free(document) }
        return try body(document)
    }
}

private enum NodeType: String {
    case document
    case blockquote = "block_quote"
    case list
    case item
    case codeBlock = "code_block"
    case htmlBlock = "html_block"
    case customBlock = "custom_block"
    case paragraph
    case heading
    case thematicBreak = "thematic_break"
    case text
    case softBreak = "softbreak"
    case lineBreak = "linebreak"
    case code
    case html = "html_inline"
    case customInline = "custom_inline"
    case emphasis = "emph"
    case strong
    case link
    case image
    case inlineAttributes = "attribute"
    case none = "NONE"
    case unknown = "<unknown>"

    // Extensions

    case strikethrough
    case table
    case tableHead = "table_header"
    case tableRow = "table_row"
    case tableCell = "table_cell"
    case taskListItem = "tasklist"
}

private struct UnsafeNodeSequence: Sequence {
    struct Iterator: IteratorProtocol {
        private var node: UnsafeNode?

        init(_ node: UnsafeNode?) {
            self.node = node
        }

        mutating func next() -> UnsafeNode? {
            guard let node else { return nil }
            defer { self.node = cmark_node_next(node) }
            return node
        }
    }

    private let node: UnsafeNode?

    init(_ node: UnsafeNode?) {
        self.node = node
    }

    func makeIterator() -> Iterator {
        .init(self.node)
    }
}
