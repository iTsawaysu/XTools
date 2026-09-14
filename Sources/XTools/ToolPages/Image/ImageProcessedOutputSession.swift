import AppKit
import Combine
import XToolsCore
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ImageProcessedOutputSession: ObservableObject, ToolWorkspacePayloadEvicting {
    static let grayscaleWorkspaceKey = ToolWorkspaceKey<ImageProcessedOutputSession>(
        toolID: "image-grayscale"
    ) { _ in
        ImageProcessedOutputSession()
    }

    @Published private(set) var source: ImageInputSelection?
    @Published private(set) var output: ProcessedImage?
    @Published private(set) var outputImage: NSImage?
    @Published private(set) var error: String?
    @Published private(set) var isProcessing = false

    private var panelTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var activePanelRequestID: UUID?
    private let renderGate = AsyncWorkGate()

    deinit {
        panelTask?.cancel()
        selectionTask?.cancel()
    }

    var sourceImage: NSImage? {
        source?.image
    }

    var sourceURL: URL? {
        source?.url
    }

    var sourceMetadata: ImageMetadata? {
        source?.metadata
    }

    func selectImage(
        filePanel: FileInputPanelClient,
        allowedContentTypes: [UTType],
        client: ImageWorkflowClient = ImageWorkflowClient(),
        operation: ImageProcessingOperation,
        selectionPublisher: @escaping ImageSelectionPublisher = { _, publish in publish() },
        onSelection: @escaping (ImageInputSelection) -> Void = { _ in },
        shouldRender: @escaping (ImageInputSelection) -> Bool = { _ in true },
        skippedRenderFailure: ImageWorkflowFailure? = nil,
        renderProvider: ImageBackgroundOutputRendererProvider? = nil,
        render: @escaping ImageBackgroundOutputRenderer
    ) {
        guard panelTask == nil else { return }
        let requestID = UUID()
        activePanelRequestID = requestID
        panelTask = Task { @MainActor [weak self] in
            do {
                guard let url = try await filePanel.selectFile(
                    FileInputPanelRequest(allowedContentTypes: allowedContentTypes)
                ) else {
                    self?.finishPanelRequest(id: requestID)
                    return
                }
                guard let self, self.finishPanelRequest(id: requestID) else { return }
                self.receiveImageURL(
                    url,
                    allowedContentTypes: allowedContentTypes,
                    client: client,
                    operation: operation,
                    selectionPublisher: selectionPublisher,
                    onSelection: onSelection,
                    shouldRender: shouldRender,
                    skippedRenderFailure: skippedRenderFailure,
                    renderProvider: renderProvider,
                    render: render
                )
            } catch is CancellationError {
                self?.finishPanelRequest(id: requestID)
            } catch {
                guard let self, self.finishPanelRequest(id: requestID) else { return }
                self.error = FileInputPanelFailure.diagnosticMessage(for: error)
            }
        }
    }

    func receiveImageURL(
        _ url: URL,
        allowedContentTypes: [UTType],
        client: ImageWorkflowClient = ImageWorkflowClient(),
        operation: ImageProcessingOperation,
        selectionPublisher: @escaping ImageSelectionPublisher = { _, publish in publish() },
        onSelection: @escaping (ImageInputSelection) -> Void = { _ in },
        shouldRender: @escaping (ImageInputSelection) -> Bool = { _ in true },
        skippedRenderFailure: ImageWorkflowFailure? = nil,
        renderProvider: ImageBackgroundOutputRendererProvider? = nil,
        render: @escaping ImageBackgroundOutputRenderer
    ) {
        cancelPanelRequest()
        cancelRender()
        source = nil
        output = nil
        outputImage = nil
        error = nil
        isProcessing = true
        let generation = renderGate.token

        selectionTask = Task { @MainActor [weak self] in
            do {
                let selection = try await client.prepareSelectionInBackground(
                    from: url,
                    allowedContentTypes: allowedContentTypes
                )
                guard let self, self.renderGate.isCurrent(generation) else { return }

                selectionPublisher(selection) {
                    self.source = selection
                }
                onSelection(selection)
                self.selectionTask = nil
                if shouldRender(selection) {
                    self.renderInBackground(operation: operation, renderProvider?() ?? render)
                } else {
                    self.output = nil
                    self.outputImage = nil
                    self.isProcessing = false
                    self.error = skippedRenderFailure?.errorDescription
                }
            } catch is CancellationError {
                guard let self, self.renderGate.isCurrent(generation) else { return }
                self.isProcessing = false
                self.selectionTask = nil
            } catch {
                guard let self, self.renderGate.isCurrent(generation) else { return }
                self.isProcessing = false
                self.selectionTask = nil
                self.error = ImageWorkflowFailure.diagnosticMessage(for: error, unknownFailure: .readFailed)
            }
        }
    }

    func rejectImageInput(_ diagnostic: String) {
        cancelPanelRequest()
        cancelRender()
        source = nil
        output = nil
        outputImage = nil
        error = diagnostic
    }

    func render(
        operation: ImageProcessingOperation,
        _ render: ImageProcessedOutputRenderer
    ) {
        error = nil
        guard let source else {
            clearOutput()
            return
        }

        do {
            let nextOutput = try render(source)
            output = nextOutput
            outputImage = NSImage(data: nextOutput.data)
        } catch {
            output = nil
            outputImage = nil
            self.error = ImageWorkflowFailure.diagnosticMessage(
                for: error,
                unknownFailure: .processingFailed(operation)
            )
        }
    }

    func clearOutput() {
        cancelRender()
        output = nil
        outputImage = nil
        error = nil
    }

    func reset() {
        cancelPanelRequest()
        cancelRender()
        source = nil
        output = nil
        outputImage = nil
        error = nil
        isProcessing = false
    }

    func evictHeavyPayloads() {
        reset()
    }

    func renderInBackground(
        operation: ImageProcessingOperation,
        _ render: @escaping ImageBackgroundOutputRenderer
    ) {
        error = nil

        guard let source else {
            clearOutput()
            return
        }

        output = nil
        outputImage = nil
        isProcessing = true
        let generation = renderGate.invalidate()
        let input = ImageProcessingInput(
            data: source.data,
            filenameExtension: source.filenameExtension,
            metadata: source.metadata
        )

        enum RenderOutcome: Sendable {
            case success(ProcessedImage)
            case failure(Error)
            case cancelled
        }

        renderGate.runDetached {
            do {
                try Task.checkCancellation()
                let output = try render(input)
                try Task.checkCancellation()
                return RenderOutcome.success(output)
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failure(error)
            }
        } publish: { [weak self] outcome in
            guard let self, self.renderGate.isCurrent(generation) else { return }
            self.isProcessing = false
            switch outcome {
            case .success(let nextOutput):
                self.output = nextOutput
                self.outputImage = NSImage(data: nextOutput.data)
                self.error = nil
            case .failure(let error):
                self.output = nil
                self.outputImage = nil
                self.error = ImageWorkflowFailure.diagnosticMessage(
                    for: error,
                    unknownFailure: .processingFailed(operation)
                )
            case .cancelled:
                break
            }
        }
    }

    func assessment(for workflow: ImageOutputWorkflow) -> ImageOutputAssessment? {
        output.map { ImageOutputPolicy.assess($0, for: workflow) }
    }

    @discardableResult
    func save(
        workflow: ImageOutputWorkflow,
        defaultBasename: String,
        filePanel: FileInputPanelClient,
        outputPanel: FileOutputPanelClient
    ) async -> ImageSaveOutcome {
        guard !isProcessing, let output else { return .cancelled }
        let assessment = ImageOutputPolicy.assess(output, for: workflow)
        let client = ImageWorkflowClient(dialog: SheetImageWorkflowDialog(filePanel: filePanel, outputPanel: outputPanel))

        do {
            let didSave = try await client.saveProcessedImage(
                output,
                assessment: assessment,
                defaultBasename: defaultBasename
            )
            // A dismissed save panel returns false without throwing; keep any
            // prior diagnostic untouched and report a silent cancellation.
            guard didSave else { return .cancelled }
            error = nil
            return .saved
        } catch ImageWorkflowFailure.blockedCompressionSave {
            // Blocked saves are a persistent state the user resolves by changing
            // parameters, so they stay in the inline workspace diagnostic.
            error = ImageWorkflowFailure.blockedCompressionSave.errorDescription
            return .blocked
        } catch {
            // A real write failure is a transient action result: surface it as a
            // toast and do not leave it lingering in the inline diagnostic.
            self.error = nil
            return .failed(ImageWorkflowFailure.diagnosticMessage(for: error, unknownFailure: .saveFailed))
        }
    }

    private func cancelRender() {
        selectionTask?.cancel()
        selectionTask = nil
        isProcessing = false
        renderGate.invalidate()
    }

    @discardableResult
    private func finishPanelRequest(id: UUID) -> Bool {
        guard activePanelRequestID == id else { return false }
        activePanelRequestID = nil
        panelTask = nil
        return true
    }

    private func cancelPanelRequest() {
        activePanelRequestID = nil
        panelTask?.cancel()
        panelTask = nil
    }
}

