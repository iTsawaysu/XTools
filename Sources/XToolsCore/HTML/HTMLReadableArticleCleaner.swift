import Foundation
import SwiftSoup

public enum HTMLReadableArticleCleaner {
    public static func clean(
        _ article: HTMLReadableArticle,
        baseURL: URL,
        policy: HTMLReadableArticleCleaningPolicy
    ) throws -> HTMLReadableArticle {
        let document = try SwiftSoup.parseBodyFragment(
            article.contentHTML,
            baseURL.absoluteString
        )
        document.outputSettings().prettyPrint(pretty: true)
        guard let body = document.body() else {
            throw HTMLReadableArticleExtractionError.articleNotFound
        }

        try removeUnsafeAndTemplateElements(from: body)
        try removePermalinkDecorations(from: body)

        if policy == .readableArticleParity {
            try removeReferenceURLModeStructures(from: body)
        }

        try resolveRelativeURLs(in: body, baseURL: baseURL)

        let title = normalizedText(article.title)
        if !title.isEmpty {
            try removeEquivalentTitleHeading(title, from: body)
        }

        guard hasMeaningfulContent(in: body) else {
            throw HTMLReadableArticleExtractionError.articleBecameEmptyAfterCleaning
        }

        if !title.isEmpty {
            let titleContainer = try preferredTitleContainer(in: body)
            try titleContainer.prependElement("h2").text(title)
        }

        let contentHTML = try serializedReadableRoot(from: body)
        return HTMLReadableArticle(
            title: title,
            contentHTML: contentHTML,
            excerpt: article.excerpt,
            byline: article.byline,
            siteName: article.siteName,
            language: article.language
        )
    }

    private static func removeUnsafeAndTemplateElements(from root: Element) throws {
        let selectors = [
            "script", "style", "template", "noscript", "iframe", "object", "embed", "canvas", "svg",
            "nav", "aside", "footer", "header", "form",
            "[hidden]", "[aria-hidden=true]",
            ".table-of-contents", ".toc", "#toc", "[class*=table-of-contents]",
            ".breadcrumb", "[class*=breadcrumb]",
            ".sidebar", "[class*=sidebar]",
            ".navigation", "[class*=navigation]",
            ".share", "[class*=share]",
            ".qrcode", ".qr-code", "[class*=qrcode]", "[class*=qr-code]",
            ".advertisement", ".advert", ".ads", "[class*=advertisement]",
            ".recommendation", ".related", "[class*=recommendation]",
            ".comments", "[class*=comments]"
        ]

        for selector in selectors {
            try root.select(selector).remove()
        }
    }

    private static func removePermalinkDecorations(from root: Element) throws {
        let selectors = [
            "a.header-anchor",
            "a.anchor",
            "a.anchor-link",
            "a[aria-hidden=true]",
            "a[class*=permalink]"
        ]

        for selector in selectors {
            try root.select(selector).remove()
        }
    }

    private static func removeReferenceURLModeStructures(from root: Element) throws {
        try root.select("pre, ul, ol").remove()
        for code in try root.select("code") {
            _ = try code.unwrap()
        }
    }

    private static func resolveRelativeURLs(in root: Element, baseURL: URL) throws {
        for link in try root.select("a[href]") {
            let raw = try link.attr("href")
            if let absolute = resolvedURLString(raw, relativeTo: baseURL) {
                try link.attr("href", absolute)
            }
        }

        for image in try root.select("img[src]") {
            let raw = try image.attr("src")
            if let absolute = resolvedURLString(raw, relativeTo: baseURL) {
                try image.attr("src", absolute)
            }
        }
    }

    private static func resolvedURLString(_ value: String, relativeTo baseURL: URL) -> String? {
        guard !value.isEmpty,
              let resolved = URL(string: value, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }
        return resolved.absoluteString
    }

    private static func removeEquivalentTitleHeading(_ title: String, from root: Element) throws {
        for heading in try root.select("h1, h2, h3, h4, h5, h6") {
            if normalizedText(try heading.text()) == title {
                try heading.remove()
                return
            }
        }
    }

    private static func hasMeaningfulContent(in root: Element) -> Bool {
        if ((try? root.select("p, blockquote, table, img, h1, h2, h3, h4, h5, h6").isEmpty) == false) {
            return true
        }
        return !normalizedText((try? root.text()) ?? "").isEmpty
    }

    private static func preferredTitleContainer(in body: Element) throws -> Element {
        if let readabilityRoot = try body.select("#readability-page-1").first() {
            return readabilityRoot.children().first ?? readabilityRoot
        }
        if body.children().count == 1, let onlyChild = body.children().first() {
            return onlyChild
        }
        return body
    }

    private static func serializedReadableRoot(from body: Element) throws -> String {
        if let readabilityRoot = try body.select("#readability-page-1").first() {
            return try readabilityRoot.outerHtml()
        }
        return "<div id=\"readability-page-1\" class=\"page\">\(try body.html())</div>"
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
