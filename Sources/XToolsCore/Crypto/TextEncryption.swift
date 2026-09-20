import CommonCrypto
import CryptoKit
@preconcurrency import CryptoSwift
import Foundation
import Security

/// Text encryption service with a modern AES-GCM default and legacy
/// OpenSSL-compatible formats retained for interoperability.
public enum TextEncryptionService {
    public enum Algorithm: String, CaseIterable, Identifiable {
        case aesGCM = "AES-GCM"
        case aes = "AES"
        case tripleDES = "TripleDES"
        case rabbit = "Rabbit"
        case rc4 = "RC4"

        public var id: String { rawValue }

        /// The modern AES-GCM mode is the only option intended for new data.
        /// OpenSSL-compatible modes are unauthenticated legacy formats kept so
        /// existing ciphertext can still be decrypted or reproduced.
        public var isInsecure: Bool {
            switch self {
            case .aesGCM:
                return false
            case .aes, .tripleDES, .rabbit, .rc4:
                return true
            }
        }

        public var isLegacy: Bool {
            self != .aesGCM
        }

        public var displayName: String {
            switch self {
            case .aesGCM:
                return "AES-GCM"
            case .aes:
                return "AES-CBC"
            case .tripleDES:
                return "TripleDES"
            case .rabbit:
                return "Rabbit"
            case .rc4:
                return "RC4"
            }
        }

        fileprivate var legacyKeyLength: Int {
            switch self {
            case .aesGCM:
                return 32
            case .aes: return 32
            case .tripleDES: return 24
            case .rabbit: return 16
            case .rc4: return 32
            }
        }

        fileprivate var legacyIVLength: Int {
            switch self {
            case .aesGCM:
                return 12
            case .aes: return AES.blockSize
            case .tripleDES: return 8
            case .rabbit: return 8
            case .rc4: return 0
            }
        }
    }

    public enum Error: LocalizedError {
        case emptyPassword
        case emptyCiphertext
        case invalidBase64
        case invalidFormat
        case decryptionFailed
        case cryptOperationFailed
        case secureRandomUnavailable

        public var errorDescription: String? {
            switch self {
            case .emptyPassword:
                return "加密口令不能为空。"
            case .emptyCiphertext:
                return "密文不能为空。"
            case .invalidBase64:
                return "密文不是有效的 Base64。"
            case .invalidFormat:
                return "密文格式与当前算法不匹配。"
            case .decryptionFailed:
                return "加密口令、算法或密文不匹配，无法解密。"
            case .cryptOperationFailed:
                return "加密或解密算法执行失败。"
            case .secureRandomUnavailable:
                return "系统安全随机数生成器不可用。"
            }
        }
    }

    /// Encrypt plaintext with password using the specified algorithm.
    /// AES-GCM returns a versioned payload; legacy algorithms return Base64-
    /// encoded "Salted__" + salt + ciphertext (crypto-js/OpenSSL compatible).
    public static func encrypt(_ plaintext: String, password: String, algorithm: Algorithm) throws -> String {
        guard !password.isEmpty else { throw Error.emptyPassword }
        guard let plaintextData = plaintext.data(using: .utf8),
              let passwordData = password.data(using: .utf8) else {
            throw Error.cryptOperationFailed
        }

        if algorithm == .aesGCM {
            return try encryptModern(plaintextData, password: Array(passwordData))
        }

        let salt = try randomBytes(count: 8)
        let derived = try deriveKeyAndIV(
            password: Array(passwordData),
            salt: salt,
            keyLength: algorithm.legacyKeyLength,
            ivLength: algorithm.legacyIVLength
        )

        let encryptedBytes = try encryptBytes(
            Array(plaintextData),
            algorithm: algorithm,
            key: derived.key,
            iv: derived.iv
        )

        return Data(saltedHeader + salt + encryptedBytes).base64EncodedString()
    }

    /// Decrypt a versioned AES-GCM envelope or legacy Base64 ciphertext with
    /// the supplied password. Returns the original plaintext string.
    public static func decrypt(_ ciphertext: String, password: String, algorithm: Algorithm) throws -> String {
        guard !password.isEmpty else { throw Error.emptyPassword }
        guard !ciphertext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.emptyCiphertext
        }
        guard let passwordData = password.data(using: .utf8) else {
            throw Error.cryptOperationFailed
        }

        if algorithm == .aesGCM {
            return try decryptModern(ciphertext, password: Array(passwordData))
        }

        let normalizedCiphertext = ciphertext.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: String(normalizedCiphertext)) else {
            throw Error.invalidBase64
        }

        let bytes = Array(data)
        guard bytes.count > saltedHeader.count + 8 else {
            throw Error.invalidFormat
        }

        let header = Array(bytes.prefix(saltedHeader.count))
        guard header == saltedHeader else {
            throw Error.invalidFormat
        }

        let saltStart = saltedHeader.count
        let saltEnd = saltStart + 8
        let salt = Array(bytes[saltStart..<saltEnd])
        let encryptedBytes = Array(bytes[saltEnd...])

        guard !encryptedBytes.isEmpty else {
            throw Error.invalidFormat
        }

        let derived = try deriveKeyAndIV(
            password: Array(passwordData),
            salt: salt,
            keyLength: algorithm.legacyKeyLength,
            ivLength: algorithm.legacyIVLength
        )

        let decryptedBytes: [UInt8]
        do {
            decryptedBytes = try decryptBytes(
                encryptedBytes,
                algorithm: algorithm,
                key: derived.key,
                iv: derived.iv
            )
        } catch {
            throw Error.decryptionFailed
        }

        guard let plaintext = String(data: Data(decryptedBytes), encoding: .utf8) else {
            throw Error.decryptionFailed
        }

        return plaintext
    }

    private static let saltedHeader = Array("Salted__".utf8)
    private static let modernPrefix = "DT-AES-GCM-v1:"
    private static let modernSaltLength = 16
    private static let modernNonceLength = 12
    private static let modernTagLength = 16
    private static let modernKeyLength = 32
    private static let modernPBKDF2Rounds: UInt32 = 600_000

    private static func encryptModern(_ plaintextData: Data, password: [UInt8]) throws -> String {
        let salt = try randomBytes(count: modernSaltLength)
        let nonceBytes = try randomBytes(count: modernNonceLength)
        let rounds = modernPBKDF2Rounds
        let metadata = modernMetadata(rounds: rounds, salt: salt, nonce: nonceBytes)
        let keyBytes = try pbkdf2SHA256(
            password: password,
            salt: salt,
            rounds: rounds,
            keyLength: modernKeyLength
        )

        let nonce = try AES.GCM.Nonce(data: Data(nonceBytes))
        let key = SymmetricKey(data: Data(keyBytes))
        let sealed = try AES.GCM.seal(
            plaintextData,
            using: key,
            nonce: nonce,
            authenticating: modernAAD(metadata: metadata)
        )

        var payload = Data(metadata)
        payload.append(sealed.ciphertext)
        payload.append(sealed.tag)

        return modernPrefix + payload.base64EncodedString()
    }

    private static func decryptModern(_ ciphertext: String, password: [UInt8]) throws -> String {
        let normalizedCiphertext = ciphertext.filter { !$0.isWhitespace }
        guard normalizedCiphertext.hasPrefix(modernPrefix) else {
            throw Error.invalidFormat
        }

        let encodedPayload = String(normalizedCiphertext.dropFirst(modernPrefix.count))
        guard let payload = Data(base64Encoded: encodedPayload) else {
            throw Error.invalidBase64
        }

        let minimumLength = 4 + modernSaltLength + modernNonceLength + modernTagLength
        guard payload.count >= minimumLength else {
            throw Error.invalidFormat
        }

        let bytes = Array(payload)
        let rounds = readUInt32BigEndian(bytes[0..<4])
        // DT-AES-GCM-v1 is immutable; payload metadata must not amplify KDF work.
        guard rounds == modernPBKDF2Rounds else { throw Error.invalidFormat }

        let saltStart = 4
        let saltEnd = saltStart + modernSaltLength
        let nonceEnd = saltEnd + modernNonceLength
        let tagStart = bytes.count - modernTagLength

        guard tagStart >= nonceEnd else {
            throw Error.invalidFormat
        }

        let salt = Array(bytes[saltStart..<saltEnd])
        let nonceBytes = Array(bytes[saltEnd..<nonceEnd])
        let ciphertextBytes = Array(bytes[nonceEnd..<tagStart])
        let tag = Array(bytes[tagStart..<bytes.count])
        let metadata = Array(bytes[0..<nonceEnd])

        let keyBytes = try pbkdf2SHA256(
            password: password,
            salt: salt,
            rounds: rounds,
            keyLength: modernKeyLength
        )

        do {
            let nonce = try AES.GCM.Nonce(data: Data(nonceBytes))
            let sealed = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: Data(ciphertextBytes),
                tag: Data(tag)
            )
            let plaintextData = try AES.GCM.open(
                sealed,
                using: SymmetricKey(data: Data(keyBytes)),
                authenticating: modernAAD(metadata: metadata)
            )

            guard let plaintext = String(data: plaintextData, encoding: .utf8) else {
                throw Error.decryptionFailed
            }

            return plaintext
        } catch {
            throw Error.decryptionFailed
        }
    }

    private static func modernMetadata(rounds: UInt32, salt: [UInt8], nonce: [UInt8]) -> [UInt8] {
        uint32BigEndian(rounds) + salt + nonce
    }

    private static func modernAAD(metadata: [UInt8]) -> Data {
        Data(Array(modernPrefix.utf8) + metadata)
    }

    private static func encryptBytes(
        _ bytes: [UInt8],
        algorithm: Algorithm,
        key: [UInt8],
        iv: [UInt8]
    ) throws -> [UInt8] {
        switch algorithm {
        case .aesGCM:
            throw Error.cryptOperationFailed
        case .aes:
            return try commonCrypt(
                operation: CCOperation(kCCEncrypt),
                algorithm: CCAlgorithm(kCCAlgorithmAES),
                options: CCOptions(kCCOptionPKCS7Padding),
                data: bytes,
                key: key,
                iv: iv
            )
        case .tripleDES:
            return try commonCrypt(
                operation: CCOperation(kCCEncrypt),
                algorithm: CCAlgorithm(kCCAlgorithm3DES),
                options: CCOptions(kCCOptionPKCS7Padding),
                data: bytes,
                key: key,
                iv: iv
            )
        case .rabbit:
            return try Rabbit(key: key, iv: iv).encrypt(bytes)
        case .rc4:
            return try commonCrypt(
                operation: CCOperation(kCCEncrypt),
                algorithm: CCAlgorithm(kCCAlgorithmRC4),
                options: CCOptions(0),
                data: bytes,
                key: key,
                iv: []
            )
        }
    }

    private static func decryptBytes(
        _ bytes: [UInt8],
        algorithm: Algorithm,
        key: [UInt8],
        iv: [UInt8]
    ) throws -> [UInt8] {
        switch algorithm {
        case .aesGCM:
            throw Error.cryptOperationFailed
        case .aes:
            return try commonCrypt(
                operation: CCOperation(kCCDecrypt),
                algorithm: CCAlgorithm(kCCAlgorithmAES),
                options: CCOptions(kCCOptionPKCS7Padding),
                data: bytes,
                key: key,
                iv: iv
            )
        case .tripleDES:
            return try commonCrypt(
                operation: CCOperation(kCCDecrypt),
                algorithm: CCAlgorithm(kCCAlgorithm3DES),
                options: CCOptions(kCCOptionPKCS7Padding),
                data: bytes,
                key: key,
                iv: iv
            )
        case .rabbit:
            return try Rabbit(key: key, iv: iv).decrypt(bytes)
        case .rc4:
            return try commonCrypt(
                operation: CCOperation(kCCDecrypt),
                algorithm: CCAlgorithm(kCCAlgorithmRC4),
                options: CCOptions(0),
                data: bytes,
                key: key,
                iv: []
            )
        }
    }

    private static func commonCrypt(
        operation: CCOperation,
        algorithm: CCAlgorithm,
        options: CCOptions,
        data: [UInt8],
        key: [UInt8],
        iv: [UInt8]
    ) throws -> [UInt8] {
        let outputCapacity = data.count + kCCBlockSizeAES128
        var output = [UInt8](repeating: 0, count: outputCapacity)
        var outputLength = 0

        let status = key.withUnsafeBytes { keyBuffer in
            data.withUnsafeBytes { dataBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    if iv.isEmpty {
                        return CCCrypt(
                            operation,
                            algorithm,
                            options,
                            keyBuffer.baseAddress,
                            key.count,
                            nil,
                            dataBuffer.baseAddress,
                            data.count,
                            outputBuffer.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }

                    return iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(
                            operation,
                            algorithm,
                            options,
                            keyBuffer.baseAddress,
                            key.count,
                            ivBuffer.baseAddress,
                            dataBuffer.baseAddress,
                            data.count,
                            outputBuffer.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw Error.cryptOperationFailed
        }

        return Array(output.prefix(outputLength))
    }

    /// EVP_BytesToKey (OpenSSL KDF) for crypto-js compatibility.
    private static func deriveKeyAndIV(
        password: [UInt8],
        salt: [UInt8],
        keyLength: Int,
        ivLength: Int
    ) throws -> (key: [UInt8], iv: [UInt8]) {
        let requiredLength = keyLength + ivLength
        var derived: [UInt8] = []
        var previousDigest: [UInt8] = []

        while derived.count < requiredLength {
            let digestInput = previousDigest + password + salt
            previousDigest = Digest.md5(digestInput)
            derived += previousDigest
        }

        guard derived.count >= requiredLength else {
            throw Error.cryptOperationFailed
        }

        let key = Array(derived.prefix(keyLength))
        let iv = ivLength == 0
            ? []
            : Array(derived[keyLength..<(keyLength + ivLength)])

        return (key, iv)
    }

    private static func pbkdf2SHA256(
        password: [UInt8],
        salt: [UInt8],
        rounds: UInt32,
        keyLength: Int
    ) throws -> [UInt8] {
        guard rounds > 0, keyLength > 0 else {
            throw Error.cryptOperationFailed
        }

        var key = [UInt8](repeating: 0, count: keyLength)
        let status = key.withUnsafeMutableBytes { keyBuffer in
            password.withUnsafeBytes { passwordBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        keyBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw Error.cryptOperationFailed
        }

        return key
    }

    private static func uint32BigEndian(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
    }

    private static func readUInt32BigEndian(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        bytes.reduce(UInt32(0)) { value, byte in
            (value << 8) | UInt32(byte)
        }
    }

    private static func randomBytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw Error.secureRandomUnavailable
        }
        return bytes
    }
}
