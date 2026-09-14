import Foundation

public enum URLPercentCoding {
    public enum CodingError: LocalizedError, Equatable, Sendable {
        case incompletePercentEscape
        case invalidPercentEscape
        case invalidUTF8

        public var errorDescription: String? {
            switch self {
            case .incompletePercentEscape:
                return "百分号后缺少两位十六进制数字。"
            case .invalidPercentEscape:
                return "百分号后只能使用两位十六进制数字。"
            case .invalidUTF8:
                return "百分号编码后的字节不是 UTF-8 文本。"
            }
        }
    }

    private static let uppercaseHexDigits = Array("0123456789ABCDEF".utf8)

    public static func encodeComponent(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.utf8.count)

        for byte in value.utf8 {
            if isUnreserved(byte) {
                output.append(Character(UnicodeScalar(byte)))
            } else {
                output.append("%")
                output.append(Character(UnicodeScalar(uppercaseHexDigits[Int(byte >> 4)])))
                output.append(Character(UnicodeScalar(uppercaseHexDigits[Int(byte & 0x0F)])))
            }
        }

        return output
    }

    public static func decode(_ value: String) throws -> String {
        let bytes = Array(value.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)

        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "%") {
                guard index + 2 < bytes.count else {
                    throw CodingError.incompletePercentEscape
                }
                guard let high = hexValue(bytes[index + 1]),
                      let low = hexValue(bytes[index + 2]) else {
                    throw CodingError.invalidPercentEscape
                }
                output.append(high << 4 | low)
                index += 3
            } else {
                output.append(byte)
                index += 1
            }
        }

        guard let decoded = String(data: Data(output), encoding: .utf8) else {
            throw CodingError.invalidUTF8
        }
        return decoded
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"),
             UInt8(ascii: "."),
             UInt8(ascii: "_"),
             UInt8(ascii: "~"):
            return true
        default:
            return false
        }
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return byte - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"):
            return byte - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"):
            return byte - UInt8(ascii: "a") + 10
        default:
            return nil
        }
    }
}
