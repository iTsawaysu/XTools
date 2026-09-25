import Foundation

public struct FormatDiagnostic: Equatable, Sendable, LocalizedError {
    public let formatName: String
    public let message: String
    public let line: Int?
    public let column: Int?
    public let excerpt: String?
    public let suggestion: String?

    public init(
        formatName: String,
        message: String,
        line: Int? = nil,
        column: Int? = nil,
        excerpt: String? = nil,
        suggestion: String? = nil
    ) {
        self.formatName = formatName
        self.message = message
        self.line = line
        self.column = column
        self.excerpt = excerpt
        self.suggestion = suggestion
    }

    public var errorDescription: String? {
        displayMessage
    }

    /// 面向用户的主诊断文案：只描述实际发生的错误或边界。
    /// 位置保留在 `line`、`column` 和 `excerpt` 字段中，不与主文案混排。
    public var displayMessage: String {
        message
    }

    /// 面向工作区诊断卡片的紧凑文案：只展示事实型主错误。
    /// 位置与详细修复建议不在默认工作区诊断中拼接，避免底层信息或伪动态文案干扰主错误。
    public var workspaceMessage: String {
        displayMessage
    }
}

extension FormatDiagnostic {
    init(
        formatName: String,
        message: String,
        input: String,
        index: String.Index,
        suggestion: String? = nil
    ) {
        let position = Self.position(in: input, at: index)
        self.init(
            formatName: formatName,
            message: message,
            line: position.line,
            column: position.column,
            excerpt: Self.lineExcerpt(in: input, line: position.line, column: position.column),
            suggestion: suggestion
        )
    }

    init(
        formatName: String,
        message: String,
        input: String,
        line: Int,
        column: Int,
        suggestion: String? = nil
    ) {
        self.init(
            formatName: formatName,
            message: message,
            line: line,
            column: column,
            excerpt: Self.lineExcerpt(in: input, line: line, column: column),
            suggestion: suggestion
        )
    }

    static func position(in text: String, at index: String.Index) -> (line: Int, column: Int) {
        var line = 1
        var column = 1
        var cursor = text.startIndex
        let boundedIndex = min(index, text.endIndex)

        while cursor < boundedIndex {
            let character = text[cursor]

            if character.isNewline {
                line += 1
                column = 1
            } else {
                column += 1
            }

            cursor = text.index(after: cursor)
        }

        return (line, column)
    }

    static func lineExcerpt(in text: String, line: Int, column: Int, maxCharacters: Int = 90) -> String? {
        guard line > 0 else { return nil }

        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let lineIndex: Int
        if lines.indices.contains(line - 1) {
            lineIndex = line - 1
        } else if line > lines.count, let fallbackIndex = lines.indices.reversed().first(where: {
            !lines[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            lineIndex = fallbackIndex
        } else {
            return nil
        }

        let rawLine = lines[lineIndex].replacingOccurrences(of: "\t", with: "  ")
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard rawLine.count > maxCharacters else { return rawLine }

        let targetOffset = max(0, min(rawLine.count, column - 1))
        let halfWindow = maxCharacters / 2
        let startOffset = max(0, min(targetOffset - halfWindow, rawLine.count - maxCharacters))
        let endOffset = min(rawLine.count, startOffset + maxCharacters)
        let startIndex = rawLine.index(rawLine.startIndex, offsetBy: startOffset)
        let endIndex = rawLine.index(rawLine.startIndex, offsetBy: endOffset)
        let prefix = startOffset > 0 ? "..." : ""
        let suffix = endOffset < rawLine.count ? "..." : ""

        return prefix + String(rawLine[startIndex..<endIndex]) + suffix
    }
}
