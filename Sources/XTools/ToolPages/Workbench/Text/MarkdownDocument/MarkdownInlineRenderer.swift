// Adapted from MarkdownUI (https://github.com/gonzalezreal/swift-markdown-ui),
// The MIT License, Copyright (c) 2020 Guillermo Gonzalez.
// 行内渲染：把文档模型的行内节点组合成 Text / AttributedString。
// 上游用 TextStyle DSL + FontProperties 属性延后解析；这里以字段级字体组合
// （MarkdownFontProperties）表达同样的嵌套语义——子样式只覆盖它显式设置的字段，
// 例如 ***粗斜体*** 必须同时保留斜体与 semibold。预览的 Clay 令牌与测试 oracle
// 的 plain 集合都通过 MarkdownInlineStyleSet 注入。

import SwiftUI

/// 字体属性的字段级组合：nil/false 表示从外层继承。
/// 语义与上游 FontProperties 一致，只是不借助 AttributeContainer 延后解析。
struct MarkdownFontProperties: Sendable, Equatable {
    var size: Double?
    var weight: Font.Weight?
    var design: Font.Design?
    var italic = false

    func merging(_ other: MarkdownFontProperties) -> MarkdownFontProperties {
        var merged = self
        if let size = other.size { merged.size = size }
        if let weight = other.weight { merged.weight = weight }
        if let design = other.design { merged.design = design }
        if other.italic { merged.italic = true }
        return merged
    }

    var font: Font {
        var font = Font.system(
            size: size ?? MarkdownFontProperties.defaultSize,
            weight: weight ?? .regular,
            design: design ?? .default
        )
        if italic {
            font = font.italic()
        }
        return font
    }

    /// 与上游 FontProperties.defaultSize 一致（macOS 为 13）。
    static let defaultSize = 13.0
}

/// 一组行内样式。`Style` 只描述相对外层的覆盖项；渲染时先合并字体属性，
/// 再把非字体属性并入 AttributeContainer（显式设置的键覆盖继承值）。
struct MarkdownInlineStyleSet: Sendable {
    struct Style: Sendable {
        var fontProperties = MarkdownFontProperties()
        var foregroundColor: Color?
        var backgroundColor: Color?
        var underlineStyle: Text.LineStyle?
        var strikethroughStyle: Text.LineStyle?
    }

    var baseFont = MarkdownFontProperties()
    var baseForegroundColor: Color?
    var code = Style()
    var emphasis = Style()
    var strong = Style()
    var strikethrough = Style()
    var link = Style()

    /// vendored 默认 Theme() 的等价集合：无主题色、无字号覆盖，供测试 oracle 使用。
    static let plain = MarkdownInlineStyleSet(
        code: Style(fontProperties: .init(design: .monospaced)),
        emphasis: Style(fontProperties: .init(italic: true)),
        strong: Style(fontProperties: .init(weight: .semibold)),
        strikethrough: Style(strikethroughStyle: .single)
    )
}

extension Sequence where Element == MarkdownInline {
    /// 行内序列 → Text。预加载的行内图片以 `Text(Image)` 拼进文本流；
    /// 不在 images 里的图片源按上游行为静默跳过（加载失败会走占位图，见
    /// MarkdownPreviewInlineImageProvider）。
    func renderText(styleSet: MarkdownInlineStyleSet, images: [String: Image]) -> Text {
        var renderer = MarkdownTextInlineRenderer(styleSet: styleSet, images: images)
        renderer.render(self)
        return renderer.result
    }
}

extension MarkdownInline {
    /// 单个行内子树 → AttributedString（oracle 出口使用）。
    func renderAttributedString(styleSet: MarkdownInlineStyleSet) -> AttributedString {
        var renderer = MarkdownAttributedStringInlineRenderer(styleSet: styleSet)
        renderer.render(self)
        return renderer.result
    }
}

// MARK: - AttributedString renderer

private struct MarkdownAttributedStringInlineRenderer {
    var result = AttributedString()

    private let styleSet: MarkdownInlineStyleSet
    private var fontProperties: MarkdownFontProperties
    private var attributes: AttributeContainer
    private var shouldSkipNextWhitespace = false

    init(styleSet: MarkdownInlineStyleSet) {
        self.styleSet = styleSet
        self.fontProperties = styleSet.baseFont
        var initial = AttributeContainer()
        initial.font = fontProperties.font
        if let color = styleSet.baseForegroundColor {
            initial.foregroundColor = color
        }
        self.attributes = initial
    }

    mutating func render(_ inline: MarkdownInline) {
        switch inline {
        case .text(let content):
            self.renderText(content)
        case .softBreak:
            self.renderSoftBreak()
        case .lineBreak:
            self.renderLineBreak()
        case .code(let content):
            self.renderCode(content)
        case .html(let content):
            self.renderHTML(content)
        case .emphasis(let children):
            self.renderStyled(children, style: styleSet.emphasis)
        case .strong(let children):
            self.renderStyled(children, style: styleSet.strong)
        case .strikethrough(let children):
            self.renderStyled(children, style: styleSet.strikethrough)
        case .link(let destination, let children):
            self.renderLink(destination: destination, children: children)
        case .image:
            // AttributedString 不支持内嵌图片（与上游一致）。
            break
        }
    }

    private mutating func renderText(_ text: String) {
        self.append(text)
    }

    private mutating func renderSoftBreak() {
        if self.shouldSkipNextWhitespace {
            self.shouldSkipNextWhitespace = false
        } else {
            self.append(" ")
        }
    }

    private mutating func renderLineBreak() {
        self.append("\n")
    }

    private mutating func renderCode(_ code: String) {
        let savedProperties = self.fontProperties
        let savedAttributes = self.attributes
        self.enter(style: styleSet.code)
        self.append(code)
        self.fontProperties = savedProperties
        self.attributes = savedAttributes
    }

    private mutating func renderHTML(_ html: String) {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<!--") else {
            return
        }
        let tag = MarkdownHTMLTag(html)
        switch tag?.name.lowercased() {
        case "br":
            self.renderLineBreak()
            self.shouldSkipNextWhitespace = true
        default:
            // 行内 HTML 按字面文本渲染（与上游预览一致，原始 HTML 不执行）。
            self.append(html)
        }
    }

    private mutating func renderStyled(_ children: [MarkdownInline], style: MarkdownInlineStyleSet.Style) {
        let savedProperties = self.fontProperties
        let savedAttributes = self.attributes
        self.enter(style: style)
        for child in children {
            self.render(child)
        }
        self.fontProperties = savedProperties
        self.attributes = savedAttributes
    }

    private mutating func renderLink(destination: String, children: [MarkdownInline]) {
        let savedProperties = self.fontProperties
        let savedAttributes = self.attributes
        self.enter(style: styleSet.link)
        self.attributes.link = URL(string: destination)
        for child in children {
            self.render(child)
        }
        self.fontProperties = savedProperties
        self.attributes = savedAttributes
    }

    private mutating func enter(style: MarkdownInlineStyleSet.Style) {
        self.fontProperties = self.fontProperties.merging(style.fontProperties)
        self.attributes.font = self.fontProperties.font
        if let color = style.foregroundColor {
            self.attributes.foregroundColor = color
        }
        if let backgroundColor = style.backgroundColor {
            self.attributes.backgroundColor = backgroundColor
        }
        if let underlineStyle = style.underlineStyle {
            self.attributes.underlineStyle = underlineStyle
        }
        if let strikethroughStyle = style.strikethroughStyle {
            self.attributes.strikethroughStyle = strikethroughStyle
        }
    }

    private mutating func append(_ text: String) {
        var text = text
        if self.shouldSkipNextWhitespace {
            self.shouldSkipNextWhitespace = false
            text = text.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
        }
        self.result += .init(text, attributes: self.attributes)
    }
}

// MARK: - Text renderer

private struct MarkdownTextInlineRenderer {
    var result = Text("")

    private let styleSet: MarkdownInlineStyleSet
    private let images: [String: Image]
    private var shouldSkipNextWhitespace = false

    init(styleSet: MarkdownInlineStyleSet, images: [String: Image]) {
        self.styleSet = styleSet
        self.images = images
    }

    mutating func render<S: Sequence>(_ inlines: S) where S.Element == MarkdownInline {
        for inline in inlines {
            self.render(inline)
        }
    }

    private mutating func render(_ inline: MarkdownInline) {
        switch inline {
        case .text(let content):
            self.renderText(content)
        case .softBreak:
            self.renderSoftBreak()
        case .html(let content):
            self.renderHTML(content)
        case .image(let source, _):
            if let image = self.images[source] {
                self.result = self.result + Text(image)
            }
        default:
            self.result = self.result + Text(inline.renderAttributedString(styleSet: self.styleSet))
        }
    }

    private mutating func renderText(_ text: String) {
        var text = text
        if self.shouldSkipNextWhitespace {
            self.shouldSkipNextWhitespace = false
            text = text.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
        }
        self.defaultRender(.text(text))
    }

    private mutating func renderSoftBreak() {
        if self.shouldSkipNextWhitespace {
            self.shouldSkipNextWhitespace = false
        } else {
            self.defaultRender(.softBreak)
        }
    }

    private mutating func renderHTML(_ html: String) {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<!--") else {
            return
        }
        let tag = MarkdownHTMLTag(html)
        switch tag?.name.lowercased() {
        case "br":
            self.defaultRender(.lineBreak)
            self.shouldSkipNextWhitespace = true
        default:
            self.defaultRender(.html(html))
        }
    }

    private mutating func defaultRender(_ inline: MarkdownInline) {
        self.result = self.result + Text(inline.renderAttributedString(styleSet: self.styleSet))
    }
}

private struct MarkdownHTMLTag {
    let name: String

    private enum Constants {
        static let tagExpression = try! NSRegularExpression(pattern: "<\\/?([a-zA-Z0-9]+)[^>]*>")
    }

    init?(_ description: String) {
        guard
            let match = Constants.tagExpression.firstMatch(
                in: description,
                range: NSRange(description.startIndex..., in: description)
            ),
            let nameRange = Range(match.range(at: 1), in: description)
        else {
            return nil
        }
        self.name = String(description[nameRange])
    }
}
