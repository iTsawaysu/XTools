import Foundation
import XToolsCore

@MainActor
enum TextDevelopmentToolPreferenceKeys {
    /// 「格式化」Hub 上次使用的分段（json/xml/yaml/sql），重启后恢复。
    static let formatterSegment = ToolPreferenceKey<String>.string(
        "tools.formatter.segment.v1",
        default: "json",
        allowedValues: ["json", "xml", "yaml", "sql"]
    )
    /// 「对比」Hub 上次使用的分段（json/text），重启后恢复。
    static let diffSegment = ToolPreferenceKey<String>.string(
        "tools.diff.segment.v1",
        default: "json",
        allowedValues: ["json", "text"]
    )
    /// 「生成器」Hub 上次使用的分段（token/uuid/password），重启后恢复。
    static let generatorSegment = ToolPreferenceKey<String>.string(
        "tools.generator.segment.v1",
        default: "token",
        allowedValues: ["token", "uuid", "password"]
    )
    /// 「图片处理」Hub 上次使用的分段（convert/compress/grayscale/favicon），重启后恢复。
    static let imageSegment = ToolPreferenceKey<String>.string(
        "tools.image.segment.v1",
        default: "convert",
        allowedValues: ["convert", "compress", "grayscale", "favicon"]
    )
    /// 「文本编码」Hub 上次使用的分段（base64/url/ascii/unicode），重启后恢复。
    static let encodingSegment = ToolPreferenceKey<String>.string(
        "tools.encoding.segment.v1",
        default: "base64",
        allowedValues: ["base64", "url", "ascii", "unicode"]
    )
    /// 「日期计算」上次使用的模式（interval/offset），重启后恢复。
    static let dateCalcMode = ToolPreferenceKey<String>.string(
        "tools.dateCalc.mode.v1",
        default: "interval",
        allowedValues: ["interval", "offset"]
    )
    static let integerBase = ToolPreferenceKey<String>.string(
        "tools.integerBase.inputBase.v1",
        default: "10",
        allowedValues: ["2", "8", "10", "16"]
    )
    static let jsonIndent = ToolPreferenceKey<String>.string(
        "tools.jsonFormatter.indent.v1",
        default: "4",
        allowedValues: ["2", "4", "compact"]
    )
    static let jsonUnescape = ToolPreferenceKey<Bool>.bool(
        "tools.jsonFormatter.unescape.v1",
        default: false
    )
    static let jsonEscape = ToolPreferenceKey<Bool>.bool(
        "tools.jsonFormatter.escape.v1",
        default: false
    )
    static let jsonSortKeys = ToolPreferenceKey<Bool>.bool(
        "tools.jsonFormatter.sortKeys.v1",
        default: false
    )
    static let htmlMarkdownRenderedPreview = ToolPreferenceKey<Bool>.bool(
        "tools.htmlToMarkdown.renderedPreview.v1",
        default: true
    )
    static let dockerConversionDirection = ToolPreferenceKey<String>.string(
        "tools.dockerConversion.direction.v1",
        default: "run-to-compose",
        allowedValues: ["run-to-compose", "compose-to-run"]
    )
    static let sqlKeywordCase = ToolPreferenceKey<SQLFormatting.KeywordCase>.rawRepresentable(
        "tools.sqlFormatter.keywordCase.v1",
        default: .upper
    )
    static let sqlIndent = ToolPreferenceKey<String>.string(
        "tools.sqlFormatter.indent.v2",
        default: "2",
        allowedValues: ["2", "4", "compact"]
    )
    static let yamlSortKeys = ToolPreferenceKey<Bool>.bool(
        "tools.yamlFormatter.sortKeys.v1",
        default: false
    )
    static let xmlIndent = ToolPreferenceKey<String>.string(
        "tools.xmlFormatter.indent.v1",
        default: "2",
        allowedValues: ["2", "4", "compact"]
    )
    static let emojiToneIndex = ToolPreferenceKey<Int>.integer(
        "tools.emoji.toneIndex.v1",
        default: 0,
        range: 0...5,
        outOfRangePolicy: .useDefault
    )

    static var allRawKeys: [String] {
        [
            integerBase.rawKey,
            jsonIndent.rawKey,
            jsonUnescape.rawKey,
            sqlKeywordCase.rawKey,
            sqlIndent.rawKey,
            emojiToneIndex.rawKey
        ]
    }
}
