import Foundation
import Yams

public enum YAMLPrettifier {
    public enum ValidationError: Error, LocalizedError, Equatable, Sendable {
        case invalidSyntax(FormatDiagnostic)
        case unsupportedCommentPreservingSort(FormatDiagnostic)
        case unsupportedAnchorPreservingSort(FormatDiagnostic)

        public var errorDescription: String? {
            switch self {
            case .invalidSyntax(let diagnostic):
                return diagnostic.workspaceMessage
            case .unsupportedCommentPreservingSort(let diagnostic):
                return diagnostic.workspaceMessage
            case .unsupportedAnchorPreservingSort(let diagnostic):
                return diagnostic.workspaceMessage
            }
        }

        public var diagnostic: FormatDiagnostic {
            switch self {
            case .invalidSyntax(let diagnostic):
                return diagnostic
            case .unsupportedCommentPreservingSort(let diagnostic):
                return diagnostic
            case .unsupportedAnchorPreservingSort(let diagnostic):
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

    public struct Options: Equatable, Sendable {
        public var indent: Int
        public var sortKeys: Bool

        public init(indent: Int = 2, sortKeys: Bool = false) {
            self.indent = indent
            self.sortKeys = sortKeys
        }
    }

    public static func formatValidated(_ input: String) throws -> String {
        try validate(input)
        return format(input)
    }

    public static func formatValidated(_ input: String, options: Options) throws -> String {
        try validate(input)
        return try format(input, options: options)
    }

    public static func format(_ input: String, options: Options) throws -> String {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        if options.sortKeys, containsStructuralComment(in: input) {
            throw ValidationError.unsupportedCommentPreservingSort(
                FormatDiagnostic(
                    formatName: "YAML",
                    message: "当前无法在保留注释的同时对键排序",
                    suggestion: "关闭键排序后重试。"
                )
            )
        }

        if options.sortKeys, containsAnchorOrAlias(in: input) {
            throw ValidationError.unsupportedAnchorPreservingSort(
                FormatDiagnostic(
                    formatName: "YAML",
                    message: "当前无法在保留锚点与别名的同时对键排序",
                    suggestion: "关闭键排序后重试。"
                )
            )
        }

        if !options.sortKeys, containsAnchorOrAlias(in: input) {
            // 序列化器在 compose→dump 之间会解析锚点、把别名展开成字面值：
            // `a: &x 1` + `b: *x` 会变成 `a: 1` + `b: 1`，之后锚点改动时别名
            // 不再跟随，输出与输入语义不同。带锚点/别名的输入改走逐行路径，
            // 原样保留这些记号（与带注释输入同一处理方式）。
            return formatPreservingComments(input, indentWidth: options.indent)
        }

        if !options.sortKeys, containsStructuralComment(in: input) {
            // 序列化器不保留注释，带注释的输入只能走逐行路径；但逐行路径同样要兑现
            // indent 选项，否则用户改了缩进宽度却看不到任何变化。
            return formatPreservingComments(input, indentWidth: options.indent)
        }

        let nodes = Array(try compose_all(yaml: input))
        var dumped = try serialize(nodes: nodes, indent: options.indent, sortKeys: options.sortKeys)
        while dumped.hasSuffix("\n") {
            dumped.removeLast()
        }
        return dumped
    }

    public static func format(_ input: String) -> String {
        formatPreservingComments(input, indentWidth: nil)
    }

    /// 逐行格式化（保留注释）。`indentWidth` 为 nil 时保持原有缩进不变。
    private static func formatPreservingComments(_ input: String, indentWidth: Int?) -> String {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var formattedLines: [String] = []
        var previousWasBlank = false
        var activeBlockScalar: BlockScalarState?

        for line in lines {
            if var blockScalar = activeBlockScalar {
                if blockScalar.contains(line) {
                    formattedLines.append(line)
                    previousWasBlank = false
                    activeBlockScalar = blockScalar
                    continue
                }

                activeBlockScalar = nil
            }

            let formattedLine = formatLine(expandingIndentationTabs(in: line))
            appendOutsideBlockLine(formattedLine, to: &formattedLines, previousWasBlank: &previousWasBlank)

            if let header = blockScalarHeader(in: formattedLine) {
                activeBlockScalar = BlockScalarState(header: header)
            }
        }

        if activeBlockScalar == nil {
            while formattedLines.last == "" {
                formattedLines.removeLast()
            }
        }

        guard let indentWidth else {
            return formattedLines.joined(separator: "\n")
        }
        return reindented(formattedLines, indentWidth: indentWidth).joined(separator: "\n")
    }

    /// 只展开行首缩进里的制表符，保留标量内容中的字面 tab。
    /// 此前是整行替换，`key: "a<TAB>b"` 会被悄悄改成 `key: "a  b"`（数据损坏）。
    private static func expandingIndentationTabs(in line: String) -> String {
        let indentation = line.prefix { $0 == "\t" || $0 == " " }
        guard indentation.contains("\t") else { return line }

        return String(indentation).replacingOccurrences(of: "\t", with: "  ")
            + String(line.dropFirst(indentation.count))
    }

    /// 逐行路径不解析结构，但要兑现 indent 选项：把输入里最小的正缩进视为一级，
    /// 按层级折算成请求的宽度。块标量内容行与空行不参与。
    ///
    /// 仅在缩进一致（所有正缩进都是该单位的整数倍）时重排——否则可能把不同层级
    /// 压平，宁可不改，保持与旧行为一致。
    private static func reindented(_ lines: [String], indentWidth: Int) -> [String] {
        guard indentWidth > 0 else { return lines }

        let unit = detectedIndentUnit(in: lines)
        guard unit > 0, unit != indentWidth, hasConsistentIndentation(lines, unit: unit) else {
            return lines
        }

        var result: [String] = []
        var activeBlockScalar: BlockScalarState?

        for line in lines {
            if var blockScalar = activeBlockScalar {
                let stillInside = blockScalar.contains(line)
                result.append(line)
                activeBlockScalar = stillInside ? blockScalar : nil
                continue
            }

            let leading = line.prefix { $0 == " " }.count
            if !line.isEmpty {
                let level = leading / unit
                result.append(String(repeating: " ", count: level * indentWidth) + line.dropFirst(leading))
            } else {
                result.append(line)
            }

            if let header = blockScalarHeader(in: line) {
                activeBlockScalar = BlockScalarState(header: header)
            }
        }

        return result
    }

    private static func detectedIndentUnit(in lines: [String]) -> Int {
        var unit = 0
        for line in lines {
            let leading = line.prefix { $0 == " " }.count
            guard leading > 0, !line.dropFirst(leading).isEmpty else { continue }
            unit = unit == 0 ? leading : min(unit, leading)
        }
        return unit
    }

    private static func hasConsistentIndentation(_ lines: [String], unit: Int) -> Bool {
        lines.allSatisfy { line in
            let leading = line.prefix { $0 == " " }.count
            return leading == 0 || leading % unit == 0
        }
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

    private struct BlockScalarHeader {
        let parentIndent: Int
        let explicitContentIndent: Int?
    }

    private struct BlockScalarIndicator {
        let explicitIndent: Int?
    }

    private struct BlockScalarState {
        let parentIndent: Int
        var contentIndent: Int?

        init(header: BlockScalarHeader) {
            parentIndent = header.parentIndent
            contentIndent = header.explicitContentIndent.map { header.parentIndent + $0 }
        }

        mutating func contains(_ line: String) -> Bool {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                return true
            }

            let indent = YAMLPrettifier.leadingIndentWidth(line)
            if let contentIndent {
                return indent >= contentIndent
            }

            guard indent > parentIndent else {
                return false
            }
            contentIndent = indent
            return true
        }
    }

    private static func blockScalarHeader(in line: String) -> BlockScalarHeader? {
        let parentIndent = leadingIndentWidth(line)
        var candidate = line.dropFirst(min(parentIndent, line.count))[...]
        candidate = candidate.drop { $0 == " " }
        var mappingIndent = parentIndent

        if candidate.hasPrefix("- ") {
            candidate = candidate.dropFirst(2).drop { $0 == " " }
            mappingIndent += 2
        } else if candidate.hasPrefix("? ") || candidate.hasPrefix(": ") {
            candidate = candidate.dropFirst(2).drop { $0 == " " }
        }

        if let indicator = parseBlockScalarIndicator(candidate) {
            return BlockScalarHeader(
                parentIndent: parentIndent,
                explicitContentIndent: indicator.explicitIndent
            )
        }

        let body = String(candidate)
        guard let delimiterIndex = firstMappingDelimiterIndex(in: body) else {
            return nil
        }

        let value = body[body.index(after: delimiterIndex)...].drop { $0 == " " }
        guard let indicator = parseBlockScalarIndicator(value) else {
            return nil
        }
        return BlockScalarHeader(
            parentIndent: mappingIndent,
            explicitContentIndent: indicator.explicitIndent
        )
    }

    private static func parseBlockScalarIndicator(_ candidate: Substring) -> BlockScalarIndicator? {
        guard let marker = candidate.first, marker == "|" || marker == ">" else {
            return nil
        }

        var index = candidate.index(after: candidate.startIndex)
        var explicitIndent: Int?
        var sawChompingIndicator = false

        while index < candidate.endIndex {
            let character = candidate[index]
            if character == "+" || character == "-" {
                guard !sawChompingIndicator else { return nil }
                sawChompingIndicator = true
            } else if let digit = character.wholeNumberValue, (1...9).contains(digit) {
                guard explicitIndent == nil else { return nil }
                explicitIndent = digit
            } else {
                break
            }
            index = candidate.index(after: index)
        }

        let remainder = candidate[index...]
        guard remainder.isEmpty || remainder.first == " " || remainder.first == "\t" else {
            return nil
        }

        let trimmedRemainder = remainder.drop { $0 == " " || $0 == "\t" }
        guard trimmedRemainder.isEmpty || trimmedRemainder.first == "#" else {
            return nil
        }
        return BlockScalarIndicator(explicitIndent: explicitIndent)
    }

    /// 输入里是否出现锚点定义（`&name`）或别名引用（`*name`）。
    /// 序列化器路径会把它们解析展开，凡命中就应改走逐行保留路径。
    private static func containsAnchorOrAlias(in input: String) -> Bool {
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var activeBlockScalar: BlockScalarState?

        for line in lines {
            if var blockScalar = activeBlockScalar {
                if blockScalar.contains(line) {
                    activeBlockScalar = blockScalar
                    continue
                }
                activeBlockScalar = nil
            }

            if lineContainsAnchorOrAliasToken(line) {
                return true
            }
            if let header = blockScalarHeader(in: line) {
                activeBlockScalar = BlockScalarState(header: header)
            }
        }

        return false
    }

    /// 只有 token 起始位置的 `&`/`*` 才可能是锚点/别名（前一字符是行首、空白
    /// 或 flow 分隔符）。`a*b`、`echo *`、`"&x"`、注释里的 `*x` 都不算，避免
    /// 把普通标量误判成锚点而白白放弃序列化路径。
    private static func lineContainsAnchorOrAliasToken(_ line: String) -> Bool {
        var inSingleQuote = false
        var inDoubleQuote = false
        var previous: Character?

        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]

            if inSingleQuote {
                if character == "'" {
                    // 单引号标量里 '' 是转义的单引号，不是引号结束。
                    let next = line.index(after: index)
                    if next < line.endIndex, line[next] == "'" {
                        index = next
                    } else {
                        inSingleQuote = false
                    }
                }
            } else if inDoubleQuote {
                if character == "\\" {
                    index = line.index(after: index)
                } else if character == "\"" {
                    inDoubleQuote = false
                }
            } else if character == "'" {
                inSingleQuote = true
            } else if character == "\"" {
                inDoubleQuote = true
            } else if character == "#", previous == nil || previous == " " || previous == "\t" {
                // 行内注释从此开始，注释内容里的 &/* 不算。
                return false
            } else if character == "&" || character == "*" {
                let isTokenStart = previous == nil || previous == " " || previous == "\t"
                    || previous == "[" || previous == "{" || previous == ","
                let next = line.index(after: index)
                if isTokenStart, next < line.endIndex, isAnchorNameCharacter(line[next]) {
                    return true
                }
            }

            previous = character
            index = line.index(after: index)
        }
        return false
    }

    private static func isAnchorNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }

    private static func containsStructuralComment(in input: String) -> Bool {
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var activeBlockScalar: BlockScalarState?
        var quoteState = CommentQuoteState()

        for line in lines {
            if var blockScalar = activeBlockScalar {
                if blockScalar.contains(line) {
                    activeBlockScalar = blockScalar
                    continue
                }
                activeBlockScalar = nil
            }

            if quoteState.containsCommentToken(in: line) {
                return true
            }
            if !quoteState.isInsideQuotedScalar,
               let header = blockScalarHeader(in: line) {
                activeBlockScalar = BlockScalarState(header: header)
            }
        }

        return false
    }

    private struct CommentQuoteState {
        var inSingleQuote = false
        var inDoubleQuote = false

        var isInsideQuotedScalar: Bool {
            inSingleQuote || inDoubleQuote
        }

        mutating func containsCommentToken(in line: String) -> Bool {
            var index = line.startIndex
            // A backslash at the end of a double-quoted physical line escapes
            // the line break, not the first character of the following line.
            var escaped = false

            while index < line.endIndex {
                let character = line[index]
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
                        let next = line.index(after: index)
                        if next < line.endIndex, line[next] == "'" {
                            index = next
                        } else {
                            inSingleQuote = false
                        }
                    }
                } else if character == "\"", canOpenQuotedScalar(in: line, at: index) {
                    inDoubleQuote = true
                } else if character == "'", canOpenQuotedScalar(in: line, at: index) {
                    inSingleQuote = true
                } else if character == "#" {
                    if index == line.startIndex {
                        return true
                    }
                    let previous = line[line.index(before: index)]
                    if previous == " " || previous == "\t" {
                        return true
                    }
                }

                index = line.index(after: index)
            }

            return false
        }

        private func canOpenQuotedScalar(in line: String, at index: String.Index) -> Bool {
            let prefix = line[..<index]
            guard let previousIndex = prefix.lastIndex(where: { !$0.isWhitespace }) else {
                return true
            }

            // Quotes inside a plain scalar (for example `it's` or
            // `say "hello"`) do not open quoted-scalar state. YAML quoted
            // scalars begin at the start of a scalar value/key or after a
            // flow/sequence indicator.
            return ":,-?[{".contains(line[previousIndex])
        }
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
            let readerSuggestion = suggestion(forReaderMessage: yamlReaderMessage(problem))
            if let offset,
               let index = yaml.index(yaml.startIndex, offsetBy: offset, limitedBy: yaml.endIndex) {
                return FormatDiagnostic(
                    formatName: "YAML",
                    message: yamlReaderMessage(problem),
                    input: yaml,
                    index: index,
                    suggestion: readerSuggestion
                )
            }

            return FormatDiagnostic(
                formatName: "YAML",
                message: yamlReaderMessage(problem),
                suggestion: readerSuggestion
            )

        case let .scanner(context, problem, mark, yaml),
             let .parser(context, problem, mark, yaml),
             let .composer(context, problem, mark, yaml):
            let syntaxMessage = yamlSyntaxMessage(problem, context: context?.text, yaml: yaml, mark: mark)
            return FormatDiagnostic(
                formatName: "YAML",
                message: syntaxMessage,
                input: yaml,
                line: mark.line,
                column: mark.column,
                suggestion: suggestion(forSyntaxMessage: syntaxMessage)
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

    /// 把已确定的中文语法错误文案映射到贴切的修复建议。
    /// 早先所有语法错误共用通用的「检查缩进…」建议，对锚点、引号、文档分隔符类
    /// 错误会指向无关方向；这里按文案给出针对性建议，未覆盖时退回通用提示。
    private static func suggestion(forSyntaxMessage message: String) -> String {
        switch message {
        case "缩进层级不一致", "缩进必须使用空格，不能使用制表符":
            return "同一层级的键使用相同数量的空格缩进，并删除行首的制表符。"
        case "键后缺少冒号":
            return "在键名后补上冒号与一个空格，例如 `key: value`。"
        case "流程列表缺少逗号或右方括号":
            return "在列表元素之间补上逗号，并补上结尾的 ]。"
        case "流程映射缺少逗号或右花括号":
            return "在映射条目之间补上逗号，并补上结尾的 }。"
        case "引号字符串没有闭合":
            return "补上与被引用内容成对的引号。"
        case "引用了未定义的锚点别名":
            return "先用 &名称 定义锚点，再在同级或后续节点用 *名称 引用。"
        case "使用了未定义的标签句柄":
            return "先在 %TAG 指令中声明该标签句柄，或改用完整标签。"
        case "只允许包含一个 YAML 文档":
            return "删除多余的 --- 分隔符，只保留一个文档。"
        case "文档分隔符出现在不允许的位置":
            return "确认 --- 只出现在文档开头或两个文档之间。"
        case "YAML 版本指令重复":
            return "每个文档只保留一条 %YAML 指令。"
        case "YAML 标签指令重复":
            return "合并重复的 %TAG 指令，或改用不同的标签句柄。"
        case "列表项缺少短横线标记":
            return "为每个列表项补上开头的短横线与一个空格。"
        case "双引号字符串中包含不支持的转义字符":
            return "改用 YAML 支持的转义序列，或把内容放进单引号字符串。"
        case "Unicode 转义后缺少十六进制数字":
            return "在 \\u 或 \\U 后补足对应的十六进制数字。"
        default:
            return genericYAMLSuggestion
        }
    }

    /// 读取阶段的失败都发生在字符解码层面，通用缩进建议在这里不成立。
    private static func suggestion(forReaderMessage message: String) -> String {
        switch message {
        case "YAML 文本包含无效的 UTF-8 字节",
             "YAML 文本包含孤立的低位代理字符",
             "YAML 文本中的 Unicode 代理对不完整",
             "YAML 文本包含无法读取的字符":
            return "确认输入是 UTF-8 兼容文本，且字符串中没有残缺的代理字符。"
        default:
            return genericYAMLSuggestion
        }
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
