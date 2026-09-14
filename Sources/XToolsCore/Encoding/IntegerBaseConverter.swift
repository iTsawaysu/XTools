import Foundation

public enum IntegerBaseConverter {
    public static let maximumInputDigitCount = 4_096

    public struct Conversions: Equatable, Sendable {
        public let binary: String
        public let octal: String
        public let decimal: String
        public let hex: String

        public init(binary: String, octal: String, decimal: String, hex: String) {
            self.binary = binary
            self.octal = octal
            self.decimal = decimal
            self.hex = hex
        }
    }

    public struct PreparedInput: Equatable, Sendable {
        public let digitCount: Int

        fileprivate let isNegative: Bool
        fileprivate let digits: [Int]
        fileprivate let base: Int

        fileprivate var isZero: Bool {
            digits.count == 1 && digits[0] == 0
        }
    }

    public enum ValidationIssue: LocalizedError, Equatable, Sendable {
        case unsupportedBase
        case emptyInput
        case signWithoutDigits
        case invalidDigit(base: Int)
        case inputTooLong(maxDigits: Int)

        public var errorDescription: String? {
            switch self {
            case .unsupportedBase:
                return "只支持二进制、八进制、十进制和十六进制。"
            case .emptyInput:
                return "输入中没有可转换的数字。"
            case .signWithoutDigits:
                return "正负号后缺少数字。"
            case .invalidDigit(base: 2):
                return "二进制数只能包含 0 和 1，可在开头使用正负号。"
            case .invalidDigit(base: 8):
                return "八进制数只能包含 0–7，可在开头使用正负号。"
            case .invalidDigit(base: 10):
                return "十进制数只能包含 0–9，可在开头使用正负号。"
            case .invalidDigit(base: 16):
                return "十六进制数只能包含 0–9、A–F，可在开头使用正负号。"
            case .invalidDigit:
                return "输入包含当前进制不支持的字符。"
            case .inputTooLong(let maxDigits):
                return "输入数值最多支持 \(maxDigits) 位数字。"
            }
        }
    }

    public static func conversions(
        input: String,
        fromBase: Int
    ) -> Conversions? {
        try? validatedConversions(input: input, fromBase: fromBase)
    }

    public static func validatedConversions(
        input: String,
        fromBase: Int
    ) throws -> Conversions {
        conversions(from: try prepare(input: input, fromBase: fromBase))
    }

    public static func prepare(
        input: String,
        fromBase: Int
    ) throws -> PreparedInput {
        guard [2, 8, 10, 16].contains(fromBase) else {
            throw ValidationIssue.unsupportedBase
        }

        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationIssue.emptyInput
        }

        var isNegative = false
        if let first = trimmed.first, first == "-" || first == "+" {
            isNegative = first == "-"
            trimmed.removeFirst()
        }
        guard !trimmed.isEmpty else {
            throw ValidationIssue.signWithoutDigits
        }

        var digits: [Int] = []
        digits.reserveCapacity(min(trimmed.count, maximumInputDigitCount))
        var digitCount = 0

        for character in trimmed {
            guard let digit = digitValue(character), digit < fromBase else {
                throw ValidationIssue.invalidDigit(base: fromBase)
            }

            digitCount += 1
            guard digitCount <= maximumInputDigitCount else {
                throw ValidationIssue.inputTooLong(maxDigits: maximumInputDigitCount)
            }
            digits.append(digit)
        }

        let normalized = stripLeadingZeros(digits)
        return PreparedInput(
            digitCount: digitCount,
            isNegative: isNegative && !(normalized.count == 1 && normalized[0] == 0),
            digits: normalized,
            base: fromBase
        )
    }

    public static func conversions(from prepared: PreparedInput) -> Conversions {
        Conversions(
            binary: render(prepared, toBase: 2),
            octal: render(prepared, toBase: 8),
            decimal: render(prepared, toBase: 10),
            hex: render(prepared, toBase: 16).uppercased()
        )
    }

    private static func render(_ integer: PreparedInput, toBase: Int) -> String {
        guard !integer.isZero else { return "0" }

        var sourceDigits = integer.digits
        var outputDigits: [Int] = []

        while !sourceDigits.isEmpty {
            let division = divide(sourceDigits, sourceBase: integer.base, divisor: toBase)
            outputDigits.append(division.remainder)
            sourceDigits = division.quotient
        }

        let magnitude = outputDigits.reversed().map(digitCharacter).map(String.init).joined()
        return integer.isNegative ? "-\(magnitude)" : magnitude
    }

    private static func divide(
        _ digits: [Int],
        sourceBase: Int,
        divisor: Int
    ) -> (quotient: [Int], remainder: Int) {
        var quotient: [Int] = []
        quotient.reserveCapacity(digits.count)

        var remainder = 0
        for digit in digits {
            let accumulator = remainder * sourceBase + digit
            let quotientDigit = accumulator / divisor
            remainder = accumulator % divisor
            if !quotient.isEmpty || quotientDigit != 0 {
                quotient.append(quotientDigit)
            }
        }

        return (quotient, remainder)
    }

    private static func stripLeadingZeros(_ digits: [Int]) -> [Int] {
        let firstNonZero = digits.firstIndex { $0 != 0 }
        guard let firstNonZero else { return [0] }
        return Array(digits[firstNonZero...])
    }

    private static func digitValue(_ character: Character) -> Int? {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else {
            return nil
        }

        switch scalar.value {
        case 48...57:
            return Int(scalar.value - 48)
        case 65...70:
            return Int(scalar.value - 65 + 10)
        case 97...102:
            return Int(scalar.value - 97 + 10)
        default:
            return nil
        }
    }

    private static func digitCharacter(_ digit: Int) -> Character {
        Character(String(digit, radix: 16))
    }
}
