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
    let allowsMultipleSelection: Bool

    init(
        allowedContentTypes: [UTType] = [],
        prompt: String? = nil,
        title: String? = nil,
        message: String? = nil,
        canChooseDirectories: Bool = false,
        canChooseFiles: Bool = true,
        allowsMultipleSelection: Bool = false
    ) {
        self.allowedContentTypes = allowedContentTypes
        self.prompt = prompt
        self.title = title
        self.message = message
        self.canChooseDirectories = canChooseDirectories
        self.canChooseFiles = canChooseFiles
        self.allowsMultipleSelection = allowsMultipleSelection
    }
}

struct FileInputPanelClient: Sendable {
    private let selectAction: @MainActor @Sendable (FileInputPanelRequest) async throws -> URL?
    private let selectFilesAction: @MainActor @Sendable (FileInputPanelRequest) async throws -> [URL]?

    init(
        select: @escaping @MainActor @Sendable (FileInputPanelRequest) async throws -> URL?,
        selectFiles: @escaping @MainActor @Sendable (FileInputPanelRequest) async throws -> [URL]? = { _ in
            throw FileInputPanelFailure.windowUnavailable
        }
    ) {
        selectAction = select
        selectFilesAction = selectFiles
    }

    @MainActor
    func selectFile(_ request: FileInputPanelRequest) async throws -> URL? {
        try await selectAction(request)
    }

    @MainActor
    func selectFiles(_ request: FileInputPanelRequest) async throws -> [URL]? {
        try await selectFilesAction(request)
    }

    static let unavailable = FileInputPanelClient { _ in
        throw FileInputPanelFailure.windowUnavailable
    }
}

typealias FileInputPanelBackendResult = FilePanelSheetResult<[URL]>

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
final class FileInputPanelCoordinator: ObservableObject, FilePanelWindowAttaching {
    private let core: FilePanelSheetRequestCore<[URL]>
    private let backendFactory: @MainActor () -> any FileInputPanelBackend
    private var backend: (any FileInputPanelBackend)?

    init(
        backendFactory: @escaping @MainActor () -> any FileInputPanelBackend = { AppKitOpenFilePanelBackend() }
    ) {
        self.backendFactory = backendFactory
        core = FilePanelSheetRequestCore(acceptsPayload: { !$0.isEmpty })
    }

    var client: FileInputPanelClient {
        FileInputPanelClient(
            select: { [weak self] request in
                guard let self else {
                    throw FileInputPanelFailure.windowUnavailable
                }
                return try await self.selectFile(request)
            },
            selectFiles: { [weak self] request in
                guard let self else {
                    throw FileInputPanelFailure.windowUnavailable
                }
                return try await self.selectFiles(request)
            }
        )
    }

    func attach(to window: NSWindow) {
        core.attach(to: window)
    }

    func detach(from window: NSWindow) {
        core.detach(from: window)
    }

    func selectFile(_ request: FileInputPanelRequest) async throws -> URL? {
        try await selectFiles(request)?.first
    }

    /// 多选与单选共用同一 sheet 请求管线：同一时刻仅一个活动请求，
    /// 后端结果统一上报 `panel.urls`，单选语义由本方法在数组上取 first。
    func selectFiles(_ request: FileInputPanelRequest) async throws -> [URL]? {
        try await core.present { [self] in
            let backend = resolvedBackend()
            backend.configure(for: request)
            return FilePanelSheetSession(
                present: { window, completion in
                    backend.beginSheetModal(for: window, completion: completion)
                },
                cancel: { backend.cancel() }
            )
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
        panel.allowsMultipleSelection = request.allowsMultipleSelection
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
            completion(.selected(panel?.urls ?? []))
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

typealias FileInputPanelWindowBinder = FilePanelWindowBinder<FileInputPanelCoordinator>
