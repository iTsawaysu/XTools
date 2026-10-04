import AppKit
import Combine
import XToolsCore
import Foundation
import UniformTypeIdentifiers

/// 列表中单张图片的转换状态。
enum ItemConversionState: Equatable {
    case idle
    case converting
    case done(BatchConversionOutput)
    case failed(String)
}

/// 完成的转换输出：指标摘要常驻内存，重载荷 data 落盘临时目录（spool）。
/// summaryText 与 requiresExplicitLargerSave 在转换完成时基于完整输出预计算
/// （assessment 不存储，避免其内嵌 ProcessedImage 钉住 data）；
/// 保存时从临时文件读取/拷贝，内存不随批量数量增长。
struct BatchConversionOutput: Equatable {
    let format: ImageFileFormat
    let pixelWidth: Int
    let pixelHeight: Int
    let originalByteCount: Int
    let quality: Double?
    let byteCount: Int
    let requiresExplicitLargerSave: Bool
    let summaryText: String
    let tempURL: URL
}

/// 批量转换的一行：URL + 元数据 + 小缩略图。
/// 导入完成后内存中不驻留原图 data；转换时再逐张经 reader 管线重读。
struct BatchConversionItem: Identifiable {
    let id: UUID
    let url: URL
    let filename: String
    let metadata: ImageMetadata
    let thumbnail: NSImage
    var state: ItemConversionState = .idle

    /// 批量保存时的目标文件名主干（原名去扩展；空名回退 converted）。
    var saveBasename: String {
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? "converted" : stem
    }
}

/// 页面拥有导入结果的展示动效：importPublisher 在会话内被调用，
/// publish() 由页面在共享 motion 事务内执行（对齐 ImageSelectionPublisher 的边界）。
typealias BatchConversionImportPublisher = (_ items: [BatchConversionItem], _ publish: () -> Void) -> Void

/// 保存用平台客户端的构造口：生产环境固定走 sheet 面板，测试注入假 writer/dialog。
typealias ImageSaveClientBuilder = @MainActor (
    _ filePanel: FileInputPanelClient,
    _ outputPanel: FileOutputPanelClient
) -> ImageWorkflowClient

/// 转换结果写入临时文件失败的专属标记：渲染/读取错误沿用共享诊断，
/// 仅落盘失败给出稳定专属诊断。
struct OutputSpoolWriteFailure: Error {}

@MainActor
final class ImageBatchConversionSession: ObservableObject, ToolWorkspacePayloadEvicting {
    /// 上限主要约束列表 UI 与保存循环时长；输出落盘后内存与批量数量解耦。
    static let defaultMaximumItemCount = 100

    /// 会话输出落盘子目录（惰性创建）；reset/deinit 删除整个子目录，
    /// App 退出遗留由系统 tmp 策略兜底。
    let spoolDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("xtools-image-converter", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    @Published private(set) var items: [BatchConversionItem] = []
    @Published private(set) var error: String?
    @Published private(set) var isImporting = false
    @Published private(set) var isProcessing = false

    let maximumItemCount: Int

    private var panelRequests = PanelRequestBox()
    private var importTask: Task<Void, Never>?
    private var conversionTask: Task<Void, Never>?
    private let importGate = AsyncWorkGate()
    private let renderGate = AsyncWorkGate()
    /// convertAll 重读磁盘时使用的最近一次导入管线（含 reader 与内容类型）。
    private var workflowClient = ImageWorkflowClient()
    private var allowedInputContentTypes: [UTType] = ImageWorkflowClient.standardImageContentTypes
    private let saveClientBuilder: ImageSaveClientBuilder

    init(
        maximumItemCount: Int = ImageBatchConversionSession.defaultMaximumItemCount,
        saveClientBuilder: @escaping ImageSaveClientBuilder = { filePanel, outputPanel in
            ImageWorkflowClient.sheet(filePanel: filePanel, outputPanel: outputPanel)
        }
    ) {
        self.maximumItemCount = maximumItemCount
        self.saveClientBuilder = saveClientBuilder
    }

    deinit {
        panelRequests.cancel()
        importTask?.cancel()
        conversionTask?.cancel()
        try? FileManager.default.removeItem(at: spoolDirectory)
    }

    // MARK: - Presentation helpers

    var sourceImage: NSImage? {
        items.first?.thumbnail
    }

    var singleItem: BatchConversionItem? {
        items.count == 1 ? items[0] : nil
    }

    var completedCount: Int {
        items.count { item in
            if case .done = item.state { return true }
            return false
        }
    }

    var failedCount: Int {
        items.count { item in
            if case .failed = item.state { return true }
            return false
        }
    }

    // MARK: - Import

    func selectImages(
        filePanel: FileInputPanelClient,
        allowedContentTypes: [UTType],
        client: ImageWorkflowClient = ImageWorkflowClient(),
        importPublisher: @escaping BatchConversionImportPublisher = { _, publish in publish() },
        onImport: @escaping () -> Void = {}
    ) {
        panelRequests.request(
            {
                let urls = try await filePanel.selectFiles(
                    FileInputPanelRequest(
                        allowedContentTypes: allowedContentTypes,
                        allowsMultipleSelection: true
                    )
                )
                return (urls?.isEmpty == false) ? urls : nil
            },
            onSuccess: { [weak self] urls in
                self?.receiveImageURLs(
                    urls,
                    allowedContentTypes: allowedContentTypes,
                    client: client,
                    importPublisher: importPublisher,
                    onImport: onImport
                )
            },
            onError: { [weak self] message in
                self?.error = message
            }
        )
    }

    func receiveImageURLs(
        _ urls: [URL],
        allowedContentTypes: [UTType],
        client: ImageWorkflowClient = ImageWorkflowClient(),
        importPublisher: @escaping BatchConversionImportPublisher = { _, publish in publish() },
        onImport: @escaping () -> Void = {}
    ) {
        guard !urls.isEmpty else { return }
        panelRequests.cancel()
        cancelActiveWork()
        error = nil
        isImporting = true
        workflowClient = client
        allowedInputContentTypes = allowedContentTypes
        let generation = importGate.token

        importTask = Task { @MainActor [weak self] in
            var imported: [BatchConversionItem] = []
            var skipped: [(name: String, reason: String)] = []
            let acceptedCount = max(0, (self?.maximumItemCount ?? 0) - (self?.items.count ?? 0))

            for (index, url) in urls.enumerated() {
                guard let self, self.importGate.isCurrent(generation) else { return }
                guard index < acceptedCount else {
                    skipped.append((name: url.lastPathComponent, reason: "超出 \(self.maximumItemCount) 张上限"))
                    continue
                }
                do {
                    let overview = try await client.prepareImportOverview(
                        from: url,
                        allowedContentTypes: allowedContentTypes
                    )
                    try Task.checkCancellation()
                    guard self.importGate.isCurrent(generation) else { return }
                    guard let thumbnail = NSImage(data: overview.previewData) else {
                        skipped.append((
                            name: url.lastPathComponent,
                            reason: ImageWorkflowFailure.unreadableImage.errorDescription ?? "图片读取失败"
                        ))
                        continue
                    }
                    imported.append(
                        BatchConversionItem(
                            id: UUID(),
                            url: url,
                            filename: url.lastPathComponent,
                            metadata: overview.metadata,
                            thumbnail: thumbnail
                        )
                    )
                } catch is CancellationError {
                    return
                } catch {
                    guard self.importGate.isCurrent(generation) else { return }
                    skipped.append((
                        name: url.lastPathComponent,
                        reason: ImageWorkflowFailure.diagnosticMessage(for: error, unknownFailure: .readFailed)
                    ))
                }
            }

            guard let self, self.importGate.isCurrent(generation) else { return }
            self.isImporting = false
            self.importTask = nil
            if !imported.isEmpty {
                importPublisher(imported) {
                    self.items.append(contentsOf: imported)
                }
            }
            self.error = Self.importSkipSummary(skipped)
            if !imported.isEmpty {
                onImport()
            }
        }
    }

    // MARK: - Conversion

    /// 全量重转：新一轮使上一轮逐张取消（世代取消）；串行逐张读盘转换，
    /// 内存峰值 ≈ 单张。rendererProvider 在循环启动时取最新参数。
    func convertAll(rendererProvider: @escaping @MainActor () -> ImageBackgroundOutputRenderer) {
        guard !items.isEmpty, !isImporting else { return }
        error = nil
        for index in items.indices {
            items[index].state = .idle
        }
        isProcessing = true
        cancelConversionTask()
        let generation = renderGate.invalidate()
        let client = workflowClient
        let allowedContentTypes = allowedInputContentTypes

        conversionTask = Task { @MainActor [weak self] in
            await self?.convertRemaining(
                fromIndex: 0,
                generation: generation,
                client: client,
                allowedContentTypes: allowedContentTypes,
                rendererProvider: rendererProvider
            )
        }
    }

    /// 移除单张后续跑仍待转换的项：同一参数下已完成的输出依然有效，
    /// 不整批重置（与 convertAll 的参数变更全量重转相区分）。
    func convertPendingItems(rendererProvider: @escaping @MainActor () -> ImageBackgroundOutputRenderer) {
        guard !items.isEmpty, !isImporting else { return }
        guard items.contains(where: { $0.state == .idle }) else { return }
        error = nil
        isProcessing = true
        cancelConversionTask()
        let generation = renderGate.invalidate()
        let client = workflowClient
        let allowedContentTypes = allowedInputContentTypes

        conversionTask = Task { @MainActor [weak self] in
            await self?.convertRemaining(
                fromIndex: 0,
                generation: generation,
                client: client,
                allowedContentTypes: allowedContentTypes,
                rendererProvider: rendererProvider,
                skipsSettledItems: true
            )
        }
    }

    func clearOutputs() {
        cancelConversion()
        for index in items.indices {
            if case let .done(output) = items[index].state {
                Self.removeSpooledFile(at: output.tempURL)
            }
            items[index].state = .idle
        }
    }

    func removeItem(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        cancelActiveWork()
        if case let .done(output) = item.state {
            Self.removeSpooledFile(at: output.tempURL)
        }
        items.removeAll { $0.id == id }
    }

    func reset() {
        panelRequests.cancel()
        cancelActiveWork()
        removeSpoolDirectory()
        items = []
        error = nil
    }

    func evictHeavyPayloads() {
        reset()
    }

    // MARK: - Save

    /// N=1 读临时文件走单文件保存面板；N>1 把落盘候选交给批量保存
    /// （选目录后逐张读取写入）。
    @discardableResult
    func saveAll(
        defaultBasename: String,
        filePanel: FileInputPanelClient,
        outputPanel: FileOutputPanelClient
    ) async -> ImageSaveOutcome {
        guard !isImporting, !isProcessing else { return .cancelled }
        let completed = items.compactMap { item -> BatchConversionSaveCandidate? in
            guard case let .done(output) = item.state else { return nil }
            return BatchConversionSaveCandidate(
                basename: item.saveBasename,
                tempURL: output.tempURL,
                format: output.format
            )
        }
        guard !completed.isEmpty else { return .blocked }
        let client = saveClientBuilder(filePanel, outputPanel)

        if completed.count == 1 {
            let candidate = completed[0]
            do {
                // 落盘文件由本会话写出，读取不走输入预算的 reader 管线。
                let data = try Data(contentsOf: candidate.tempURL)
                guard try await client.saveConvertedImage(
                    data: data,
                    format: candidate.format,
                    defaultBasename: defaultBasename
                ) else { return .cancelled }
                error = nil
                return .saved
            } catch {
                self.error = nil
                return .failed(ImageWorkflowFailure.diagnosticMessage(for: error, unknownFailure: .saveFailed))
            }
        }

        do {
            guard try await client.saveConvertedImages(completed) else { return .cancelled }
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

    // MARK: - Private

    private func convertRemaining(
        fromIndex start: Int,
        generation: Int,
        client: ImageWorkflowClient,
        allowedContentTypes: [UTType],
        rendererProvider: @escaping @MainActor () -> ImageBackgroundOutputRenderer,
        skipsSettledItems: Bool = false
    ) async {
        guard renderGate.isCurrent(generation) else { return }
        let render = rendererProvider()
        for index in start..<max(start, items.count) {
            guard renderGate.isCurrent(generation), index < items.count else { return }
            if skipsSettledItems {
                switch items[index].state {
                case .done, .failed:
                    continue
                case .idle, .converting:
                    break
                }
            }
            let itemID = items[index].id
            let url = items[index].url
            items[index].state = .converting
            do {
                let selection = try await client.prepareSelectionInBackground(
                    from: url,
                    allowedContentTypes: allowedContentTypes
                )
                try Task.checkCancellation()
                guard renderGate.isCurrent(generation) else { return }
                let input = ImageProcessingInput(
                    data: selection.data,
                    filenameExtension: selection.filenameExtension,
                    metadata: selection.metadata
                )
                let output = try await Self.renderOffMain(
                    render,
                    input,
                    itemID: itemID,
                    spoolDirectory: spoolDirectory
                )
                try Task.checkCancellation()
                guard renderGate.isCurrent(generation), index < items.count, items[index].url == url else { return }
                items[index].state = .done(output)
            } catch is CancellationError {
                return
            } catch {
                guard renderGate.isCurrent(generation), index < items.count, items[index].url == url else { return }
                items[index].state = .failed(Self.itemFailureMessage(for: error))
            }
        }
        guard renderGate.isCurrent(generation) else { return }
        isProcessing = false
        conversionTask = nil
    }

    /// 后台执行渲染并原子落盘：输出 data 不随结果回主线程，
    /// 内存峰值保持单张。落盘失败按该张失败处理，不阻塞其余。
    private static func renderOffMain(
        _ render: @escaping ImageBackgroundOutputRenderer,
        _ input: ImageProcessingInput,
        itemID: UUID,
        spoolDirectory: URL
    ) async throws -> BatchConversionOutput {
        let worker = Task.detached(priority: .userInitiated) {
            let output = try render(input)
            try Task.checkCancellation()
            let tempURL = spoolDirectory.appendingPathComponent(
                "\(itemID.uuidString).\(output.format.fileExtension)"
            )
            do {
                try FileManager.default.createDirectory(at: spoolDirectory, withIntermediateDirectories: true)
                try output.data.write(to: tempURL, options: [.atomic])
            } catch {
                throw OutputSpoolWriteFailure()
            }
            let assessment = ImageOutputPolicy.assess(output, for: .conversion)
            return BatchConversionOutput(
                format: output.format,
                pixelWidth: output.pixelWidth,
                pixelHeight: output.pixelHeight,
                originalByteCount: output.originalByteCount,
                quality: output.quality,
                byteCount: output.byteCount,
                requiresExplicitLargerSave: assessment.requiresExplicitLargerSave,
                summaryText: ImageOutputPresentation.processingOutputSummary(assessment),
                tempURL: tempURL
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// 渲染/读取错误沿用共享诊断；落盘失败给出稳定专属诊断。
    static func itemFailureMessage(for error: Error) -> String {
        error is OutputSpoolWriteFailure
            ? "转换结果写入临时文件失败。"
            : ImageWorkflowFailure.diagnosticMessage(for: error, unknownFailure: .processingFailed(.conversion))
    }

    /// 跳过项汇总诊断：最多展开两条明细（文件名截断），其余计数。
    static func importSkipSummary(_ skipped: [(name: String, reason: String)]) -> String? {
        guard !skipped.isEmpty else { return nil }
        let details = skipped.map { "\(Self.abbreviatedName($0.name))（\(Self.compactReason($0.reason))）" }
        let shown = details.prefix(2).joined(separator: "、")
        let suffix = skipped.count > 2 ? "等" : ""
        return "已跳过 \(skipped.count) 张：\(shown)\(suffix)。"
    }

    private static func abbreviatedName(_ name: String) -> String {
        guard name.count > 16 else { return name }
        return "\(name.prefix(8))…\(name.suffix(7))"
    }

    private static func compactReason(_ reason: String) -> String {
        reason.hasSuffix("。") ? String(reason.dropLast()) : reason
    }

    private func cancelConversion() {
        cancelConversionTask()
        renderGate.invalidate()
        isProcessing = false
        for index in items.indices {
            if case .converting = items[index].state {
                items[index].state = .idle
            }
        }
    }

    // MARK: - Spool cleanup

    /// 落盘清理不抛错：个别临时文件的残留由系统 tmp 策略兜底。
    private static func removeSpooledFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func removeSpoolDirectory() {
        try? FileManager.default.removeItem(at: spoolDirectory)
    }

    private func cancelConversionTask() {
        conversionTask?.cancel()
        conversionTask = nil
    }

    private func cancelActiveWork() {
        importTask?.cancel()
        importTask = nil
        importGate.invalidate()
        isImporting = false
        cancelConversion()
    }

}
