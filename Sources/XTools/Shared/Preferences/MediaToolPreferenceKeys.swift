import Foundation
import XToolsCore

@MainActor
enum MediaToolPreferenceKeys {
    static let base64FileOutputMode = ToolPreferenceKey<Base64Conversion.FileOutputMode>.rawRepresentable(
        "tools.base64File.outputMode.v1",
        default: .dataURL
    )

    static let imageConverterTargetFormat = ToolPreferenceKey<ImageFileFormat>.rawRepresentable(
        "tools.imageConverter.targetFormat.v1",
        default: .png
    )
    static let imageConverterQuality = ToolPreferenceKey<Double>.double(
        "tools.imageConverter.quality.v1",
        default: ImageFileFormat.jpeg.defaultConversionQuality ?? 0.82,
        range: 0.1...1.0
    )
    static let imageConverterTransparencyFillMode = ToolPreferenceKey<ImageTransparencyFillMode>.rawRepresentable(
        "tools.imageConverter.transparencyFillMode.v1",
        default: .unset
    )
    static let imageConverterCustomTransparencyFillHex = ToolPreferenceKey<String>(
        rawKey: "tools.imageConverter.customTransparencyFillHex.v1",
        defaultValue: ImageRGBColor.white.hexString,
        read: { defaults, key in
            defaults.string(forKey: key)
        },
        write: { defaults, key, value in
            defaults.set(value, forKey: key)
        },
        normalize: { value in
            ImageRGBColor(hex: value)?.hexString ?? ImageRGBColor.white.hexString
        }
    )

    static let imageCompressorPreference = ToolPreferenceKey<ImageCompressionPreference>.rawRepresentable(
        "tools.imageCompressor.preference.v1",
        default: .balanced
    )
    static let imageCompressorLimitsDimensions = ToolPreferenceKey<Bool>.bool(
        "tools.imageCompressor.limitsDimensions.v1",
        default: false
    )
    static let imageCompressorMaxPixelLength = ToolPreferenceKey<Int>.integer(
        "tools.imageCompressor.maxPixelLength.v1",
        default: 1920,
        range: 128...12_000,
        outOfRangePolicy: .useDefault
    )

    static let imageWatermarkOpacity = ToolPreferenceKey<Double>.double(
        "tools.imageWatermark.opacity.v1",
        default: 0.5,
        range: 0.1...1.0
    )
    static let imageWatermarkFontSize = ToolPreferenceKey<Double>.double(
        "tools.imageWatermark.fontSize.v1",
        default: 36,
        range: 12...1024
    )
    static let imageWatermarkSizeRatio = ToolPreferenceKey<Double>.double(
        "tools.imageWatermark.sizeRatio.v2",
        default: ImageWatermarkSizing.defaultRatio,
        range: ImageWatermarkSizing.ratioRange
    )
    static let imageWatermarkPosition = ToolPreferenceKey<ImageWatermarkPosition>.rawRepresentable(
        "tools.imageWatermark.position.v1",
        default: .bottomRight
    )
    static let imageWatermarkColor = ToolPreferenceKey<ImageWatermarkTextColor>.rawRepresentable(
        "tools.imageWatermark.color.v1",
        default: .white
    )

    static let allRawKeys = [
        base64FileOutputMode.rawKey,
        imageConverterTargetFormat.rawKey,
        imageConverterQuality.rawKey,
        imageConverterTransparencyFillMode.rawKey,
        imageConverterCustomTransparencyFillHex.rawKey,
        imageCompressorPreference.rawKey,
        imageCompressorLimitsDimensions.rawKey,
        imageCompressorMaxPixelLength.rawKey,
        imageWatermarkOpacity.rawKey,
        imageWatermarkFontSize.rawKey,
        imageWatermarkSizeRatio.rawKey,
        imageWatermarkPosition.rawKey,
        imageWatermarkColor.rawKey
    ]
}
