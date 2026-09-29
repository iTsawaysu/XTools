import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import XToolsCore

struct MarkdownRemoteImageTests {
    private let url = URL(string: "https://images.example.com/picture.png")!

    @Test func downloadsBoundedRasterDataAndProducesAnEagerThumbnail() async throws {
        let data = try makePreviewPNG(width: 96, height: 48)
        let budget = MarkdownRemoteImageBudget(thumbnailDimension: 24)
        let client = ImageFixtureClient { request, limit in
            #expect(limit == budget.encodedByteLimit)
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
            #expect(request.httpShouldHandleCookies == false)
            #expect(request.value(forHTTPHeaderField: "Accept") == "image/*")
            return (data, imageResponse(request.url!))
        }
        let result = try await MarkdownRemoteImageService(client: client, budget: budget).load(url)
        #expect(result.image.width == 24)
        #expect(result.image.height == 12)
        #expect(result.decodedByteCount == result.image.bytesPerRow * result.image.height)
        #expect(result.decodedByteCount <= budget.imageDecodedByteLimit)
    }

    @Test func invalidURLsNeverReachTheInjectedTransport() async {
        let client = ImageFixtureClient { _, _ in
            Issue.record("Invalid image URL reached transport")
            throw MarkdownRemoteImageError.requestFailed
        }
        let service = MarkdownRemoteImageService(client: client)
        for address in ["file:///tmp/private.png", "http://127.0.0.1/a.png", "https://user:secret@example.com/a.png"] {
            await #expect(throws: MarkdownRemoteImageError.deniedURL) {
                _ = try await service.load(URL(string: address)!)
            }
        }
    }

    @Test func validatesStatusMIMEFinalURLAndEncodedBytes() async throws {
        let data = try makePreviewPNG()
        let cases: [(HTTPURLResponse, MarkdownRemoteImageError)] = [
            (imageResponse(url, status: 404), .requestFailed),
            (imageResponse(url, mime: "text/html"), .unsupportedContentType),
            (imageResponse(url, mime: "image/svg+xml"), .unsupportedContentType),
            (imageResponse(URL(string: "http://10.0.0.1/a.png")!), .deniedURL)
        ]
        for (response, error) in cases {
            let service = MarkdownRemoteImageService(client: ImageFixtureClient { _, _ in (data, response) })
            await #expect(throws: error) { _ = try await service.load(url) }
        }
        let service = MarkdownRemoteImageService(
            client: ImageFixtureClient { _, _ in (data, imageResponse(url)) },
            budget: .init(encodedByteLimit: 8)
        )
        await #expect(throws: MarkdownRemoteImageError.encodedByteLimit) {
            _ = try await service.load(url)
        }
    }

    @Test func transportFailuresDoNotEchoArbitraryPayloads() async {
        let client = ImageFixtureClient { _, _ in
            throw NSError(domain: "secret-user-token", code: 17)
        }
        await #expect(throws: MarkdownRemoteImageError.requestFailed) {
            _ = try await MarkdownRemoteImageService(client: client).load(url)
        }
        let messages: [MarkdownRemoteImageError] = [
            .deniedURL, .requestFailed, .unsupportedContentType, .encodedByteLimit,
            .sourcePixelLimit, .unreadableImage, .decodedByteLimit, .scopeBudget
        ]
        for error in messages {
            #expect(!error.message.contains("secret-user-token"))
        }
    }

    @Test func preservesTransportLimitAndCancellationCategories() async {
        let limited = ImageFixtureClient { _, limit in
            throw HTMLToMarkdownURLFetchError.responseTooLarge(limit)
        }
        await #expect(throws: MarkdownRemoteImageError.encodedByteLimit) {
            _ = try await MarkdownRemoteImageService(client: limited).load(url)
        }
        let cancelled = ImageFixtureClient { _, _ in throw CancellationError() }
        await #expect(throws: CancellationError.self) {
            _ = try await MarkdownRemoteImageService(client: cancelled).load(url)
        }
    }

    @Test func checksMetadataBeforeDecompressionAndUsesOverflowSafeDimensions() throws {
        let data = try makePreviewPNG(width: 64, height: 64)
        #expect(throws: MarkdownRemoteImageError.sourcePixelLimit) {
            _ = try MarkdownRemoteImageService.decode(data, budget: .init(sourcePixelLimit: 1024))
        }
        let largeImage = try makePreviewPNGAbovePixelLimit()
        let source = try #require(CGImageSourceCreateWithData(largeImage as CFData, nil))
        let metadata = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(metadata[kCGImagePropertyPixelWidth] as? Int == 5000)
        #expect(metadata[kCGImagePropertyPixelHeight] as? Int == 4001)
        #expect(largeImage.count < MarkdownRemoteImageBudget().encodedByteLimit)
        #expect(throws: MarkdownRemoteImageError.sourcePixelLimit) {
            _ = try MarkdownRemoteImageService.decode(largeImage, budget: .init())
        }
        for dimensions in [(Int.max, 2), (0, 1), (-1, 1)] {
            #expect(throws: MarkdownRemoteImageError.sourcePixelLimit) {
                try MarkdownRemoteImageService.validateDimensions(
                    width: dimensions.0, height: dimensions.1, budget: .init()
                )
            }
        }
        #expect(throws: MarkdownRemoteImageError.decodedByteLimit) {
            _ = try MarkdownRemoteImageService.decode(data, budget: .init(imageDecodedByteLimit: 4))
        }
        #expect(throws: MarkdownRemoteImageError.unreadableImage) {
            _ = try MarkdownRemoteImageService.decode(Data("not a bitmap".utf8), budget: .init())
        }
    }

    @Test func memoizesDuplicatesAndFailuresWithoutCrossingAuthorizationScopes() async throws {
        let fixture = try MarkdownRemoteImageService.decode(makePreviewPNG(), budget: .init())
        let recorder = ImageLoadRecorder()
        let loader: @Sendable (URL) async throws -> MarkdownRemoteImage = { requested in
            await recorder.record(requested)
            if requested.path.contains("bad") { throw MarkdownRemoteImageError.unreadableImage }
            return fixture
        }
        let first = MarkdownRemoteImageSession(loader: loader)
        _ = try await first.image(for: url)
        _ = try await first.image(for: url)
        let bad = url.appendingPathComponent("bad")
        for _ in 0..<2 {
            await #expect(throws: MarkdownRemoteImageError.unreadableImage) {
                _ = try await first.image(for: bad)
            }
        }
        #expect(await recorder.requestCount == 2)
        let second = MarkdownRemoteImageSession(loader: loader)
        _ = try await second.image(for: url)
        #expect(await recorder.requestCount == 3)
        first.cancel()
        await #expect(throws: CancellationError.self) { _ = try await first.image(for: url) }
        _ = try await second.image(for: url)
        #expect(await recorder.requestCount == 3)
        second.cancel()
    }

    @Test func boundsConcurrencyAndUniqueURLAdmission() async throws {
        let fixture = try MarkdownRemoteImageService.decode(makePreviewPNG(), budget: .init())
        let recorder = ImageLoadRecorder()
        let session = MarkdownRemoteImageSession(
            budget: .init(maximumURLs: 6, maximumConcurrentLoads: 2),
            loader: { requested in
                await recorder.start(requested)
                try await Task.sleep(for: .milliseconds(20))
                await recorder.finish()
                return fixture
            }
        )
        let urls = (0..<6).map { url.appendingPathComponent(String($0)) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for requested in urls { group.addTask { _ = try await session.image(for: requested) } }
            try await group.waitForAll()
        }
        #expect(await recorder.peakActive == 2)
        #expect(await recorder.requestCount == 6)
        await #expect(throws: MarkdownRemoteImageError.scopeBudget) {
            _ = try await session.image(for: url.appendingPathComponent("seventh"))
        }
        #expect(await recorder.requestCount == 6)
        #expect(await session.resourceUsage.urlCount == 6)
        session.cancel()
    }

    @Test func decodedCacheHasAnAggregateLimitAndDoesNotEvictIntoLiveViews() async throws {
        let fixture = try MarkdownRemoteImageService.decode(makePreviewPNG(), budget: .init())
        let recorder = ImageLoadRecorder()
        let session = MarkdownRemoteImageSession(
            budget: .init(scopeDecodedByteLimit: fixture.decodedByteCount),
            loader: { requested in await recorder.record(requested); return fixture }
        )
        _ = try await session.image(for: url)
        let other = url.appendingPathComponent("second")
        for _ in 0..<2 {
            await #expect(throws: MarkdownRemoteImageError.scopeBudget) {
                _ = try await session.image(for: other)
            }
        }
        _ = try await session.image(for: url)
        #expect(await recorder.requestCount == 2)
        #expect(await session.resourceUsage.decodedBytes == fixture.decodedByteCount)
        await session.invalidate()
        #expect(await session.resourceUsage.decodedBytes == 0)
        #expect(await session.resourceUsage.urlCount == 0)
    }

    @Test func scopeCancellationCancelsActiveLoadsAndDrainsQueuedRequests() async throws {
        let fixture = try MarkdownRemoteImageService.decode(makePreviewPNG(), budget: .init())
        let recorder = ImageLoadRecorder()
        let session = MarkdownRemoteImageSession(
            budget: .init(maximumConcurrentLoads: 2),
            loader: { requested in
                await recorder.start(requested)
                do { try await Task.sleep(for: .seconds(30)) }
                catch { await recorder.recordCancellation(); throw error }
                return fixture
            }
        )
        let pending = (0..<5).map { index in
            Task { try await session.image(for: url.appendingPathComponent(String(index))) }
        }
        for _ in 0..<100 {
            if await session.resourceUsage.queued == 3 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await session.resourceUsage.queued == 3, "All requests must enter the bounded queue")
        session.cancel()
        #expect(session.isCancelled, "Publication is revoked synchronously")
        for request in pending {
            await #expect(throws: CancellationError.self) { _ = try await request.value }
        }
        #expect(await recorder.requestCount == 2)
        #expect(await recorder.cancellations == 2)
        #expect(await session.resourceUsage.queued == 0)
        #expect(await session.resourceUsage.active == 0)
    }

    @Test func uncooperativeLateCompletionCannotRefillCancelledCache() async throws {
        let fixture = try MarkdownRemoteImageService.decode(makePreviewPNG(), budget: .init())
        let suspended = SuspendedImageFixture()
        let session = MarkdownRemoteImageSession(loader: { _ in
            await suspended.wait()
            return fixture
        })
        let pending = Task { try await session.image(for: url) }
        for _ in 0..<100 {
            if await suspended.started { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await suspended.started)
        await session.invalidate()
        await suspended.release()
        await #expect(throws: CancellationError.self) { _ = try await pending.value }
        #expect(await session.resourceUsage.decodedBytes == 0)
        #expect(await session.resourceUsage.urlCount == 0)
    }
}

private struct ImageFixtureClient: HTMLToMarkdownURLFetchClient {
    let body: @Sendable (URLRequest, Int) async throws -> (Data, URLResponse)
    func fetchData(for request: URLRequest, byteLimit: Int) async throws -> (Data, URLResponse) {
        try await body(request, byteLimit)
    }
}

private func imageResponse(_ url: URL, status: Int = 200, mime: String = "image/png") -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": mime])!
}

private func makePreviewPNG(width: Int = 8, height: Int = 8) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

/// A complete 20,005,000-pixel PNG, generated through ImageIO rather than a
/// forged header. One-bit grayscale keeps fixture construction near 2.5 MiB.
private func makePreviewPNGAbovePixelLimit() throws -> Data {
    let width = 5000
    let height = 4001
    let bytesPerRow = (width + 7) / 8
    let pixels = Data(repeating: 0, count: bytesPerRow * height)
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let image = try #require(CGImage(
        width: width, height: height, bitsPerComponent: 1, bitsPerPixel: 1,
        bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    ))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return data as Data
}

private actor ImageLoadRecorder {
    var requestCount = 0
    var active = 0
    var peakActive = 0
    var cancellations = 0
    func record(_ url: URL) { requestCount += 1 }
    func start(_ url: URL) { record(url); active += 1; peakActive = max(peakActive, active) }
    func finish() { active -= 1 }
    func recordCancellation() { cancellations += 1; active -= 1 }
}

private actor SuspendedImageFixture {
    var started = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        started = true
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
