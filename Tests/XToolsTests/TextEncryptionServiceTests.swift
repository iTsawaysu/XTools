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

    @Test func legacyDecryptAcceptsUnpaddedCiphertext() throws {
        let ciphertext = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aes)
        let unpadded = ciphertext.trimmingCharacters(in: CharacterSet(charactersIn: "="))
        #expect(unpadded != ciphertext, "Expected the vector to carry Base64 padding")

        let plaintext = try TextEncryptionService.decrypt(unpadded, password: "secret", algorithm: .aes)

        #expect(plaintext == "plain")
    }

    @Test func modernDecryptAcceptsUnpaddedCiphertext() throws {
        let ciphertext = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aesGCM)
        let unpadded = Self.modernPrefix
            + String(ciphertext.dropFirst(Self.modernPrefix.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        #expect(unpadded != ciphertext, "Expected the vector to carry Base64 padding")

        let plaintext = try TextEncryptionService.decrypt(unpadded, password: "secret", algorithm: .aesGCM)

        #expect(plaintext == "plain")
    }

    @Test func legacyDecryptAcceptsBase64URLCiphertext() throws {
        // 固定向量含 "+"，转成 base64url（-_、去填充）后必须仍可解密。
        let urlSafe = "U2FsdGVkX18xMjM0NTY3OL6cbdLbc08RGJjKnfIc-Ik"

        let plaintext = try TextEncryptionService.decrypt(urlSafe, password: "secret", algorithm: .aes)

        #expect(plaintext == "hello")
    }

    @Test func modernDecryptAcceptsBase64URLCiphertext() throws {
        let ciphertext = try TextEncryptionService.encrypt("plain", password: "secret", algorithm: .aesGCM)
        let payload = String(ciphertext.dropFirst(Self.modernPrefix.count))
        let data = try #require(Data(base64Encoded: payload))
        let urlSafe = Self.modernPrefix + Base64Conversion.encodeBase64URL(data)

        let plaintext = try TextEncryptionService.decrypt(urlSafe, password: "secret", algorithm: .aesGCM)

        #expect(plaintext == "plain")
    }

    @Test func garbageCiphertextStillReportsInvalidBase64() {
        // 余 1 长度（不可能是 Base64）与字母表外字符都仍拒绝。
        #expect(throws: TextEncryptionService.Error.invalidBase64) {
            _ = try TextEncryptionService.decrypt("not base64", password: "secret", algorithm: .aes)
        }
        #expect(throws: TextEncryptionService.Error.invalidBase64) {
            _ = try TextEncryptionService.decrypt(Self.modernPrefix + "@@@@", password: "secret", algorithm: .aesGCM)
        }
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

    @Test func rabbitCipherMatchesRFC4503OfficialVectors() throws {
        // RFC 4503 A.2（带 IV）官方向量：全零 key，明文为 48 零字节，
        // 即连续 3 个密钥流块的直接呈现。
        let zeroKey = [UInt8](repeating: 0, count: 16)
        let zeroMessage = [UInt8](repeating: 0, count: 48)
        let vectors: [([UInt8], String)] = [
            ([UInt8](repeating: 0, count: 8), "c6a7275ef85495d87ccd5d376705b7ed5f29a6ac04f5efd47b8f293270dc4a8d2ade822b29de6c1ee52bdb8a47bf8f66"),
            ([0xc3, 0x73, 0xf5, 0x75, 0xc1, 0x26, 0x7e, 0x59], "1fcd4eb9580012e2e0dccc9222017d6da75f4e10d12125017b2499ffed936f2eebc112c393e738392356bdd012029ba7"),
        ]

        for (iv, expected) in vectors {
            #expect(DigestEncoding.format(try RabbitCipher(key: zeroKey, iv: iv).encrypt(zeroMessage), mode: "hex") == expected)
        }
    }

    @Test func rabbitCipherMatchesCapturedLegacyGoldens() throws {
        // 迁移期用原 CryptoSwift Rabbit 固化的金标：自研实现必须逐字节等价，
        // 历史 Salted__ Rabbit 密文才能继续解密。覆盖非零 key/iv 长明文（跨块）
        // 与未对齐 16 字节块的尾块缓冲。
        let vectors: [(key: [UInt8], iv: [UInt8], plaintext: [UInt8], ciphertext: String)] = [
            (
                [0x91, 0x28, 0x13, 0x29, 0x2e, 0x3d, 0x36, 0xfe, 0x3b, 0xfc, 0x62, 0xf1, 0xdc, 0x51, 0xc3, 0xac],
                [0xa6, 0xeb, 0x56, 0x1a, 0xd2, 0xf4, 0x17, 0x27],
                Array("The quick brown fox jumps over the lazy dog".utf8),
                "1934cde66d2fac03d853db39ce4011ce852f12640a3b4275a4d31faadb693bbfc31bf8309c3427d267b320"
            ),
            (
                Array("Sixteen byte key".utf8),
                [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07],
                [UInt8](repeating: 0, count: 13),
                "7b262d3b75c02ef2c02a1de68a"
            ),
        ]

        for (key, iv, plaintext, expectedCiphertext) in vectors {
            let cipher = try RabbitCipher(key: key, iv: iv)
            let ciphertext = cipher.encrypt(plaintext)
            #expect(DigestEncoding.format(ciphertext, mode: "hex") == expectedCiphertext)
            #expect(cipher.decrypt(ciphertext) == plaintext)
        }
    }

    @Test func rabbitCipherRejectsWrongKeyAndIVSizes() {
        #expect(throws: RabbitCipher.Error.invalidKeyOrIV) {
            _ = try RabbitCipher(key: [UInt8](repeating: 0, count: 15), iv: [UInt8](repeating: 0, count: 8))
        }
        #expect(throws: RabbitCipher.Error.invalidKeyOrIV) {
            _ = try RabbitCipher(key: [UInt8](repeating: 0, count: 16), iv: [UInt8](repeating: 0, count: 7))
        }
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
