import Foundation
import XToolsCore

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
