import Foundation

public enum UnicodeEscaping {
    public enum DecodingError: LocalizedError, Equatable, Sendable {
        case incompleteEscape
        case invalidHexEscape
        case isolatedHighSurrogate
        case isolatedLowSurrogate

        public var errorDescription: String? {
            switch self {
            case .incompleteEscape:
                return "Unicode 转义必须写成 \\u 后跟四位十六进制数字。"
            case .invalidHexEscape:
                return "Unicode 转义只能包含 0–9、A–F 的十六进制数字。"
            case .isolatedHighSurrogate:
                return "高位代理转义后缺少对应的低位代理转义。"
            case .isolatedLowSurrogate:
                return "低位代理转义前缺少对应的高位代理转义。"
            }
        }
    }

    public static func encode(_ input: String) -> String {
        input.utf16.map { "\\u" + leftPadHex(String($0, radix: 16)) }.joined()
    }

    public static func decode(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.count)

        var index = value.startIndex
        while index < value.endIndex {
            guard let escape = parseEscape(in: value, at: index) else {
                output.append(value[index])
                index = value.index(after: index)
                continue
            }

            if isHighSurrogate(escape.codeUnit),
               let lowEscape = parseEscape(in: value, at: escape.endIndex),
               isLowSurrogate(lowEscape.codeUnit) {
                let scalarValue = 0x10000
                    + ((UInt32(escape.codeUnit) - 0xD800) << 10)
                    + (UInt32(lowEscape.codeUnit) - 0xDC00)
                if let scalar = UnicodeScalar(scalarValue) {
                    output.append(Character(scalar))
                    index = lowEscape.endIndex
                    continue
                }
            }

            if isSurrogate(escape.codeUnit) {
                output.append(contentsOf: value[index..<escape.endIndex])
            } else if let scalar = UnicodeScalar(UInt32(escape.codeUnit)) {
                output.append(Character(scalar))
            } else {
                output.append(contentsOf: value[index..<escape.endIndex])
            }
            index = escape.endIndex
        }

        return output
    }

    public static func decodeValidated(_ value: String) throws -> String {
        try validateEscapes(in: value)
        return decode(value)
    }

    private struct Escape {
        let codeUnit: UInt16
        let endIndex: String.Index
    }

    private static func parseEscape(in value: String, at index: String.Index) -> Escape? {
        guard index < value.endIndex,
              value[index] == "\\",
              let uIndex = value.index(index, offsetBy: 1, limitedBy: value.endIndex),
              uIndex < value.endIndex,
              value[uIndex] == "u" else {
            return nil
        }

        var hexStart = value.index(after: uIndex)
        var hex = ""
        hex.reserveCapacity(4)

        for _ in 0..<4 {
            guard hexStart < value.endIndex,
                  isASCIIHexDigit(value[hexStart]) else {
                return nil
            }
            hex.append(value[hexStart])
            hexStart = value.index(after: hexStart)
        }

        guard let codeUnit = UInt16(hex, radix: 16) else {
            return nil
        }
        return Escape(codeUnit: codeUnit, endIndex: hexStart)
    }

    private static func validateEscapes(in value: String) throws {
        var index = value.startIndex
        while index < value.endIndex {
            guard value[index] == "\\",
                  let uIndex = value.index(index, offsetBy: 1, limitedBy: value.endIndex),
                  uIndex < value.endIndex,
                  value[uIndex] == "u" else {
                index = value.index(after: index)
                continue
            }

            var cursor = value.index(after: uIndex)
            var hex = ""
            for _ in 0..<4 {
                guard cursor < value.endIndex else {
                    throw DecodingError.incompleteEscape
                }
                guard isASCIIHexDigit(value[cursor]) else {
                    throw DecodingError.invalidHexEscape
                }
                hex.append(value[cursor])
                cursor = value.index(after: cursor)
            }

            guard let codeUnit = UInt16(hex, radix: 16) else {
                throw DecodingError.invalidHexEscape
            }
            if isHighSurrogate(codeUnit) {
                guard let lowEscape = parseEscape(in: value, at: cursor),
                      isLowSurrogate(lowEscape.codeUnit) else {
                    throw DecodingError.isolatedHighSurrogate
                }
                index = lowEscape.endIndex
            } else if isLowSurrogate(codeUnit) {
                throw DecodingError.isolatedLowSurrogate
            } else {
                index = cursor
            }
        }
    }

    private static func isASCIIHexDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value else {
            return false
        }
        return (48...57).contains(value) || (65...70).contains(value) || (97...102).contains(value)
    }

    private static func isSurrogate(_ codeUnit: UInt16) -> Bool {
        isHighSurrogate(codeUnit) || isLowSurrogate(codeUnit)
    }

    private static func isHighSurrogate(_ codeUnit: UInt16) -> Bool {
        (0xD800...0xDBFF).contains(codeUnit)
    }

    private static func isLowSurrogate(_ codeUnit: UInt16) -> Bool {
        (0xDC00...0xDFFF).contains(codeUnit)
    }

    private static func leftPadHex(_ hex: String) -> String {
        let padCount = 4 - hex.count
        guard padCount > 0 else { return hex }
        return String(repeating: "0", count: padCount) + hex
    }
}
