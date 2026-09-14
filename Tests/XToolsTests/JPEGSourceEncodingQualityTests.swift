import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import XToolsCore

struct JPEGSourceEncodingQualityTests {
    @Test func quantizationReaderParsesEightAndSixteenBitTablesAcrossSegments() throws {
        let eightBitValues = (1...64).map(UInt16.init)
        let sixteenBitValues = (257...320).map(UInt16.init)
        let data = Self.jpegData(dqtSegments: [
            Self.dqtPayload(tableID: 0, values: eightBitValues, precision: 0),
            Self.dqtPayload(tableID: 2, values: sixteenBitValues, precision: 1)
        ])

        let tables = try #require(JPEGQuantizationTables(data: data))

        #expect(tables.valuesByTableID[0] == eightBitValues)
        #expect(tables.valuesByTableID[2] == sixteenBitValues)
        #expect(tables.valuesByTableID.count == 2)
    }

    @Test func quantizationReaderRejectsMissingAndTruncatedTables() {
        #expect(JPEGQuantizationTables(data: Data([0xFF, 0xD8, 0xFF, 0xD9])) == nil)

        let truncated = Data([
            0xFF, 0xD8,
            0xFF, 0xDB,
            0x00, 0x43,
            0x00,
            0x01, 0x02, 0x03,
            0xFF, 0xD9
        ])
        #expect(JPEGQuantizationTables(data: truncated) == nil)

        let illegalPrecision = Self.jpegData(dqtSegments: [Data([0x20]) + Data(repeating: 1, count: 64)])
        #expect(JPEGQuantizationTables(data: illegalPrecision) == nil)
    }

    @Test func generatedJPEGMatchesEquivalentImageIOQuantizationBucket() throws {
        let image = try Self.makePatternImage(width: 96, height: 64)

        for sourceQuality in [0.50, 0.70, 0.82, 0.92, 1.0] {
            let source = try Self.encode(image, format: .jpeg, quality: sourceQuality)
            let sourceTables = try #require(JPEGQuantizationTables(data: source))
            let matchedQuality = try #require(JPEGSourceEncodingQuality.matchedImageIOQuality(for: source))
            let matchedData = try Self.encode(image, format: .jpeg, quality: matchedQuality)
            let matchedTables = try #require(JPEGQuantizationTables(data: matchedData))

            #expect(matchedTables == sourceTables)
        }
    }

    @Test func watermarkUsesSourceMatchedJPEGQualityInsteadOfMaximumQuality() throws {
        let image = try Self.makePatternImage(width: 512, height: 320)
        let source = try Self.encode(image, format: .jpeg, quality: 0.82)
        let recipe = ImageWatermarkRecipe(
            text: "TOOLS",
            opacity: 0.65,
            fontSize: 42,
            position: .bottomRight,
            color: .white
        )

        let automatic = try ImageProcessor.watermark(
            data: source,
            sourceFilenameExtension: "jpg",
            recipe: recipe,
            outputFormat: nil
        )
        let maximum = try ImageProcessor.watermark(
            data: source,
            sourceFilenameExtension: "jpg",
            text: recipe.text,
            opacity: recipe.opacity,
            fontSize: recipe.fontSize,
            position: recipe.position,
            outputFormat: nil,
            quality: 1.0
        )
        let expectedQuality = try #require(JPEGSourceEncodingQuality.matchedImageIOQuality(for: source))

        #expect(automatic.format == .jpeg)
        #expect(automatic.quality == expectedQuality)
        #expect(automatic.quality != 1.0)
        #expect(automatic.byteCount < maximum.byteCount)
        #expect(maximum.quality == 1.0)
    }

    @Test func watermarkLossyPolicyFallsBackWithoutJPEGTablesAndForOtherFormats() {
        let invalidJPEG = Data([0xFF, 0xD8, 0xFF, 0xD9])

        #expect(ImageProcessor.watermarkEncodingQuality(for: .jpeg, sourceData: invalidJPEG) == 0.92)
        #expect(ImageProcessor.watermarkEncodingQuality(for: .heic, sourceData: Data()) == 0.92)
        #expect(ImageProcessor.watermarkEncodingQuality(for: .webP, sourceData: Data()) == 0.92)
        #expect(ImageProcessor.watermarkEncodingQuality(for: .avif, sourceData: Data()) == 0.92)
        #expect(ImageProcessor.watermarkEncodingQuality(for: .png, sourceData: Data()) == nil)
        #expect(ImageProcessor.watermarkEncodingQuality(for: .tiff, sourceData: Data()) == nil)
    }

    @Test func legacyExplicitWatermarkQualityIsHonored() throws {
        let image = try Self.makePatternImage(width: 160, height: 90)
        let source = try Self.encode(image, format: .jpeg, quality: 0.82)

        let output = try ImageProcessor.watermark(
            data: source,
            sourceFilenameExtension: "jpg",
            text: "DEV",
            opacity: 0.65,
            fontSize: 18,
            position: .bottomRight,
            outputFormat: nil,
            quality: 0.70
        )

        #expect(output.quality == 0.70)
    }

    private static func jpegData(dqtSegments: [Data]) -> Data {
        var result = Data([0xFF, 0xD8])
        for payload in dqtSegments {
            result.append(contentsOf: [0xFF, 0xDB])
            let length = payload.count + 2
            result.append(UInt8((length >> 8) & 0xFF))
            result.append(UInt8(length & 0xFF))
            result.append(payload)
        }
        result.append(contentsOf: [0xFF, 0xD9])
        return result
    }

    private static func dqtPayload(tableID: UInt8, values: [UInt16], precision: UInt8) -> Data {
        precondition(values.count == 64)
        var result = Data([(precision << 4) | tableID])
        for value in values {
            if precision == 0 {
                result.append(UInt8(value & 0xFF))
            } else {
                result.append(UInt8((value >> 8) & 0xFF))
                result.append(UInt8(value & 0xFF))
            }
        }
        return result
    }

    private static func makePatternImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw TestImageError.creationFailed
        }

        for y in 0..<height {
            let value = CGFloat(y) / CGFloat(max(1, height - 1))
            context.setFillColor(CGColor(red: value, green: 0.25, blue: 1 - value, alpha: 1))
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        for x in stride(from: 0, to: width, by: 17) {
            context.setFillColor(CGColor(red: 0.9, green: 0.6, blue: 0.15, alpha: 1))
            context.fill(CGRect(x: x, y: (x * 7) % max(1, height), width: 7, height: 11))
        }

        guard let image = context.makeImage() else {
            throw TestImageError.creationFailed
        }
        return image
    }

    private static func encode(
        _ image: CGImage,
        format: ImageFileFormat,
        quality: Double?
    ) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            format.utTypeIdentifier as CFString,
            1,
            nil
        ) else {
            throw TestImageError.creationFailed
        }

        var properties: [CFString: Any] = [:]
        if let quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.creationFailed
        }
        return output as Data
    }

    private enum TestImageError: Error {
        case creationFailed
    }
}
