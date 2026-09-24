import Foundation

public enum ASCIIBinaryConversion {
    public enum ConversionError: LocalizedError, Equatable, Sendable {
        case nonASCIIText
        case emptyASCIIInput
        case invalidASCIIToken
        case asciiOutOfRange
        case invalidBinaryCharacter
        case incompleteBinaryByte
        case invalidUTF8

        public var errorDescription: String? {
            switch self {
            case .nonASCIIText:
                return "ASCII 只能表示 U+0000–U+007F 范围内的字符。"
            case .emptyASCIIInput:
                return "输入中没有 ASCII 十进制数值。"
            case .invalidASCIIToken:
                return "ASCII 输入包含非十进制整数。"
            case .asciiOutOfRange:
                return "ASCII 十进制数值必须在 0–127 之间。"
            case .invalidBinaryCharacter:
                return "二进制输入只能包含 0 和 1，以及分隔空白。"
            case .incompleteBinaryByte:
                return "二进制输入的有效位数必须是 8 的倍数。"
            case .invalidUTF8:
                return "这些二进制字节不是 UTF-8 文本。"
            }
        }
    }

    public static func textToBinary(_ input: String) -> String {
        input.utf8.map(\.binaryByteString).joined(separator: " ")
    }

    public static func textToASCII(_ input: String) -> String? {
        try? validatedTextToASCII(input)
    }

    public static func validatedTextToASCII(_ input: String) throws -> String {
        var values: [String] = []
        values.reserveCapacity(input.unicodeScalars.count)

        for scalar in input.unicodeScalars {
            guard scalar.value <= 0x7F else {
                throw ConversionError.nonASCIIText
            }
            values.append(String(scalar.value))
        }
        return values.joined(separator: " ")
    }

    public static func asciiToText(_ input: String) -> String? {
        try? validatedASCIIToText(input)
    }

    public static func validatedASCIIToText(_ input: String) throws -> String {
        let tokens = input.split { character in
            character.isWhitespace || character == ","
        }
        guard !tokens.isEmpty else {
            throw ConversionError.emptyASCIIInput
        }

        var output = ""
        output.reserveCapacity(tokens.count)

        for token in tokens {
            guard token.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) else {
                throw ConversionError.invalidASCIIToken
            }
            guard let value = UInt32(String(token)), value <= 0x7F,
                  let scalar = UnicodeScalar(value) else {
                throw ConversionError.asciiOutOfRange
            }
            output.unicodeScalars.append(scalar)
        }

        return output
    }

    public static func binaryToText(_ input: String) -> String? {
        try? validatedBinaryToText(input)
    }

    public static func validatedBinaryToText(_ input: String) throws -> String {
        let bytes = try validatedBinaryBytes(from: input)
        guard let text = String(data: Data(bytes), encoding: .utf8) else {
            throw ConversionError.invalidUTF8
        }
        return text
    }

    private static func validatedBinaryBytes(from input: String) throws -> [UInt8] {
        let bits = input.filter { !$0.isWhitespace }
        guard !bits.isEmpty else { return [] }
        guard bits.allSatisfy({ $0 == "0" || $0 == "1" }) else {
            throw ConversionError.invalidBinaryCharacter
        }
        guard bits.count.isMultiple(of: 8) else {
            throw ConversionError.incompleteBinaryByte
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(bits.count / 8)

        var start = bits.startIndex
        while start < bits.endIndex {
            let end = bits.index(start, offsetBy: 8)
            guard let byte = UInt8(bits[start..<end], radix: 2) else {
                throw ConversionError.invalidBinaryCharacter
            }
            bytes.append(byte)
            start = end
        }

        return bytes
    }
}
