import Foundation
import Yams

public enum YAMLPrettifier {
    public enum ValidationError: Error, LocalizedError, Equatable, Sendable {
        case invalidSyntax(FormatDiagnostic)

        public var errorDescription: String? {
            switch self {
            case .invalidSyntax(let diagnostic):
                return diagnostic.workspaceMessage
            }
        }

        public var diagnostic: FormatDiagnostic {
            switch self {
            case .invalidSyntax(let diagnostic):
                return diagnostic
            }
        }
    }

    public static func validate(_ input: String) throws {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        do {
            _ = try Yams.load(yaml: input)
        } catch let yamlError as YamlError {
            throw ValidationError.invalidSyntax(diagnostic(from: yamlError, input: input))
        } catch {
            throw ValidationError.invalidSyntax(
                FormatDiagnostic(
                    formatName: "YAML",
                    message: "YAML 语法错误",
                    suggestion: genericYAMLSuggestion
                )
            )
        }
    }

    public static func formatValidated(_ input: String) throws -> String {
        try validate(input)
        return format(input)
    }

    public static func format(_ input: String) -> String {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var formattedLines: [String] = []
        var previousWasBlank = false
        var activeBlockScalarParentIndent: Int?

        for line in lines {
            if let parentIndent = activeBlockScalarParentIndent {
                if line.trimmingCharacters(in: .whitespaces).isEmpty || leadingIndentWidth(line) > parentIndent {
                    formattedLines.append(line)
                    previousWasBlank = false
                    continue
                }

                activeBlockScalarParentIndent = nil
            }

            let formattedLine = formatLine(line.replacingOccurrences(of: "\t", with: "  "))
            appendOutsideBlockLine(formattedLine, to: &formattedLines, previousWasBlank: &previousWasBlank)

            if let parentIndent = blockScalarParentIndent(in: formattedLine) {
                activeBlockScalarParentIndent = parentIndent
            }
        }

        while formattedLines.last == "" {
            formattedLines.removeLast()
        }

        return formattedLines.joined(separator: "\n")
    }

    private static func formatLine(_ line: String) -> String {
        let trimmedRight = trimTrailingWhitespace(line)
        guard !trimmedRight.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ""
        }

        let leadingSpaces = String(trimmedRight.prefix { $0 == " " })
        let body = String(trimmedRight.dropFirst(leadingSpaces.count))
        return leadingSpaces + normalizeFirstMappingDelimiter(in: body)
    }

    private static func normalizeFirstMappingDelimiter(in body: String) -> String {
        guard !body.trimmingCharacters(in: .whitespaces).hasPrefix("#") else {
            return body
        }

        guard let delimiterIndex = firstMappingDelimiterIndex(in: body) else {
            return body
        }

        return normalizedMappingLine(body, delimiterIndex: delimiterIndex)
    }

    private static func isMappingDelimiter(in body: String, at index: String.Index) -> Bool {
        let afterColon = body.index(after: index)
        return afterColon == body.endIndex || body[afterColon] == " "
    }

    private static func normalizedMappingLine(_ body: String, delimiterIndex: String.Index) -> String {
        let rawKey = String(body[..<delimiterIndex]).trimmingCharacters(in: .whitespaces)
        guard !rawKey.isEmpty else {
            return body
        }

        var valueStart = body.index(after: delimiterIndex)
        while valueStart < body.endIndex, body[valueStart] == " " {
            valueStart = body.index(after: valueStart)
        }

        guard valueStart < body.endIndex else {
            return "\(rawKey):"
        }

        return "\(rawKey): \(body[valueStart...])"
    }

    private static func trimTrailingWhitespace(_ line: String) -> String {
        var end = line.endIndex
        while end > line.startIndex {
            let previous = line.index(before: end)
            guard line[previous] == " " else {
                break
            }
            end = previous
        }
        return String(line[..<end])
    }

    private static func appendOutsideBlockLine(_ line: String, to result: inout [String], previousWasBlank: inout Bool) {
        if line.isEmpty {
            if !result.isEmpty, !previousWasBlank {
                result.append("")
            }
            previousWasBlank = true
        } else {
            result.append(line)
            previousWasBlank = false
        }
    }

    private static func blockScalarParentIndent(in line: String) -> Int? {
        let parentIndent = leadingIndentWidth(line)
        let body = String(line.dropFirst(parentIndent))

        guard let delimiterIndex = firstMappingDelimiterIndex(in: body) else {
            return nil
        }

        var valueStart = body.index(after: delimiterIndex)
        while valueStart < body.endIndex, body[valueStart] == " " {
            valueStart = body.index(after: valueStart)
        }

        guard valueStart < body.endIndex else {
            return nil
        }

        let marker = body[valueStart]
        return marker == "|" || marker == ">" ? parentIndent : nil
    }

    private static func firstMappingDelimiterIndex(in body: String) -> String.Index? {
        var index = body.startIndex
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false

        while index < body.endIndex {
            let character = body[index]

            if inDoubleQuote {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inDoubleQuote = false
                }
            } else if inSingleQuote {
                if character == "'" {
                    let nextIndex = body.index(after: index)
                    if nextIndex < body.endIndex, body[nextIndex] == "'" {
                        index = nextIndex
                    } else {
                        inSingleQuote = false
                    }
                }
            } else if character == "\"" {
                inDoubleQuote = true
            } else if character == "'" {
                inSingleQuote = true
            } else if character == ":", isMappingDelimiter(in: body, at: index) {
                return index
            }

            index = body.index(after: index)
        }

        return nil
    }

    private static func leadingIndentWidth(_ line: String) -> Int {
        var width = 0

        for character in line {
            if character == " " {
                width += 1
            } else if character == "\t" {
                width += 2
            } else {
                break
            }
        }

        return width
    }

    private static func diagnostic(from error: YamlError, input: String) -> FormatDiagnostic {
        switch error {
        case let .reader(problem, offset, _, yaml):
            if let offset,
               let index = yaml.index(yaml.startIndex, offsetBy: offset, limitedBy: yaml.endIndex) {
                return FormatDiagnostic(
                    formatName: "YAML",
                    message: yamlReaderMessage(problem),
                    input: yaml,
                    index: index,
                    suggestion: genericYAMLSuggestion
                )
            }

            return FormatDiagnostic(
                formatName: "YAML",
                message: yamlReaderMessage(problem),
                suggestion: genericYAMLSuggestion
            )

        case let .scanner(context, problem, mark, yaml),
             let .parser(context, problem, mark, yaml),
             let .composer(context, problem, mark, yaml):
            return FormatDiagnostic(
                formatName: "YAML",
                message: yamlSyntaxMessage(problem, context: context?.text, yaml: yaml, mark: mark),
                input: yaml,
                line: mark.line,
                column: mark.column,
                suggestion: genericYAMLSuggestion
            )

        case let .duplicatedKeysInMapping(duplicates, yaml):
            if let mark = duplicates.values.lazy.flatMap({ $0.compactMap(\.mark) }).first {
                return FormatDiagnostic(
                    formatName: "YAML",
                    message: "映射中存在重复键",
                    input: yaml,
                    line: mark.line,
                    column: mark.column,
                    suggestion: "删除重复键，或把同名配置合并到同一个键下。"
                )
            }

            return FormatDiagnostic(
                formatName: "YAML",
                message: "映射中存在重复键",
                suggestion: "删除重复键，或把同名配置合并到同一个键下。"
            )

        case .no:
            return FormatDiagnostic(
                formatName: "YAML",
                message: "无效的 YAML",
                suggestion: genericYAMLSuggestion
            )
        case .memory:
            return FormatDiagnostic(
                formatName: "YAML",
                message: "解析 YAML 时内存不足",
                suggestion: "缩小输入后重试。"
            )
        case let .writer(problem),
             let .emitter(problem),
             let .representer(problem):
            return FormatDiagnostic(
                formatName: "YAML",
                message: yamlOutputMessage(problem),
                suggestion: genericYAMLSuggestion
            )
        case .dataCouldNotBeDecoded:
            return FormatDiagnostic(
                formatName: "YAML",
                message: "YAML 文本编码无法识别",
                suggestion: "确认输入是 UTF-8 兼容文本。"
            )
        }
    }

    private static func yamlReaderMessage(_ problem: String) -> String {
        let normalized = normalizedYAMLProblem(problem)

        switch normalized {
        case "invalid trailing UTF-8 octet":
            return "YAML 文本包含无效的 UTF-8 字节"
        case "unexpected low surrogate area":
            return "YAML 文本包含孤立的低位代理字符"
        case "expected low surrogate area":
            return "YAML 文本中的 Unicode 代理对不完整"
        default:
            return "YAML 文本包含无法读取的字符"
        }
    }

    private static func yamlSyntaxMessage(_ problem: String, context: String?, yaml: String, mark: Mark) -> String {
        let normalized = normalizedYAMLProblem(problem)
        let normalizedContext = normalizedYAMLProblem(context ?? "")

        switch normalized {
        case "could not find expected ':'":
            return "键后缺少冒号"
        case "did not find expected ',' or ']'":
            return "流程列表缺少逗号或右方括号"
        case "did not find expected ',' or '}'":
            return "流程映射缺少逗号或右花括号"
        case "did not find expected key":
            if hasIndentationMismatch(around: mark, in: yaml) {
                return "缩进层级不一致"
            }
            return "映射项缺少键"
        case "did not find expected <document start>":
            if isLikelyMissingMappingColon(around: mark, in: yaml) {
                return "键后缺少冒号"
            }
            return "YAML 顶层文档结构不完整"
        case "did not find expected '-' indicator":
            return "列表项缺少短横线标记"
        case "did not find expected node content":
            return "缺少节点内容"
        case "mapping values are not allowed in this context":
            if isLikelyMissingMappingColon(around: mark, in: yaml) {
                return "键后缺少冒号"
            }
            return "冒号出现在不允许的位置"
        case "found a tab character where an indentation space is expected":
            return "缩进必须使用空格，不能使用制表符"
        case "found character that cannot start any token":
            if yamlScalar(at: mark, in: yaml) == "\t" {
                return "缩进必须使用空格，不能使用制表符"
            }
            return "当前位置的字符不能开始 YAML 节点"
        case "found unexpected document indicator":
            return "文档分隔符出现在不允许的位置"
        case "found unexpected end of stream":
            if normalizedContext.contains("quoted scalar") {
                return "引号字符串没有闭合"
            }
            return "YAML 内容在结构闭合前结束"
        case "found unknown escape character":
            return "双引号字符串中包含不支持的转义字符"
        case "did not find expected hexdecimal number":
            return "Unicode 转义后缺少十六进制数字"
        case "found unexpected ':'":
            return "冒号出现在不允许的位置"
        case "found undefined tag handle":
            return "使用了未定义的标签句柄"
        case "found undefined alias":
            return "引用了未定义的锚点别名"
        case "but found another document":
            return "只允许包含一个 YAML 文档"
        case "found duplicate %YAML directive":
            return "YAML 版本指令重复"
        case "found duplicate %TAG directive":
            return "YAML 标签指令重复"
        default:
            return fallbackYAMLSyntaxMessage(for: normalized)
        }
    }

    private static func fallbackYAMLSyntaxMessage(for normalized: String) -> String {
        if normalized.contains("quoted scalar") {
            return "引号字符串没有闭合"
        }
        if normalized.contains("directive") {
            return "YAML 指令写法不完整"
        }
        if normalized.contains("tag") {
            return "YAML 标签写法不完整"
        }
        if normalized.contains("escape") {
            return "字符串转义写法不正确"
        }
        if normalized.contains("expected") {
            return "YAML 结构缺少必要的分隔符"
        }
        if normalized.contains("unexpected") {
            return "YAML 结构中出现了不该出现的内容"
        }
        return "YAML 语法错误"
    }

    private static func yamlOutputMessage(_: String) -> String {
        return "YAML 输出生成失败"
    }

    private static func normalizedYAMLProblem(_ problem: String) -> String {
        problem.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasIndentationMismatch(around mark: Mark, in yaml: String) -> Bool {
        let lines = yaml.components(separatedBy: .newlines)
        guard lines.indices.contains(mark.line - 1),
              let previous = previousSignificantLine(before: mark.line, in: lines) else {
            return false
        }

        let currentLine = lines[mark.line - 1]
        let currentIndent = leadingIndentWidth(currentLine)
        let previousIndent = leadingIndentWidth(previous.text)
        let currentTrimmed = currentLine.trimmingCharacters(in: .whitespaces)

        guard !currentTrimmed.isEmpty, !currentTrimmed.hasPrefix("#") else {
            return false
        }

        return currentIndent > 0
            && previousIndent > currentIndent
            && (firstMappingDelimiterIndex(in: currentTrimmed) != nil || currentTrimmed.hasPrefix("- "))
    }

    private static func isLikelyMissingMappingColon(around mark: Mark, in yaml: String) -> Bool {
        let lines = yaml.components(separatedBy: .newlines)
        guard let previous = previousSignificantLine(before: mark.line, in: lines) else {
            return false
        }

        let previousTrimmed = previous.text.trimmingCharacters(in: .whitespaces)
        guard !previousTrimmed.isEmpty,
              !previousTrimmed.hasPrefix("#"),
              !previousTrimmed.hasPrefix("- "),
              firstMappingDelimiterIndex(in: previousTrimmed) == nil else {
            return false
        }

        guard lines.indices.contains(mark.line - 1) else {
            return false
        }

        let currentLine = lines[mark.line - 1]
        return leadingIndentWidth(currentLine) > leadingIndentWidth(previous.text)
            && firstMappingDelimiterIndex(in: currentLine.trimmingCharacters(in: .whitespaces)) != nil
    }

    private static func previousSignificantLine(before line: Int, in lines: [String]) -> (number: Int, text: String)? {
        guard line > 1 else { return nil }

        for index in stride(from: line - 2, through: 0, by: -1) {
            let text = lines[index]
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (index + 1, text)
            }
        }

        return nil
    }

    private static func yamlScalar(at mark: Mark, in yaml: String) -> Unicode.Scalar? {
        let lines = yaml.components(separatedBy: .newlines)
        guard lines.indices.contains(mark.line - 1) else { return nil }

        let lineScalars = Array(lines[mark.line - 1].unicodeScalars)
        let scalarOffset = max(0, mark.column - 1)
        guard lineScalars.indices.contains(scalarOffset) else { return nil }
        return lineScalars[scalarOffset]
    }

    private static let genericYAMLSuggestion = "检查缩进、冒号后的空格、列表括号和引号是否闭合。"
}
