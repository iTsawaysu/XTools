import XToolsCore
import Foundation
import WebKit

@MainActor
final class WebKitHTMLReadableArticleExtractor: HTMLReadableArticleExtracting {
    private let timeout: Duration

    init(timeout: TimeInterval = 8) {
        self.timeout = .milliseconds(Int64(max(0.1, timeout) * 1_000))
    }

    func extractArticle(from html: String, baseURL: URL) async throws -> HTMLReadableArticle {
        try Task.checkCancellation()

        let script: String
        do {
            script = try HTMLReadabilityScriptResource.load()
        } catch {
            throw HTMLReadableArticleExtractionError.readabilityUnavailable
        }

        let gate = HTMLReadabilityResultGate()
        let operationTask = Task { @MainActor in
            do {
                let article = try await Self.runReadability(
                    html: html,
                    baseURL: baseURL,
                    script: script
                )
                await gate.resolve(.success(article))
            } catch is CancellationError {
                await gate.resolve(.cancelled)
            } catch let error as HTMLReadableArticleExtractionError {
                await gate.resolve(.failure(error))
            } catch {
                await gate.resolve(.failure(.readabilityMalformedResult))
            }
        }
        let timeoutTask = Task { [timeout] in
            do {
                try await Task.sleep(for: timeout)
                await gate.resolve(.failure(.readabilityTimedOut))
            } catch {
                // The operation completed or the parent task was cancelled.
            }
        }

        return try await withTaskCancellationHandler {
            let outcome = await gate.value()
            operationTask.cancel()
            timeoutTask.cancel()
            switch outcome {
            case .success(let article):
                return article
            case .failure(let error):
                throw error
            case .cancelled:
                throw CancellationError()
            }
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            Task {
                await gate.resolve(.cancelled)
            }
        }
    }

    private static func runReadability(
        html: String,
        baseURL: URL,
        script: String
    ) async throws -> HTMLReadableArticle {
        try Task.checkCancellation()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigationWaiter = HTMLReadabilityNavigationWaiter()
        webView.navigationDelegate = navigationWaiter
        webView.loadHTMLString("<!doctype html><html><head></head><body></body></html>", baseURL: nil)

        return try await withTaskCancellationHandler {
            try await navigationWaiter.waitUntilFinished()
            try Task.checkCancellation()

            let contentWorld = WKContentWorld.world(name: "XTools.HTMLReadability")
            _ = try await webView.evaluateJavaScript(
                script,
                contentWorld: contentWorld
            )
            let rawResult = try await webView.callAsyncJavaScript(
                Self.extractionFunction,
                arguments: [
                    "html": html,
                    "baseURL": baseURL.absoluteString
                ],
                contentWorld: contentWorld
            )
            try Task.checkCancellation()

            guard let resultJSON = rawResult as? String,
                  let data = resultJSON.data(using: .utf8) else {
                throw HTMLReadableArticleExtractionError.articleNotFound
            }

            do {
                let result = try JSONDecoder().decode(ReadabilityJavaScriptResult.self, from: data)
                let content = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else {
                    throw HTMLReadableArticleExtractionError.articleNotFound
                }
                return HTMLReadableArticle(
                    title: result.title,
                    contentHTML: content,
                    excerpt: result.excerpt,
                    byline: result.byline,
                    siteName: result.siteName,
                    language: result.lang
                )
            } catch let error as HTMLReadableArticleExtractionError {
                throw error
            } catch {
                throw HTMLReadableArticleExtractionError.readabilityMalformedResult
            }
        } onCancel: {
            Task { @MainActor in
                webView.stopLoading()
            }
        }
    }

    private static let extractionFunction = #"""
    const parser = new DOMParser();
    const document = parser.parseFromString(html, "text/html");
    if (!document || !document.documentElement) {
        return null;
    }

    let base = document.querySelector("base");
    if (!base) {
        base = document.createElement("base");
        document.head.prepend(base);
    }
    base.href = baseURL;

    const article = new Readability(document, {
        charThreshold: 100,
        keepClasses: true
    }).parse();
    if (!article || !article.content) {
        return null;
    }

    return JSON.stringify({
        title: article.title || "",
        content: article.content || "",
        excerpt: article.excerpt || null,
        byline: article.byline || null,
        siteName: article.siteName || null,
        lang: article.lang || null
    });
    """#
}

private struct ReadabilityJavaScriptResult: Decodable {
    let title: String
    let content: String
    let excerpt: String?
    let byline: String?
    let siteName: String?
    let lang: String?
}

@MainActor
private final class HTMLReadabilityNavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    func waitUntilFinished() async throws {
        if let result {
            return try result.get()
        }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        finish(.failure(HTMLReadableArticleExtractionError.readabilityUnavailable))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        finish(.failure(HTMLReadableArticleExtractionError.readabilityUnavailable))
    }

    private func finish(_ result: Result<Void, Error>) {
        guard self.result == nil else { return }
        self.result = result
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        }
    }
}

private enum HTMLReadabilityOutcome: Sendable {
    case success(HTMLReadableArticle)
    case failure(HTMLReadableArticleExtractionError)
    case cancelled
}

private actor HTMLReadabilityResultGate {
    private var outcome: HTMLReadabilityOutcome?
    private var continuation: CheckedContinuation<HTMLReadabilityOutcome, Never>?

    func resolve(_ outcome: HTMLReadabilityOutcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: outcome)
        }
    }

    func value() async -> HTMLReadabilityOutcome {
        if let outcome { return outcome }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}
