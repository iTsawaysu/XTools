import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import XToolsCore

struct ImageProcessingTests {
    @Test func supportedOutputFormatsFollowDestinationIdentifiers() {
        let formats = ImageFileFormat.supportedOutputFormats(destinationTypeIdentifiers: [
            UTType.jpeg.identifier,
            UTType.png.identifier,
            UTType.heic.identifier
        ])

        #expect(formats == [.jpeg, .png, .heic])
        #expect(!formats.contains(.webP))
    }

    @Test func supportedInputAndOutputFormatsAreGatedIndependently() {
        let readable = ImageFileFormat.supportedInputFormats(sourceTypeIdentifiers: [
            UTType.jpeg.identifier,
            UTType.webP.identifier,
            "public.avif"
        ])
        let writable = ImageFileFormat.supportedOutputFormats(destinationTypeIdentifiers: [
            UTType.jpeg.identifier,
            "public.avif"
        ])

        #expect(readable == [.jpeg, .webP, .avif])
        #expect(writable == [.jpeg, .avif])
        #expect(!writable.contains(.webP))
    }

    @Test func transparencyFillColorUsesStableHexRecipe() {
        #expect(ImageRGBColor(hex: "#336699") == ImageRGBColor(red: 0x33, green: 0x66, blue: 0x99))
        #expect(ImageRGBColor(hex: " ffffff ") == .white)
        #expect(ImageRGBColor.black.hexString == "#000000")
        #expect(ImageRGBColor(hex: "#123") == nil)
        #expect(ImageRGBColor(hex: "##FFFFFF") == nil)
        #expect(ImageRGBColor(hex: "not-a-color") == nil)
    }

    @Test func compressionPreferencesUseUserLevelQualityOrder() {
        #expect(ImageCompressionPreference.clarity.displayName == "清晰优先")
        #expect(ImageCompressionPreference.balanced.displayName == "均衡")
        #expect(ImageCompressionPreference.smallerFile.displayName == "更小体积")
        #expect(ImageCompressionPreference.clarity.qualityUpperBound > ImageCompressionPreference.balanced.qualityUpperBound)
        #expect(ImageCompressionPreference.balanced.qualityUpperBound > ImageCompressionPreference.smallerFile.qualityUpperBound)
        #expect(ImageCompressionPreference.clarity.qualityLowerBound > ImageCompressionPreference.balanced.qualityLowerBound)
        #expect(ImageCompressionPreference.balanced.qualityLowerBound > ImageCompressionPreference.smallerFile.qualityLowerBound)
        #expect(ImageCompressionPreference.clarity.qualityUpperBound - ImageCompressionPreference.clarity.qualityLowerBound >= 0.15)
    }

    @Test func conversionDefaultsUseFormatSpecificQualityBalance() {
        #expect(ImageFileFormat.jpeg.defaultConversionQuality == 0.82)
        #expect(ImageFileFormat.heic.defaultConversionQuality == 0.86)
        #expect(ImageFileFormat.heic.defaultConversionQuality! > ImageFileFormat.jpeg.defaultConversionQuality!)
        #expect(ImageFileFormat.avif.defaultConversionQuality == 0.82)
        #expect(ImageFileFormat.png.defaultConversionQuality == nil)
        #expect(ImageFileFormat.tiff.defaultConversionQuality == nil)
    }


    @Test func watermarkRelativeSizingTargetsTextWidthAcrossContentAndCanvasSizes() {
        let landscape = ImageWatermarkSizing.fontSize(
            text: "Watermark",
            sizeRatio: 0.30,
            pixelWidth: 5_184,
            pixelHeight: 3_456
        )
        let halfScale = ImageWatermarkSizing.fontSize(
            text: "Watermark",
            sizeRatio: 0.30,
            pixelWidth: 2_592,
            pixelHeight: 1_728
        )
        let longText = ImageWatermarkSizing.fontSize(
            text: "A much longer watermark sentence",
            sizeRatio: 0.30,
            pixelWidth: 5_184,
            pixelHeight: 3_456
        )
        let shortText = ImageWatermarkSizing.fontSize(
            text: "W",
            sizeRatio: 0.30,
            pixelWidth: 5_184,
            pixelHeight: 3_456
        )

        #expect(abs(halfScale * 2 - landscape) < 0.001)
        #expect(longText < landscape)
        #expect(shortText > landscape)

        for ratio in [0.10, 0.30, 0.80] {
            let fontSize = ImageWatermarkSizing.fontSize(
                text: "Watermark",
                sizeRatio: ratio,
                pixelWidth: 5_184,
                pixelHeight: 3_456
            )
            let renderedWidth = ("Watermark" as NSString).size(withAttributes: [
                .font: ImageWatermarkSizing.font(ofSize: CGFloat(fontSize))
            ]).width
            #expect(abs(Double(renderedWidth) / 5_184 - ratio) < 0.001)
        }

        #expect(ImageWatermarkSizing.clampedRatio(0) == 0.10)
        #expect(ImageWatermarkSizing.clampedRatio(1) == 0.80)
        #expect(ImageWatermarkSizing.clampedRatio(.infinity) == 0.30)
    }

    @Test func watermarkRecipeIncludesNineAnchorsAndBlackWhiteColor() {
        #expect(ImageWatermarkPosition.allCases == [
            .topLeft, .topCenter, .topRight,
            .centerLeft, .center, .centerRight,
            .bottomLeft, .bottomCenter, .bottomRight
        ])
        #expect(ImageWatermarkPosition(rawValue: "topLeft") == .topLeft)
        #expect(ImageWatermarkPosition(rawValue: "center") == .center)
        #expect(ImageWatermarkPosition(rawValue: "bottomRight") == .bottomRight)

        let recipe = ImageWatermarkRecipe(
            text: "DEV",
            opacity: 0.65,
            fontSize: 48,
            position: .centerRight,
            color: .black
        )
        #expect(recipe == ImageWatermarkRecipe(
            text: "DEV",
            opacity: 0.65,
            fontSize: 48,
            position: .centerRight,
            color: .black
        ))
        #expect(recipe != ImageWatermarkRecipe(
            text: "DEV",
            opacity: 0.65,
            fontSize: 48,
            position: .centerRight,
            color: .white
        ))
    }

    @Test func conversionTargetsUseWritableAllowlistWithoutHidingOpaqueDestinations() {
        let supported: [ImageFileFormat] = [.jpeg, .png, .heic, .tiff, .webP, .avif]

        #expect(ImageFileFormat.conversionTargetFormats(
            sourceFormat: .jpeg,
            supportedOutputFormats: supported
        ) == [.png, .heic, .avif, .tiff, .webP])
        #expect(ImageFileFormat.conversionTargetFormats(
            sourceFormat: .png,
            supportedOutputFormats: supported
        ) == [.jpeg, .heic, .avif, .tiff, .webP])
        #expect(ImageFileFormat.conversionTargetFormats(
            sourceFormat: .webP,
            supportedOutputFormats: [.jpeg, .png, .heic, .tiff, .avif]
        ) == [.jpeg, .png, .heic, .avif, .tiff])
        #expect(ImageFileFormat.conversionTargetFormats(
            sourceFormat: .jpeg,
            supportedOutputFormats: [.jpeg, .heic]
        ) == [.heic])
        #expect(!ImageFileFormat.conversionTargetFormats(
            sourceFormat: .heic,
            supportedOutputFormats: supported
        ).contains(.heic))
    }

    @Test func compressionCandidatesTrySmallerDailyFormatsWithoutDroppingAlpha() {
        #expect(ImageProcessor.compressionCandidateFormats(
            for: .jpeg,
            hasAlpha: false,
            supportedOutputFormats: [.jpeg, .png, .heic]
        ) == [.jpeg, .heic])
        #expect(ImageProcessor.compressionCandidateFormats(
            for: .png,
            hasAlpha: false,
            supportedOutputFormats: [.jpeg, .png, .heic, .avif]
        ) == [.png, .avif, .heic, .jpeg])
        #expect(ImageProcessor.compressionCandidateFormats(
            for: .png,
            hasAlpha: true,
            supportedOutputFormats: [.jpeg, .png, .heic, .avif]
        ) == [.png, .avif])
        #expect(ImageProcessor.compressionCandidateFormats(
            for: .tiff,
            hasAlpha: false,
            supportedOutputFormats: [.jpeg, .png, .heic, .tiff]
        ) == [.heic, .jpeg])
    }

    @Test func compressionFormatFallsBackWhenSourceFormatCannotBeEncoded() {
        #expect(ImageProcessor.compressionFormat(
            for: .webP,
            hasAlpha: false,
            supportedOutputFormats: [.jpeg, .png]
        ) == .jpeg)
        #expect(ImageProcessor.compressionFormat(
            for: .webP,
            hasAlpha: true,
            supportedOutputFormats: [.jpeg, .png]
        ) == .png)
        #expect(ImageProcessor.compressionFormat(
            for: .png,
            hasAlpha: true,
            supportedOutputFormats: [.jpeg, .png]
        ) == .png)
    }

    @Test func compressionAssessmentBlocksLargerOutput() {
        let output = Self.processedImage(byteCount: 120, originalByteCount: 100)

        let assessment = ImageOutputPolicy.assess(output, for: .compression)

        #expect(assessment.canSave == false)
        #expect(assessment.severity == .blocked)
        #expect(assessment.requiresExplicitLargerSave == false)
        #expect(assessment.sizeDeltaPercent == 20)
    }

    @Test func conversionAssessmentAllowsLargerOutputWithExplicitSave() {
        let output = Self.processedImage(byteCount: 125, originalByteCount: 100)

        let assessment = ImageOutputPolicy.assess(output, for: .conversion)

        #expect(assessment.canSave)
        #expect(assessment.severity == .warning)
        #expect(assessment.requiresExplicitLargerSave)
        #expect(assessment.sizeDeltaPercent == 25)
    }

    @Test func watermarkAssessmentTreatsSmallerOutputAsSuccess() {
        let output = Self.processedImage(byteCount: 75, originalByteCount: 100)

        let assessment = ImageOutputPolicy.assess(output, for: .watermark)

        #expect(assessment.canSave)
        #expect(assessment.severity == .success)
        #expect(assessment.requiresExplicitLargerSave == false)
        #expect(assessment.sizeDeltaPercent == -25)
    }

    @Test func grayscaleProducesEstimatedOutputForAssessment() throws {
        let original = try Self.makeImageData(width: 96, height: 96, format: .jpeg, quality: 0.8)

        let output = try ImageProcessor.grayscale(
            data: original,
            sourceFilenameExtension: "jpg",
            outputFormat: nil,
            quality: 0.82
        )
        let assessment = ImageOutputPolicy.assess(output, for: .grayscale)

        #expect(output.format == .jpeg)
        #expect(output.pixelWidth == 96)
        #expect(output.pixelHeight == 96)
        #expect(assessment.canSave)
    }

    @Test func grayscalePreservesAlphaWhenOutputFormatSupportsAlpha() throws {
        let original = try Self.makeImageData(
            width: 48,
            height: 48,
            format: .png,
            quality: 1.0,
            includesTransparency: true
        )

        let output = try ImageProcessor.grayscale(
            data: original,
            sourceFilenameExtension: "png",
            outputFormat: nil,
            quality: 0.82
        )
        let metadata = try ImageProcessor.inspect(data: output.data, filenameExtension: "png")

        #expect(output.format == .png)
        #expect(metadata.hasAlpha)
        #expect(metadata.transparency == .transparent)
        #expect(output.pixelWidth == 48)
        #expect(output.pixelHeight == 48)
    }

    @Test func compressionKeepsPixelSizeUnlessMaximumSideIsEnabled() throws {
        let original = try Self.makeImageData(width: 180, height: 120, format: .jpeg, quality: 1.0)

        let compressed = try ImageProcessor.compress(
            data: original,
            sourceFilenameExtension: "jpg",
            quality: 0.72,
            maxPixelLength: nil
        )

        #expect(compressed.isSmallerThanOriginal)
        #expect(compressed.pixelWidth == 180)
        #expect(compressed.pixelHeight == 120)
        #expect(compressed.wasResized == false)
        #expect([ImageFileFormat.jpeg, .heic].contains(compressed.format))
    }

    @Test func compressionRespectsExplicitMaximumSide() throws {
        let original = try Self.makeImageData(width: 180, height: 120, format: .jpeg, quality: 1.0)

        let compressed = try ImageProcessor.compress(
            data: original,
            sourceFilenameExtension: "jpg",
            quality: 0.72,
            maxPixelLength: 60
        )

        #expect(max(compressed.pixelWidth, compressed.pixelHeight) == 60)
        #expect(compressed.wasResized)
        #expect(compressed.isSmallerThanOriginal)
    }

    @Test func compressionHonorsRequestedQualityBelowSearchFloor() throws {
        let original = try Self.makeImageData(width: 180, height: 120, format: .jpeg, quality: 1.0)

        let compressed = try ImageProcessor.compress(
            data: original,
            sourceFilenameExtension: "jpg",
            quality: 0.1,
            maxPixelLength: nil
        )

        #expect(compressed.quality == 0.1)
    }

    @Test func conversionReportsLargerOutputBeforeSave() throws {
        let original = try Self.makeImageData(width: 96, height: 96, format: .jpeg, quality: 0.55)

        let converted = try ImageProcessor.convert(
            data: original,
            to: .png,
            quality: nil,
            maxPixelLength: nil
        )

        #expect(converted.format == .png)
        #expect(converted.isLargerThanOriginal)
        #expect(converted.pixelWidth == 96)
        #expect(converted.pixelHeight == 96)
    }

    @Test func conversionToTIFFUsesReadableTIFFOutput() throws {
        let original = try Self.makeImageData(width: 96, height: 64, format: .jpeg, quality: 0.75)

        let converted = try ImageProcessor.convert(
            data: original,
            to: .tiff,
            quality: nil,
            maxPixelLength: nil
        )
        let metadata = try ImageProcessor.inspect(data: converted.data, filenameExtension: "tiff")

        #expect(converted.format == .tiff)
        #expect(metadata.format == .tiff)
        #expect(converted.pixelWidth == 96)
        #expect(converted.pixelHeight == 64)
    }

    @Test func transparentConversionToOpaqueFormatRequiresExplicitFill() throws {
        let original = try Self.makeImageData(
            width: 48,
            height: 48,
            format: .png,
            quality: 1.0,
            includesTransparency: true
        )

        #expect(throws: ImageProcessorError.missingTransparencyFill) {
            try ImageProcessor.convert(
                data: original,
                to: .jpeg,
                quality: 1.0,
                maxPixelLength: nil
            )
        }

        let converted = try ImageProcessor.convert(
            data: original,
            to: .jpeg,
            quality: 1.0,
            maxPixelLength: nil,
            transparencyFill: .black
        )
        let metadata = try ImageProcessor.inspect(data: converted.data, filenameExtension: "jpg")

        #expect(converted.format == .jpeg)
        #expect(metadata.format == .jpeg)
        #expect(metadata.hasAlpha == false)
        #expect(metadata.transparency == .opaque)
        #expect(converted.pixelWidth == 48)
        #expect(converted.pixelHeight == 48)
    }

    @Test func explicitTransparencyFillChangesFlattenedPixels() throws {
        let original = try Self.makeImageData(
            width: 48,
            height: 48,
            format: .png,
            quality: 1.0,
            includesTransparency: true
        )

        let blackOutput = try ImageProcessor.convert(
            data: original,
            to: .jpeg,
            quality: 1.0,
            maxPixelLength: nil,
            transparencyFill: .black
        )
        let whiteOutput = try ImageProcessor.convert(
            data: original,
            to: .jpeg,
            quality: 1.0,
            maxPixelLength: nil,
            transparencyFill: .white
        )
        let blackPixel = try Self.pixelRGBA(in: blackOutput.data, x: 2, y: 0)
        let whitePixel = try Self.pixelRGBA(in: whiteOutput.data, x: 2, y: 0)

        #expect(whitePixel.r > blackPixel.r)
        #expect(whitePixel.g > blackPixel.g)
        #expect(whitePixel.b > blackPixel.b)
    }

    @Test func avifPreservesTransparencyWhenRuntimeCanEncodeIt() throws {
        guard ImageFileFormat.avif.canEncode else { return }
        let original = try Self.makeImageData(
            width: 48,
            height: 48,
            format: .png,
            quality: 1.0,
            includesTransparency: true
        )

        let converted = try ImageProcessor.convert(
            data: original,
            to: .avif,
            quality: ImageFileFormat.avif.defaultConversionQuality,
            maxPixelLength: nil
        )
        let metadata = try ImageProcessor.inspect(data: converted.data, filenameExtension: "avif")

        #expect(converted.format == .avif)
        #expect(metadata.format == .avif)
        #expect(metadata.pixelWidth == 48)
        #expect(metadata.pixelHeight == 48)
        #expect(metadata.hasAlpha)
        #expect(metadata.transparency == .transparent)
    }

    @Test func opaqueRGBAImageDoesNotRequireTransparencyFill() throws {
        let original = try Self.makeImageData(width: 48, height: 48, format: .png, quality: 1.0)
        let sourceMetadata = try ImageProcessor.inspect(data: original, filenameExtension: "png")

        #expect(sourceMetadata.hasAlpha)
        #expect(sourceMetadata.transparency == .opaque)
        let converted = try ImageProcessor.convert(
            data: original,
            to: .jpeg,
            quality: 1.0,
            maxPixelLength: nil
        )
        #expect(converted.format == .jpeg)
    }

    @Test func watermarkDefaultsToSourceFormat() throws {
        let original = try Self.makeImageData(width: 160, height: 90, format: .jpeg, quality: 0.82)

        let watermarked = try ImageProcessor.watermark(
            data: original,
            sourceFilenameExtension: "jpg",
            recipe: ImageWatermarkRecipe(
                text: "DEV",
                opacity: 0.65,
                fontSize: 18,
                position: .bottomRight,
                color: .white
            ),
            outputFormat: nil
        )

        let metadata = try ImageProcessor.inspect(data: watermarked.data, filenameExtension: "jpg")
        #expect(watermarked.format == .jpeg)
        #expect(metadata.format == .jpeg)
        #expect(watermarked.pixelWidth == 160)
        #expect(watermarked.pixelHeight == 90)
    }

    @Test func watermarkMatchesSourceJPEGQualityWithoutSizeSearch() throws {
        let original = try Self.makeImageData(width: 160, height: 90, format: .jpeg, quality: 0.82)

        let watermarked = try ImageProcessor.watermark(
            data: original,
            sourceFilenameExtension: "jpg",
            recipe: ImageWatermarkRecipe(
                text: "DEV",
                opacity: 0.65,
                fontSize: 18,
                position: .bottomRight,
                color: .white
            ),
            outputFormat: nil
        )
        let sourceMatchedQuality = try #require(
            JPEGSourceEncodingQuality.matchedImageIOQuality(for: original)
        )

        #expect(watermarked.quality == sourceMatchedQuality)
        #expect(watermarked.quality != ImageProcessor.highFidelityEncodingQuality)
        #expect(watermarked.format == .jpeg)
    }

    @Test func watermarkHandlesTinyImagesAndExtremeTextParameters() throws {
        let original = try Self.makeImageData(width: 24, height: 24, format: .png, quality: 1.0)

        let watermarked = try ImageProcessor.watermark(
            data: original,
            sourceFilenameExtension: "png",
            recipe: ImageWatermarkRecipe(
                text: String(repeating: "W", count: 80),
                opacity: 2.0,
                fontSize: 1024,
                position: .topRight,
                color: .black
            ),
            outputFormat: nil
        )

        #expect(watermarked.format == .png)
        #expect(watermarked.pixelWidth == 24)
        #expect(watermarked.pixelHeight == 24)
    }

    @Test func watermarkMaximumFontSizeFitsCommonImageOrientations() throws {
        for (width, height, position) in [
            (800, 450, ImageWatermarkPosition.bottomRight),
            (450, 800, ImageWatermarkPosition.topLeft)
        ] {
            let original = try Self.makeImageData(width: width, height: height, format: .png, quality: 1.0)
            let watermarked = try ImageProcessor.watermark(
                data: original,
                sourceFilenameExtension: "png",
                recipe: ImageWatermarkRecipe(
                    text: String(repeating: "W", count: 80),
                    opacity: 0.8,
                    fontSize: 1024,
                    position: position,
                    color: .white
                ),
                outputFormat: nil
            )

            #expect(watermarked.pixelWidth == width)
            #expect(watermarked.pixelHeight == height)
        }
    }

    @Test func watermarkBlackAndWhiteColorsChangeNeutralPixelsInOppositeDirections() throws {
        let original = try Self.makeSolidImageData(width: 240, height: 180, red: 128, green: 128, blue: 128)
        let black = try ImageProcessor.watermark(
            data: original,
            sourceFilenameExtension: "png",
            recipe: ImageWatermarkRecipe(
                text: "WATERMARK",
                opacity: 1,
                fontSize: 32,
                position: .center,
                color: .black
            ),
            outputFormat: nil
        )
        let white = try ImageProcessor.watermark(
            data: original,
            sourceFilenameExtension: "png",
            recipe: ImageWatermarkRecipe(
                text: "WATERMARK",
                opacity: 1,
                fontSize: 32,
                position: .center,
                color: .white
            ),
            outputFormat: nil
        )

        #expect(try Self.averageLuminanceDelta(from: original, to: black.data) < 0)
        #expect(try Self.averageLuminanceDelta(from: original, to: white.data) > 0)
    }

    @Test func watermarkNineAnchorsStayInsideExpectedCanvasThirds() throws {
        let width = 240
        let height = 180
        let original = try Self.makeSolidImageData(width: width, height: height, red: 220, green: 220, blue: 220)

        for position in ImageWatermarkPosition.allCases {
            let output = try ImageProcessor.watermark(
                data: original,
                sourceFilenameExtension: "png",
                recipe: ImageWatermarkRecipe(
                    text: "WM",
                    opacity: 1,
                    fontSize: 28,
                    position: position,
                    color: .black
                ),
                outputFormat: nil
            )
            let changedBounds = try Self.changedPixelBounds(from: original, to: output.data)
            let bounds = try #require(changedBounds)
            let centerX = Double(bounds.minX + bounds.maxX) / 2
            let centerY = Double(bounds.minY + bounds.maxY) / 2

            switch position {
            case .topLeft, .centerLeft, .bottomLeft:
                #expect(centerX < Double(width) / 3)
            case .topCenter, .center, .bottomCenter:
                #expect(centerX >= Double(width) / 3 && centerX <= Double(width) * 2 / 3)
            case .topRight, .centerRight, .bottomRight:
                #expect(centerX > Double(width) * 2 / 3)
            }

            switch position {
            case .topLeft, .topCenter, .topRight:
                #expect(centerY < Double(height) / 3)
            case .centerLeft, .center, .centerRight:
                #expect(centerY >= Double(height) / 3 && centerY <= Double(height) * 2 / 3)
            case .bottomLeft, .bottomCenter, .bottomRight:
                #expect(centerY > Double(height) * 2 / 3)
            }
        }
    }

    @Test func watermarkPreviewUsesBoundedSourceAndSameRecipe() throws {
        let original = try Self.makeSolidImageData(width: 1600, height: 1200, red: 160, green: 160, blue: 160)
        let previewSource = try ImageProcessor.previewImageData(data: original, maxPixelLength: 800)
        let preview = try ImageProcessor.watermarkPreview(
            data: previewSource,
            sourcePixelWidth: 1600,
            sourcePixelHeight: 1200,
            recipe: ImageWatermarkRecipe(
                text: "PREVIEW",
                opacity: 0.7,
                fontSize: 120,
                position: .bottomCenter,
                color: .white
            )
        )
        let metadata = try ImageProcessor.inspect(data: preview, filenameExtension: "png")

        #expect(metadata.format == .png)
        #expect(metadata.pixelWidth == 800)
        #expect(metadata.pixelHeight == 600)
    }

    @Test func watermarkPreviewMatchesFinalGeometryForRotatedSource() throws {
        let original = try Self.makeImageData(
            width: 96,
            height: 64,
            format: .jpeg,
            quality: 0.9,
            properties: [kCGImagePropertyOrientation: 6]
        )
        let orientedSource = try ImageProcessor.previewImageData(data: original, maxPixelLength: 96)
        let recipe = ImageWatermarkRecipe(
            text: "ROTATE",
            opacity: 1,
            fontSize: 18,
            position: .bottomCenter,
            color: .black
        )
        let preview = try ImageProcessor.watermarkPreview(
            data: orientedSource,
            sourcePixelWidth: 96,
            sourcePixelHeight: 64,
            recipe: recipe
        )
        let final = try ImageProcessor.watermark(
            data: original,
            sourceFilenameExtension: "jpg",
            recipe: recipe,
            outputFormat: .png
        )
        let previewChangedBounds = try Self.changedPixelBounds(from: orientedSource, to: preview)
        let finalChangedBounds = try Self.changedPixelBounds(from: orientedSource, to: final.data)
        let previewBounds = try #require(previewChangedBounds)
        let finalBounds = try #require(finalChangedBounds)

        #expect(final.pixelWidth == 64)
        #expect(final.pixelHeight == 96)
        #expect(abs(previewBounds.minX - finalBounds.minX) <= 1)
        #expect(abs(previewBounds.minY - finalBounds.minY) <= 1)
        #expect(abs(previewBounds.maxX - finalBounds.maxX) <= 1)
        #expect(abs(previewBounds.maxY - finalBounds.maxY) <= 1)
    }

    @Test func watermarkPreservesDPIAndSafeTIFFMetadataWhileClearingOrientation() throws {
        let original = try Self.makeImageData(
            width: 96,
            height: 64,
            format: .jpeg,
            quality: 0.9,
            properties: [
                kCGImagePropertyDPIWidth: 144,
                kCGImagePropertyDPIHeight: 144,
                kCGImagePropertyOrientation: 6,
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFMake: "DevTools",
                    kCGImagePropertyTIFFOrientation: 6
                ]
            ]
        )
        let output = try ImageProcessor.watermark(
            data: original,
            sourceFilenameExtension: "jpg",
            recipe: ImageWatermarkRecipe(
                text: "META",
                opacity: 0.7,
                fontSize: 16,
                position: .topCenter,
                color: .black
            ),
            outputFormat: nil
        )
        let properties = try Self.imageProperties(in: output.data)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

        #expect(output.pixelWidth == 64)
        #expect(output.pixelHeight == 96)
        #expect((properties[kCGImagePropertyDPIWidth] as? Double) == 144)
        #expect((properties[kCGImagePropertyDPIHeight] as? Double) == 144)
        #expect(tiff?[kCGImagePropertyTIFFMake] as? String == "DevTools")
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect((tiff?[kCGImagePropertyTIFFOrientation] as? Int ?? 1) == 1)
    }

    @Test func watermarkPreservesAlphaAndUsesLosslessPNGAndTIFFEncodingPaths() throws {
        let transparent = try Self.makeImageData(
            width: 64,
            height: 48,
            format: .png,
            quality: 1,
            includesTransparency: true
        )
        let recipe = ImageWatermarkRecipe(
            text: "ALPHA",
            opacity: 0.5,
            fontSize: 14,
            position: .bottomCenter,
            color: .white
        )
        let png = try ImageProcessor.watermark(
            data: transparent,
            sourceFilenameExtension: "png",
            recipe: recipe,
            outputFormat: nil
        )
        let tiff = try ImageProcessor.watermark(
            data: transparent,
            sourceFilenameExtension: "png",
            recipe: recipe,
            outputFormat: .tiff
        )
        let pngMetadata = try ImageProcessor.inspect(data: png.data, filenameExtension: "png")
        let tiffMetadata = try ImageProcessor.inspect(data: tiff.data, filenameExtension: "tiff")

        #expect(png.quality == nil)
        #expect(tiff.quality == nil)
        #expect(pngMetadata.transparency == .transparent)
        #expect(tiffMetadata.transparency == .transparent)
        #expect(tiffMetadata.pixelWidth == 64)
        #expect(tiffMetadata.pixelHeight == 48)
    }

    @Test func watermarkDoesNotAddAlphaChannelToOpaqueSource() throws {
        let opaqueJPEG = try Self.makeImageData(width: 64, height: 48, format: .jpeg, quality: 0.9)
        let output = try ImageProcessor.watermark(
            data: opaqueJPEG,
            sourceFilenameExtension: "jpg",
            recipe: ImageWatermarkRecipe(
                text: "OPAQUE",
                opacity: 0.6,
                fontSize: 14,
                position: .bottomRight,
                color: .white
            ),
            outputFormat: .png
        )
        let metadata = try ImageProcessor.inspect(data: output.data, filenameExtension: "png")

        #expect(metadata.hasAlpha == false)
        #expect(metadata.transparency == .opaque)
    }

    @Test func watermarkPreservesSixteenBitPNGDepthWhenImageIOSupportsIt() throws {
        let original = try Self.make16BitPNGData(width: 48, height: 32)
        let sourceImage = try Self.cgImage(in: original)
        guard sourceImage.bitsPerComponent == 16 else { return }

        let output = try ImageProcessor.watermark(
            data: original,
            sourceFilenameExtension: "png",
            recipe: ImageWatermarkRecipe(
                text: "16",
                opacity: 0.6,
                fontSize: 12,
                position: .topLeft,
                color: .black
            ),
            outputFormat: nil
        )
        let outputImage = try Self.cgImage(in: output.data)

        #expect(outputImage.bitsPerComponent == 16)
        #expect(outputImage.width == 48)
        #expect(outputImage.height == 32)
    }

    @Test func imageBudgetRejectsOversizedByteAndPixelInputs() throws {
        #expect(throws: ImageProcessorError.inputFileTooLarge(
            actualBytes: ImageProcessingBudget.maxInputBytes + 1,
            maxBytes: ImageProcessingBudget.maxInputBytes
        )) {
            try ImageProcessingBudget.validateInputByteCount(ImageProcessingBudget.maxInputBytes + 1)
        }

        #expect(throws: ImageProcessorError.imageTooLarge(
            pixelCount: ImageProcessingBudget.maxPixelCount + 1,
            maxPixelCount: ImageProcessingBudget.maxPixelCount
        )) {
            try ImageProcessingBudget.validateDimensions(
                width: ImageProcessingBudget.maxPixelCount + 1,
                height: 1
            )
        }

        try ImageProcessingBudget.validateInputByteCount(ImageProcessingBudget.maxInputBytes)
        try ImageProcessingBudget.validateDimensions(width: 10_000, height: 5_000)
        #expect(ImageProcessorError.imageTooLarge(
            pixelCount: ImageProcessingBudget.maxPixelCount + 1,
            maxPixelCount: ImageProcessingBudget.maxPixelCount
        ).errorDescription == "图片像素总数上限为 5000 万像素，所选图片已超出。")
    }

    @Test func compressAppliesExternalOptimizerWhenItProducesSmallerPNG() throws {
        // A transparent image forces the PNG-only candidate path.
        let original = try Self.makeImageData(width: 64, height: 64, format: .png, quality: 1.0, includesTransparency: true)

        // Fake optimizer returns a tiny fixed payload, standing in for pngquant.
        let tiny = Data(repeating: 0, count: 8)
        let optimizer = StubOptimizer(result: tiny)

        let compressed = try ImageProcessor.compress(
            data: original,
            sourceFilenameExtension: "png",
            quality: 0.8,
            maxPixelLength: nil,
            optimizer: optimizer
        )

        #expect(compressed.format == .png)
        #expect(compressed.data == tiny)
        #expect(optimizer.calls.contains(.png))
    }

    @Test func compressKeepsImageIOOutputWhenOptimizerReturnsNil() throws {
        let original = try Self.makeImageData(width: 64, height: 64, format: .png, quality: 1.0, includesTransparency: true)

        let baseline = try ImageProcessor.compress(
            data: original,
            sourceFilenameExtension: "png",
            quality: 0.8,
            maxPixelLength: nil
        )
        let withNilOptimizer = try ImageProcessor.compress(
            data: original,
            sourceFilenameExtension: "png",
            quality: 0.8,
            maxPixelLength: nil,
            optimizer: StubOptimizer(result: nil)
        )

        #expect(withNilOptimizer.data == baseline.data)
    }

    private final class StubOptimizer: ExternalImageOptimizing, @unchecked Sendable {
        let result: Data?
        private(set) var calls: [ImageFileFormat] = []

        init(result: Data?) {
            self.result = result
        }

        func optimize(_ data: Data, format: ImageFileFormat, lossy: Bool) -> Data? {
            calls.append(format)
            return result
        }
    }

    private static func makeImageData(
        width: Int,
        height: Int,
        format: ImageFileFormat,
        quality: Double,
        includesTransparency: Bool = false,
        properties extraProperties: [CFString: Any] = [:]
    ) throws -> Data {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let offset = ((y * width) + x) * 4
                pixels[offset] = UInt8((x * 37 + y * 13) % 256)
                pixels[offset + 1] = UInt8((x * 11 + y * 29) % 256)
                pixels[offset + 2] = UInt8((x * 19 + y * 7) % 256)
                pixels[offset + 3] = includesTransparency && (x + y).isMultiple(of: 2) ? 96 : 255
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
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
              ) else {
            throw TestImageError.renderingFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.utTypeIdentifier as CFString, 1, nil) else {
            throw TestImageError.destinationUnavailable
        }

        var properties = extraProperties
        if format.supportsLossyQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.encodingFailed
        }
        return output as Data
    }

    private static func makeSolidImageData(
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8
    ) throws -> Data {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = red
            pixels[offset + 1] = green
            pixels[offset + 2] = blue
            pixels[offset + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
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
              ) else {
            throw TestImageError.renderingFailed
        }
        return try encodeTestImage(image, format: .png, quality: 1, properties: [:])
    }

    private static func make16BitPNGData(width: Int, height: Int) throws -> Data {
        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt16((x * 1301 + y * 733) % 65_536)
                pixels[offset + 1] = UInt16((x * 997 + y * 1901) % 65_536)
                pixels[offset + 2] = UInt16((x * 2371 + y * 401) % 65_536)
                pixels[offset + 3] = UInt16.max
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 16,
                bitsPerPixel: 64,
                bytesPerRow: width * 8,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder16Little.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw TestImageError.renderingFailed
        }
        return try encodeTestImage(image, format: .png, quality: 1, properties: [:])
    }

    private static func cgImage(in data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TestImageError.renderingFailed
        }
        return image
    }

    private static func encodeTestImage(
        _ image: CGImage,
        format: ImageFileFormat,
        quality: Double,
        properties extraProperties: [CFString: Any]
    ) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.utTypeIdentifier as CFString, 1, nil) else {
            throw TestImageError.destinationUnavailable
        }
        var properties = extraProperties
        if format.supportsLossyQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.encodingFailed
        }
        return output as Data
    }

    private static func imageProperties(in data: Data) throws -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw TestImageError.renderingFailed
        }
        return properties
    }

    private static func rgbaPixels(in data: Data) throws -> (width: Int, height: Int, bytes: [UInt8]) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TestImageError.renderingFailed
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                throw TestImageError.renderingFailed
            }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (image.width, image.height, bytes)
    }

    private static func averageLuminanceDelta(from original: Data, to output: Data) throws -> Double {
        let source = try rgbaPixels(in: original)
        let result = try rgbaPixels(in: output)
        guard source.width == result.width, source.height == result.height else {
            throw TestImageError.renderingFailed
        }
        var total = 0.0
        for index in stride(from: 0, to: source.bytes.count, by: 4) {
            total += Double(result.bytes[index]) - Double(source.bytes[index])
            total += Double(result.bytes[index + 1]) - Double(source.bytes[index + 1])
            total += Double(result.bytes[index + 2]) - Double(source.bytes[index + 2])
        }
        return total / Double(source.width * source.height * 3)
    }

    private static func changedPixelBounds(
        from original: Data,
        to output: Data
    ) throws -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        let source = try rgbaPixels(in: original)
        let result = try rgbaPixels(in: output)
        guard source.width == result.width, source.height == result.height else {
            throw TestImageError.renderingFailed
        }
        var minX = source.width
        var minY = source.height
        var maxX = -1
        var maxY = -1
        for y in 0..<source.height {
            for x in 0..<source.width {
                let offset = (y * source.width + x) * 4
                let changed = (0..<4).contains { channel in
                    abs(Int(source.bytes[offset + channel]) - Int(result.bytes[offset + channel])) > 2
                }
                if changed {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return (minX, minY, maxX, maxY)
    }

    private static func pixelRGBA(in data: Data, x: Int, y: Int) throws -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              x >= 0, y >= 0, x < image.width, y < image.height else {
            throw TestImageError.renderingFailed
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        return try pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                throw TestImageError.renderingFailed
            }

            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let offset = ((y * image.width) + x) * 4
            return (buffer[offset], buffer[offset + 1], buffer[offset + 2], buffer[offset + 3])
        }
    }

    private static func processedImage(byteCount: Int, originalByteCount: Int) -> ProcessedImage {
        ProcessedImage(
            data: Data(repeating: 0, count: byteCount),
            format: .jpeg,
            pixelWidth: 1,
            pixelHeight: 1,
            originalByteCount: originalByteCount,
            quality: nil,
            wasResized: false
        )
    }

    private enum TestImageError: Error {
        case renderingFailed
        case destinationUnavailable
        case encodingFailed
    }
}
