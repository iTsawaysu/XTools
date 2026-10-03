// Adapted from MarkdownUI (https://github.com/gonzalezreal/swift-markdown-ui),
// The MIT License, Copyright (c) 2020 Guillermo Gonzalez.
// Modifications for XTools: types renamed from BlockNode/InlineNode and made
// Sendable, unused rewrite helpers dropped, comments localized where they
// document app-specific decisions. The parsed-shape parity with the vendored
// 2.4.1 snapshot is locked by HTMLToMarkdownConverterTests' GFM oracle.

import Foundation

/// GFM 文档模型：`MarkdownDocument.parse` 产出、`IndexMarkdownPreviewContent`
/// 渲染、`MarkdownDocumentRenderer` 回建 C AST 生成 oracle 输出。
enum MarkdownBlock: Hashable, Sendable {
    case blockquote(children: [MarkdownBlock])
    case bulletedList(isTight: Bool, items: [MarkdownListItem])
    case numberedList(isTight: Bool, start: Int, items: [MarkdownListItem])
    case taskList(isTight: Bool, items: [MarkdownTaskListItem])
    case codeBlock(fenceInfo: String?, content: String)
    case htmlBlock(content: String)
    case paragraph(content: [MarkdownInline])
    case heading(level: Int, content: [MarkdownInline])
    case table(columnAlignments: [MarkdownTableColumnAlignment], rows: [MarkdownTableRow])
    case thematicBreak
}

enum MarkdownInline: Hashable, Sendable {
    case text(String)
    case softBreak
    case lineBreak
    case code(String)
    case html(String)
    case emphasis(children: [MarkdownInline])
    case strong(children: [MarkdownInline])
    case strikethrough(children: [MarkdownInline])
    case link(destination: String, children: [MarkdownInline])
    case image(source: String, children: [MarkdownInline])
}

struct MarkdownListItem: Hashable, Sendable {
    let children: [MarkdownBlock]
}

struct MarkdownTaskListItem: Hashable, Sendable {
    let isCompleted: Bool
    let children: [MarkdownBlock]
}

enum MarkdownTableColumnAlignment: Character, Sendable {
    case none = "\0"
    case left = "l"
    case center = "c"
    case right = "r"
}

struct MarkdownTableRow: Hashable, Sendable {
    let cells: [MarkdownTableCell]
}

struct MarkdownTableCell: Hashable, Sendable {
    let content: [MarkdownInline]
}

/// 段落里"独立成块"的图片：source 为图片地址，alt 为替代文本，
/// destination 是包在外面的链接地址（`[![alt](src)](href)`）。
struct MarkdownImageData: Hashable, Sendable {
    var source: String
    var alt: String
    var destination: String?
}

extension MarkdownBlock {
    var childBlocks: [MarkdownBlock] {
        switch self {
        case .blockquote(let children):
            return children
        case .bulletedList(_, let items):
            return items.flatMap(\.children)
        case .numberedList(_, _, let items):
            return items.flatMap(\.children)
        case .taskList(_, let items):
            return items.flatMap(\.children)
        default:
            return []
        }
    }

    var isParagraph: Bool {
        guard case .paragraph = self else { return false }
        return true
    }
}

extension MarkdownInline {
    var childInlines: [MarkdownInline] {
        switch self {
        case .emphasis(let children), .strong(let children), .strikethrough(let children):
            return children
        case .link(_, let children), .image(_, let children):
            return children
        default:
            return []
        }
    }

    /// 顶层图片或"链接恰好只包一张图片"的复合图片；其余嵌套位置返回 nil。
    var imageData: MarkdownImageData? {
        switch self {
        case .image(let source, let children):
            return .init(source: source, alt: children.renderPlainText(), destination: nil)
        case .link(let destination, let children) where children.count == 1:
            guard var imageData = children.first?.imageData else { return nil }
            imageData.destination = destination
            return imageData
        default:
            return nil
        }
    }
}

extension Sequence where Element == MarkdownInline {
    /// 纯文本投影：文本/行内代码/HTML 按字面收集，软换行折叠成空格。
    func renderPlainText() -> String {
        flatMap { inline -> [String] in
            switch inline {
            case .text(let content), .code(let content), .html(let content):
                return [content]
            case .softBreak:
                return [" "]
            case .lineBreak:
                return ["\n"]
            default:
                return []
            }
        }
        .joined()
    }
}
