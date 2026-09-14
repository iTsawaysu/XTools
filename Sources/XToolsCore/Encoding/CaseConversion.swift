import Foundation

public enum CaseConversion {
    public static func words(_ value: String) -> [String] {
        rawTokens(in: value)
            .flatMap(splitToken)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
    }

    public static func styles(_ input: String) -> [(label: String, value: String)] {
        let w = words(input)
        guard !w.isEmpty else { return [] }
        let cap = { (s: String) in s.prefix(1).uppercased() + s.dropFirst() }
        return [
            ("camelCase", w.enumerated().map { $0.offset == 0 ? $0.element : cap($0.element) }.joined()),
            ("PascalCase", w.map(cap).joined()),
            ("snake_case", w.joined(separator: "_")),
            ("kebab-case", w.joined(separator: "-")),
            ("CONSTANT", w.joined(separator: "_").uppercased()),
            ("Title Case", w.map(cap).joined(separator: " ")),
            ("UPPER", w.joined(separator: " ").uppercased()),
            ("lower", w.joined(separator: " "))
        ]
    }

    fileprivate enum CharacterKind {
        case uppercase
        case lowercase
        case digit
        case other
    }

    private static func rawTokens(in value: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for character in value {
            if character.isLetterOrNumber {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func splitToken(_ token: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousKind: CharacterKind?

        for character in token {
            let kind = character.caseConversionKind

            if shouldSplitBefore(kind: kind, previousKind: previousKind) && !current.isEmpty {
                words.append(current)
                current = ""
            } else if kind == .lowercase,
                      previousKind == .uppercase,
                      current.count > 1,
                      let last = current.popLast() {
                words.append(current)
                current = String(last)
            }

            current.append(character)
            previousKind = kind
        }

        if !current.isEmpty {
            words.append(current)
        }
        return words
    }

    private static func shouldSplitBefore(kind: CharacterKind, previousKind: CharacterKind?) -> Bool {
        guard let previousKind else { return false }

        switch (previousKind, kind) {
        case (.lowercase, .uppercase), (.digit, .uppercase):
            return true
        default:
            return false
        }
    }
}

private extension Character {
    var isLetterOrNumber: Bool {
        unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    var caseConversionKind: CaseConversion.CharacterKind {
        guard isLetterOrNumber else { return .other }

        if unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            return .digit
        }

        let string = String(self)
        if string.uppercased() == string, string.lowercased() != string {
            return .uppercase
        }
        if string.lowercased() == string, string.uppercased() != string {
            return .lowercase
        }
        return .other
    }
}
