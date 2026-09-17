import XToolsCore
import Foundation

enum ToolPreferenceOutOfRangePolicy {
    case clamp
    case useDefault
}

@MainActor
struct ToolPreferenceKey<Value> {
    let rawKey: String
    let defaultValue: Value

    fileprivate let read: (UserDefaults, String) -> Value?
    fileprivate let write: (UserDefaults, String, Value) -> Void
    fileprivate let normalize: (Value) -> Value
}

extension ToolPreferenceKey where Value == Bool {
    static func bool(_ rawKey: String, default defaultValue: Bool) -> Self {
        Self(
            rawKey: rawKey,
            defaultValue: defaultValue,
            read: { defaults, key in
                defaults.object(forKey: key) as? Bool
            },
            write: { defaults, key, value in
                defaults.set(value, forKey: key)
            },
            normalize: { $0 }
        )
    }
}

extension ToolPreferenceKey where Value == Int {
    static func integer(
        _ rawKey: String,
        default defaultValue: Int,
        range: ClosedRange<Int>? = nil,
        outOfRangePolicy: ToolPreferenceOutOfRangePolicy = .clamp
    ) -> Self {
        if let range {
            precondition(range.contains(defaultValue))
        }

        return Self(
            rawKey: rawKey,
            defaultValue: defaultValue,
            read: { defaults, key in
                defaults.object(forKey: key) as? Int
            },
            write: { defaults, key, value in
                defaults.set(value, forKey: key)
            },
            normalize: { value in
                guard let range else { return value }
                guard !range.contains(value) else { return value }
                switch outOfRangePolicy {
                case .clamp:
                    return min(max(value, range.lowerBound), range.upperBound)
                case .useDefault:
                    return defaultValue
                }
            }
        )
    }
}

extension ToolPreferenceKey where Value == Double {
    static func double(
        _ rawKey: String,
        default defaultValue: Double,
        range: ClosedRange<Double>? = nil
    ) -> Self {
        if let range {
            precondition(range.contains(defaultValue))
        }

        return Self(
            rawKey: rawKey,
            defaultValue: defaultValue,
            read: { defaults, key in
                defaults.object(forKey: key) as? Double
            },
            write: { defaults, key, value in
                defaults.set(value, forKey: key)
            },
            normalize: { value in
                guard let range else { return value }
                return min(max(value, range.lowerBound), range.upperBound)
            }
        )
    }
}

extension ToolPreferenceKey where Value == String {
    static func string(
        _ rawKey: String,
        default defaultValue: String,
        allowedValues: Set<String>? = nil
    ) -> Self {
        if let allowedValues {
            precondition(allowedValues.contains(defaultValue))
        }

        return Self(
            rawKey: rawKey,
            defaultValue: defaultValue,
            read: { defaults, key in
                defaults.string(forKey: key)
            },
            write: { defaults, key, value in
                defaults.set(value, forKey: key)
            },
            normalize: { value in
                guard let allowedValues else { return value }
                return allowedValues.contains(value) ? value : defaultValue
            }
        )
    }
}

extension ToolPreferenceKey where Value: RawRepresentable, Value.RawValue == String {
    static func rawRepresentable(
        _ rawKey: String,
        default defaultValue: Value
    ) -> Self {
        Self(
            rawKey: rawKey,
            defaultValue: defaultValue,
            read: { defaults, key in
                guard let rawValue = defaults.string(forKey: key) else { return nil }
                return Value(rawValue: rawValue)
            },
            write: { defaults, key, value in
                defaults.set(value.rawValue, forKey: key)
            },
            normalize: { $0 }
        )
    }
}

@MainActor
final class ToolPreferenceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func value<Value>(for key: ToolPreferenceKey<Value>) -> Value {
        key.normalize(key.read(defaults, key.rawKey) ?? key.defaultValue)
    }

    func set<Value>(_ value: Value, for key: ToolPreferenceKey<Value>) {
        key.write(defaults, key.rawKey, key.normalize(value))
    }
}

@MainActor
enum AppShellPreferenceKeys {
    static let autoResumeLastTool = ToolPreferenceKey<Bool>.bool(
        "tools.shell.autoResumeLastTool.v1", default: false
    )
    static let selectedToolID = ToolPreferenceKey<String>.string(
        "tools.shell.selectedToolID.v1",
        default: ""
    )

    static let sidebarVisibility = ToolPreferenceKey<String>.string(
        "tools.shell.sidebarVisibility.v1",
        default: "visible",
        allowedValues: ["visible", "hidden"]
    )
}

@MainActor
enum SensitiveToolPreferenceKeys {
    static let hashDigestEncoding = ToolPreferenceKey<String>.string(
        "tools.hashText.digestEncoding.v1",
        default: "hex",
        allowedValues: ["hex", "binary", "base64", "base64url"]
    )

    static let obfuscatorKeepFirst = ToolPreferenceKey<Int>.integer(
        "tools.stringObfuscator.keepFirst.v1",
        default: 4,
        range: 0...20,
        outOfRangePolicy: .useDefault
    )
    static let obfuscatorKeepLast = ToolPreferenceKey<Int>.integer(
        "tools.stringObfuscator.keepLast.v1",
        default: 4,
        range: 0...20,
        outOfRangePolicy: .useDefault
    )
    static let obfuscatorKeepSpaces = ToolPreferenceKey<Bool>.bool(
        "tools.stringObfuscator.keepSpaces.v1",
        default: true
    )
    static let obfuscatorReplacementCharacter = ToolPreferenceKey<String>.string(
        "tools.stringObfuscator.replacementCharacter.v1",
        default: "*"
    )

    static let tokenLength = ToolPreferenceKey<Int>.integer(
        "tools.tokenGenerator.length.v1",
        default: 32,
        range: 1...512,
        outOfRangePolicy: .useDefault
    )
    static let tokenMode = ToolPreferenceKey<TokenGenerationMode>.rawRepresentable(
        "tools.tokenGenerator.mode.v1",
        default: .characterSet
    )
    static let tokenQuantity = ToolPreferenceKey<Int>.integer(
        "tools.tokenGenerator.quantity.v1",
        default: 1,
        range: 1...20,
        outOfRangePolicy: .useDefault
    )
    static let tokenLowercaseEnabled = ToolPreferenceKey<Bool>.bool(
        "tools.tokenGenerator.lowercaseEnabled.v1",
        default: true
    )
    static let tokenUppercaseEnabled = ToolPreferenceKey<Bool>.bool(
        "tools.tokenGenerator.uppercaseEnabled.v1",
        default: true
    )
    static let tokenNumbersEnabled = ToolPreferenceKey<Bool>.bool(
        "tools.tokenGenerator.numbersEnabled.v1",
        default: true
    )
    static let tokenSymbolsEnabled = ToolPreferenceKey<Bool>.bool(
        "tools.tokenGenerator.symbolsEnabled.v1",
        default: false
    )

    static let uuidQuantity = ToolPreferenceKey<Int>.integer(
        "tools.uuidGenerator.quantity.v1",
        default: 8,
        range: 1...32,
        outOfRangePolicy: .useDefault
    )
    static let uuidVersion = ToolPreferenceKey<UUIDGenerationVersion>.rawRepresentable(
        "tools.uuidGenerator.version.v1",
        default: .v4
    )

    static let passwordLength = ToolPreferenceKey<Int>.integer(
        "tools.passwordGenerator.length.v1",
        default: 16,
        range: 8...128,
        outOfRangePolicy: .useDefault
    )
    static let passwordQuantity = ToolPreferenceKey<Int>.integer(
        "tools.passwordGenerator.quantity.v1",
        default: 5,
        range: 1...20,
        outOfRangePolicy: .useDefault
    )
    static let passwordLowercaseEnabled = ToolPreferenceKey<Bool>.bool(
        "tools.passwordGenerator.lowercaseEnabled.v1",
        default: true
    )
    static let passwordUppercaseEnabled = ToolPreferenceKey<Bool>.bool(
        "tools.passwordGenerator.uppercaseEnabled.v1",
        default: true
    )
    static let passwordNumbersEnabled = ToolPreferenceKey<Bool>.bool(
        "tools.passwordGenerator.numbersEnabled.v1",
        default: true
    )
    static let passwordSymbolsEnabled = ToolPreferenceKey<Bool>.bool(
        "tools.passwordGenerator.symbolsEnabled.v1",
        default: false
    )
    static let passwordExcludeAmbiguous = ToolPreferenceKey<Bool>.bool(
        "tools.passwordGenerator.excludeAmbiguous.v1",
        default: true
    )

    static let allRawKeys = [
        hashDigestEncoding.rawKey,
        obfuscatorKeepFirst.rawKey,
        obfuscatorKeepLast.rawKey,
        obfuscatorKeepSpaces.rawKey,
        obfuscatorReplacementCharacter.rawKey,
        tokenMode.rawKey,
        tokenLength.rawKey,
        tokenQuantity.rawKey,
        tokenLowercaseEnabled.rawKey,
        tokenUppercaseEnabled.rawKey,
        tokenNumbersEnabled.rawKey,
        tokenSymbolsEnabled.rawKey,
        uuidQuantity.rawKey,
        uuidVersion.rawKey,
        passwordLength.rawKey,
        passwordQuantity.rawKey,
        passwordLowercaseEnabled.rawKey,
        passwordUppercaseEnabled.rawKey,
        passwordNumbersEnabled.rawKey,
        passwordSymbolsEnabled.rawKey,
        passwordExcludeAmbiguous.rawKey
    ]
}

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

@MainActor
enum TextDevelopmentToolPreferenceKeys {
    static let integerBase = ToolPreferenceKey<String>.string(
        "tools.integerBase.inputBase.v1",
        default: "10",
        allowedValues: ["2", "8", "10", "16"]
    )
    static let jsonIndent = ToolPreferenceKey<String>.string(
        "tools.jsonFormatter.indent.v1",
        default: "4",
        allowedValues: ["2", "4", "compact"]
    )
    static let sqlKeywordCase = ToolPreferenceKey<SQLFormatting.KeywordCase>.rawRepresentable(
        "tools.sqlFormatter.keywordCase.v1",
        default: .upper
    )
    static let sqlIndent = ToolPreferenceKey<String>.string(
        "tools.sqlFormatter.indent.v2",
        default: "2",
        allowedValues: ["2", "4", "compact"]
    )
    static let emojiToneIndex = ToolPreferenceKey<Int>.integer(
        "tools.emoji.toneIndex.v1",
        default: 0,
        range: 0...5,
        outOfRangePolicy: .useDefault
    )

    static var allRawKeys: [String] {
        [
            integerBase.rawKey,
            jsonIndent.rawKey,
            sqlKeywordCase.rawKey,
            sqlIndent.rawKey,
            emojiToneIndex.rawKey
        ]
    }
}
