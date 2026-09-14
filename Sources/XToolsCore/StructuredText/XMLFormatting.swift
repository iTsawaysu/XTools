import Foundation

public enum XMLFormatting {
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

    public static func format(_ input: String, indentWidth: Int = 2) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let hadDeclaration = trimmed.hasPrefix("<?xml")

        do {
            if let syntaxDiagnostic = syntaxDiagnostic(for: trimmed) {
                throw FormattingError.invalidXML(syntaxDiagnostic)
            }

            let document = try XMLDocument(xmlString: trimmed, options: [.nodePreserveCDATA])
            guard let root = document.rootElement() else {
                throw FormattingError.invalidXML(
                    FormatDiagnostic(formatName: "XML", message: "XML 文档缺少根节点")
                )
            }

            var outputParts: [String] = []
            if hadDeclaration, let declaration = xmlDeclaration(in: trimmed) {
                outputParts.append(declaration)
            }
            outputParts.append(render(root, level: 0, indentWidth: max(0, indentWidth)))
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

    private static func syntaxDiagnostic(for input: String) -> FormatDiagnostic? {
        if input.localizedCaseInsensitiveContains("<!DOCTYPE") {
            return FormatDiagnostic(
                formatName: "XML",
                message: "不支持 DOCTYPE 声明",
                suggestion: "移除 DOCTYPE 或外部实体声明后再格式化；工具不会展开外部实体。"
            )
        }

        guard let data = input.data(using: .utf8) else {
            return FormatDiagnostic(
                formatName: "XML",
                message: "无法读取 XML 文本",
                suggestion: "确认输入是 UTF-8 兼容文本。"
            )
        }

        let delegate = XMLSyntaxErrorDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard !parser.parse() else {
            return nil
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

    private static func xmlMessage(from error: Error?) -> String {
        guard let error else { return "XML 语法错误" }

        let nsError = error as NSError
        guard nsError.domain == "NSXMLParserErrorDomain" else {
            return "XML 语法错误"
        }

        switch nsError.code {
        case 5:
            return "XML 文档没有正确闭合，或存在多个根节点"
        case 26:
            return "引用了未定义的实体，或 & 没有正确转义"
        case 42:
            return "同一个标签上有重复属性名"
        case 39:
            return "属性值必须使用引号"
        case 68:
            return "文本中的 & 没有转义，或实体引用不完整"
        case 76:
            return "开始标签和结束标签不匹配"
        default:
            return "XML 语法错误"
        }
    }

    private static func xmlDeclaration(in input: String) -> String? {
        guard input.hasPrefix("<?xml"), let end = input.range(of: "?>") else { return nil }
        return String(input[..<end.upperBound])
    }

    private static func render(_ node: XMLNode, level: Int, indentWidth: Int) -> String {
        let indent = String(repeating: " ", count: level * indentWidth)
        guard node.kind == .element else {
            return indent + node.xmlString(options: [])
        }

        let children = node.children ?? []
        guard !children.isEmpty else {
            return indent + node.xmlString(options: [])
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
            return indent + node.xmlString(options: [])
        }

        if !hasStructuredChild {
            return indent + node.xmlString(options: [])
        }

        let compact = node.xmlString(options: [])
        guard let openingEnd = compact.firstIndex(of: ">"), let name = node.name else {
            return indent + compact
        }

        let opening = String(compact[...openingEnd])
        let renderedChildren = significantChildren.map {
            render($0, level: level + 1, indentWidth: indentWidth)
        }.joined(separator: "\n")

        return "\(indent)\(opening)\n\(renderedChildren)\n\(indent)</\(name)>"
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

private final class XMLSyntaxErrorDelegate: NSObject, XMLParserDelegate {
    var error: Error?

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError
    }
}
