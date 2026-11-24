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
    @Test func rootNavigationKeepsDiffResultsUntilPressureAndRebuildsBothDrafts() async throws {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let defaults = UserDefaults(suiteName: "DiffNavigationRetention.\(UUID())")!
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let model = RootViewModel()
        model.selectedToolID = "diff"
        let host = NSHostingView(rootView: RootView(viewModel: model, defaults: defaults, workspaceRepository: repository))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await settle(host)

        let json = repository.model(for: IndexJSONDiffSegment.key)
        let text = repository.model(for: IndexTextDiffSegment.key)
        let largeDraft = String(repeating: "0123456789", count: 14_000)
        let jsonLeft = #"{"draft":"\#(largeDraft)","version":1}"#
        let textRight = "\(largeDraft)\nright"
        json.left = jsonLeft
        json.right = #"{"draft":"\#(largeDraft)","version":2}"#
        text.left = "\(largeDraft)\nleft"
        text.right = textRight
        try await waitUntil { !json.diffRows.isEmpty && !text.diffRows.isEmpty }
        let jsonRows = json.diffRows
        let textRows = text.diffRows

        model.selectedToolID = "http-status-codes"
        try await settle(host)
        if !reduceMotion {
            #expect(json.diffRows == jsonRows)
            #expect(text.diffRows == textRows)
            for id: ToolID in ["integer-base-converter", "roman-numeral-converter", "date-calculator"] {
                model.selectedToolID = id
                try await settle(host)
            }
        }
        #expect(json.diffRows == jsonRows)
        #expect(text.diffRows == textRows)
        repository.evictHeavyPayloads { $0 == "diff" }
        try await waitUntil { json.diffRows.isEmpty && text.diffRows.isEmpty }
        #expect(json.left == jsonLeft)
        #expect(text.right == textRight)

        model.selectedToolID = "diff"
        try await settle(host)
        try await waitUntil { !json.diffRows.isEmpty }
        #expect(json.diffRows == jsonRows)
        #expect(text.diffRows.isEmpty)

        repository.model(for: DiffHubWorkspaceModel.key).segment = .text
        try await settle(host)
        try await waitUntil { !text.diffRows.isEmpty }
        #expect(text.diffRows == textRows)
    }

    @Test func memoryPressureStreamKeepsActiveWorkspaceAndClearsOnlyIdleResult() async throws {
        let repository = ToolWorkspaceRepository(defaults: UserDefaults(suiteName: "PagePressure.\(UUID())")!)
        let diff = repository.model(for: IndexTextDiffSegment.key)
        diff.left = "alpha\nbeta"
        diff.right = "alpha\ngamma"
        let regex = repository.model(for: RegexToolWorkspaceModel.key)
        regex.pattern = "[a-z]"
        regex.text = "abc"
        regex.execution.run(pattern: regex.pattern, text: regex.text, flags: regex.flags)
        try await waitUntil { !diff.diffRows.isEmpty && regex.execution.report != nil }

        let (events, continuation) = AsyncStream<Void>.makeStream()
        let host = NSHostingView(rootView: ToolPageStage(target: .tool("diff"), workspaceRepository: repository,
                                                        memoryPressureEvents: events) { _ in Color.clear })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { continuation.finish(); window.close() }
        try await settle(host)

        let displayedRows = diff.diffRows
        continuation.yield(())
        try await waitUntil { regex.execution.report == nil }
        #expect(diff.diffRows == displayedRows)
        #expect(regex.pattern == "[a-z]")
        #expect(regex.text == "abc")
    }

    @Test func rootNavigationPreservesAllAcceptedImageSlotsAndPendingOutput() async throws {
        let defaults = UserDefaults(suiteName: "PageNavigationRetention.\(UUID())")!
        let repository = ToolWorkspaceRepository(defaults: defaults)
        let model = RootViewModel()
        model.selectedToolID = "image-tools"
        let host = NSHostingView(rootView: RootView(viewModel: model, defaults: defaults, workspaceRepository: repository))
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
