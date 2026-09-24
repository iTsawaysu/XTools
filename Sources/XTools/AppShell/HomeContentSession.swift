import Combine
import Foundation
import XToolsCore

typealias HomeContentDetectionOperation = @Sendable (String) async -> SmartPasteDetector.Kind?
typealias HomeContentProcessingOperation = @Sendable (
    HomeContentAction,
    String
) async -> Result<HomeContentResult, HomeContentFailure>

@MainActor
final class HomeContentSession: ObservableObject {
    static let key = ToolWorkspaceKey<HomeContentSession>(
        toolID: "__shell-home__",
        slot: "content-session"
    ) { _ in
        HomeContentSession()
    }

    @Published var input = "" {
        didSet {
            guard input != oldValue else { return }
            inputDidChange()
        }
    }

    @Published var selectedAction: HomeContentAction? {
        didSet {
            guard !isApplyingAutomaticSelection else { return }
            usesAutomaticActionSelection = false
            guard selectedAction != oldValue else { return }
            invalidateProcessing()
            publishInputDiagnosticIfNeeded()
        }
    }

    @Published private(set) var detection: SmartPasteDetector.Kind?
    @Published private(set) var result: HomeContentResult?
    @Published private(set) var failure: String?
    @Published private(set) var isDetecting = false
    @Published private(set) var isProcessing = false
    @Published private(set) var usesAutomaticActionSelection = true
    @Published private(set) var isOutputCollapsed = false

    var canRun: Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && SmartPasteDetector.isWithinCharacterLimit(
                input,
                limit: HomeContentProcessor.maximumCharacterCount
            )
            && selectedAction != nil
            && !isDetecting
            && !isProcessing
    }

    private let detect: HomeContentDetectionOperation
    private let process: HomeContentProcessingOperation
    private let detectionGate = AsyncWorkGate()
    private let processingGate = AsyncWorkGate()
    private var isApplyingAutomaticSelection = false

    init(
        detect: @escaping HomeContentDetectionOperation = { HomeContentProcessor.detect($0) },
        process: @escaping HomeContentProcessingOperation = {
            HomeContentProcessor.run($0, input: $1)
        }
    ) {
        self.detect = detect
        self.process = process
    }

    func run() {
        invalidateProcessing()

        guard !isDetecting, let action = selectedAction else { return }
        let snapshot = input
        guard !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        guard SmartPasteDetector.isWithinCharacterLimit(
            snapshot,
            limit: HomeContentProcessor.maximumCharacterCount
        ) else {
            failure = HomeContentFailure.inputTooLong(
                maximumCharacterCount: HomeContentProcessor.maximumCharacterCount
            ).message
            return
        }

        let process = process
        isProcessing = true
        processingGate.runDetached {
            await process(action, snapshot)
        } publish: { [weak self] outcome in
            guard let self else { return }
            self.isProcessing = false
            switch outcome {
            case .success(let result):
                self.result = result
                self.failure = nil
                self.isOutputCollapsed = false
            case .failure(let failure):
                self.result = nil
                self.failure = failure.message
            }
        }
    }

    func reportPasteboardUnavailable() {
        failure = "剪贴板中没有可粘贴的文本。"
    }

    func useAutomaticActionSelection() {
        usesAutomaticActionSelection = true
        invalidateProcessing()
        applyAutomaticSelection(detection.flatMap(HomeContentProcessor.preferredAction(for:)))
        publishInputDiagnosticIfNeeded()
    }

    func toggleOutputCollapsed() {
        guard result != nil else { return }
        isOutputCollapsed.toggle()
    }

    func clear() {
        _ = detectionGate.invalidate()
        _ = processingGate.invalidate()
        usesAutomaticActionSelection = true
        isApplyingAutomaticSelection = true
        input = ""
        selectedAction = nil
        isApplyingAutomaticSelection = false
        detection = nil
        result = nil
        failure = nil
        isDetecting = false
        isProcessing = false
        isOutputCollapsed = false
    }

    private func inputDidChange() {
        _ = detectionGate.invalidate()
        isDetecting = false
        invalidateProcessing()
        detection = nil
        if usesAutomaticActionSelection {
            applyAutomaticSelection(nil)
        }

        let snapshot = input
        guard !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            failure = nil
            return
        }
        guard SmartPasteDetector.isWithinCharacterLimit(
            snapshot,
            limit: HomeContentProcessor.maximumCharacterCount
        ) else {
            failure = HomeContentFailure.inputTooLong(
                maximumCharacterCount: HomeContentProcessor.maximumCharacterCount
            ).message
            return
        }

        failure = nil
        isDetecting = true
        let detect = detect
        detectionGate.runDetached {
            await detect(snapshot)
        } publish: { [weak self] kind in
            guard let self else { return }
            self.isDetecting = false
            self.detection = kind
            guard self.usesAutomaticActionSelection else { return }
            self.applyAutomaticSelection(kind.flatMap(HomeContentProcessor.preferredAction(for:)))
        }
    }

    private func applyAutomaticSelection(_ action: HomeContentAction?) {
        guard selectedAction != action else { return }
        let wasApplyingAutomaticSelection = isApplyingAutomaticSelection
        isApplyingAutomaticSelection = true
        defer { isApplyingAutomaticSelection = wasApplyingAutomaticSelection }
        selectedAction = action
    }

    private func invalidateProcessing() {
        _ = processingGate.invalidate()
        result = nil
        failure = nil
        isProcessing = false
        isOutputCollapsed = false
    }

    private func publishInputDiagnosticIfNeeded() {
        guard !SmartPasteDetector.isWithinCharacterLimit(
            input,
            limit: HomeContentProcessor.maximumCharacterCount
        ) else { return }
        failure = HomeContentFailure.inputTooLong(
            maximumCharacterCount: HomeContentProcessor.maximumCharacterCount
        ).message
    }
}
