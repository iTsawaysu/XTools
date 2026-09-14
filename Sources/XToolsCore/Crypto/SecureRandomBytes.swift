import Foundation
import Security

public enum SecureRandomBytes {
    public enum GenerationError: Error, Equatable, Sendable {
        case invalidByteCount
        case randomSourceUnavailable
    }

    public typealias Source = (Int) throws -> [UInt8]

    public static func generate(
        count: Int,
        source: Source? = nil
    ) throws -> [UInt8] {
        guard count >= 0 else {
            throw GenerationError.invalidByteCount
        }
        guard count > 0 else { return [] }

        if let source {
            let bytes = try source(count)
            guard bytes.count == count else {
                throw GenerationError.invalidByteCount
            }
            return bytes
        }

        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw GenerationError.randomSourceUnavailable
        }
        return bytes
    }
}
