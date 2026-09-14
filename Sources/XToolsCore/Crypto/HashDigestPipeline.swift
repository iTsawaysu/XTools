import CommonCrypto
import CryptoKit
@preconcurrency import CryptoSwift
import Foundation

/// Declaration order is the product order: generally suitable digests appear
/// before compatibility-only algorithms.
public enum HashDigestAlgorithm: String, CaseIterable, Identifiable, Sendable {
    case sha256
    case sha512
    case sha384
    case sha224
    case sha3_512
    case ripemd160
    case sha1
    case md5

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .sha256:
            return "SHA-256"
        case .sha512:
            return "SHA-512"
        case .sha384:
            return "SHA-384"
        case .sha224:
            return "SHA-224"
        case .sha3_512:
            return "SHA3-512"
        case .ripemd160:
            return "RIPEMD-160"
        case .sha1:
            return "SHA-1"
        case .md5:
            return "MD5"
        }
    }

    public var isCompatibilityOnly: Bool {
        switch self {
        case .sha1, .md5:
            return true
        case .sha256, .sha512, .sha384, .sha224, .sha3_512, .ripemd160:
            return false
        }
    }
}

public enum HashDigestPipeline {
    public struct DigestItem: Equatable, Sendable {
        public let algorithm: HashDigestAlgorithm
        public let bytes: [UInt8]

        public init(algorithm: HashDigestAlgorithm, bytes: [UInt8]) {
            self.algorithm = algorithm
            self.bytes = bytes
        }

        public var name: String { algorithm.displayName }
        public var isCompatibilityOnly: Bool { algorithm.isCompatibilityOnly }
    }

    /// Cancellation is checked before and after each synchronous algorithm so
    /// an invalidated request stops at the next algorithm boundary.
    public static func compute(
        _ bytes: [UInt8],
        shouldCancel: () -> Bool = { Task.isCancelled }
    ) throws -> [DigestItem] {
        let data = Data(bytes)
        var items: [DigestItem] = []
        items.reserveCapacity(HashDigestAlgorithm.allCases.count)

        for algorithm in HashDigestAlgorithm.allCases {
            try checkCancellation(using: shouldCancel)
            let digest = algorithm.digest(bytes: bytes, data: data)
            try checkCancellation(using: shouldCancel)
            items.append(DigestItem(algorithm: algorithm, bytes: digest))
        }

        return items
    }

    public static func compute(
        text: String,
        shouldCancel: () -> Bool = { Task.isCancelled }
    ) throws -> [DigestItem] {
        try compute(Array(text.utf8), shouldCancel: shouldCancel)
    }

    private static func checkCancellation(using shouldCancel: () -> Bool) throws {
        if shouldCancel() {
            throw CancellationError()
        }
    }
}

private extension HashDigestAlgorithm {
    func digest(bytes: [UInt8], data: Data) -> [UInt8] {
        switch self {
        case .sha256:
            return Array(SHA256.hash(data: data))
        case .sha512:
            return Array(SHA512.hash(data: data))
        case .sha384:
            return Array(SHA384.hash(data: data))
        case .sha224:
            var digest = [UInt8](repeating: 0, count: Int(CC_SHA224_DIGEST_LENGTH))
            bytes.withUnsafeBytes { buffer in
                _ = CC_SHA224(buffer.baseAddress, CC_LONG(buffer.count), &digest)
            }
            return digest
        case .sha3_512:
            return Digest.sha3(bytes, variant: .sha512)
        case .ripemd160:
            return RIPEMD160.hash(bytes)
        case .sha1:
            return Array(Insecure.SHA1.hash(data: data))
        case .md5:
            return Array(Insecure.MD5.hash(data: data))
        }
    }
}
