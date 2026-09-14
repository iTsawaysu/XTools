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
            return digest.map { leftPadBinary(String($0, radix: 2)) }.joined(separator: " ")
        case .base64:
            return Data(digest).base64EncodedString()
        case .base64url:
            return Data(digest).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        case .hex, .none:
            return digest.toHexStringLowercased()
        }
    }

    private static func leftPadBinary(_ bits: String) -> String {
        let padCount = 8 - bits.count
        guard padCount > 0 else { return bits }
        return String(repeating: "0", count: padCount) + bits
    }
}

private extension Array where Element == UInt8 {
    func toHexStringLowercased() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
