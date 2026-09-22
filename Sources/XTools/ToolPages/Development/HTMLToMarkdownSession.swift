import Combine
import XToolsCore
import Foundation

typealias HTMLToMarkdownURLOperation = @Sendable (
    _ urlText: String,
    _ extractArticleOnly: Bool,
    _ progress: @escaping HTMLToMarkdownURLPipeline.ProgressHandler
) async throws -> HTMLToMarkdownURLResult

typealias HTMLToMarkdownManualOperation = @Sendable (
    _ html: String
) throws -> HTMLToMarkdownConversionResult

@MainActor
final class HTMLToMarkdownSession: ObservableObject {
    @Published var urlText = "" {
        didSet {
            guard urlText != oldValue else { return }
            revokeRemoteImageAuthorization()
            if error != nil {
                error = nil
            }
            if phase == .failed && inputHTML.isEmpty && markdown.isEmpty {
                phase = .idle
            }
        }
    }
    @Published var extractArticleOnly: Bool = true {
        didSet {
            guard extractArticleOnly != oldValue else { return }
            revokeRemoteImageAuthorization()
            if !urlText.isEmpty && !isURLProcessing {
                fetchURL()
            }
        }
    }
    @Published private(set) var inputHTML = ""
    @Published private(set) var markdown = ""
    @Published private(set) var error: String?
    @Published private(set) var warning: String?
    @Published private(set) var phase: HTMLToMarkdownSessionPhase = .idle
    @Published private(set) var formatAttempt = 0
    @Published private(set) var previewAuthorizationGeneration = 0

    private let urlOperation: HTMLToMarkdownURLOperation
    private let manualOperation: HTMLToMarkdownManualOperation
    private let manualDebounce: Duration
    private let workGate = AsyncWorkGate()

    init(
        extractor: any HTMLReadableArticleExtracting = WebKitHTMLReadableArticleExtractor(),
        urlOperation: HTMLToMarkdownURLOperation? = nil,
        manualOperation: @escaping HTMLToMarkdownManualOperation = HTMLToMarkdownSession.defaultManualOperation,
        manualDebounce: Duration = .milliseconds(250)
    ) {
        if let urlOperation {
            self.urlOperation = urlOperation
        } else {
            let pipeline = HTMLToMarkdownURLPipeline(extractor: extractor)
            self.urlOperation = { urlText, extractArticleOnly, progress in
                try await pipeline.convert(urlText: urlText, extractArticleOnly: extractArticleOnly, progress: progress)
            }
        }
        self.manualOperation = manualOperation
        self.manualDebounce = manualDebounce
    }

    var isURLProcessing: Bool {
        HTMLToMarkdownSessionProjection.isURLProcessing(phase)
    }

    var processingText: String? {
        HTMLToMarkdownSessionProjection.processingText(phase)
    }

    var canClear: Bool {
        !urlText.isEmpty
            || !inputHTML.isEmpty
            || !markdown.isEmpty
            || error != nil
            || warning != nil
            || phase != .idle
    }

    func fetchURL() {
        revokeRemoteImageAuthorization()
        let requestURLText = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestURLText.isEmpty else {
            _ = workGate.invalidate()
            markdown = ""
            error = HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .emptyURL)
            warning = nil
            phase = .failed
            formatAttempt += 1
            return
        }

        do {
            _ = try HTMLToMarkdownURLFetchService.normalizedURL(from: requestURLText)
        } catch let fetchError as HTMLToMarkdownURLFetchError {
            _ = workGate.invalidate()
            markdown = ""
            self.error = HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: fetchError)
            warning = nil
            phase = .failed
            formatAttempt += 1
            return
        } catch {
            _ = workGate.invalidate()
            markdown = ""
            self.error = HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .invalidURL)
            warning = nil
            phase = .failed
            formatAttempt += 1
            return
        }

        let currentGeneration = workGate.invalidate()
        markdown = ""
        error = nil
        warning = nil
        phase = .fetching
        let urlOperation = self.urlOperation

        let extractArticleOnly = self.extractArticleOnly

        workGate.schedule(debounce: .zero) { [weak self] in
            guard let self, self.workGate.isCurrent(currentGeneration) else { return }
            do {
                let result = try await urlOperation(
                    requestURLText,
                    extractArticleOnly,
                    { [weak self] stage in
                        await self?.receive(stage, generation: currentGeneration)
                    }
                )
                guard self.workGate.isCurrent(currentGeneration) else { return }

                self.inputHTML = result.cleanedHTML
                self.markdown = result.markdown
                
                if self.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.finishFailure("提取结果为空。页面可能由客户端 JS 动态渲染，或无有效文本内容。", generation: currentGeneration)
                    return
                }
                
                self.error = nil
                self.warning = HTMLToMarkdownDiagnostics.conversionWarningMessage(
                    for: result.warnings
                )
                self.phase = .ready
            } catch is CancellationError {
                // A new action, clear, or session deallocation owns the replacement state.
            } catch let conversionError as HTMLToMarkdownConversionError {
                self.finishFailure(
                    HTMLToMarkdownDiagnostics.conversionErrorMessage(for: conversionError),
                    generation: currentGeneration
                )
            } catch let fetchError as HTMLToMarkdownURLFetchError {
                self.finishFailure(
                    HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: fetchError),
                    generation: currentGeneration
                )
            } catch let extractionError as HTMLReadableArticleExtractionError {
                self.finishFailure(
                    HTMLToMarkdownDiagnostics.articleExtractionErrorMessage(for: extractionError),
                    generation: currentGeneration
                )
            } catch {
                self.finishFailure(
                    HTMLToMarkdownDiagnostics.urlFetchErrorMessage(for: .requestFailed),
                    generation: currentGeneration
                )
            }
        }
    }

    func userEditedHTML(_ html: String) {
        revokeRemoteImageAuthorization()
        let currentGeneration = workGate.invalidate()
        inputHTML = html
        markdown = ""
        error = nil
        warning = nil

        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .idle
            return
        }

        phase = .waitingForManualConversion
        let manualOperation = self.manualOperation

        workGate.schedule(debounce: manualDebounce) { [weak self] in
            guard let self, self.workGate.isCurrent(currentGeneration) else { return }
            self.phase = .converting(.manual)

            let convertTask = Task.detached(priority: .userInitiated) {
                try manualOperation(trimmed)
            }

            do {
                let result = try await withTaskCancellationHandler {
                    try await convertTask.value
                } onCancel: {
                    convertTask.cancel()
                }

                guard self.workGate.isCurrent(currentGeneration) else { return }
                self.markdown = result.markdown
                self.error = nil
                self.warning = HTMLToMarkdownDiagnostics.conversionWarningMessage(
                    for: result.warnings
                )
                self.phase = .ready
            } catch is CancellationError {
                // Superseded generation or explicit cancel — do not publish markdown.
            } catch let conversionError as HTMLToMarkdownConversionError {
                self.finishFailure(
                    HTMLToMarkdownDiagnostics.conversionErrorMessage(for: conversionError),
                    generation: currentGeneration
                )
            } catch {
                DiagnosticFallbackLog.record(error, context: "HTMLToMarkdownSession.convert")
                self.finishFailure(
                    "HTML 转换失败，输入内容无法解析。",
                    generation: currentGeneration
                )
            }
        }
    }

    func clear() {
        revokeRemoteImageAuthorization()
        _ = workGate.invalidate()
        urlText = ""
        inputHTML = ""
        markdown = ""
        error = nil
        warning = nil
        phase = .idle
    }

    func cancel() {
        _ = workGate.invalidate()
        phase = markdown.isEmpty && inputHTML.isEmpty ? .idle : .ready
    }

    private func receive(
        _ stage: HTMLToMarkdownURLPipelineStage,
        generation currentGeneration: Int
    ) {
        guard workGate.isCurrent(currentGeneration) else { return }
        switch stage {
        case .fetching:
            phase = .fetching
        case .extracting:
            phase = .extracting
        case .converting:
            phase = .converting(.url)
        }
    }

    private func finishFailure(_ message: String, generation currentGeneration: Int) {
        guard workGate.isCurrent(currentGeneration) else { return }
        markdown = ""
        error = message
        warning = nil
        phase = .failed
        formatAttempt += 1
    }

    private func revokeRemoteImageAuthorization() {
        previewAuthorizationGeneration &+= 1
    }

    nonisolated private static func defaultManualOperation(
        _ html: String
    ) throws -> HTMLToMarkdownConversionResult {
        try HTMLToMarkdownConverter.convert(
            html,
            options: .manual,
            shouldCancel: { Task.isCancelled }
        )
    }
}
