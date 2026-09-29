import Foundation

public enum HTMLToMarkdownDiagnostics {
    public static func conversionWarningMessage(for warnings: [HTMLToMarkdownWarning]) -> String? {
        guard !warnings.isEmpty else { return nil }

        if warnings.contains(.emptyVisibleContent) {
            return warningText(for: .emptyVisibleContent)
        }

        let hasElementConversionLoss = warnings.contains { warning in
            switch warning {
            case .unsupportedElement, .droppedUnsafeElement:
                return true
            case .flattenedTableSpan, .emptyVisibleContent, .completedInputExceedsThreshold:
                return false
            }
        }
        if hasElementConversionLoss {
            return "部分 HTML 内容无法完整转换。"
        }

        if warnings.contains(.flattenedTableSpan) {
            return warningText(for: .flattenedTableSpan)
        }

        let largestInputLimit = warnings.compactMap { warning -> Int? in
            if case .completedInputExceedsThreshold(let limit) = warning { return limit }
            return nil
        }.max()
        if let largestInputLimit {
            return warningText(for: .completedInputExceedsThreshold(largestInputLimit))
        }

        return nil
    }

    public static func conversionWarningDiagnostic(for warnings: [HTMLToMarkdownWarning]) -> FormatDiagnostic? {
        guard let message = conversionWarningMessage(for: warnings) else { return nil }
        var seen = Set<String>()
        var details: [String] = []
        for warning in warnings {
            let detail: String
            switch warning {
            case .unsupportedElement(let element):
                detail = "\(safeElementName(element))：无等价 Markdown 元素，已保留可转换的文字或链接。"
            case .droppedUnsafeElement(let element):
                detail = "\(safeElementName(element))：已移除，未写入 Markdown。"
            case .flattenedTableSpan:
                detail = "表格合并单元格已展开，rowspan / colspan 布局未保留。"
            case .emptyVisibleContent, .completedInputExceedsThreshold:
                detail = warningText(for: warning)
            }
            if seen.insert(detail).inserted { details.append(detail) }
        }
        if details.count > 32 {
            let omitted = details.count - 32
            details = Array(details.prefix(32)) + ["另有 \(omitted) 项转换提示，未展开显示。"]
        }
        return FormatDiagnostic(formatName: "HTML 转换", message: message, details: details)
    }

    private static func safeElementName(_ element: String) -> String {
        knownElementNames.contains(element) ? "<\(element)>" : "其他 HTML 元素"
    }

    private static let knownElementNames: Set<String> = [
        "script", "style", "template", "noscript", "iframe", "canvas", "video", "audio", "svg", "math",
        "object", "embed", "img", "input", "button", "select", "textarea", "form"
    ]

    public static func warningText(for warning: HTMLToMarkdownWarning) -> String {
        switch warning {
        case .unsupportedElement:
            return "部分 HTML 内容无法完整转换。"
        case .flattenedTableSpan:
            return "复杂表格无法完整转换。"
        case .droppedUnsafeElement:
            return "部分 HTML 内容无法完整转换。"
        case .emptyVisibleContent:
            return "未检测到可见内容。"
        case .completedInputExceedsThreshold(let limit):
            return "输入超过 \(ByteSizeFormatter.format(bytes: limit))，本次已完成转换。"
        }
    }

    public static func conversionErrorMessage(for error: HTMLToMarkdownConversionError) -> String {
        switch error {
        case .inputExceedsPreParseByteLimit(let limit):
            return "输入超过 \(ByteSizeFormatter.format(bytes: limit))，未开始转换。"
        case .domDepthExceeded(let limit):
            return "HTML 嵌套超过 \(limit) 层，未进行转换。"
        }
    }

    public static func urlFetchErrorMessage(for error: HTMLToMarkdownURLFetchError) -> String {
        switch error {
        case .emptyURL:
            return "URL 为空。"
        case .invalidURL:
            return "URL 格式无效；仅支持 http 或 https 地址。"
        case .unsupportedScheme(let scheme):
            return "`\(safeSchemeName(scheme))` 协议不支持；仅支持 http 或 https。"
        case .privateNetworkDisallowed:
            return "不允许访问本地或私有网络地址。"
        case .requestFailed:
            return "无法获取 URL，网络请求失败或连接中断。"
        case .nonHTTPResponse:
            return "URL 没有返回 HTTP 响应。"
        case .unacceptableStatusCode(let statusCode):
            return "URL 返回 HTTP \(statusCode)，无法转换。"
        case .unsupportedContentType:
            return "URL 返回的不是 HTML 页面。"
        case .responseTooLarge(let limit):
            return "页面超过 \(ByteSizeFormatter.format(bytes: limit)) 上限，已停止获取。"
        case .emptyResponse:
            return "URL 返回空内容。"
        case .undecodableText:
            return "无法识别页面文本编码。"
        }
    }

    public static func articleExtractionErrorMessage(for error: HTMLReadableArticleExtractionError) -> String {
        switch error {
        case .readabilityUnavailable, .articleNotFound:
            return "未能识别网页正文。"
        case .readabilityTimedOut:
            return "网页正文解析超时。"
        case .readabilityMalformedResult:
            return "网页正文解析结果无效。"
        case .articleBecameEmptyAfterCleaning:
            return "网页正文清理后没有可转换内容。"
        }
    }

    private static func safeSchemeName(_ scheme: String) -> String {
        guard scheme.range(
            of: #"^[A-Za-z][A-Za-z0-9+.-]{0,19}$"#,
            options: .regularExpression
        ) != nil else {
            return "未知"
        }
        return scheme
    }

}
