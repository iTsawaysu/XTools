import Foundation

public enum RomanNumeralConverter {
    public enum ValidationIssue: LocalizedError, Equatable, Sendable {
        case emptyInput
        case invalidArabicCharacter
        case arabicOutOfRange
        case invalidRomanCharacter
        case nonCanonicalRoman

        public var errorDescription: String? {
            switch self {
            case .emptyInput:
                return "输入中没有可转换的数字。"
            case .invalidArabicCharacter:
                return "阿拉伯数字输入只能包含 0–9。"
            case .arabicOutOfRange:
                return "阿拉伯数字必须是 1–3999 的整数。"
            case .invalidRomanCharacter:
                return "罗马数字只能包含 I、V、X、L、C、D、M。"
            case .nonCanonicalRoman:
                return "罗马数字的排列不符合标准写法。"
            }
        }
    }

    private static let romanPairs: [(value: Int, numeral: String)] = [
        (1000, "M"),
        (900, "CM"),
        (500, "D"),
        (400, "CD"),
        (100, "C"),
        (90, "XC"),
        (50, "L"),
        (40, "XL"),
        (10, "X"),
        (9, "IX"),
        (5, "V"),
        (4, "IV"),
        (1, "I")
    ]

    private static let romanValues: [Character: Int] = [
        "I": 1,
        "V": 5,
        "X": 10,
        "L": 50,
        "C": 100,
        "D": 500,
        "M": 1000
    ]

    public static func toRoman(_ value: Int) -> String? {
        guard (1...3999).contains(value) else {
            return nil
        }

        var remaining = value
        var result = ""
        for pair in romanPairs {
            while remaining >= pair.value {
                result += pair.numeral
                remaining -= pair.value
            }
        }
        return result
    }

    public static func normalizedArabicInput(_ value: String) -> String {
        String(value.filter { ("0"..."9").contains($0) })
    }

    public static func normalizedRomanInput(_ value: String) -> String {
        String(value.uppercased().filter { romanValues[$0] != nil })
    }

    public static func toNumber(_ value: String) -> Int? {
        try? validatedNumber(fromRoman: value)
    }

    public static func validatedRoman(fromArabic value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ValidationIssue.emptyInput
        }
        guard normalized.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) else {
            throw ValidationIssue.invalidArabicCharacter
        }
        guard let number = Int(normalized), let roman = toRoman(number) else {
            throw ValidationIssue.arabicOutOfRange
        }
        return roman
    }

    public static func validatedNumber(fromRoman value: String) throws -> Int {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let chars = Array(normalized)
        guard !chars.isEmpty else {
            throw ValidationIssue.emptyInput
        }
        guard chars.allSatisfy({ romanValues[$0] != nil }) else {
            throw ValidationIssue.invalidRomanCharacter
        }

        var total = 0
        for index in chars.indices {
            let current = romanValues[chars[index]] ?? 0
            let next = index + 1 < chars.count ? romanValues[chars[index + 1]] ?? 0 : 0
            total += current < next ? -current : current
        }

        guard let canonical = toRoman(total), canonical == normalized else {
            throw ValidationIssue.nonCanonicalRoman
        }
        return total
    }
}
