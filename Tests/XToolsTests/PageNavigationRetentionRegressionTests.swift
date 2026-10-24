import AppKit
import Foundation
import os
import SwiftUI
import Testing
@testable import XTools
@testable import XToolsCore

@MainActor
@Suite(.serialized)
struct PageNavigationRetentionRegressionTests {
    @Test func rootNavigationPreservesAllAcceptedImageSlotsAndPendingOutput() async throws {
        let defaults = UserDefaults(suiteName: "PageNavigationRetention.\(UUID())")!
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let model = ShellNavigationModel()
        model.selectedToolID = "image-tools"
        let host = NSHostingView(rootView: RootView(navigation: model, defaults: defaults, workspaceRepository: repository))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await settle(host)

        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: "/retained-image.png")
        let client = ImageWorkflowClient(reader: .constant(data: data))
        let single = repository.model(for: ImageProcessedOutputSession.grayscaleWorkspaceKey)
        let batch = repository.model(for: ImageConverterToolWorkspaceModel.key).session
        let favicon = repository.model(for: FaviconOutputSetSession.workspaceKey)
        let renderGate = DispatchSemaphore(value: 0)
        let renderStarted = OSAllocatedUnfairLock(initialState: false)
        defer { renderGate.signal() }
        single.receiveImageURL(url, allowedContentTypes: [.png], client: client, operation: .grayscale) { input in
            renderStarted.withLock { $0 = true }
            _ = renderGate.wait(timeout: .now() + 5)
            return ProcessedImage(data: input.data, format: .png, pixelWidth: 2, pixelHeight: 2, originalByteCount: input.data.count, quality: nil, wasResized: false)
        }
        batch.receiveImageURLs([url], allowedContentTypes: [.png], client: client)
        favicon.receiveImageURL(url, client: client)
        try await waitUntil { renderStarted.withLock { $0 } && !batch.isImporting && !favicon.isProcessing }
        try #require(single.source != nil)
        try #require(batch.items.count == 1)
        try #require(favicon.package != nil)
        let faviconPackage = favicon.package
        model.selectedToolID = "regex-tester"
        try await settle(host)
        #expect(single.sourceURL == url)
        #expect(single.isProcessing)
        #expect(batch.items.count == 1)
        #expect(favicon.package == faviconPackage)
        renderGate.signal()
        try await waitUntil { !single.isProcessing }
        #expect(single.output?.data == data)
        model.selectedToolID = "image-tools"
        try await settle(host)
        #expect(single.sourceURL == url)
        #expect(single.output?.data == data)
        #expect(batch.items.count == 1)
        #expect(favicon.package == faviconPackage)
    }

    @Test func retainedCronReentryRefreshesReferenceTime() async throws {
        let repository = ToolWorkspaceRepository(defaults: UserDefaults(suiteName: "CronReentry.\(UUID())")!)
        let workspace = repository.model(for: CrontabToolWorkspaceModel.key)
        let host = NSHostingView(rootView: IndexCrontabPage().environmentObject(repository).environment(\.toolPageEntryGeneration, 1))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await settle(host)
        let initial = try #require(workspace.generatedAt)
        host.rootView = IndexCrontabPage().environmentObject(repository).environment(\.toolPageEntryGeneration, 0)
        try await settle(host)
        #expect(workspace.generatedAt == initial)
        host.rootView = IndexCrontabPage().environmentObject(repository).environment(\.toolPageEntryGeneration, 2)
        try await settle(host)
        let refreshed = try #require(workspace.generatedAt)
        #expect(refreshed > initial)
        #expect(workspace.nextRuns.allSatisfy { $0 > initial })
    }

    private func settle<V: View>(_ host: NSHostingView<V>) async throws {
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}
