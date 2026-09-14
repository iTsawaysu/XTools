import Foundation

public enum FaviconArtifactGroup: String, CaseIterable, Codable, Hashable, Sendable {
    case browser
    case apple
    case pwa
    case configuration

    public var displayName: String {
        switch self {
        case .browser: return "Browser"
        case .apple: return "Apple"
        case .pwa: return "PWA"
        case .configuration: return "Configuration"
        }
    }
}

public enum FaviconArtifactID: String, CaseIterable, Codable, Hashable, Sendable {
    case faviconICO = "favicon.ico"
    case appleTouchIcon = "apple-touch-icon.png"
    case webAppManifest192 = "web-app-manifest-192x192.png"
    case webAppManifest512 = "web-app-manifest-512x512.png"
    case siteWebManifest = "site.webmanifest"
}

public struct FaviconArtifact: Equatable, Identifiable, Sendable {
    public let id: FaviconArtifactID
    public let filename: String
    public let mediaType: String
    public let group: FaviconArtifactGroup
    public let purpose: String
    public let details: String
    public let data: Data
    public let previewSizes: [Int]

    public init(
        id: FaviconArtifactID,
        mediaType: String,
        group: FaviconArtifactGroup,
        purpose: String,
        details: String,
        data: Data,
        previewSizes: [Int] = []
    ) {
        self.id = id
        self.filename = id.rawValue
        self.mediaType = mediaType
        self.group = group
        self.purpose = purpose
        self.details = details
        self.data = data
        self.previewSizes = previewSizes
    }
}

public struct FaviconPackage: Equatable, Sendable {
    public let artifacts: [FaviconArtifact]
    public let htmlSnippet: String
    public let iconPreviews: [GeneratedIcon]

    public init(artifacts: [FaviconArtifact], htmlSnippet: String, iconPreviews: [GeneratedIcon]) {
        self.artifacts = artifacts
        self.htmlSnippet = htmlSnippet
        self.iconPreviews = iconPreviews
    }

    public var saveableArtifacts: [FaviconArtifact] { artifacts }

    public func artifact(_ id: FaviconArtifactID) -> FaviconArtifact? {
        artifacts.first { $0.id == id }
    }

    public func icon(size: Int) -> GeneratedIcon? {
        iconPreviews.first { $0.size == size }
    }
}

public enum FaviconPackageError: Error, Equatable, Sendable {
    case missingIcon(size: Int)
    case duplicateIcon(size: Int)
    case invalidIcon(size: Int)
    case integerOverflow
}

extension FaviconPackageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .missingIcon(size): return "缺少 Favicon 的 \(size)×\(size) 图标。"
        case let .duplicateIcon(size): return "Favicon 包中重复出现 \(size)×\(size) 图标。"
        case let .invalidIcon(size): return "Favicon 图标尺寸无效：\(size)×\(size)。"
        case .integerOverflow: return "Favicon ICO 容器大小超出支持范围。"
        }
    }
}

public enum FaviconICOBuilder {
    public static let requiredSizes = [16, 32, 48]

    /// The PNG payloads are copied byte-for-byte. The builder deliberately
    /// does not decode or re-encode them, so the generated container remains
    /// deterministic and the image processor's existing resize semantics are
    /// preserved.
    public static func build(icons: [GeneratedIcon]) throws -> Data {
        let indexed = try index(icons: icons, sizes: requiredSizes)
        let headerLength = 6
        let entryLength = 16
        let payloadOffset = headerLength + entryLength * requiredSizes.count

        var totalLength = payloadOffset
        for size in requiredSizes {
            guard let icon = indexed[size], icon.data.count <= Int(UInt32.max) else {
                throw FaviconPackageError.integerOverflow
            }
            let (next, overflow) = totalLength.addingReportingOverflow(icon.data.count)
            guard !overflow, next <= Int(UInt32.max) else {
                throw FaviconPackageError.integerOverflow
            }
            totalLength = next
        }

        var output = Data(capacity: totalLength)
        appendUInt16LE(0, to: &output)
        appendUInt16LE(1, to: &output)
        appendUInt16LE(UInt16(requiredSizes.count), to: &output)

        var offset = payloadOffset
        for size in requiredSizes {
            guard let icon = indexed[size],
                  let offset32 = UInt32(exactly: offset),
                  let length32 = UInt32(exactly: icon.data.count) else {
                throw FaviconPackageError.integerOverflow
            }
            output.append(UInt8(size))
            output.append(UInt8(size))
            output.append(0) // palette count
            output.append(0) // reserved
            appendUInt16LE(1, to: &output) // color planes
            appendUInt16LE(32, to: &output) // bits per pixel
            appendUInt32LE(length32, to: &output)
            appendUInt32LE(offset32, to: &output)
            offset += icon.data.count
        }

        for size in requiredSizes {
            output.append(indexed[size]!.data)
        }
        return output
    }

    private static func index(icons: [GeneratedIcon], sizes: [Int]) throws -> [Int: GeneratedIcon] {
        var result: [Int: GeneratedIcon] = [:]
        for icon in icons {
            guard sizes.contains(icon.size) else { continue }
            guard icon.pixelWidth == icon.size, icon.pixelHeight == icon.size, icon.format == .png else {
                throw FaviconPackageError.invalidIcon(size: icon.size)
            }
            guard result[icon.size] == nil else {
                throw FaviconPackageError.duplicateIcon(size: icon.size)
            }
            result[icon.size] = icon
        }
        for size in sizes where result[size] == nil {
            throw FaviconPackageError.missingIcon(size: size)
        }
        return result
    }

    private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }
}

public enum FaviconPackageBuilder {
    public static let requiredSizes = [16, 32, 48, 180, 192, 512]

    public static func build(icons: [GeneratedIcon]) throws -> FaviconPackage {
        let indexed = try index(icons: icons)
        let ico = try FaviconICOBuilder.build(icons: icons)
        let manifest = manifestText()
        let artifacts = [
            FaviconArtifact(
                id: .faviconICO,
                mediaType: "image/x-icon",
                group: .browser,
                purpose: "传统浏览器标签页与书签图标",
                details: "ICO 容器，内含 16×16、32×32、48×48 PNG",
                data: ico,
                previewSizes: [16, 32, 48]
            ),
            FaviconArtifact(
                id: .appleTouchIcon,
                mediaType: "image/png",
                group: .apple,
                purpose: "Apple Touch Icon / iOS 主屏幕图标",
                details: "180×180 PNG",
                data: indexed[180]!.data,
                previewSizes: [180]
            ),
            FaviconArtifact(
                id: .webAppManifest192,
                mediaType: "image/png",
                group: .pwa,
                purpose: "普通 Web App 图标",
                details: "192×192 PNG，purpose 为 any",
                data: indexed[192]!.data,
                previewSizes: [192]
            ),
            FaviconArtifact(
                id: .webAppManifest512,
                mediaType: "image/png",
                group: .pwa,
                purpose: "普通 Web App 大尺寸图标",
                details: "512×512 PNG，purpose 为 any",
                data: indexed[512]!.data,
                previewSizes: [512]
            ),
            FaviconArtifact(
                id: .siteWebManifest,
                mediaType: "application/manifest+json",
                group: .configuration,
                purpose: "图标清单配置",
                details: "只包含 192/512 图标，不是完整 PWA manifest",
                data: Data(manifest.utf8)
            )
        ]
        return FaviconPackage(
            artifacts: artifacts,
            htmlSnippet: htmlSnippet,
            iconPreviews: requiredSizes.map { indexed[$0]! }
        )
    }

    public static let htmlSnippet = """
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/site.webmanifest">
"""

    public static func sourceWarning(metadata: ImageMetadata) -> String? {
        var reasons: [String] = []
        if metadata.hasAlpha || metadata.transparency != .opaque {
            reasons.append("源图片含透明区域")
        }
        if metadata.pixelWidth != metadata.pixelHeight {
            reasons.append("源图片不是正方形，生成结果会以透明画布居中")
        }
        guard !reasons.isEmpty else { return nil }
        return reasons.joined(separator: "；") + "。Apple Touch 外观请在真实设备或不透明背景下确认。"
    }

    private static func manifestText() -> String {
        """
{
  "icons": [
    {
      "src": "/web-app-manifest-192x192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any"
    },
    {
      "src": "/web-app-manifest-512x512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any"
    }
  ]
}
"""
    }

    private static func index(icons: [GeneratedIcon]) throws -> [Int: GeneratedIcon] {
        var result: [Int: GeneratedIcon] = [:]
        for icon in icons {
            guard requiredSizes.contains(icon.size) else { continue }
            guard icon.pixelWidth == icon.size, icon.pixelHeight == icon.size, icon.format == .png else {
                throw FaviconPackageError.invalidIcon(size: icon.size)
            }
            guard result[icon.size] == nil else {
                throw FaviconPackageError.duplicateIcon(size: icon.size)
            }
            result[icon.size] = icon
        }
        for size in requiredSizes where result[size] == nil {
            throw FaviconPackageError.missingIcon(size: size)
        }
        return result
    }
}
