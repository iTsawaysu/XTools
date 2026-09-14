import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct FileInputPanelRequest: Sendable {
    let allowedContentTypes: [UTType]
    let prompt: String?
    let title: String?
    let message: String?
    let canChooseDirectories: Bool
    let canChooseFiles: Bool

    init(
        allowedContentTypes: [UTType] = [],
        prompt: String? = nil,
        title: String? = nil,
        message: String? = nil,
        canChooseDirectories: Bool = false,
        canChooseFiles: Bool = true
    ) {
        self.allowedContentTypes = allowedContentTypes
        self.prompt = prompt
        self.title = title
        self.message = message
        self.canChooseDirectories = canChooseDirectories
        self.canChooseFiles = canChooseFiles
    }
}

enum FileInputPanelFailure: Error, Equatable, LocalizedError {
    case windowUnavailable
    case requestInProgress
    case invalidSelection

    var errorDescription: String? {
        switch self {
        case .windowUnavailable:
            return "暂时无法打开文件选择器。"
        case .requestInProgress:
            return "已有文件选择器正在打开。"
        case .invalidSelection:
            return "没有取得可用的文件。"
        }
    }

    static func diagnosticMessage(for error: any Error) -> String {
        if let failure = error as? FileInputPanelFailure,
           let message = failure.errorDescription {
            return message
        }
        return FileInputPanelFailure.windowUnavailable.errorDescription ?? "暂时无法打开文件选择器。"
    }
}

struct FileInputPanelClient: Sendable {
    private let selectAction: @MainActor @Sendable (FileInputPanelRequest) async throws -> URL?

    init(
        select: @escaping @MainActor @Sendable (FileInputPanelRequest) async throws -> URL?
    ) {
        selectAction = select
    }

    @MainActor
    func selectFile(_ request: FileInputPanelRequest) async throws -> URL? {
        try await selectAction(request)
    }

    static let unavailable = FileInputPanelClient { _ in
        throw FileInputPanelFailure.windowUnavailable
    }
}

enum FileInputPanelBackendResult {
    case selected(URL?)
    case cancelled
}

@MainActor
protocol FileInputPanelBackend: AnyObject {
    func configure(for request: FileInputPanelRequest)
    func beginSheetModal(
        for window: NSWindow,
        completion: @escaping @MainActor (FileInputPanelBackendResult) -> Void
    )
    func cancel()
}

@MainActor
final class FileInputPanelCoordinator: ObservableObject {
    typealias BackendFactory = @MainActor () -> any FileInputPanelBackend

    private struct ActiveRequest {
        let id: UUID
        let continuation: CheckedContinuation<URL?, any Error>
    }

    private let backendFactory: BackendFactory
    private weak var owningWindow: NSWindow?
    private var backend: (any FileInputPanelBackend)?
    private var activeRequest: ActiveRequest?

    init(
        backendFactory: @escaping BackendFactory = { AppKitOpenFilePanelBackend() }
    ) {
        self.backendFactory = backendFactory
    }

    var client: FileInputPanelClient {
        FileInputPanelClient { [weak self] request in
            guard let self else {
                throw FileInputPanelFailure.windowUnavailable
            }
            return try await self.selectFile(request)
        }
    }

    func attach(to window: NSWindow) {
        guard owningWindow !== window else { return }
        cancelActiveRequest()
        owningWindow = window
    }

    func detach(from window: NSWindow) {
        guard owningWindow === window else { return }
        cancelActiveRequest()
        owningWindow = nil
    }

    func selectFile(_ request: FileInputPanelRequest) async throws -> URL? {
        try Task.checkCancellation()
        guard activeRequest == nil else {
            throw FileInputPanelFailure.requestInProgress
        }
        guard let owningWindow else {
            throw FileInputPanelFailure.windowUnavailable
        }

        let backend = resolvedBackend()
        backend.configure(for: request)
        let requestID = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeRequest = ActiveRequest(id: requestID, continuation: continuation)
                backend.beginSheetModal(for: owningWindow) { [weak self] result in
                    self?.finishRequest(id: requestID, result: result)
                }

                if Task.isCancelled {
                    cancelActiveRequest(id: requestID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelActiveRequest(id: requestID)
            }
        }
    }

    private func resolvedBackend() -> any FileInputPanelBackend {
        if let backend {
            return backend
        }

        let backend = backendFactory()
        self.backend = backend
        return backend
    }

    private func finishRequest(id: UUID, result: FileInputPanelBackendResult) {
        guard let request = takeActiveRequest(id: id) else { return }

        switch result {
        case .selected(let url):
            guard let url else {
                request.continuation.resume(throwing: FileInputPanelFailure.invalidSelection)
                return
            }
            request.continuation.resume(returning: url)
        case .cancelled:
            request.continuation.resume(returning: nil)
        }
    }

    private func cancelActiveRequest(id: UUID? = nil) {
        guard let request = activeRequest,
              id == nil || request.id == id else {
            return
        }

        activeRequest = nil
        backend?.cancel()
        request.continuation.resume(throwing: CancellationError())
    }

    private func takeActiveRequest(id: UUID) -> ActiveRequest? {
        guard let request = activeRequest, request.id == id else { return nil }
        activeRequest = nil
        return request
    }
}

@MainActor
private final class AppKitOpenFilePanelBackend: FileInputPanelBackend {
    private let panel: NSOpenPanel

    init(panel: NSOpenPanel = NSOpenPanel()) {
        self.panel = panel
    }

    func configure(for request: FileInputPanelRequest) {
        panel.canChooseFiles = request.canChooseFiles
        panel.canChooseDirectories = request.canChooseDirectories
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = request.allowedContentTypes
        panel.allowsOtherFileTypes = false
        panel.prompt = request.prompt
        panel.title = request.title ?? ""
        panel.message = request.message
        panel.delegate = nil
        panel.accessoryView = nil
        panel.isAccessoryViewDisclosed = false
        panel.treatsFilePackagesAsDirectories = false
        panel.resolvesAliases = true
    }

    func beginSheetModal(
        for window: NSWindow,
        completion: @escaping @MainActor (FileInputPanelBackendResult) -> Void
    ) {
        panel.beginSheetModal(for: window) { [weak panel] response in
            guard response == .OK else {
                completion(.cancelled)
                return
            }
            completion(.selected(panel?.url))
        }
    }

    func cancel() {
        panel.cancel(nil)
    }
}

enum SingleFileDropResolution: Equatable {
    case unhandled
    case accepted(URL)
    case rejectedMultipleFiles
}

enum SingleFileDropResolver {
    static let multipleFilesDiagnostic = "一次只能拖入一个文件。"

    static func resolve(_ urls: [URL]) -> SingleFileDropResolution {
        switch urls.count {
        case 0:
            return .unhandled
        case 1:
            return .accepted(urls[0])
        default:
            return .rejectedMultipleFiles
        }
    }
}

private struct FileInputPanelClientKey: EnvironmentKey {
    static let defaultValue = FileInputPanelClient.unavailable
}

extension EnvironmentValues {
    var fileInputPanelClient: FileInputPanelClient {
        get { self[FileInputPanelClientKey.self] }
        set { self[FileInputPanelClientKey.self] = newValue }
    }
}

struct FileInputPanelWindowBinder: NSViewRepresentable {
    let coordinator: FileInputPanelCoordinator

    func makeNSView(context _: Context) -> FileInputPanelWindowView {
        FileInputPanelWindowView(coordinator: coordinator)
    }

    func updateNSView(_ nsView: FileInputPanelWindowView, context _: Context) {
        nsView.updateCoordinator(coordinator)
    }

    static func dismantleNSView(
        _ nsView: FileInputPanelWindowView,
        coordinator _: ()
    ) {
        nsView.detach()
    }
}

@MainActor
final class FileInputPanelWindowView: NSView {
    private var panelCoordinator: FileInputPanelCoordinator
    private weak var observedWindow: NSWindow?

    init(coordinator: FileInputPanelCoordinator) {
        panelCoordinator = coordinator
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportWindowChange()
    }

    func updateCoordinator(_ coordinator: FileInputPanelCoordinator) {
        guard panelCoordinator !== coordinator else { return }
        if let observedWindow {
            panelCoordinator.detach(from: observedWindow)
        }
        panelCoordinator = coordinator
        reportWindowChange()
    }

    func detach() {
        if let observedWindow {
            panelCoordinator.detach(from: observedWindow)
        }
        observedWindow = nil
    }

    private func reportWindowChange() {
        let nextWindow = window
        guard observedWindow !== nextWindow else { return }

        if let observedWindow {
            panelCoordinator.detach(from: observedWindow)
        }
        observedWindow = nextWindow
        if let nextWindow {
            panelCoordinator.attach(to: nextWindow)
        }
    }
}
