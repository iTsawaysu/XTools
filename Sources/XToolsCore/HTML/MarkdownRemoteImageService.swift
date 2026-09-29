import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Preview budgets, separate from user-initiated image conversion/export limits.
/// A scope retains at most 32 URLs and 32 MiB of decoded bitmaps. Downloads and
/// transient decoding are also bounded by the three-operation concurrency cap.
public struct MarkdownRemoteImageBudget: Equatable, Sendable {
    public let encodedByteLimit: Int
    public let sourcePixelLimit: Int
    public let thumbnailDimension: Int
    public let imageDecodedByteLimit: Int
    public let scopeDecodedByteLimit: Int
    public let maximumURLs: Int
    public let maximumConcurrentLoads: Int

    public init(
        encodedByteLimit: Int = 5 * 1024 * 1024,
        sourcePixelLimit: Int = 20_000_000,
        thumbnailDimension: Int = 2048,
        imageDecodedByteLimit: Int = 16 * 1024 * 1024,
        scopeDecodedByteLimit: Int = 32 * 1024 * 1024,
        maximumURLs: Int = 32,
        maximumConcurrentLoads: Int = 3
    ) {
        self.encodedByteLimit = max(1, min(encodedByteLimit, 5 * 1024 * 1024))
        self.sourcePixelLimit = max(1, min(sourcePixelLimit, 20_000_000))
        self.thumbnailDimension = max(1, min(thumbnailDimension, 2048))
        self.imageDecodedByteLimit = max(1, min(imageDecodedByteLimit, 16 * 1024 * 1024))
        self.scopeDecodedByteLimit = max(1, min(scopeDecodedByteLimit, 32 * 1024 * 1024))
        self.maximumURLs = max(1, min(maximumURLs, 32))
        self.maximumConcurrentLoads = max(1, min(maximumConcurrentLoads, 3))
    }
}

public enum MarkdownRemoteImageError: Error, Equatable, Sendable {
    case deniedURL
    case requestFailed
    case unsupportedContentType
    case encodedByteLimit
    case sourcePixelLimit
    case unreadableImage
    case decodedByteLimit
    case scopeBudget

    public var message: String {
        switch self {
        case .deniedURL: "图片地址未获准加载。"
        case .requestFailed: "远程图片加载失败。"
        case .unsupportedContentType: "响应不是支持的栅格图片。"
        case .encodedByteLimit: "图片文件超过预览大小上限。"
        case .sourcePixelLimit: "图片像素数量超过预览上限。"
        case .unreadableImage: "图片数据无法解码。"
        case .decodedByteLimit: "图片解码内存超过预览上限。"
        case .scopeBudget: "当前预览的图片数量或内存已达上限。"
        }
    }
}

public struct MarkdownRemoteImage: Sendable {
    public let image: CGImage
    public let decodedByteCount: Int
}

/// No UI, URL logging, shared cache or unbounded data task. The reused transport
/// checks DNS before the initial request and every redirect. As in HTML fetch,
/// DNS preflight is not connection pinning and cannot eliminate rebinding races.
public struct MarkdownRemoteImageService: Sendable {
    private let client: any HTMLToMarkdownURLFetchClient
    public let budget: MarkdownRemoteImageBudget

    public init(
        client: any HTMLToMarkdownURLFetchClient = LiveHTMLToMarkdownURLFetchClient(),
        budget: MarkdownRemoteImageBudget = .init()
    ) {
        self.client = client
        self.budget = budget
    }

    public func load(_ url: URL) async throws -> MarkdownRemoteImage {
        try Task.checkCancellation()
        guard Self.isAllowedURL(url) else { throw MarkdownRemoteImageError.deniedURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await client.fetchData(for: request, byteLimit: budget.encodedByteLimit)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw CancellationError() }
            switch error as? HTMLToMarkdownURLFetchError {
            case .responseTooLarge: throw MarkdownRemoteImageError.encodedByteLimit
            case .privateNetworkDisallowed, .invalidURL, .unsupportedScheme:
                throw MarkdownRemoteImageError.deniedURL
            default: throw MarkdownRemoteImageError.requestFailed
            }
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw MarkdownRemoteImageError.requestFailed
        }
        guard let responseURL = response.url, Self.isAllowedURL(responseURL) else {
            throw MarkdownRemoteImageError.deniedURL
        }
        guard let mime = response.mimeType?.lowercased(), Self.rasterMIMETypes.contains(mime) else {
            throw MarkdownRemoteImageError.unsupportedContentType
        }
        return try Self.decode(data, budget: budget)
    }

    private static let rasterMIMETypes: Set<String> = [
        "image/png", "image/jpeg", "image/gif", "image/webp", "image/avif",
        "image/heic", "image/heif", "image/tiff", "image/bmp", "image/x-ms-bmp",
        "image/x-icon", "image/vnd.microsoft.icon"
    ]

    private static func isAllowedURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil, url.user == nil, url.password == nil,
              (try? HTMLToMarkdownURLFetchService.normalizedURL(from: url.absoluteString)) != nil else {
            return false
        }
        return true
    }

    static func validateDimensions(width: Int, height: Int, budget: MarkdownRemoteImageBudget) throws {
        guard let pixels = ImageProcessingBudget.pixelCount(width: width, height: height),
              pixels <= budget.sourcePixelLimit else {
            throw MarkdownRemoteImageError.sourcePixelLimit
        }
    }

    static func decode(_ data: Data, budget: MarkdownRemoteImageBudget) throws -> MarkdownRemoteImage {
        try Task.checkCancellation()
        guard data.count <= budget.encodedByteLimit else { throw MarkdownRemoteImageError.encodedByteLimit }
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [
                kCGImageSourceShouldCache: false
              ] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw MarkdownRemoteImageError.unreadableImage
        }
        guard let sourceType = CGImageSourceGetType(source) as String?,
              let mime = UTType(sourceType)?.preferredMIMEType,
              rasterMIMETypes.contains(mime) else {
            throw MarkdownRemoteImageError.unsupportedContentType
        }
        try validateDimensions(width: width, height: height, budget: budget)
        try Task.checkCancellation()
        // Decode frame zero only. Never fall back to full-size decoding when a
        // thumbnail cannot be produced; that would bypass the display budget.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: budget.thumbnailDimension,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: false
        ] as CFDictionary) else { throw MarkdownRemoteImageError.unreadableImage }
        let cost = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard max(image.width, image.height) <= budget.thumbnailDimension,
              !cost.overflow, cost.partialValue > 0,
              cost.partialValue <= budget.imageDecodedByteLimit else {
            throw MarkdownRemoteImageError.decodedByteLimit
        }
        try Task.checkCancellation()
        return MarkdownRemoteImage(image: image, decodedByteCount: cost.partialValue)
    }
}
