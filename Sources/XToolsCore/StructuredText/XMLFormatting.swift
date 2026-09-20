import Foundation

public enum XMLFormatting {
    /// 允许的最大元素嵌套深度。
    ///
    /// 缩进渲染递归实现，每层都会对整棵子树调用一次 `xmlString`；而深层 `XMLNode`
    /// 树连释放都是递归的。实测约 160 层渲染即栈溢出，2000 层即使不渲染也会在
    /// 释放时崩溃。这里取与 JSON 侧同一量级的保守上限（JSON 为 32），
    /// 足以覆盖真实文档。
    public static let maximumNestingDepth = 64

    public enum FormattingError: Error, LocalizedError, Equatable {
        case invalidXML(FormatDiagnostic)

        public var errorDescription: String? {
            switch self {
            case .invalidXML(let diagnostic):
                return diagnostic.workspaceMessage
            }
        }

        public var diagnostic: FormatDiagnostic {
            switch self {
            case .invalidXML(let diagnostic):
                return diagnostic
            }
        }
    }

    public static func format(_ input: String, indentWidth: Int = 2, minify: Bool = false) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let normalizedInput = normalizeStringEncodingDeclaration(in: trimmed)
        do {
            if let syntaxDiagnostic = syntaxDiagnostic(for: normalizedInput) {
                throw FormattingError.invalidXML(syntaxDiagnostic)
            }

            let document = try XMLDocument(
                xmlString: normalizedInput,
                options: [
                    .nodePreserveCDATA,
                    .nodePreserveWhitespace,
                    .nodePreserveEmptyElements,
                    .nodePreserveQuotes,
                    .nodeLoadExternalEntitiesNever
                ]
            )
            guard let root = document.rootElement() else {
                throw FormattingError.invalidXML(
                    FormatDiagnostic(formatName: "XML", message: "XML 文档缺少根节点")
                )
            }

            // 缩进渲染是递归的，且每层都要对整个子树调用一次 xmlString；深度守卫在
            // syntaxDiagnostic 里随解析一起完成，必须在构造 XMLDocument 之前拦住：
            // 深层文档一旦被构造成 XMLNode 树，连释放都是递归的，会在 dealloc 时崩溃。

            var outputParts = topLevelPreamble(in: normalizedInput)
            let topChildren = document.children ?? []
            if let rootIndex = topChildren.firstIndex(where: { $0.kind == .element }) {
                for child in topChildren[rootIndex...] {
                    if child.kind == .element {
                        if minify {
                            outputParts.append(render(child, level: 0, indentWidth: 0, minify: true))
                        } else {
                            outputParts.append(render(child, level: 0, indentWidth: max(0, indentWidth), minify: false))
                        }
                    } else if child.kind == .comment || child.kind == .processingInstruction {
                        outputParts.append(child.xmlString(options: []))
                    }
                }
            } else {
                if minify {
                    outputParts.append(render(root, level: 0, indentWidth: 0, minify: true))
                } else {
                    outputParts.append(render(root, level: 0, indentWidth: max(0, indentWidth), minify: false))
                }
            }
            return outputParts.joined(separator: "\n")
        } catch let formattingError as FormattingError {
            throw formattingError
        } catch {
            throw FormattingError.invalidXML(
                FormatDiagnostic(
                    formatName: "XML",
                    message: xmlMessage(from: error),
                    suggestion: "检查标签是否成对闭合、属性值是否使用引号。"
                )
            )
        }
    }

    public static func minify(_ input: String) throws -> String {
        try format(input, indentWidth: 0, minify: true)
    }

    private static func syntaxDiagnostic(for input: String) -> FormatDiagnostic? {
        guard let data = input.data(using: .utf8) else {
            return FormatDiagnostic(
                formatName: "XML",
                message: "无法读取 XML 文本",
                suggestion: "确认输入是 UTF-8 兼容文本。"
            )
        }

        let delegate = XMLSyntaxErrorDelegate(depthLimit: maximumNestingDepth)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate

        guard !parser.parse() else {
            return nil
        }

        // 深度超限时解析是被主动 abort 的，随后的解析错误只是副产品，必须先报深度。
        if delegate.exceededDepthLimit {
            return FormatDiagnostic(
                formatName: "XML",
                message: "XML 嵌套层级过深，超过最大安全深度 \(maximumNestingDepth) 层",
                suggestion: "减少标签嵌套层数后重试。"
            )
        }

        let line = max(1, parser.lineNumber)
        let column = max(1, parser.columnNumber)
        let message = xmlMessage(from: delegate.error ?? parser.parserError)

        return FormatDiagnostic(
            formatName: "XML",
            message: message,
            input: input,
            line: line,
            column: column,
            suggestion: "检查标签是否成对闭合、是否只有一个根节点、属性名是否重复，以及属性值是否使用引号。"
        )
    }

    /// 把 libxml 的解析错误码翻译成用户能据以定位的文案。
    /// 码值取自 `XMLParserDelegate` 上报的 NSError（`parser.parserError` 只给出
    /// 笼统的 5/111，必须优先取 delegate 的细粒度错误）。下表经语料实测确认：
    /// 4=文档为空、5=文档结束异常、26=未定义实体、38=属性值未闭合、
    /// 39=属性值缺引号、42=属性名重复、45=注释未闭合、68=名称非法（该码同时
    /// 覆盖未转义的 & 与非法标签名，故文案必须同时说明两者）、76=标签不匹配。
    private static func xmlMessage(from error: Error?) -> String {
        guard let error else { return "XML 语法错误" }

        let nsError = error as NSError
        guard nsError.domain == "NSXMLParserErrorDomain" else {
            return "XML 语法错误"
        }

        switch nsError.code {
        case 4:
            return "输入中没有 XML 内容"
        case 5:
            return "XML 文档没有正确闭合，或存在多个根节点"
        case 26, 111:
            return "引用了未定义的实体，或 & 没有正确转义"
        case 38:
            return "属性值没有闭合"
        case 39:
            return "属性值必须使用引号"
        case 42:
            return "同一个标签上有重复属性名"
        case 45:
            return "注释没有闭合"
        case 68:
            return "文本中的 & 没有正确转义，或标签名与属性名无效"
        case 76:
            return "开始标签和结束标签不匹配"
        default:
            return "XML 语法错误"
        }
    }

    /// The public API receives an already-decoded Swift `String`. A legacy
    /// byte-encoding declaration must therefore not ask Foundation to decode
    /// the String's UTF-8 representation a second time.
    private static func normalizeStringEncodingDeclaration(in input: String) -> String {
        guard input.hasPrefix("<?xml"),
              let declarationEnd = input.range(of: "?>")?.upperBound else {
            return input
        }

        let declarationRange = input.startIndex..<declarationEnd
        let declaration = String(input[declarationRange])
        guard let valueRange = encodingValueRange(in: declaration) else {
            return input
        }

        let encoding = declaration[valueRange].lowercased()
        guard encoding != "utf-8", encoding != "utf8" else {
            return input
        }

        var normalizedDeclaration = declaration
        normalizedDeclaration.replaceSubrange(valueRange, with: "UTF-8")
        var normalized = input
        normalized.replaceSubrange(declarationRange, with: normalizedDeclaration)
        return normalized
    }

    private static func encodingValueRange(in declaration: String) -> Range<String.Index>? {
        var searchStart = declaration.startIndex

        while searchStart < declaration.endIndex,
              let nameRange = declaration.range(
                of: "encoding",
                options: .caseInsensitive,
                range: searchStart..<declaration.endIndex
              ) {
            let beforeIsNameCharacter = nameRange.lowerBound > declaration.startIndex
                && isXMLNameCharacter(declaration[declaration.index(before: nameRange.lowerBound)])
            let afterIsNameCharacter = nameRange.upperBound < declaration.endIndex
                && isXMLNameCharacter(declaration[nameRange.upperBound])
            if beforeIsNameCharacter || afterIsNameCharacter {
                searchStart = nameRange.upperBound
                continue
            }

            var index = nameRange.upperBound
            while index < declaration.endIndex, declaration[index].isWhitespace {
                index = declaration.index(after: index)
            }
            guard index < declaration.endIndex, declaration[index] == "=" else {
                searchStart = nameRange.upperBound
                continue
            }
            index = declaration.index(after: index)
            while index < declaration.endIndex, declaration[index].isWhitespace {
                index = declaration.index(after: index)
            }
            guard index < declaration.endIndex,
                  declaration[index] == "\"" || declaration[index] == "'" else {
                return nil
            }

            let quote = declaration[index]
            let valueStart = declaration.index(after: index)
            guard let valueEnd = declaration[valueStart...].firstIndex(of: quote) else {
                return nil
            }
            return valueStart..<valueEnd
        }

        return nil
    }

    private static func isXMLNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-" || character == ":"
    }

    private static func doctypeDeclaration(in input: String) -> String? {
        var index = input.startIndex

        while index < input.endIndex {
            if input[index...].hasPrefix("<!--") {
                if let endRange = input.range(of: "-->", range: index..<input.endIndex) {
                    index = endRange.upperBound
                    continue
                } else {
                    return nil
                }
            }

            if input[index...].hasPrefix("<?") {
                if let endRange = input.range(of: "?>", range: index..<input.endIndex) {
                    index = endRange.upperBound
                    continue
                } else {
                    return nil
                }
            }

            if input[index...].range(of: "<!DOCTYPE", options: [.caseInsensitive, .anchored]) != nil {
                let start = index
                var inBracket = false
                var inSingleQuote = false
                var inDoubleQuote = false
                var inComment = false
                var curr = index

                while curr < input.endIndex {
                    if inComment {
                        if input[curr...].hasPrefix("-->") {
                            inComment = false
                            curr = input.index(curr, offsetBy: 2)
                        }
                    } else if inSingleQuote {
                        if input[curr] == "'" {
                            inSingleQuote = false
                        }
                    } else if inDoubleQuote {
                        if input[curr] == "\"" {
                            inDoubleQuote = false
                        }
                    } else {
                        if input[curr...].hasPrefix("<!--") {
                            inComment = true
                            curr = input.index(curr, offsetBy: 3)
                        } else if input[curr] == "\"" {
                            inDoubleQuote = true
                        } else if input[curr] == "'" {
                            inSingleQuote = true
                        } else if input[curr] == "[" {
                            inBracket = true
                        } else if input[curr] == "]" {
                            inBracket = false
                        } else if input[curr] == ">" && !inBracket {
                            return String(input[start...curr])
                        }
                    }
                    curr = input.index(after: curr)
                }
                return nil
            }

            if input[index] == "<" && !input[index...].hasPrefix("<!") && !input[index...].hasPrefix("<?") {
                break
            }

            index = input.index(after: index)
        }

        return nil
    }

    private static func topLevelPreamble(in input: String) -> [String] {
        var parts: [String] = []
        var index = input.startIndex

        while index < input.endIndex {
            while index < input.endIndex, input[index].isWhitespace {
                index = input.index(after: index)
            }
            guard index < input.endIndex else { break }

            if input[index...].hasPrefix("<!--") {
                guard let end = input.range(of: "-->", range: index..<input.endIndex) else { break }
                parts.append(String(input[index..<end.upperBound]))
                index = end.upperBound
                continue
            }

            if input[index...].hasPrefix("<?") {
                guard let end = input.range(of: "?>", range: index..<input.endIndex) else { break }
                parts.append(String(input[index..<end.upperBound]))
                index = end.upperBound
                continue
            }

            if input[index...].range(of: "<!DOCTYPE", options: [.caseInsensitive, .anchored]) != nil,
               let doctype = doctypeDeclaration(in: String(input[index...])) {
                parts.append(doctype)
                index = input.index(index, offsetBy: doctype.count)
                continue
            }

            break
        }

        return parts
    }



    private enum XMLSpaceMode {
        case `default`
        case preserve
    }

    private struct LayoutPrefix {
        let raw: String

        static func spaces(_ count: Int) -> LayoutPrefix {
            LayoutPrefix(raw: String(repeating: " ", count: max(0, count)))
        }

        func appendingSpaces(_ count: Int) -> LayoutPrefix {
            LayoutPrefix(raw: raw + String(repeating: " ", count: max(0, count)))
        }
    }

    private static func render(
        _ node: XMLNode,
        level: Int,
        indentWidth: Int,
        minify: Bool,
        inheritedSpace: XMLSpaceMode = .default,
        includeLeadingIndent: Bool = true,
        layoutPrefixOverride: LayoutPrefix? = nil
    ) -> String {
        let fallbackLayoutPrefix = layoutPrefixOverride ?? .spaces(level * indentWidth)
        let preserveLeadingWhitespace = inheritedSpace == .preserve && !includeLeadingIndent
        let layoutPrefix = preserveLeadingWhitespace
            ? leadingPreservedLinePrefix(of: node) ?? fallbackLayoutPrefix
            : fallbackLayoutPrefix
        let layoutIndent = layoutPrefix.raw
        let indent = includeLeadingIndent ? layoutIndent : ""
        guard node.kind == .element else {
            return indent + node.xmlString(options: [])
        }

        let element = node as? XMLElement
        let effectiveSpace = xmlSpaceMode(for: element, inherited: inheritedSpace)
        let children = node.children ?? []
        guard !children.isEmpty else {
            return indent + elementXMLString(node, preservingLeadingWhitespace: preserveLeadingWhitespace)
        }

        if effectiveSpace == .preserve {
            guard let name = node.name,
                  let opening = openingTag(of: node, preservingLeadingWhitespace: preserveLeadingWhitespace) else {
                return indent + node.xmlString(options: [])
            }

            var currentLayoutPrefix = layoutPrefix
            let renderedChildren = children.map { child in
                let renderedChild = render(
                    child,
                    level: level + 1,
                    indentWidth: indentWidth,
                    minify: minify,
                    inheritedSpace: .preserve,
                    includeLeadingIndent: false,
                    layoutPrefixOverride: currentLayoutPrefix
                )
                currentLayoutPrefix = preservedLinePrefix(after: renderedChild) ?? currentLayoutPrefix
                return renderedChild
            }.joined()
            let trailingContent = preservedTrailingContent(
                of: node,
                opening: opening,
                children: children,
                name: name
            )
            return "\(indent)\(opening)\(renderedChildren)\(trailingContent)</\(name)>"
        }

        let significantChildren = children.filter { child in
            guard child.kind == .text else { return true }
            return !(child.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let hasStructuredChild = significantChildren.contains { isStructuredContent($0.kind) }
        let hasSignificantText = significantChildren.contains { isTextContent($0.kind) }

        // Pretty-printing mixed content inserts new text-node whitespace. Keep
        // that subtree compact so visible text remains byte-for-byte meaningful.
        if hasStructuredChild && hasSignificantText {
            return indent + elementXMLString(node, preservingLeadingWhitespace: preserveLeadingWhitespace)
        }

        if !hasStructuredChild {
            return indent + elementXMLString(node, preservingLeadingWhitespace: preserveLeadingWhitespace)
        }

        guard let opening = openingTag(of: node, preservingLeadingWhitespace: preserveLeadingWhitespace),
              let name = node.name else {
            return indent + elementXMLString(node, preservingLeadingWhitespace: preserveLeadingWhitespace)
        }

        let renderedChildren = significantChildren.map { child in
            render(
                child,
                level: level + 1,
                indentWidth: indentWidth,
                minify: minify,
                inheritedSpace: .default,
                includeLeadingIndent: !minify,
                layoutPrefixOverride: layoutPrefixOverride == nil
                    ? nil
                    : layoutPrefix.appendingSpaces(indentWidth)
            )
        }.joined(separator: minify ? "" : "\n")

        if minify {
            return "\(indent)\(opening)\(renderedChildren)</\(name)>"
        }

        // A default subtree can begin within an inherited `xml:space="preserve"`
        // text node. Its opening tag must use that preserved prefix, while its
        // generated closing tag returns to the preserved line's layout indent.
        return "\(indent)\(opening)\n\(renderedChildren)\n\(layoutIndent)</\(name)>"
    }

    private static func leadingPreservedLinePrefix(of node: XMLNode) -> LayoutPrefix? {
        let raw = node.xmlString(options: [])
        guard let elementStart = raw.firstIndex(of: "<") else { return nil }
        return preservedLinePrefix(after: String(raw[..<elementStart]))
    }

    private static func preservedLinePrefix(after text: String) -> LayoutPrefix? {
        guard let lineBreak = text.lastIndex(where: { $0 == "\n" || $0 == "\r" }) else {
            return nil
        }

        let trailingText = text[text.index(after: lineBreak)...]
        guard trailingText.allSatisfy({ $0 == " " || $0 == "\t" }) else {
            return nil
        }
        return LayoutPrefix(raw: String(trailingText))
    }

    private static func xmlSpaceMode(for element: XMLElement?, inherited: XMLSpaceMode) -> XMLSpaceMode {
        guard let value = element?.attribute(forName: "xml:space")?.stringValue else {
            return inherited
        }

        switch value {
        case "preserve":
            return .preserve
        case "default":
            return .default
        default:
            return inherited
        }
    }

    private static func openingTag(of node: XMLNode, preservingLeadingWhitespace: Bool) -> String? {
        let compact = elementXMLString(node, preservingLeadingWhitespace: preservingLeadingWhitespace)
        var index = compact.startIndex
        var quote: Character?

        while index < compact.endIndex {
            let character = compact[index]
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return String(compact[...index])
            }
            index = compact.index(after: index)
        }

        return nil
    }

    private static func elementXMLString(_ node: XMLNode, preservingLeadingWhitespace: Bool) -> String {
        let raw = node.xmlString(options: [])
        guard !preservingLeadingWhitespace, let elementStart = raw.firstIndex(of: "<") else {
            return raw
        }
        return String(raw[elementStart...])
    }

    private static func preservedTrailingContent(
        of node: XMLNode,
        opening: String,
        children: [XMLNode],
        name: String
    ) -> String {
        let raw = elementXMLString(node, preservingLeadingWhitespace: opening.first?.isWhitespace == true)
        let closing = "</\(name)>"
        guard raw.hasPrefix(opening), raw.hasSuffix(closing) else {
            return ""
        }

        let contentStart = raw.index(raw.startIndex, offsetBy: opening.count)
        let contentEnd = raw.index(raw.endIndex, offsetBy: -closing.count)
        let content = raw[contentStart..<contentEnd]
        let rawChildren = children.map { $0.xmlString(options: []) }.joined()
        guard content.hasPrefix(rawChildren) else {
            return ""
        }
        return String(content.dropFirst(rawChildren.count))
    }

    private static func isStructuredContent(_ kind: XMLNode.Kind) -> Bool {
        switch kind {
        case .element, .comment, .processingInstruction:
            return true
        default:
            return false
        }
    }

    private static func isTextContent(_ kind: XMLNode.Kind) -> Bool {
        switch kind {
        case .text:
            return true
        default:
            return false
        }
    }
}

/// 解析期同时统计元素嵌套深度：超过上限就主动 abort。
///
/// 守卫之所以放在解析阶段而不是渲染前，是因为深层文档一旦被构造成 `XMLNode` 树，
/// 连释放都是递归的——实测 2000 层文档即使不渲染，`dealloc` 也会栈溢出崩溃。
/// 用 SAX 回调计数（由 C 层解析器驱动，本身不递归）可以从根上避免构造深树。
private final class XMLSyntaxErrorDelegate: NSObject, XMLParserDelegate {
    var error: Error?
    private(set) var exceededDepthLimit = false

    private let depthLimit: Int
    private var currentDepth = 0

    init(depthLimit: Int) {
        self.depthLimit = depthLimit
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentDepth += 1
        guard currentDepth > depthLimit else { return }
        exceededDepthLimit = true
        parser.abortParsing()
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        currentDepth -= 1
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError
    }
}
