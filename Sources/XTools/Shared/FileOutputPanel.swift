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
        throw FileInputPanelFailure.windowUnavailable
    }
}

typealias FileOutputPanelBackendResult = FilePanelSheetResult<URL?>

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
final class FileOutputPanelCoordinator: ObservableObject, FilePanelWindowAttaching {
    private let core: FilePanelSheetRequestCore<URL?>
    private let backendFactory: @MainActor () -> any FileOutputPanelBackend
    private var backend: (any FileOutputPanelBackend)?

    init(
        backendFactory: @escaping @MainActor () -> any FileOutputPanelBackend = { AppKitSaveFilePanelBackend() }
    ) {
        self.backendFactory = backendFactory
        core = FilePanelSheetRequestCore(acceptsPayload: { $0 != nil })
    }

    var client: FileOutputPanelClient {
        FileOutputPanelClient { [weak self] request in
            guard let self else {
                throw FileInputPanelFailure.windowUnavailable
            }
            return try await self.selectFile(request)
        }
    }

    func attach(to window: NSWindow) {
        core.attach(to: window)
    }

    func detach(from window: NSWindow) {
        core.detach(from: window)
    }

    func selectFile(_ request: FileOutputPanelRequest) async throws -> URL? {
        // present 的续体类型是 URL??（取消为外层 nil）：压平成调用方期望的 URL?。
        try await core.present { [self] in
            let backend = resolvedBackend()
            backend.configure(for: request)
            return FilePanelSheetSession(
                present: { window, completion in
                    backend.beginSheetModal(for: window, completion: completion)
                },
                cancel: { backend.cancel() }
            )
        }.flatMap { $0 }
    }

    private func resolvedBackend() -> any FileOutputPanelBackend {
        if let backend {
            return backend
        }

        let backend = backendFactory()
        self.backend = backend
        return backend
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

typealias FileOutputPanelWindowBinder = FilePanelWindowBinder<FileOutputPanelCoordinator>
