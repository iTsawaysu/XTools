import AppKit
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers


extension ImageProcessor {
    struct ImageProperties {
        let width: Int
        let height: Int
        let hasAlpha: Bool?
    }

    struct DecodedImage {
        let image: CGImage
        let wasResized: Bool
    }

    static func makeSource(from data: Data) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            throw ImageProcessorError.unreadableImage
        }
        return source
    }

    static func imageProperties(from source: CGImageSource) throws -> ImageProperties {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw ImageProcessorError.missingImageProperties
        }
        return ImageProperties(
            width: width,
            height: height,
            hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool
        )
    }

    static func makeImage(from source: CGImageSource, maxPixelLength: Int?) throws -> DecodedImage {
        let properties = try imageProperties(from: source)
        if maxPixelLength == nil {
            try ImageProcessingBudget.validateDimensions(width: properties.width, height: properties.height)
        }
        let originalMax = max(properties.width, properties.height)
        let requestedMax = maxPixelLength.map { max(1, min($0, originalMax)) } ?? originalMax

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: requestedMax
        ]

        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return DecodedImage(
                image: image,
                wasResized: max(image.width, image.height) < originalMax
            )
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            throw ImageProcessorError.unreadableImage
        }
        return DecodedImage(image: image, wasResized: false)
    }

    static func detectedFormat(source: CGImageSource, filenameExtension: String?) -> ImageFileFormat? {
        if let type = CGImageSourceGetType(source) as String?,
           let format = ImageFileFormat(utTypeIdentifier: type) {
            return format
        }
        if let filenameExtension {
            return ImageFileFormat(filenameExtension: filenameExtension)
        }
        return nil
    }

    static func compressionFormat(
        for sourceFormat: ImageFileFormat?,
        hasAlpha: Bool,
        supportedOutputFormats: [ImageFileFormat] = ImageFileFormat.supportedOutputFormats
    ) -> ImageFileFormat {
        if let sourceFormat, supportedOutputFormats.contains(sourceFormat) {
            return sourceFormat
        }

        if hasAlpha, supportedOutputFormats.contains(.png) {
            return .png
        }

        if supportedOutputFormats.contains(.jpeg) {
            return .jpeg
        }

        return supportedOutputFormats.first ?? .jpeg
    }

    static func makeProcessedImage(
        image: CGImage,
        format: ImageFileFormat,
        originalByteCount: Int,
        quality: Double?,
        wasResized: Bool,
        transparencyFill: ImageRGBColor? = nil,
        encodingProperties: [CFString: Any] = [:]
    ) throws -> ProcessedImage {
        try checkCancellation()
        let encoded = try encode(
            image: image,
            format: format,
            quality: quality,
            transparencyFill: transparencyFill,
            encodingProperties: encodingProperties
        )
        try checkCancellation()

        return ProcessedImage(
            data: encoded,
            format: format,
            pixelWidth: image.width,
            pixelHeight: image.height,
            originalByteCount: originalByteCount,
            quality: quality,
            wasResized: wasResized
        )
    }

    static func encode(
        image: CGImage,
        format: ImageFileFormat,
        quality: Double?,
        transparencyFill: ImageRGBColor? = nil,
        encodingProperties: [CFString: Any] = [:]
    ) throws -> Data {
        let imageForEncoding = try imageForEncoding(
            image,
            format: format,
            transparencyFill: transparencyFill
        )
        let output = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(output, format.utTypeIdentifier as CFString, 1, nil) else {
            throw ImageProcessorError.unsupportedFormat(format)
        }

        var properties = encodingProperties
        if let quality, format.supportsLossyQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        properties.merge(losslessEncodingProperties(for: format)) { _, newValue in newValue }

        CGImageDestinationAddImage(destination, imageForEncoding, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessorError.encodingFailed(format)
        }

        return output as Data
    }

    static func sanitizedEncodingProperties(from source: CGImageSource) -> [CFString: Any] {
        guard var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return [:]
        }

        properties.removeValue(forKey: kCGImagePropertyPixelWidth)
        properties.removeValue(forKey: kCGImagePropertyPixelHeight)
        properties.removeValue(forKey: kCGImagePropertyOrientation)
        properties.removeValue(forKey: kCGImagePropertyThumbnailImages)
        properties.removeValue(forKey: "{Thumbnail}" as CFString)

        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation)
            tiff.removeValue(forKey: "ImageWidth" as CFString)
            tiff.removeValue(forKey: "ImageLength" as CFString)
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }

        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
            properties[kCGImagePropertyExifDictionary] = exif
        }

        return properties
    }

    static func losslessEncodingProperties(for format: ImageFileFormat) -> [CFString: Any] {
        switch format {
        case .png:
            return [
                kCGImagePropertyPNGCompressionFilter: pngAllCompressionFilters
            ]
        case .tiff:
            return [
                kCGImagePropertyTIFFCompression: NSBitmapImageRep.TIFFCompression.lzw.rawValue
            ]
        case .jpeg, .heic, .webP, .avif:
            return [:]
        }
    }

    private static var pngAllCompressionFilters: Int {
        0x08 | 0x10 | 0x20 | 0x40 | 0x80
    }

    static func imageForEncoding(
        _ image: CGImage,
        format: ImageFileFormat,
        transparencyFill: ImageRGBColor?
    ) throws -> CGImage {
        guard image.hasAlpha && !format.preservesAlpha else { return image }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ImageProcessorError.renderingFailed
        }

        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let fill = transparencyFill ?? .white
        context.setFillColor(CGColor(
            red: CGFloat(fill.red) / 255,
            green: CGFloat(fill.green) / 255,
            blue: CGFloat(fill.blue) / 255,
            alpha: 1
        ))
        context.fill(rect)
        context.interpolationQuality = .high
        context.draw(image, in: rect)

        guard let flattened = context.makeImage() else {
            throw ImageProcessorError.renderingFailed
        }
        return flattened
    }

    /// Classifies opacity by scanning alpha in horizontal strips so peak memory
    /// stays O(width × stripHeight) instead of O(width × height), with early
    /// exit on the first non-opaque sample.
    static func transparencyState(for image: CGImage) throws -> ImageTransparencyState {
        guard image.hasAlpha else { return .opaque }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return .unknown }
        guard ImageProcessingBudget.pixelCount(width: width, height: height) != nil else {
            return .unknown
        }

        let stripHeight = min(64, height)
        var alpha = [UInt8](repeating: 0, count: width * stripHeight)
        let context = CIContext(options: [.cacheIntermediates: false])
        let ciImage = CIImage(cgImage: image)

        var originY = 0
        while originY < height {
            try checkCancellation()
            let rows = min(stripHeight, height - originY)
            let sampleCount = width * rows

            let didRender = alpha.withUnsafeMutableBytes { buffer -> Bool in
                guard let baseAddress = buffer.baseAddress else { return false }
                context.render(
                    ciImage,
                    toBitmap: baseAddress,
                    rowBytes: width,
                    bounds: CGRect(x: 0, y: originY, width: width, height: rows),
                    format: .A8,
                    colorSpace: nil
                )
                return true
            }
            guard didRender else { return .unknown }

            for index in 0..<sampleCount {
                if alpha[index] < 255 {
                    return .transparent
                }
            }
            originY += rows
        }
        return .opaque
    }

    static func renderIcon(sourceImage: CGImage, size: Int) throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageProcessorError.renderingFailed
        }

        let canvas = CGRect(x: 0, y: 0, width: size, height: size)
        context.clear(canvas)
        context.interpolationQuality = .high

        let scale = min(CGFloat(size) / CGFloat(sourceImage.width), CGFloat(size) / CGFloat(sourceImage.height))
        let drawWidth = CGFloat(sourceImage.width) * scale
        let drawHeight = CGFloat(sourceImage.height) * scale
        let drawRect = CGRect(
            x: (CGFloat(size) - drawWidth) / 2,
            y: (CGFloat(size) - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight
        )
        context.draw(sourceImage, in: drawRect)

        guard let output = context.makeImage() else {
            throw ImageProcessorError.renderingFailed
        }
        return output
    }

    static func renderWatermark(recipe: ImageWatermarkRecipe, on sourceImage: CGImage) throws -> CGImage {
        try checkCancellation()
        let width = sourceImage.width
        let height = sourceImage.height
        let colorSpace = sourceImage.colorSpace?.model == .rgb
            ? sourceImage.colorSpace!
            : (CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB())
        let bitsPerComponent = sourceImage.bitsPerComponent > 8 ? 16 : 8
        // Keep the source's Alpha-channel contract. A source without Alpha
        // should not gain a new channel merely because the renderer needs a
        // bitmap context for the text overlay.
        let alphaInfo: CGImageAlphaInfo = sourceImage.hasAlpha ? .premultipliedLast : .noneSkipLast
        let bitmapInfo = CGBitmapInfo(rawValue: alphaInfo.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw ImageProcessorError.renderingFailed
        }

        let padding = watermarkPadding(imageSize: CGSize(width: width, height: height))
        let attributesAndSize = watermarkAttributes(
            text: recipe.text,
            opacity: recipe.opacity,
            fontSize: recipe.fontSize,
            maxTextSize: CGSize(
                width: max(1, CGFloat(width) - padding * 2),
                height: max(1, CGFloat(height) - padding * 2)
            )
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: attributesAndSize.font,
            .foregroundColor: recipe.color.nsColor.withAlphaComponent(clampedUnit(recipe.opacity))
        ]
        let point = watermarkPoint(
            position: recipe.position,
            textSize: attributesAndSize.textSize,
            imageSize: CGSize(width: width, height: height),
            padding: padding
        )

        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.clear(canvas)
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(sourceImage, in: canvas)
        context.setBlendMode(.normal)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (recipe.text as NSString).draw(at: point, withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()

        guard let output = context.makeImage() else {
            throw ImageProcessorError.renderingFailed
        }
        try checkCancellation()
        return output
    }

    static func renderGrayscale(_ sourceImage: CGImage) throws -> CGImage {
        try checkCancellation()
        let input = CIImage(cgImage: sourceImage)
        guard let filter = CIFilter(name: "CIPhotoEffectMono") else {
            throw ImageProcessorError.renderingFailed
        }
        filter.setValue(input, forKey: kCIInputImageKey)

        guard let outputImage = filter.outputImage else {
            throw ImageProcessorError.renderingFailed
        }

        let context = CIContext()
        let extent = CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
        guard let output = context.createCGImage(outputImage, from: extent) else {
            throw ImageProcessorError.renderingFailed
        }
        try checkCancellation()
        return output
    }

    static func watermarkPoint(
        position: ImageWatermarkPosition,
        textSize: CGSize,
        imageSize: CGSize,
        padding: CGFloat
    ) -> CGPoint {
        let x: CGFloat
        let y: CGFloat
        switch position {
        case .topLeft:
            x = padding
            y = imageSize.height - textSize.height - padding
        case .topCenter:
            x = (imageSize.width - textSize.width) / 2
            y = imageSize.height - textSize.height - padding
        case .topRight:
            x = imageSize.width - textSize.width - padding
            y = imageSize.height - textSize.height - padding
        case .centerLeft:
            x = padding
            y = (imageSize.height - textSize.height) / 2
        case .center:
            x = (imageSize.width - textSize.width) / 2
            y = (imageSize.height - textSize.height) / 2
        case .centerRight:
            x = imageSize.width - textSize.width - padding
            y = (imageSize.height - textSize.height) / 2
        case .bottomLeft:
            x = padding
            y = padding
        case .bottomCenter:
            x = (imageSize.width - textSize.width) / 2
            y = padding
        case .bottomRight:
            x = imageSize.width - textSize.width - padding
            y = padding
        }
        return CGPoint(
            x: clampedOrigin(x, extent: textSize.width, canvasExtent: imageSize.width, padding: padding),
            y: clampedOrigin(y, extent: textSize.height, canvasExtent: imageSize.height, padding: padding)
        )
    }

    static func qualityCandidates(maximum: Double, minimum: Double) -> [Double] {
        let maxQuality = clampedQuality(maximum)
        let minQuality = min(clampedQuality(minimum), maxQuality)
        var values: [Double] = []
        var current = maxQuality

        while current >= minQuality {
            values.append(round(current * 100) / 100)
            current -= 0.05
        }

        if values.last.map({ $0 > minQuality }) ?? true {
            values.append(minQuality)
        }
        return Array(Set(values)).sorted(by: >)
    }

    static func clampedQuality(_ quality: Double) -> Double {
        guard quality.isFinite else { return 0.82 }
        return min(max(quality, 0.05), 1.0)
    }

    static func clampedUnit(_ value: Double) -> CGFloat {
        guard value.isFinite else { return 1 }
        return CGFloat(min(max(value, 0), 1))
    }

    static func watermarkPadding(imageSize: CGSize) -> CGFloat {
        let minDimension = max(1, min(imageSize.width, imageSize.height))
        return min(max(12, minDimension * 0.035), max(1, minDimension / 4))
    }

    static func watermarkAttributes(
        text: String,
        opacity: Double,
        fontSize: Double,
        maxTextSize: CGSize
    ) -> (font: NSFont, textSize: CGSize) {
        var effectiveFontSize = clampedFontSize(fontSize, maxTextSize: maxTextSize)
        var font = ImageWatermarkSizing.font(ofSize: effectiveFontSize)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(clampedUnit(opacity))
        ]
        var textSize = (text as NSString).size(withAttributes: attributes)

        let widthScale = maxTextSize.width / max(textSize.width, 1)
        let heightScale = maxTextSize.height / max(textSize.height, 1)
        let scale = min(widthScale, heightScale)
        if scale.isFinite, scale > 0, scale < 1 {
            effectiveFontSize = max(1, floor(effectiveFontSize * scale))
            font = ImageWatermarkSizing.font(ofSize: effectiveFontSize)
            attributes[.font] = font
            textSize = (text as NSString).size(withAttributes: attributes)
        }

        return (font, textSize)
    }

    static func clampedFontSize(_ fontSize: Double, maxTextSize: CGSize) -> CGFloat {
        let fallback = min(max(maxTextSize.height, 1), 36)
        let requested = fontSize.isFinite ? CGFloat(fontSize) : fallback
        return min(max(requested, 1), max(1, max(maxTextSize.width, maxTextSize.height) * 2))
    }

    static func clampedOrigin(
        _ origin: CGFloat,
        extent: CGFloat,
        canvasExtent: CGFloat,
        padding: CGFloat
    ) -> CGFloat {
        let available = canvasExtent - extent
        guard available > 0 else { return 0 }

        let lower = min(padding, available)
        let upper = max(0, available - padding)
        guard lower <= upper else {
            return available / 2
        }
        return min(max(origin, lower), upper)
    }

    static func checkCancellation() throws {
        try Task.checkCancellation()
    }
}

extension CGImage {
    var hasAlpha: Bool {
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return false
        }
    }
}

extension ImageWatermarkTextColor {
    var nsColor: NSColor {
        switch self {
        case .white: return .white
        case .black: return .black
        }
    }

}
