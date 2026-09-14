import AppKit
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFileFormat: String, CaseIterable, Sendable {
    case jpeg
    case png
    case heic
    case webP
    case avif
    case tiff

    public init?(filenameExtension: String) {
        switch filenameExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
        case "jpg", "jpeg", "jpe":
            self = .jpeg
        case "png":
            self = .png
        case "heic", "heif":
            self = .heic
        case "webp":
            self = .webP
        case "avif":
            self = .avif
        case "tif", "tiff":
            self = .tiff
        default:
            return nil
        }
    }

    public init?(utTypeIdentifier: String) {
        if utTypeIdentifier == Self.avifTypeIdentifier {
            self = .avif
            return
        }

        guard let type = UTType(utTypeIdentifier) else { return nil }

        if type.conforms(to: .jpeg) {
            self = .jpeg
        } else if type.conforms(to: .png) {
            self = .png
        } else if type.conforms(to: .heic) || type.conforms(to: .heif) {
            self = .heic
        } else if type.conforms(to: .webP) {
            self = .webP
        } else if type.conforms(to: .tiff) {
            self = .tiff
        } else {
            return nil
        }
    }

    public var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .webP: return "WebP"
        case .avif: return "AVIF"
        case .tiff: return "TIFF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .webP: return "webp"
        case .avif: return "avif"
        case .tiff: return "tiff"
        }
    }

    public var utTypeIdentifier: String {
        switch self {
        case .jpeg: return UTType.jpeg.identifier
        case .png: return UTType.png.identifier
        case .heic: return UTType.heic.identifier
        case .webP: return UTType.webP.identifier
        case .avif: return Self.avifTypeIdentifier
        case .tiff: return UTType.tiff.identifier
        }
    }

    public static var supportedInputFormats: [ImageFileFormat] {
        let identifiers = Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
        return supportedInputFormats(sourceTypeIdentifiers: identifiers)
    }

    public static func supportedInputFormats(sourceTypeIdentifiers identifiers: Set<String>) -> [ImageFileFormat] {
        allCases.filter { identifiers.contains($0.utTypeIdentifier) }
    }

    public static var supportedOutputFormats: [ImageFileFormat] {
        let identifiers = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        return supportedOutputFormats(destinationTypeIdentifiers: identifiers)
    }

    public static func supportedOutputFormats(destinationTypeIdentifiers identifiers: Set<String>) -> [ImageFileFormat] {
        allCases.filter { identifiers.contains($0.utTypeIdentifier) }
    }

    public static func conversionTargetFormats(
        sourceFormat: ImageFileFormat?,
        supportedOutputFormats: [ImageFileFormat] = ImageFileFormat.supportedOutputFormats
    ) -> [ImageFileFormat] {
        guard sourceFormat != nil else { return [] }
        let preferredTargets: [ImageFileFormat] = [.jpeg, .png, .heic, .avif, .tiff, .webP]
        return preferredTargets.filter { format in
            format != sourceFormat && supportedOutputFormats.contains(format)
        }
    }

    public var canEncode: Bool {
        Self.supportedOutputFormats.contains(self)
    }

    public var supportsLossyQuality: Bool {
        switch self {
        case .jpeg, .heic, .webP, .avif:
            return true
        case .png, .tiff:
            return false
        }
    }

    public var defaultConversionQuality: Double? {
        switch self {
        case .jpeg, .webP, .avif:
            return 0.82
        case .heic:
            return 0.86
        case .png, .tiff:
            return nil
        }
    }

    public var preservesAlpha: Bool {
        switch self {
        case .png, .webP, .avif, .tiff:
            return true
        case .jpeg, .heic:
            return false
        }
    }

    private static let avifTypeIdentifier = "public.avif"
}

public enum ImageCompressionPreference: String, CaseIterable, Sendable {
    case clarity
    case balanced
    case smallerFile

    public var displayName: String {
        switch self {
        case .clarity: return "清晰优先"
        case .balanced: return "均衡"
        case .smallerFile: return "更小体积"
        }
    }

    public var qualityUpperBound: Double {
        switch self {
        case .clarity: return 0.90
        case .balanced: return 0.80
        case .smallerFile: return 0.68
        }
    }

    public var qualityLowerBound: Double {
        switch self {
        case .clarity: return 0.70
        case .balanced: return 0.55
        case .smallerFile: return 0.25
        }
    }
}

public enum ImageWatermarkPosition: String, CaseIterable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case centerLeft
    case center
    case centerRight
    case bottomLeft
    case bottomCenter
    case bottomRight
}

public enum ImageWatermarkTextColor: String, CaseIterable, Sendable {
    case white
    case black
}

public struct ImageWatermarkRecipe: Equatable, Sendable {
    public let text: String
    public let opacity: Double
    public let fontSize: Double
    public let position: ImageWatermarkPosition
    public let color: ImageWatermarkTextColor

    public init(
        text: String,
        opacity: Double,
        fontSize: Double,
        position: ImageWatermarkPosition,
        color: ImageWatermarkTextColor
    ) {
        self.text = text
        self.opacity = opacity
        self.fontSize = fontSize
        self.position = position
        self.color = color
    }
}

public enum ImageTransparencyState: Equatable, Sendable {
    case opaque
    case transparent
    case unknown
}

public struct ImageRGBColor: Codable, Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.first == "#" ? String(trimmed.dropFirst()) : trimmed
        guard normalized.count == 6, let value = UInt32(normalized, radix: 16) else {
            return nil
        }

        self.init(
            red: UInt8((value >> 16) & 0xff),
            green: UInt8((value >> 8) & 0xff),
            blue: UInt8(value & 0xff)
        )
    }

    public static let white = ImageRGBColor(red: 255, green: 255, blue: 255)
    public static let black = ImageRGBColor(red: 0, green: 0, blue: 0)

    public var hexString: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }
}

public enum ImageTransparencyFillMode: String, CaseIterable, Sendable {
    case unset
    case white
    case black
    case custom

    public func color(customHex: String) -> ImageRGBColor? {
        switch self {
        case .unset:
            return nil
        case .white:
            return .white
        case .black:
            return .black
        case .custom:
            return ImageRGBColor(hex: customHex)
        }
    }
}

public struct ImageMetadata: Equatable, Sendable {
    public let format: ImageFileFormat?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let byteCount: Int
    public let hasAlpha: Bool
    public let transparency: ImageTransparencyState
}

public struct ProcessedImage: Equatable, Sendable {
    public let data: Data
    public let format: ImageFileFormat
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let originalByteCount: Int
    public let quality: Double?
    public let wasResized: Bool

    public var byteCount: Int { data.count }
    public var isSmallerThanOriginal: Bool { byteCount < originalByteCount }
    public var isLargerThanOriginal: Bool { byteCount > originalByteCount }
}

public struct GeneratedIcon: Equatable, Sendable {
    public let size: Int
    public let data: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let format: ImageFileFormat
}

public enum ImageProcessingBudget {
    public static let maxInputBytes = 50 * 1024 * 1024
    public static let maxPixelCount = 50_000_000

    public static func validateInputByteCount(_ byteCount: Int) throws {
        guard byteCount <= maxInputBytes else {
            throw ImageProcessorError.inputFileTooLarge(actualBytes: byteCount, maxBytes: maxInputBytes)
        }
    }

    public static func validateDimensions(width: Int, height: Int) throws {
        guard let count = pixelCount(width: width, height: height) else {
            throw ImageProcessorError.imageTooLarge(pixelCount: Int.max, maxPixelCount: maxPixelCount)
        }
        guard count <= maxPixelCount else {
            throw ImageProcessorError.imageTooLarge(pixelCount: count, maxPixelCount: maxPixelCount)
        }
    }

    public static func pixelCount(width: Int, height: Int) -> Int? {
        guard width > 0, height > 0 else { return nil }
        let result = width.multipliedReportingOverflow(by: height)
        return result.overflow ? nil : result.partialValue
    }
}

public enum ImageProcessorError: Error, Equatable {
    case unreadableImage
    case missingImageProperties
    case unsupportedFormat(ImageFileFormat)
    case encodingFailed(ImageFileFormat)
    case renderingFailed
    case invalidIconSize(Int)
    case inputFileTooLarge(actualBytes: Int, maxBytes: Int)
    case imageTooLarge(pixelCount: Int, maxPixelCount: Int)
    case missingTransparencyFill
}

extension ImageProcessorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "所选文件不包含可读取的图片数据。"
        case .missingImageProperties:
            return "无法读取图片的尺寸信息。"
        case .unsupportedFormat(let format):
            return "当前系统不支持输出 \(format.displayName) 图片。"
        case .encodingFailed(let format):
            return "无法将图片编码为 \(format.displayName)。"
        case .renderingFailed:
            return "图片渲染失败。"
        case .invalidIconSize:
            return "图标尺寸必须大于 0 像素。"
        case .inputFileTooLarge(_, let maxBytes):
            return "图片文件大小上限为 \(ByteSizeFormatter.format(bytes: maxBytes))，所选文件已超出。"
        case .imageTooLarge(_, let maxPixelCount):
            return "图片像素总数上限为 \(Self.formatPixels(maxPixelCount))，所选图片已超出。"
        case .missingTransparencyFill:
            return "转换为不支持透明区域的格式前，请先选择透明区域填充颜色。"
        }
    }

    private static func formatPixels(_ count: Int) -> String {
        guard count >= 10_000 else { return "\(count) 像素" }
        if count.isMultiple(of: 10_000) {
            return "\(count / 10_000) 万像素"
        }
        return String(format: "%.1f 万像素", Double(count) / 10_000)
    }
}
