import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import XToolsCore

struct FaviconPackageTests {
    @Test func packageUsesStableFiveFileDeploymentContract() throws {
        let icons = try makeIcons()
        let package = try FaviconPackageBuilder.build(icons: icons)

        #expect(package.artifacts.map(\.id) == [
            .faviconICO,
            .appleTouchIcon,
            .webAppManifest192,
            .webAppManifest512,
            .siteWebManifest
        ])
        #expect(package.artifacts.map(\.filename) == [
            "favicon.ico",
            "apple-touch-icon.png",
            "web-app-manifest-192x192.png",
            "web-app-manifest-512x512.png",
            "site.webmanifest"
        ])
        #expect(package.artifact(.appleTouchIcon)?.data == icons.first { $0.size == 180 }?.data)
        #expect(package.artifact(.webAppManifest192)?.data == icons.first { $0.size == 192 }?.data)
        #expect(package.artifact(.webAppManifest512)?.data == icons.first { $0.size == 512 }?.data)
        #expect(package.iconPreviews.map(\.size) == [16, 32, 48, 180, 192, 512])
    }

    @Test func icoDirectoryPointsAtOriginalPNGPayloads() throws {
        let icons = try makeIcons()
        let ico = try FaviconICOBuilder.build(icons: icons)

        #expect(readUInt16(ico, at: 0) == 0)
        #expect(readUInt16(ico, at: 2) == 1)
        #expect(readUInt16(ico, at: 4) == 3)

        for (index, size) in FaviconICOBuilder.requiredSizes.enumerated() {
            let entry = 6 + index * 16
            #expect(Int(ico[entry]) == size)
            #expect(Int(ico[entry + 1]) == size)
            #expect(readUInt16(ico, at: entry + 4) == 1)
            #expect(readUInt16(ico, at: entry + 6) == 32)
            let length = Int(readUInt32(ico, at: entry + 8))
            let offset = Int(readUInt32(ico, at: entry + 12))
            let payload = ico.subdata(in: offset..<(offset + length))
            #expect(payload == icons.first { $0.size == size }?.data)
            #expect(payload.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        }

        let source = CGImageSourceCreateWithData(ico as CFData, nil)
        #expect(source != nil)
        if let source {
            #expect(CGImageSourceGetCount(source) >= 1)
            #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
        }
    }

    @Test func manifestAndHTMLReferenceOnlyGeneratedFiles() throws {
        let package = try FaviconPackageBuilder.build(icons: makeIcons())
        let manifestData = try #require(package.artifact(.siteWebManifest)?.data)
        let object = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let icons = try #require(object["icons"] as? [[String: String]])

        #expect(icons == [
            [
                "src": "/web-app-manifest-192x192.png",
                "sizes": "192x192",
                "type": "image/png",
                "purpose": "any"
            ],
            [
                "src": "/web-app-manifest-512x512.png",
                "sizes": "512x512",
                "type": "image/png",
                "purpose": "any"
            ]
        ])
        #expect(package.htmlSnippet == """
        <link rel="icon" href="/favicon.ico" sizes="any">
        <link rel="apple-touch-icon" href="/apple-touch-icon.png">
        <link rel="manifest" href="/site.webmanifest">
        """)
        #expect(!package.htmlSnippet.contains("maskable"))
        #expect(!String(decoding: manifestData, as: UTF8.self).contains("name"))
    }

    @Test func packageRejectsMissingAndDuplicateRequiredSizes() throws {
        let icons = try makeIcons()
        #expect(throws: FaviconPackageError.missingIcon(size: 48)) {
            try FaviconPackageBuilder.build(icons: icons.filter { $0.size != 48 })
        }
        #expect(throws: FaviconPackageError.duplicateIcon(size: 16)) {
            try FaviconPackageBuilder.build(icons: icons + [icons[0]])
        }
        let malformed = GeneratedIcon(
            size: 16,
            data: icons[0].data,
            pixelWidth: 15,
            pixelHeight: 16,
            format: .png
        )
        #expect(throws: FaviconPackageError.invalidIcon(size: 16)) {
            try FaviconPackageBuilder.build(icons: [malformed] + icons.dropFirst())
        }
    }

    @Test func sourceWarningCoversAlphaAndNonSquareInputsWithoutMaskableClaims() {
        let metadata = ImageMetadata(
            format: .png,
            pixelWidth: 640,
            pixelHeight: 480,
            byteCount: 128,
            hasAlpha: true,
            transparency: .transparent
        )
        let warning = FaviconPackageBuilder.sourceWarning(metadata: metadata)
        #expect(warning?.contains("透明") == true)
        #expect(warning?.contains("不是正方形") == true)
        #expect(warning?.contains("真实设备") == true)
        #expect(warning?.contains("maskable") == false)
    }

    private func makeIcons() throws -> [GeneratedIcon] {
        let input = try makePNG(width: 20, height: 12)
        return try ImageProcessor.generateIcons(data: input, sizes: FaviconPackageBuilder.requiredSizes)
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let pixels = [UInt8](repeating: 0xCC, count: width * height * 4)
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }
}
