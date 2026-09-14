import Foundation

public enum HTMLToMarkdownSessionSource: Equatable, Sendable {
    case manual
    case url
}

public enum HTMLToMarkdownSessionPhase: Equatable, Sendable {
    case idle
    case waitingForManualConversion
    case fetching
    case extracting
    case converting(HTMLToMarkdownSessionSource)
    case ready
    case failed
}

public enum HTMLToMarkdownSessionProjection {
    public static func isURLProcessing(_ phase: HTMLToMarkdownSessionPhase) -> Bool {
        switch phase {
        case .fetching, .extracting, .converting(.url):
            true
        case .idle, .waitingForManualConversion, .converting(.manual), .ready, .failed:
            false
        }
    }

    public static func processingText(_ phase: HTMLToMarkdownSessionPhase) -> String? {
        switch phase {
        case .fetching:
            "正在获取网页…"
        case .extracting:
            "正在提取正文…"
        case .converting(.url), .converting(.manual):
            "正在转换 Markdown…"
        case .waitingForManualConversion:
            "等待输入完成…"
        case .idle, .ready, .failed:
            nil
        }
    }
}
