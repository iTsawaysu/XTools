import AppKit
import Foundation
import SwiftUI

/// 文件 sheet 面板（NSOpenPanel / NSSavePanel）共用的失败枚举与请求管线骨架。
///
/// 打开与保存两套面板共用同一套请求语义：同一时刻至多一个在途请求；任务取消
/// 或窗口重挂载/卸载会取消当前 sheet 并以 CancellationError 恢复；面板确认但
/// 结果为空时按 invalidSelection 失败。枚举沿用打开面板的历史名，同时是
/// PanelRequestBox 与保存面板的共享失败词汇表。
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

/// 面板 sheet 终局：确认（载荷仍需经空选择校验）或用户取消。
enum FilePanelSheetResult<Payload> {
    case selected(Payload)
    case cancelled
}

/// 一次面板呈现会话：面板特化把已解析、已配置的后端包成呈现/取消钩子。
@MainActor
final class FilePanelSheetSession<Payload: Sendable> {
    let present: @MainActor (NSWindow, @escaping @MainActor (FilePanelSheetResult<Payload>) -> Void) -> Void
    let cancel: @MainActor () -> Void

    init(
        present: @escaping @MainActor (NSWindow, @escaping @MainActor (FilePanelSheetResult<Payload>) -> Void) -> Void,
        cancel: @escaping @MainActor () -> Void
    ) {
        self.present = present
        self.cancel = cancel
    }
}

/// sheet 请求管线骨架：登记 requestID、续体等待、任务取消与窗口重挂载取消、
/// 空选择失败映射。两个 `*Panel.swift` 仅保留面板特化（后端解析/配置、空选择
/// 判定）。
@MainActor
final class FilePanelSheetRequestCore<Payload: Sendable> {
    private struct ActiveRequest {
        let id: UUID
        let continuation: CheckedContinuation<Payload?, any Error>
    }

    /// 面板确认载荷的空选择判定（打开面板：URL 数组非空；保存面板：URL 非 nil）。
    private let acceptsPayload: @MainActor (Payload) -> Bool
    private weak var owningWindow: NSWindow?
    private var activeRequest: ActiveRequest?
    private var activeSession: FilePanelSheetSession<Payload>?

    init(acceptsPayload: @escaping @MainActor (Payload) -> Bool) {
        self.acceptsPayload = acceptsPayload
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

    /// 呈现面板：互斥/窗口守卫通过后执行面板特化的准备闭包（解析并配置后端、
    /// 返回呈现会话），再挂续体等待确认或取消。
    func present(_ prepare: @MainActor () -> FilePanelSheetSession<Payload>) async throws -> Payload? {
        try Task.checkCancellation()
        guard activeRequest == nil else {
            throw FileInputPanelFailure.requestInProgress
        }
        guard let owningWindow else {
            throw FileInputPanelFailure.windowUnavailable
        }

        let session = prepare()
        let requestID = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeRequest = ActiveRequest(id: requestID, continuation: continuation)
                activeSession = session
                session.present(owningWindow) { [weak self] result in
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

    private func finishRequest(id: UUID, result: FilePanelSheetResult<Payload>) {
        guard let request = takeActiveRequest(id: id) else { return }

        switch result {
        case .selected(let payload):
            guard acceptsPayload(payload) else {
                request.continuation.resume(throwing: FileInputPanelFailure.invalidSelection)
                return
            }
            request.continuation.resume(returning: payload)
        case .cancelled:
            request.continuation.resume(returning: nil)
        }
        activeSession = nil
    }

    private func cancelActiveRequest(id: UUID? = nil) {
        guard let request = activeRequest,
              id == nil || request.id == id else {
            return
        }

        activeRequest = nil
        activeSession?.cancel()
        activeSession = nil
        request.continuation.resume(throwing: CancellationError())
    }

    private func takeActiveRequest(id: UUID) -> ActiveRequest? {
        guard let request = activeRequest, request.id == id else { return nil }
        activeRequest = nil
        return request
    }
}

// MARK: - 窗口挂载

/// 窗口绑定视图面向任一面板协调器：协调器只需实现 attach/detach。
@MainActor
protocol FilePanelWindowAttaching: AnyObject {
    func attach(to window: NSWindow)
    func detach(from window: NSWindow)
}

struct FilePanelWindowBinder<PanelCoordinator: FilePanelWindowAttaching>: NSViewRepresentable {
    let coordinator: PanelCoordinator

    func makeNSView(context _: Context) -> FilePanelWindowView<PanelCoordinator> {
        FilePanelWindowView(coordinator: coordinator)
    }

    func updateNSView(_ nsView: FilePanelWindowView<PanelCoordinator>, context _: Context) {
        nsView.updateCoordinator(coordinator)
    }

    static func dismantleNSView(
        _ nsView: FilePanelWindowView<PanelCoordinator>,
        coordinator _: ()
    ) {
        nsView.detach()
    }
}

@MainActor
final class FilePanelWindowView<PanelCoordinator: FilePanelWindowAttaching>: NSView {
    private var panelCoordinator: PanelCoordinator
    private weak var observedWindow: NSWindow?

    init(coordinator: PanelCoordinator) {
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

    func updateCoordinator(_ coordinator: PanelCoordinator) {
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
