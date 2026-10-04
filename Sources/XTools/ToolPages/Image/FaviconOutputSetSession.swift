import AppKit
import Combine
import XToolsCore
import Foundation

struct FaviconOutputSpec: Hashable, Sendable {
    let size: Int
}

typealias FaviconIconSetGenerator = @Sendable (_ data: Data, _ sizes: [Int]) throws -> [GeneratedIcon]

@MainActor
final class FaviconOutputSetSession: ObservableObject, ToolWorkspacePayloadEvicting {
    static let workspaceKey = ToolWorkspaceKey<FaviconOutputSetSession>(toolID: "image-tools", slot: "favicon") { _ in
        FaviconOutputSetSession()
    }

    static let defaultOutputSpecs: [FaviconOutputSpec] = [
        FaviconOutputSpec(size: 16),
        FaviconOutputSpec(size: 32),
        FaviconOutputSpec(size: 48),
        FaviconOutputSpec(size: 180),
        FaviconOutputSpec(size: 192),
        FaviconOutputSpec(size: 512)
    ]

    @Published private(set) var source: ImageInputSelection?
    @Published private(set) var icons: [GeneratedIcon] = []
    @Published private(set) var package: FaviconPackage?
    @Published private(set) var error: String?
    @Published private(set) var isProcessing = false

    let outputSpecs: [FaviconOutputSpec]

    private var panelRequests = PanelRequestBox()
    private var selectionTask: Task<Void, Never>?
    private let workGate = AsyncWorkGate()

    init(outputSpecs: [FaviconOutputSpec] = FaviconOutputSetSession.defaultOutputSpecs) {
        self.outputSpecs = outputSpecs
    }

    deinit {
        panelRequests.cancel()
        selectionTask?.cancel()
    }

    var sourceImage: NSImage? {
        source?.image
    }

    var sourceURL: URL? {
        source?.url
    }

    func icon(for outputSpec: FaviconOutputSpec) -> GeneratedIcon? {
        icons.first { $0.size == outputSpec.size }
    }

    func artifact(_ id: FaviconArtifactID) -> FaviconArtifact? {
        package?.artifact(id)
    }

    var sourceWarning: String? {
        source.map(\.metadata).flatMap(FaviconPackageBuilder.sourceWarning(metadata:))
    }

    /// 选择 Favicon 源图片并生成部署包。`selectionPublisher`/`generator`
    /// 缺省时与 `ImageProcessedOutputSession` 同风格：发布事务直接放行、
    /// 使用默认图标生成器（测试可用自定义 generator 收窄生成面）。
    func selectImage(
        filePanel: FileInputPanelClient,
        client: ImageWorkflowClient = ImageWorkflowClient(),
        selectionPublisher: @escaping ImageSelectionPublisher = { _, publish in publish() },
        generator: @escaping FaviconIconSetGenerator = FaviconOutputSetSession.generateIcons
    ) {
        panelRequests.request(
            {
                try await filePanel.selectFile(
                    FileInputPanelRequest(
                        allowedContentTypes: ImageWorkflowClient.faviconInputContentTypes
                    )
                )
            },
            onSuccess: { [weak self] url in
                self?.receiveImageURL(
                    url,
                    client: client,
                    selectionPublisher: selectionPublisher,
                    generator: generator
                )
            },
            onError: { [weak self] message in
                self?.error = message
            }
        )
    }

    /// 接收拖放/面板路径的图片 URL 并生成部署包；参数缺省语义同 selectImage。
    func receiveImageURL(
        _ url: URL,
        client: ImageWorkflowClient = ImageWorkflowClient(),
        selectionPublisher: @escaping ImageSelectionPublisher = { _, publish in publish() },
        generator: @escaping FaviconIconSetGenerator = FaviconOutputSetSession.generateIcons
    ) {
        panelRequests.cancel()
        cancelGeneration()
        source = nil
        icons = []
        package = nil
        error = nil
        isProcessing = true
        let currentGeneration = workGate.token

        selectionTask = Task { @MainActor [weak self] in
            do {
                let selection = try await client.prepareSelectionInBackground(
                    from: url,
                    allowedContentTypes: ImageWorkflowClient.faviconInputContentTypes
                )
                guard let self, self.workGate.isCurrent(currentGeneration) else { return }

                selectionPublisher(selection) {
                    self.source = selection
                }
                self.selectionTask = nil
                self.generateIconsInBackground(generator: generator)
            } catch is CancellationError {
                guard let self, self.workGate.isCurrent(currentGeneration) else { return }
                self.isProcessing = false
                self.selectionTask = nil
            } catch {
                guard let self, self.workGate.isCurrent(currentGeneration) else { return }
                self.isProcessing = false
                self.selectionTask = nil
                self.error = ImageWorkflowFailure.diagnosticMessage(for: error, unknownFailure: .readFailed)
            }
        }
    }


    func rejectImageInput(_ diagnostic: String) {
        cancelGeneration()
        source = nil
        icons = []
        package = nil
        error = diagnostic
    }

    func generateIconsInBackground(
        generator: @escaping FaviconIconSetGenerator = FaviconOutputSetSession.generateIcons
    ) {
        error = nil
        icons = []
        package = nil
        isProcessing = false

        guard let source else { return }

        isProcessing = true
        let currentGeneration = workGate.invalidate()
        let sourceData = source.data
        let iconSizes = outputSpecs.map(\.size)

        enum GenerateOutcome: Sendable {
            case success([GeneratedIcon])
            case failure(Error)
            case cancelled
        }

        workGate.runDetached {
            do {
                try Task.checkCancellation()
                let icons = try generator(sourceData, iconSizes)
                try Task.checkCancellation()
                return GenerateOutcome.success(icons)
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failure(error)
            }
        } publish: { [weak self] outcome in
            guard let self, self.workGate.isCurrent(currentGeneration) else { return }
            self.isProcessing = false
            switch outcome {
            case .success(let icons):
                self.icons = icons
                if Set(icons.map(\.size)).isSuperset(of: FaviconPackageBuilder.requiredSizes) {
                    do {
                        self.package = try FaviconPackageBuilder.build(icons: icons)
                        self.error = nil
                    } catch {
                        self.icons = []
                        self.package = nil
                        self.error = ImageWorkflowFailure.diagnosticMessage(
                            for: error,
                            unknownFailure: .processingFailed(.favicon)
                        )
                    }
                } else {
                    // Custom generation specs are retained as a narrow test
                    // seam. Production defaults always publish a complete
                    // deployment package atomically.
                    self.package = nil
                    self.error = nil
                }
            case .failure(let error):
                self.icons = []
                self.package = nil
                self.error = ImageWorkflowFailure.diagnosticMessage(
                    for: error,
                    unknownFailure: .processingFailed(.favicon)
                )
            case .cancelled:
                break
            }
        }
    }

    @discardableResult
    func saveArtifact(
        _ id: FaviconArtifactID,
        filePanel: FileInputPanelClient,
        outputPanel: FileOutputPanelClient
    ) async -> ImageSaveOutcome {
        let client = ImageWorkflowClient.sheet(filePanel: filePanel, outputPanel: outputPanel)
        guard let artifact = package?.artifact(id) else { return .blocked }
        do {
            guard try await client.saveArtifact(artifact) else { return .cancelled }
            error = nil
            return .saved
        } catch {
            self.error = nil
            return .failed(ImageWorkflowFailure.diagnosticMessage(for: error, unknownFailure: .saveFailed))
        }
    }

    @discardableResult
    func savePackage(
        filePanel: FileInputPanelClient,
        outputPanel: FileOutputPanelClient
    ) async -> ImageSaveOutcome {
        guard let package else { return .blocked }
        let client = ImageWorkflowClient.sheet(filePanel: filePanel, outputPanel: outputPanel)
        do {
            guard try await client.saveArtifacts(package.saveableArtifacts) else { return .cancelled }
            error = nil
            return .saved
        } catch let failure as ImageWorkflowFailure {
            self.error = nil
            if case let .partialSaveFailed(savedCount, totalCount) = failure {
                return .partiallySaved(savedCount: savedCount, totalCount: totalCount)
            }
            return .failed(ImageWorkflowFailure.diagnosticMessage(for: failure, unknownFailure: .saveFailed))
        } catch {
            self.error = nil
            return .failed(ImageWorkflowFailure.diagnosticMessage(for: error, unknownFailure: .saveFailed))
        }
    }

    func reset() {
        cancelGeneration()
        source = nil
        icons = []
        package = nil
        error = nil
    }

    func evictHeavyPayloads() {
        reset()
    }

    func cancelGeneration() {
        panelRequests.cancel()
        selectionTask?.cancel()
        selectionTask = nil
        isProcessing = false
        workGate.invalidate()
    }


    nonisolated static func generateIcons(data: Data, sizes: [Int]) throws -> [GeneratedIcon] {
        try ImageProcessor.generateIcons(data: data, sizes: sizes)
    }

}
