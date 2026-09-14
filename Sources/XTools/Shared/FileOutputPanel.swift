import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct FileOutputPanelRequest: Sendable {
    var defaultFilename: String?
    let allowedContentTypes: [UTType]
    let prompt: String?
    let title: String?
    let message: String?

    init(
        defaultFilename: String? = nil,
        allowedContentTypes: [UTType],
        prompt: String? = nil,
        title: String? = nil,
        message: String? = nil
    ) {
        self.defaultFilename = defaultFilename
        self.allowedContentTypes = allowedContentTypes
        self.prompt = prompt
        self.title = title
        self.message = message
    }
}

enum FileOutputPanelFailure: Error, Equatable, LocalizedError {
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
        if let failure = error as? FileOutputPanelFailure,
           let message = failure.errorDescription {
            return message
        }
        return FileOutputPanelFailure.windowUnavailable.errorDescription ?? "暂时无法打开文件选择器。"
    }
}

struct FileOutputPanelClient: Sendable {
    private let selectAction: @MainActor @Sendable (FileOutputPanelRequest) async throws -> URL?

    init(
        select: @escaping @MainActor @Sendable (FileOutputPanelRequest) async throws -> URL?
    ) {
        selectAction = select
    }

    @MainActor
    func selectFile(_ request: FileOutputPanelRequest) async throws -> URL? {
        try await selectAction(request)
    }

    static let unavailable = FileOutputPanelClient { _ in
        throw FileOutputPanelFailure.windowUnavailable
    }
}

enum FileOutputPanelBackendResult {
    case selected(URL?)
    case cancelled
}

@MainActor
protocol FileOutputPanelBackend: AnyObject {
    func configure(for request: FileOutputPanelRequest)
    func beginSheetModal(
        for window: NSWindow,
        completion: @escaping @MainActor (FileOutputPanelBackendResult) -> Void
    )
    func cancel()
}

@MainActor
final class FileOutputPanelCoordinator: ObservableObject {
    typealias BackendFactory = @MainActor () -> any FileOutputPanelBackend

    private struct ActiveRequest {
        let id: UUID
        let continuation: CheckedContinuation<URL?, any Error>
    }

    private let backendFactory: BackendFactory
    private weak var owningWindow: NSWindow?
    private var backend: (any FileOutputPanelBackend)?
    private var activeRequest: ActiveRequest?

    init(
        backendFactory: @escaping BackendFactory = { AppKitSaveFilePanelBackend() }
    ) {
        self.backendFactory = backendFactory
    }

    var client: FileOutputPanelClient {
        FileOutputPanelClient { [weak self] request in
            guard let self else {
                throw FileOutputPanelFailure.windowUnavailable
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

    func selectFile(_ request: FileOutputPanelRequest) async throws -> URL? {
        try Task.checkCancellation()
        guard activeRequest == nil else {
            throw FileOutputPanelFailure.requestInProgress
        }
        guard let owningWindow else {
            throw FileOutputPanelFailure.windowUnavailable
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

    private func resolvedBackend() -> any FileOutputPanelBackend {
        if let backend {
            return backend
        }

        let backend = backendFactory()
        self.backend = backend
        return backend
    }

    private func finishRequest(id: UUID, result: FileOutputPanelBackendResult) {
        guard let request = takeActiveRequest(id: id) else { return }

        switch result {
        case .selected(let url):
            guard let url else {
                request.continuation.resume(throwing: FileOutputPanelFailure.invalidSelection)
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
private final class AppKitSaveFilePanelBackend: FileOutputPanelBackend {
    private let panel: NSSavePanel

    init(panel: NSSavePanel = NSSavePanel()) {
        self.panel = panel
    }

    func configure(for request: FileOutputPanelRequest) {
        if let defaultFilename = request.defaultFilename {
            panel.nameFieldStringValue = defaultFilename
        }
        panel.canCreateDirectories = false
        panel.allowedContentTypes = request.allowedContentTypes
        panel.allowsOtherFileTypes = false
        panel.prompt = request.prompt
        panel.title = request.title ?? ""
        panel.message = request.message
        panel.delegate = nil
        panel.accessoryView = nil
        panel.treatsFilePackagesAsDirectories = false
    }

    func beginSheetModal(
        for window: NSWindow,
        completion: @escaping @MainActor (FileOutputPanelBackendResult) -> Void
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



private struct FileOutputPanelClientKey: EnvironmentKey {
    static let defaultValue = FileOutputPanelClient.unavailable
}

extension EnvironmentValues {
    var fileOutputPanelClient: FileOutputPanelClient {
        get { self[FileOutputPanelClientKey.self] }
        set { self[FileOutputPanelClientKey.self] = newValue }
    }
}

struct FileOutputPanelWindowBinder: NSViewRepresentable {
    let coordinator: FileOutputPanelCoordinator

    func makeNSView(context _: Context) -> FileOutputPanelWindowView {
        FileOutputPanelWindowView(coordinator: coordinator)
    }

    func updateNSView(_ nsView: FileOutputPanelWindowView, context _: Context) {
        nsView.updateCoordinator(coordinator)
    }

    static func dismantleNSView(
        _ nsView: FileOutputPanelWindowView,
        coordinator _: ()
    ) {
        nsView.detach()
    }
}

@MainActor
final class FileOutputPanelWindowView: NSView {
    private var panelCoordinator: FileOutputPanelCoordinator
    private weak var observedWindow: NSWindow?

    init(coordinator: FileOutputPanelCoordinator) {
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

    func updateCoordinator(_ coordinator: FileOutputPanelCoordinator) {
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
