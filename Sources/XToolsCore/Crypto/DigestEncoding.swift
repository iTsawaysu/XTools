import Foundation

public enum DigestEncoding {
    public enum Mode: String {
        case hex
        case binary
        case base64
        case base64url
    }

    public static func format(_ digest: [UInt8], mode: String) -> String {
        switch Mode(rawValue: mode) {
        case .binary:
            return digest.map(\.binaryByteString).joined(separator: " ")
        case .base64:
            return Data(digest).base64EncodedString()
        case .base64url:
            return Base64Conversion.encodeBase64URL(Data(digest))
        case .hex, .none:
            return digest.toHexStringLowercased()
        }
    }
}

extension Array where Element == UInt8 {
    private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)

    func toHexStringLowercased() -> String {
        guard !isEmpty else { return "" }
        return String(unsafeUninitializedCapacity: count * 2) { buffer in
            var ptr = buffer.baseAddress!
            for byte in self {
                ptr.pointee = Self.hexDigits[Int(byte >> 4)]
                ptr += 1
                ptr.pointee = Self.hexDigits[Int(byte & 0x0F)]
                ptr += 1
            }
            return count * 2
        }
    }
}
