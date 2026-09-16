import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers


public enum ImageProcessor {
    public static let highFidelityEncodingQuality: Double = 1.0
    public static let watermarkFallbackLossyQuality: Double = 0.92

    /// Longest edge used when probing transparency during `inspect` only.
    /// Full-resolution classification remains available via `transparencyState(for:)`
    /// on convert/compress paths that already decode the working image.
    public static let inspectTransparencyProbeMaxPixelLength = 2_048

    public static func inspect(data: Data, filenameExtension: String?) throws -> ImageMetadata {
        try checkCancellation()
        try ImageProcessingBudget.validateInputByteCount(data.count)
        let source = try makeSource(from: data)
        let properties = try imageProperties(from: source)
        try ImageProcessingBudget.validateDimensions(width: properties.width, height: properties.height)

        // Fast path: ImageIO reports no alpha → skip decode and pixel scan.
        if properties.hasAlpha == false {
            return ImageMetadata(
                format: detectedFormat(source: source, filenameExtension: filenameExtension),
                pixelWidth: properties.width,
                pixelHeight: properties.height,
                byteCount: data.count,
                hasAlpha: false,
                transparency: .opaque
            )
        }

        // When alpha may be present, probe transparency without always decoding
        // the full-resolution bitmap. Convert/compress still classify at full res.
        let longestEdge = max(properties.width, properties.height)
        let probeLimit: Int? =
            longestEdge > inspectTransparencyProbeMaxPixelLength
            ? inspectTransparencyProbeMaxPixelLength
            : nil
        let decodedImage = try makeImage(from: source, maxPixelLength: probeLimit).image
        let hasAlpha = properties.hasAlpha ?? decodedImage.hasAlpha
        let transparency = try transparencyState(for: decodedImage)

        return ImageMetadata(
            format: detectedFormat(source: source, filenameExtension: filenameExtension),
            pixelWidth: properties.width,
            pixelHeight: properties.height,
            byteCount: data.count,
            hasAlpha: hasAlpha,
            transparency: transparency
        )
    }

    public static func previewImageData(data: Data, maxPixelLength: Int = 1024) throws -> Data {
        try checkCancellation()
        try ImageProcessingBudget.validateInputByteCount(data.count)
        let source = try makeSource(from: data)
        let properties = try imageProperties(from: source)
        try ImageProcessingBudget.validateDimensions(width: properties.width, height: properties.height)
        let decoded = try makeImage(from: source, maxPixelLength: maxPixelLength)
        try checkCancellation()
        return try encode(image: decoded.image, format: .png, quality: nil)
    }

    public static func generateIcons(data: Data, sizes: [Int]) throws -> [GeneratedIcon] {
        try checkCancellation()
        try ImageProcessingBudget.validateInputByteCount(data.count)
        guard !sizes.isEmpty else {
            return []
        }
        if let invalidSize = sizes.first(where: { $0 <= 0 }) {
            throw ImageProcessorError.invalidIconSize(invalidSize)
        }

        let decoded = try makeImage(from: try makeSource(from: data), maxPixelLength: nil)
        return try sizes.map { size in
            try checkCancellation()
            let icon = try renderIcon(sourceImage: decoded.image, size: size)
            let encoded = try encode(image: icon, format: .png, quality: nil)
            try checkCancellation()

            return GeneratedIcon(
                size: size,
                data: encoded,
                pixelWidth: icon.width,
                pixelHeight: icon.height,
                format: .png
            )
        }
    }

    public static func convert(
        data: Data,
        to format: ImageFileFormat,
        quality: Double?,
        maxPixelLength: Int?,
        transparencyFill: ImageRGBColor? = nil
    ) throws -> ProcessedImage {
        try checkCancellation()
        try ImageProcessingBudget.validateInputByteCount(data.count)
        let decoded = try makeImage(from: try makeSource(from: data), maxPixelLength: maxPixelLength)
        try checkCancellation()
        let transparency = try transparencyState(for: decoded.image)
        if !format.preservesAlpha,
           transparency != .opaque,
           transparencyFill == nil {
            throw ImageProcessorError.missingTransparencyFill
        }
        let outputQuality = format.supportsLossyQuality ? clampedQuality(quality ?? format.defaultConversionQuality ?? 0.82) : nil
        return try makeProcessedImage(
            image: decoded.image,
            format: format,
            originalByteCount: data.count,
            quality: outputQuality,
            wasResized: decoded.wasResized,
            transparencyFill: transparencyFill
        )
    }

    public static func compress(
        data: Data,
        sourceFilenameExtension: String?,
        quality: Double,
        minimumQuality: Double = 0.25,
        maxPixelLength: Int?,
        optimizer: any ExternalImageOptimizing = NoExternalImageOptimizer(),
        lossyOptimization: Bool = true
    ) throws -> ProcessedImage {
        try checkCancellation()
        try ImageProcessingBudget.validateInputByteCount(data.count)
        let source = try makeSource(from: data)
        let decoded = try makeImage(from: source, maxPixelLength: maxPixelLength)
        try checkCancellation()
        let sourceFormat = detectedFormat(source: source, filenameExtension: sourceFilenameExtension)
        let transparency = try transparencyState(for: decoded.image)
        let formats = compressionCandidateFormats(for: sourceFormat, hasAlpha: transparency != .opaque)
        let maximumQuality = clampedQuality(quality)
        var best: ProcessedImage?
        var lastError: Error?

        for format in formats {
            try checkCancellation()
            let candidates: [Double?] = format.supportsLossyQuality
                ? qualityCandidates(maximum: maximumQuality, minimum: minimumQuality).map(Optional.some)
                : [nil]
            var bestForFormat: ProcessedImage?

            for candidate in candidates {
                try checkCancellation()
                do {
                    var output = try makeProcessedImage(
                        image: decoded.image,
                        format: format,
                        originalByteCount: data.count,
                        quality: candidate,
                        wasResized: decoded.wasResized
                    )

                    try checkCancellation()
                    if let optimized = optimizer.optimize(output.data, format: format, lossy: lossyOptimization),
                       optimized.count < output.byteCount {
                        output = ProcessedImage(
                            data: optimized,
                            format: output.format,
                            pixelWidth: output.pixelWidth,
                            pixelHeight: output.pixelHeight,
                            originalByteCount: output.originalByteCount,
                            quality: output.quality,
                            wasResized: output.wasResized
                        )
                    }

                    if best.map({ output.byteCount < $0.byteCount }) ?? true {
                        best = output
                    }
                    if bestForFormat.map({ output.byteCount < $0.byteCount }) ?? true {
                        bestForFormat = output
                    }
                } catch let cancellation as CancellationError {
                    throw cancellation
                } catch {
                    lastError = error
                }
            }

            if let bestForFormat, bestForFormat.isSmallerThanOriginal {
                return bestForFormat
            }
        }

        if let best {
            return best
        }
        if let processorError = lastError as? ImageProcessorError {
            throw processorError
        }
        let fallback = formats.first ?? .jpeg
        throw ImageProcessorError.encodingFailed(fallback)
    }

    public static func compressionCandidateFormats(
        for sourceFormat: ImageFileFormat?,
        hasAlpha: Bool,
        supportedOutputFormats: [ImageFileFormat] = ImageFileFormat.supportedOutputFormats
    ) -> [ImageFileFormat] {
        var formats: [ImageFileFormat] = []

        func append(_ format: ImageFileFormat) {
            guard supportedOutputFormats.contains(format), !formats.contains(format) else { return }
            formats.append(format)
        }

        if let sourceFormat,
           sourceFormat != .tiff,
           sourceFormat != .webP,
           (!hasAlpha || sourceFormat.preservesAlpha) {
            append(sourceFormat)
        }

        if hasAlpha {
            append(.png)
            append(.avif)
        } else {
            append(.avif)
            append(.heic)
            append(.jpeg)
        }

        if formats.isEmpty {
            formats.append(compressionFormat(
                for: sourceFormat,
                hasAlpha: hasAlpha,
                supportedOutputFormats: supportedOutputFormats
            ))
        }

        return formats
    }

    public static func watermark(
        data: Data,
        sourceFilenameExtension: String?,
        recipe: ImageWatermarkRecipe,
        outputFormat: ImageFileFormat?
    ) throws -> ProcessedImage {
        try watermark(
            data: data,
            sourceFilenameExtension: sourceFilenameExtension,
            recipe: recipe,
            outputFormat: outputFormat,
            lossyQualityOverride: nil
        )
    }

    static func watermarkEncodingQuality(
        for format: ImageFileFormat,
        sourceData: Data
    ) -> Double? {
        switch format {
        case .jpeg:
            return JPEGSourceEncodingQuality.matchedImageIOQuality(for: sourceData)
                ?? watermarkFallbackLossyQuality
        case .heic, .webP, .avif:
            return watermarkFallbackLossyQuality
        case .png, .tiff:
            return nil
        }
    }

    private static func watermark(
        data: Data,
        sourceFilenameExtension: String?,
        recipe: ImageWatermarkRecipe,
        outputFormat: ImageFileFormat?,
        lossyQualityOverride: Double?
    ) throws -> ProcessedImage {
        try checkCancellation()
        try ImageProcessingBudget.validateInputByteCount(data.count)
        let source = try makeSource(from: data)
        let sourceFormat = detectedFormat(source: source, filenameExtension: sourceFilenameExtension)
        let format = outputFormat ?? sourceFormat ?? .png
        let sourceProperties = sanitizedEncodingProperties(from: source)
        let decoded = try makeImage(from: source, maxPixelLength: nil)
        try checkCancellation()
        let watermarked = try renderWatermark(recipe: recipe, on: decoded.image)
        let outputQuality = format.supportsLossyQuality
            ? lossyQualityOverride.map(clampedQuality)
                ?? watermarkEncodingQuality(for: format, sourceData: data)
            : nil

        return try makeProcessedImage(
            image: watermarked,
            format: format,
            originalByteCount: data.count,
            quality: outputQuality,
            wasResized: false,
            encodingProperties: sourceProperties
        )
    }

    public static func watermarkPreview(
        data: Data,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int,
        recipe: ImageWatermarkRecipe
    ) throws -> Data {
        try checkCancellation()
        try ImageProcessingBudget.validateInputByteCount(data.count)
        let source = try makeSource(from: data)
        let decoded = try makeImage(from: source, maxPixelLength: nil)
        let directScale = min(
            Double(decoded.image.width) / Double(max(1, sourcePixelWidth)),
            Double(decoded.image.height) / Double(max(1, sourcePixelHeight))
        )
        // ImageIO applies EXIF orientation while preparing the bounded
        // preview. Metadata dimensions can still be reported in the encoded
        // (unrotated) order, so also consider the transposed aspect ratio.
        // Taking the larger valid scale keeps preview and final typography
        // aligned for orientation 5–8 without changing the normal path.
        let transposedScale = min(
            Double(decoded.image.width) / Double(max(1, sourcePixelHeight)),
            Double(decoded.image.height) / Double(max(1, sourcePixelWidth))
        )
        let scale = max(directScale, transposedScale)
        let previewRecipe = ImageWatermarkRecipe(
            text: recipe.text,
            opacity: recipe.opacity,
            fontSize: max(1, recipe.fontSize * scale),
            position: recipe.position,
            color: recipe.color
        )
        let watermarked = try renderWatermark(recipe: previewRecipe, on: decoded.image)
        return try encode(image: watermarked, format: .png, quality: nil)
    }

    public static func watermark(
        data: Data,
        sourceFilenameExtension: String?,
        text: String,
        opacity: Double,
        fontSize: Double,
        position: ImageWatermarkPosition,
        outputFormat: ImageFileFormat?,
        quality: Double
    ) throws -> ProcessedImage {
        try watermark(
            data: data,
            sourceFilenameExtension: sourceFilenameExtension,
            recipe: ImageWatermarkRecipe(
                text: text,
                opacity: opacity,
                fontSize: fontSize,
                position: position,
                color: .white
            ),
            outputFormat: outputFormat,
            lossyQualityOverride: quality
        )
    }

    public static func grayscale(
        data: Data,
        sourceFilenameExtension: String?,
        outputFormat: ImageFileFormat?,
        quality: Double
    ) throws -> ProcessedImage {
        try checkCancellation()
        try ImageProcessingBudget.validateInputByteCount(data.count)
        let source = try makeSource(from: data)
        let sourceFormat = detectedFormat(source: source, filenameExtension: sourceFilenameExtension)
        let format = outputFormat ?? sourceFormat ?? .png
        let decoded = try makeImage(from: source, maxPixelLength: nil)
        try checkCancellation()
        let grayscale = try renderGrayscale(decoded.image)
        let outputQuality = format.supportsLossyQuality ? clampedQuality(quality) : nil

        return try makeProcessedImage(
            image: grayscale,
            format: format,
            originalByteCount: data.count,
            quality: outputQuality,
            wasResized: false
        )
    }
}
