import XToolsCore
import Foundation
import Testing

struct TextEncryptionServiceTests {
    @Test func allAlgorithmsRoundTrip() throws {
        let plaintext = "hello 加密\nline 2"
        let password = "correct horse battery staple"

        for algorithm in TextEncryptionService.Algorithm.allCases {
            let ciphertext = try TextEncryptionService.encrypt(plaintext, password: password, algorithm: algorithm)
            let decrypted = try TextEncryptionService.decrypt(ciphertext, password: password, algorithm: algorithm)

            #expect(decrypted == plaintext)
        }
    }

    @Test func encryptedOutputsDifferAcrossAlgorithms() throws {
        let plaintext = "abc"
        let password = "123"
        var ciphertexts = Set<String>()

        for algorithm in TextEncryptionService.Algorithm.allCases {
            let ciphertext = try TextEncryptionService.encrypt(plaintext, password: password, algorithm: algorithm)
            ciphertexts.insert(ciphertext)
        }

        #expect(ciphertexts.count == TextEncryptionService.Algorithm.allCases.count)
    }

    @Test func aesGCMOutputUsesVersionedModernFormat() throws {
        let ciphertext = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aesGCM)
        let decrypted = try TextEncryptionService.decrypt(ciphertext, password: "secret", algorithm: .aesGCM)

        #expect(ciphertext.hasPrefix(Self.modernPrefix))
        #expect(!ciphertext.contains("plain"))
        #expect(decrypted == "plain")
    }

    @Test func aesGCMOutputsDifferForSameInput() throws {
        let first = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aesGCM)
        let second = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aesGCM)

        #expect(first != second)
    }

    @Test func aesGCMV1RejectsNonContractPBKDF2RoundsBeforeKDF() throws {
        let ciphertext = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aesGCM)

        for rounds in [UInt32(0), 1, 599_999, 600_001, UInt32.max] {
            let mutated = try Self.modernPayload(ciphertext, replacingRoundsWith: rounds)
            #expect(throws: TextEncryptionService.Error.invalidFormat) {
                _ = try TextEncryptionService.decrypt(mutated, password: "secret", algorithm: .aesGCM)
            }
        }
    }

    @Test func aesGCMTamperedPayloadFailsAuthentication() throws {
        let ciphertext = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aesGCM)
        let tamperedTag = try Self.tamperModernPayload(ciphertext)
        let tamperedSalt = try Self.tamperModernPayload(ciphertext, offset: 4)

        #expect(throws: TextEncryptionService.Error.decryptionFailed) {
            _ = try TextEncryptionService.decrypt(tamperedTag, password: "secret", algorithm: .aesGCM)
        }
        #expect(throws: TextEncryptionService.Error.decryptionFailed) {
            _ = try TextEncryptionService.decrypt(tamperedSalt, password: "secret", algorithm: .aesGCM)
        }
    }

    @Test func wrongAlgorithmDoesNotDecryptToPlaintext() throws {
        let plaintext = "abc"
        let password = "123"

        for encryptionAlgorithm in TextEncryptionService.Algorithm.allCases {
            let ciphertext = try TextEncryptionService.encrypt(plaintext, password: password, algorithm: encryptionAlgorithm)

            for decryptionAlgorithm in TextEncryptionService.Algorithm.allCases where decryptionAlgorithm != encryptionAlgorithm {
                do {
                    let decrypted = try TextEncryptionService.decrypt(ciphertext, password: password, algorithm: decryptionAlgorithm)
                    #expect(decrypted != plaintext)
                } catch TextEncryptionService.Error.decryptionFailed,
                        TextEncryptionService.Error.invalidBase64,
                        TextEncryptionService.Error.invalidFormat,
                        TextEncryptionService.Error.modernCiphertextWithLegacyAlgorithm,
                        TextEncryptionService.Error.legacyCiphertextWithModernAlgorithm,
                        TextEncryptionService.Error.cryptOperationFailed {
                    continue
                }
            }
        }
    }

    @Test func modernCiphertextWithLegacyAlgorithmReportsSwitchHint() throws {
        let ciphertext = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aesGCM)

        for algorithm in [TextEncryptionService.Algorithm.aes, .tripleDES, .rabbit, .rc4] {
            #expect(throws: TextEncryptionService.Error.modernCiphertextWithLegacyAlgorithm) {
                _ = try TextEncryptionService.decrypt(ciphertext, password: "secret", algorithm: algorithm)
            }
        }
    }

    @Test func legacyCiphertextWithModernAlgorithmReportsSwitchHint() throws {
        let ciphertext = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aes)

        #expect(throws: TextEncryptionService.Error.legacyCiphertextWithModernAlgorithm) {
            _ = try TextEncryptionService.decrypt(ciphertext, password: "secret", algorithm: .aesGCM)
        }
    }

    @Test func mismatchHintsKeepFactualToneAndNameTheSwitch() {
        #expect(
            TextEncryptionService.Error.modernCiphertextWithLegacyAlgorithm.errorDescription
                == "密文是 AES-GCM 格式（以 DT-AES-GCM-v1: 开头）；把算法切换为 AES-GCM 后再解密。"
        )
        #expect(
            TextEncryptionService.Error.legacyCiphertextWithModernAlgorithm.errorDescription
                == "密文是 OpenSSL 兼容格式（Salted__ 开头）；把算法切换为 AES 或 TripleDES 等传统算法后再解密。"
        )
    }

    @Test func encryptedOutputUsesOpenSSLSaltedFormat() throws {
        let ciphertext = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aes)
        let data = try #require(Data(base64Encoded: ciphertext), "Expected ciphertext to be valid Base64")

        #expect(data.starts(with: Data("Salted__".utf8)))
        #expect(data.count > "Salted__".utf8.count + 8)
        #expect(!ciphertext.contains("plain"))
    }

    @Test func decryptsOpenSSLAES256CBCVector() throws {
        let ciphertext = "U2FsdGVkX18xMjM0NTY3OL6cbdLbc08RGJjKnfIc+Ik="
        let plaintext = try TextEncryptionService.decrypt(ciphertext, password: "secret", algorithm: .aes)

        #expect(plaintext == "hello")
    }

    @Test func emptyPasswordThrows() throws {
        #expect(throws: TextEncryptionService.Error.emptyPassword) {
            _ = try TextEncryptionService.encrypt("plain", password: "", algorithm: .aes)
        }
    }

    @Test func invalidBase64Throws() throws {
        #expect(throws: TextEncryptionService.Error.invalidBase64) {
            _ = try TextEncryptionService.decrypt("not base64", password: "secret", algorithm: .aes)
        }
    }

    @Test func invalidSaltedFormatThrows() throws {
        let notSalted = Data("NotSalted12345678payload".utf8).base64EncodedString()

        #expect(throws: TextEncryptionService.Error.invalidFormat) {
            _ = try TextEncryptionService.decrypt(notSalted, password: "secret", algorithm: .aes)
        }
    }

    @Test func decryptAcceptsWhitespaceWrappedBase64() throws {
        let ciphertext = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aes)
        let splitIndex = ciphertext.index(ciphertext.startIndex, offsetBy: min(8, ciphertext.count))
        let wrapped = String(ciphertext[..<splitIndex]) + "\n " + String(ciphertext[splitIndex...])

        let plaintext = try TextEncryptionService.decrypt(wrapped, password: "secret", algorithm: .aes)

        #expect(plaintext == "plain")
    }

    @Test func legacyVectorWithWrongPasswordReportsDecryptionFailed() throws {
        // Legacy CBC has no authentication: other ciphertexts may yield valid
        // padding and UTF-8 under a wrong password. This fixed vector rejects it.
        let ciphertext = "U2FsdGVkX18xMjM0NTY3OL6cbdLbc08RGJjKnfIc+Ik="

        #expect(throws: TextEncryptionService.Error.decryptionFailed) {
            _ = try TextEncryptionService.decrypt(ciphertext, password: "wrong", algorithm: .aes)
        }
    }

    @Test func aesGCMWrongPasswordThrowsDecryptionFailed() throws {
        let ciphertext = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aesGCM)

        #expect(throws: TextEncryptionService.Error.decryptionFailed) {
            _ = try TextEncryptionService.decrypt(ciphertext, password: "wrong", algorithm: .aesGCM)
        }
    }

    @Test func invalidFormatDescriptionIsUserFriendly() {
        #expect(
            TextEncryptionService.Error.invalidFormat.localizedDescription
            == "密文格式与当前算法不匹配。"
        )
    }

    @Test func userFacingErrorsCallTheInputAnEncryptionPassword() {
        #expect(TextEncryptionService.Error.emptyPassword.errorDescription == "加密口令不能为空。")
        #expect(
            TextEncryptionService.Error.decryptionFailed.errorDescription
                == "加密口令、算法或密文不匹配，无法解密。"
        )
    }

    @Test func everyErrorUsesFactualMessageWithoutSensitiveInput() {
        let secret = "private-password-value"
        let errors: [TextEncryptionService.Error] = [
            .emptyPassword, .invalidBase64, .invalidFormat, .decryptionFailed,
            .modernCiphertextWithLegacyAlgorithm, .legacyCiphertextWithModernAlgorithm,
            .cryptOperationFailed, .secureRandomUnavailable,
        ]
        for error in errors {
            ToolDiagnosticContract.expectFactual(
                error.errorDescription ?? "",
                sensitiveInputs: [secret]
            )
        }
    }

    @Test func insecureAlgorithmsAreFlagged() {
        #expect(TextEncryptionService.Algorithm.aesGCM.isInsecure == false)
        #expect(TextEncryptionService.Algorithm.aes.isInsecure == true)
        #expect(TextEncryptionService.Algorithm.rabbit.isInsecure == true)
        #expect(TextEncryptionService.Algorithm.tripleDES.isInsecure == true)
        #expect(TextEncryptionService.Algorithm.rc4.isInsecure == true)
    }

    @Test func algorithmDisplayNamesDoNotIncludeCompatibilityMarker() {
        let displayNames = TextEncryptionService.Algorithm.allCases.map(\.displayName)

        #expect(displayNames == ["AES-GCM", "AES-CBC", "TripleDES", "Rabbit", "RC4"])
        #expect(displayNames.allSatisfy { !$0.contains("兼容") })
    }

    @Test func decryptRejectsEmptyPassword() throws {
        let ciphertext = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aes)

        #expect(throws: TextEncryptionService.Error.emptyPassword) {
            _ = try TextEncryptionService.decrypt(ciphertext, password: "", algorithm: .aes)
        }
    }

    @Test func ciphertextShorterThanHeaderPlusSaltThrowsInvalidFormat() throws {
        // "Salted__" (8 bytes) + 8-byte salt is the minimum; anything at or below
        // that boundary carries no ciphertext and must be rejected as invalid.
        let tooShort = Data(Array("Salted__".utf8) + [UInt8](repeating: 0, count: 8)).base64EncodedString()

        #expect(throws: TextEncryptionService.Error.invalidFormat) {
            _ = try TextEncryptionService.decrypt(tooShort, password: "pw", algorithm: .aes)
        }
    }

    @Test func unicodePasswordRoundTrips() throws {
        let plaintext = "secret message"
        let password = "пароль密码🔑"

        let ciphertext = try TextEncryptionService.encrypt(plaintext, password: password, algorithm: .aesGCM)
        let decrypted = try TextEncryptionService.decrypt(ciphertext, password: password, algorithm: .aesGCM)

        #expect(decrypted == plaintext)
    }

    private static let modernPrefix = "DT-AES-GCM-v1:"

    private static func modernPayload(
        _ ciphertext: String,
        replacingRoundsWith rounds: UInt32
    ) throws -> String {
        #expect(ciphertext.hasPrefix(modernPrefix))
        let encodedPayload = String(ciphertext.dropFirst(modernPrefix.count))
        var payload = Array(try #require(Data(base64Encoded: encodedPayload)))
        payload[0] = UInt8((rounds >> 24) & 0xff)
        payload[1] = UInt8((rounds >> 16) & 0xff)
        payload[2] = UInt8((rounds >> 8) & 0xff)
        payload[3] = UInt8(rounds & 0xff)
        return modernPrefix + Data(payload).base64EncodedString()
    }

    private static func tamperModernPayload(_ ciphertext: String, offset: Int? = nil) throws -> String {
        #expect(ciphertext.hasPrefix(modernPrefix))
        let encodedPayload = String(ciphertext.dropFirst(modernPrefix.count))
        var payload = Array(try #require(Data(base64Encoded: encodedPayload)))
        let targetOffset = offset ?? payload.index(before: payload.endIndex)
        payload[targetOffset] ^= 0x01
        return modernPrefix + Data(payload).base64EncodedString()
    }
}
