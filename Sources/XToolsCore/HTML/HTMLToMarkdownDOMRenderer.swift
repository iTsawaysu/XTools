import Foundation
import SwiftSoup

private enum HTMLToMarkdownRenderContext {
    case normal
    case preformatted
    case tableCell
}

final class HTMLToMarkdownDOMRenderer {
    private let options: HTMLToMarkdownOptions
    private let cancellation: DiffCancellationChecker
    private var warnings: [HTMLToMarkdownWarning] = []

    init(
        options: HTMLToMarkdownOptions,
        shouldCancel: @escaping @Sendable () -> Bool = { false }
    ) {
        self.options = options
        self.cancellation = DiffCancellationChecker(shouldCancel: shouldCancel)
    }

    func convert(_ html: String) throws -> HTMLToMarkdownConversionResult {
        try cancellation.check()

        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return HTMLToMarkdownConversionResult(markdown: "", warnings: [])
        }

        do {
            let baseURI = options.baseURL?.absoluteString ?? ""
            let document = try SwiftSoup.parseHTML(trimmed, baseURI)
            try cancellation.check()
            try recordDroppedUnsafeElements(in: document)
            let root: Node = document.body() ?? document
            let rendered = try renderChildren(of: root, context: .normal)
            let markdown = normalizeDocumentMarkdown(rendered)

            if markdown.isEmpty {
                appendWarning(.emptyVisibleContent)
            }

            if html.utf8.count > options.liveConversionByteLimit {
                appendWarning(.inputTooLarge(options.liveConversionByteLimit))
            }

            return HTMLToMarkdownConversionResult(markdown: markdown, warnings: warnings)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let fallback = escapeMarkdownText(trimmed)
            appendWarning(.unsupportedElement("HTML 解析失败，已按纯文本降级。"))
            return HTMLToMarkdownConversionResult(markdown: fallback, warnings: warnings)
        }
    }

    private func renderNode(_ node: Node, context: HTMLToMarkdownRenderContext) throws -> String {
        if let text = node as? TextNode {
            return renderTextNode(text, context: context)
        }

        if let data = node as? DataNode {
            return context == .preformatted ? data.getWholeData() : ""
        }

        try cancellation.check()

        guard let element = node as? Element else {
            return try renderChildren(of: node, context: context)
        }

        let tagName = element.tagNameNormal()

        switch tagName {
        case "script", "style", "template":
            appendWarning(.droppedUnsafeElement(tagName))
            return ""
        case "head", "meta", "link", "base", "title":
            return ""
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(tagName.dropFirst()) ?? 1
            let text = try renderInlineChildren(of: element)
            return block(String(repeating: "#", count: level) + " " + text)
        case "p":
            return block(try renderInlineChildren(of: element))
        case "br":
            return "  \n"
        case "hr":
            return block("---")
        case "strong", "b":
            return wrapInline("**", try renderInlineChildren(of: element))
        case "em", "i":
            return wrapInline("*", try renderInlineChildren(of: element))
        case "del", "s", "strike":
            return wrapInline("~~", try renderInlineChildren(of: element))
        case "code":
            if element.parent()?.nodeName().lowercased() == "pre" {
                return rawText(in: element)
            }
            return inlineCode(rawText(in: element))
        case "pre":
            return fencedCodeBlock(for: element)
        case "a":
            return try link(for: element)
        case "img":
            return image(for: element)
        case "ul":
            return block(try renderList(element, ordered: false))
        case "ol":
            return block(try renderList(element, ordered: true))
        case "li":
            return try renderInlineChildren(of: element)
        case "blockquote":
            return block(blockquote(try renderChildren(of: element, context: .normal)))
        case "table":
            return block(try renderTable(element))
        case "thead", "tbody", "tfoot", "tr", "th", "td":
            return try renderInlineChildren(of: element)
        case "input":
            return inputFallback(for: element)
        case "textarea", "select", "button", "label", "option":
            return try renderInlineChildren(of: element)
        case "iframe", "video", "audio", "canvas", "svg":
            return try unsupportedMediaFallback(for: element, tagName: tagName)
        default:
            return try renderChildren(of: element, context: context)
        }
    }

    private func renderChildren(of node: Node, context: HTMLToMarkdownRenderContext) throws -> String {
        var parts: [String] = []
        for child in node.getChildNodes() {
            try cancellation.check()
            parts.append(try renderNode(child, context: context))
        }
        return parts.joined()
    }

    private func renderInlineChildren(of node: Node) throws -> String {
        collapseInlineWhitespace(try renderChildren(of: node, context: .normal))
    }

    private func renderTextNode(_ textNode: TextNode, context: HTMLToMarkdownRenderContext) -> String {
        let text = textNode.getWholeText()
        if context == .preformatted {
            return text
        }

        let collapsed = collapseWhitespaceRuns(text)
        if collapsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return collapsed.isEmpty ? "" : " "
        }

        return escapeMarkdownText(collapsed)
    }

    private func link(for element: Element) throws -> String {
        let label = try renderInlineChildren(of: element)
        let href = resolvedAttribute("href", for: element)
        guard !href.isEmpty else {
            return label
        }

        let title = attribute("title", for: element)
        let visibleLabel = label.isEmpty ? escapeMarkdownText(href) : label
        return "[\(visibleLabel)](\(escapeMarkdownDestination(href))\(markdownTitle(title)))"
    }

    private func image(for element: Element) -> String {
        let source = resolvedAttribute("src", for: element)
        guard !source.isEmpty else {
            appendWarning(.unsupportedElement("img"))
            return ""
        }

        let alt = escapeImageAlt(attribute("alt", for: element))
        let title = attribute("title", for: element)
        return "![\(alt)](\(escapeMarkdownDestination(source))\(markdownTitle(title)))"
    }

    private func inputFallback(for element: Element) -> String {
        let type = attribute("type", for: element).lowercased()
        if type == "checkbox" {
            return element.hasAttr("checked") ? "[x] " : "[ ] "
        }

        if let value = firstNonEmptyAttribute(["value", "placeholder", "aria-label"], for: element) {
            return escapeMarkdownText(value)
        }

        return ""
    }

    private func unsupportedMediaFallback(for element: Element, tagName: String) throws -> String {
        if let source = firstNonEmptyResolvedAttribute(["src", "poster", "href"], for: element) {
            let label = firstNonEmptyAttribute(["title", "aria-label", "alt"], for: element) ?? source
            appendWarning(.unsupportedElement(tagName))
            return "[\(escapeMarkdownText(label))](\(escapeMarkdownDestination(source)))"
        }

        let children = try renderInlineChildren(of: element)
        if !children.isEmpty {
            appendWarning(.unsupportedElement(tagName))
            return children
        }

        appendWarning(.unsupportedElement(tagName))
        return ""
    }

    private func fencedCodeBlock(for pre: Element) -> String {
        let codeElement = firstChildElement(named: "code", in: pre)
        let language = languageHint(from: codeElement ?? pre)
        let code = rawText(in: codeElement ?? pre).trimmingCharacters(in: .newlines)
        let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: code) + 1))
        let languageSuffix = language.map { escapeFenceLanguage($0) } ?? ""
        return block("\(fence)\(languageSuffix)\n\(code)\n\(fence)")
    }

    private func inlineCode(_ text: String) -> String {
        let fence = String(repeating: "`", count: max(1, longestBacktickRun(in: text) + 1))
        let needsPadding = text.hasPrefix("`") || text.hasSuffix("`") || text.hasPrefix(" ") || text.hasSuffix(" ")
        let body = needsPadding ? " \(text) " : text
        return "\(fence)\(body)\(fence)"
    }

    private func rawText(in node: Node) -> String {
        if let text = node as? TextNode {
            return text.getWholeText()
        }

        if let data = node as? DataNode {
            return data.getWholeData()
        }

        return node.getChildNodes()
            .map { rawText(in: $0) }
            .joined()
    }

    private func renderList(_ list: Element, ordered: Bool) throws -> String {
        try cancellation.check()
        let start = ordered ? max(Int(attribute("start", for: list)) ?? 1, 1) : 1
        let items = list.getChildNodes().compactMap { $0 as? Element }.filter { $0.tagNameNormal() == "li" }
        var lines: [String] = []

        for (offset, item) in items.enumerated() {
            try cancellation.check()
            let marker = ordered ? "\(start + offset). " : "+ "
            let renderedItem = try renderListItem(item, marker: marker)
            if !renderedItem.isEmpty {
                lines.append(renderedItem)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func renderListItem(_ item: Element, marker: String) throws -> String {
        let taskMarker = taskListMarker(in: item)
        var mainFragments: [String] = []
        var nestedLists: [String] = []
        var skippedTaskInput = false

        for child in item.getChildNodes() {
            if let childElement = child as? Element {
                let tagName = childElement.tagNameNormal()
                if tagName == "ul" || tagName == "ol" {
                    nestedLists.append(try renderList(childElement, ordered: tagName == "ol"))
                    continue
                }

                if !skippedTaskInput, tagName == "input", isCheckbox(childElement) {
                    skippedTaskInput = true
                    continue
                }
            }

            mainFragments.append(try renderNode(child, context: .normal))
        }

        var main = collapseInlineWhitespace(mainFragments.joined())
        if let taskMarker, !main.hasPrefix("[ ] ") && !main.hasPrefix("[x] ") {
            main = taskMarker + main
        }

        let mainLines = splitNonEmptyLines(main.isEmpty ? "" : main)
        var outputLines: [String] = []

        if mainLines.isEmpty {
            outputLines.append(marker.trimmingCharacters(in: .whitespaces))
        } else {
            outputLines.append(marker + mainLines[0])
            for line in mainLines.dropFirst() {
                outputLines.append(String(repeating: " ", count: marker.count) + line)
            }
        }

        for nested in nestedLists where !nested.isEmpty {
            outputLines.append(indentBlock(nested, by: marker.count))
        }

        return outputLines.joined(separator: "\n")
    }

    private func taskListMarker(in item: Element) -> String? {
        for child in item.getChildNodes() {
            if let text = child as? TextNode,
               text.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            guard let element = child as? Element,
                  element.tagNameNormal() == "input",
                  isCheckbox(element) else {
                return nil
            }

            return element.hasAttr("checked") ? "[x] " : "[ ] "
        }

        return nil
    }

    private func renderTable(_ table: Element) throws -> String {
        try cancellation.check()
        let rows = tableRows(in: table)
        guard !rows.isEmpty else {
            appendWarning(.emptyVisibleContent)
            return ""
        }

        var renderedRows: [[String]] = []
        for row in rows {
            try cancellation.check()
            let cells = try tableCells(in: row).map { cell in
                try renderTableCell(cell)
            }
            if !cells.isEmpty {
                renderedRows.append(cells)
            }
        }

        guard !renderedRows.isEmpty else {
            appendWarning(.emptyVisibleContent)
            return ""
        }

        let columnCount = renderedRows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return "" }

        let header = paddedRow(renderedRows[0], columnCount: columnCount)
        let alignments = tableCells(in: rows[0]).map(tableAlignment).padded(to: columnCount, with: nil)
        let bodyRows = renderedRows.dropFirst().map { paddedRow($0, columnCount: columnCount) }

        var lines = [
            markdownTableRow(header),
            markdownTableRow(alignments.map { separator(for: $0) })
        ]
        lines.append(contentsOf: bodyRows.map(markdownTableRow))
        return lines.joined(separator: "\n")
    }

    private func tableRows(in table: Element) -> [Element] {
        do {
            return try table.select("tr").map { $0 }
        } catch {
            return []
        }
    }

    private func tableCells(in row: Element) -> [Element] {
        row.children().filter { child in
            let tagName = child.tagNameNormal()
            return tagName == "th" || tagName == "td"
        }
    }

    private func renderTableCell(_ cell: Element) throws -> String {
        if cell.hasAttr("rowspan") || cell.hasAttr("colspan") {
            appendWarning(.flattenedTableSpan)
        }

        let rendered = collapseInlineWhitespace(try renderChildren(of: cell, context: .tableCell))
        return escapeTableCell(rendered)
    }

    private func tableAlignment(_ cell: Element) -> String? {
        let align = attribute("align", for: cell).lowercased()
        if ["left", "center", "right"].contains(align) {
            return align
        }

        let style = attribute("style", for: cell).lowercased()
        if style.contains("text-align: center") || style.contains("text-align:center") {
            return "center"
        }
        if style.contains("text-align: right") || style.contains("text-align:right") {
            return "right"
        }
        if style.contains("text-align: left") || style.contains("text-align:left") {
            return "left"
        }

        return nil
    }

    private func separator(for alignment: String?) -> String {
        switch alignment {
        case "left":
            return ":---"
        case "center":
            return ":---:"
        case "right":
            return "---:"
        default:
            return "---"
        }
    }

    private func markdownTableRow(_ row: [String]) -> String {
        "| " + row.joined(separator: " | ") + " |"
    }

    private func paddedRow(_ row: [String], columnCount: Int) -> [String] {
        row.padded(to: columnCount, with: "")
    }

    private func block(_ markdown: String) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "\n\n\(trimmed)\n\n"
    }

    private func blockquote(_ markdown: String) -> String {
        let normalized = normalizeDocumentMarkdown(markdown)
        guard !normalized.isEmpty else { return "" }
        return normalized
            .components(separatedBy: .newlines)
            .map { line in
                line.isEmpty ? ">" : "> \(line)"
            }
            .joined(separator: "\n")
    }

    private func wrapInline(_ marker: String, _ content: String) -> String {
        guard !content.isEmpty else { return "" }
        return marker + content + marker
    }

    private func normalizeDocumentMarkdown(_ markdown: String) -> String {
        var result = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                line.trimmingCharacters(in: .whitespaces).isEmpty ? "" : line
            }
            .joined(separator: "\n")

        // Collapse runs of 3+ newlines to exactly 2 in a single pass.
        var collapsed = ""
        collapsed.reserveCapacity(result.utf8.count)
        var newlineRun = 0
        for character in result {
            if character == "\n" {
                newlineRun += 1
                if newlineRun <= 2 {
                    collapsed.append(character)
                }
            } else {
                newlineRun = 0
                collapsed.append(character)
            }
        }
        result = collapsed

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func collapseInlineWhitespace(_ markdown: String) -> String {
        collapseWhitespaceRuns(markdown)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func collapseWhitespaceRuns(_ text: String) -> String {
        var output = ""
        var previousWasWhitespace = false

        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !previousWasWhitespace {
                    output.append(" ")
                    previousWasWhitespace = true
                }
            } else {
                output.unicodeScalars.append(scalar)
                previousWasWhitespace = false
            }
        }

        return output
    }

    private func escapeMarkdownText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private func escapeImageAlt(_ text: String) -> String {
        escapeMarkdownText(text)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func escapeTableCell(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "|", with: "\\|")
    }

    private func escapeMarkdownDestination(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    private func markdownTitle(_ title: String) -> String {
        guard !title.isEmpty else { return "" }
        let escaped = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return " \"\(escaped)\""
    }

    private func escapeFenceLanguage(_ language: String) -> String {
        language
            .filter { !$0.isWhitespace && $0 != "`" }
    }

    private func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    private func splitNonEmptyLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func indentBlock(_ block: String, by width: Int) -> String {
        let indent = String(repeating: " ", count: width)
        return block
            .components(separatedBy: .newlines)
            .map { $0.isEmpty ? "" : indent + $0 }
            .joined(separator: "\n")
    }

    private func languageHint(from element: Element?) -> String? {
        guard let element else { return nil }

        for attributeName in ["data-language", "data-lang"] {
            let value = attribute(attributeName, for: element)
            if !value.isEmpty { return value }
        }

        let classValue = attribute("class", for: element)
        for part in classValue.split(whereSeparator: { $0.isWhitespace }) {
            let value = String(part)
            if value.hasPrefix("language-") {
                return String(value.dropFirst("language-".count))
            }
            if value.hasPrefix("lang-") {
                return String(value.dropFirst("lang-".count))
            }
        }

        return nil
    }

    private func firstChildElement(named tagName: String, in element: Element) -> Element? {
        element.children().first { $0.tagNameNormal() == tagName }
    }

    private func isCheckbox(_ element: Element) -> Bool {
        attribute("type", for: element).lowercased() == "checkbox"
    }

    private func attribute(_ name: String, for element: Element) -> String {
        (try? element.attr(name)) ?? ""
    }

    private func resolvedAttribute(_ name: String, for element: Element) -> String {
        let absolute = (try? element.attr("abs:\(name)")) ?? ""
        if !absolute.isEmpty {
            return absolute
        }
        return attribute(name, for: element)
    }

    private func firstNonEmptyAttribute(_ names: [String], for element: Element) -> String? {
        for name in names {
            let value = attribute(name, for: element)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private func firstNonEmptyResolvedAttribute(_ names: [String], for element: Element) -> String? {
        for name in names {
            let value = resolvedAttribute(name, for: element)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private func appendWarning(_ warning: HTMLToMarkdownWarning) {
        if !warnings.contains(warning) {
            warnings.append(warning)
        }
    }

    private func recordDroppedUnsafeElements(in document: Document) throws {
        try cancellation.check()
        for tagName in ["script", "style", "template"] {
            if ((try? document.select(tagName).isEmpty) == false) {
                appendWarning(.droppedUnsafeElement(tagName))
            }
        }
    }
}

private extension Array {
    func padded(to size: Int, with value: Element) -> [Element] {
        if count >= size { return self }
        return self + Array(repeating: value, count: size - count)
    }
}
