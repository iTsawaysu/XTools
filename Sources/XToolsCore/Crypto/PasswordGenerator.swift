import Foundation

public enum PasswordGenerator {
    public struct Options: Equatable, Sendable {
        public var length: Int
        public var quantity: Int
        public var lower: Bool
        public var upper: Bool
        public var numbers: Bool
        public var symbols: Bool
        public var excludeAmbiguous: Bool

        public init(
            length: Int,
            quantity: Int,
            lower: Bool,
            upper: Bool,
            numbers: Bool,
            symbols: Bool,
            excludeAmbiguous: Bool
        ) {
            self.length = length
            self.quantity = quantity
            self.lower = lower
            self.upper = upper
            self.numbers = numbers
            self.symbols = symbols
            self.excludeAmbiguous = excludeAmbiguous
        }
    }

    public enum Failure: LocalizedError, Equatable, Sendable {
        case emptyCharacterSet
        case requiredCharactersExceedLength
        case randomSourceUnavailable

        public var errorDescription: String? {
            switch self {
            case .emptyCharacterSet:
                return "字符集不能为空。"
            case .requiredCharactersExceedLength:
                return "密码长度不能小于已启用字符类别的数量。"
            case .randomSourceUnavailable:
                return "系统安全随机数生成器不可用。"
            }
        }
    }

    public enum Outcome: Equatable, Sendable {
        case produced([String])
        case failed(Failure)
    }

    /// Verbatim page glue: empty charset → Chinese diagnostic; CSPRNG failure → Chinese diagnostic.
    public static func generate(
        _ options: Options,
        nextWord: SecureRandomString.WordSource? = nil
    ) -> Outcome {
        let requiredSets = PasswordComposition.enabledCharacterSets(
            lower: options.lower,
            upper: options.upper,
            numbers: options.numbers,
            symbols: options.symbols,
            excludeAmbiguous: options.excludeAmbiguous
        )
        let sets = requiredSets.joined()

        guard !sets.isEmpty else {
            return .failed(.emptyCharacterSet)
        }

        do {
            let values: [String]
            if let nextWord {
                values = try SecureRandomString.generate(
                    length: options.length,
                    quantity: options.quantity,
                    characters: sets,
                    requiredCharacters: requiredSets,
                    nextWord: nextWord
                )
            } else {
                values = try SecureRandomString.generate(
                    length: options.length,
                    quantity: options.quantity,
                    characters: sets,
                    requiredCharacters: requiredSets
                )
            }
            return .produced(values)
        } catch SecureRandomString.GenerationError.requiredCharactersExceedLength {
            return .failed(.requiredCharactersExceedLength)
        } catch {
            return .failed(.randomSourceUnavailable)
        }
    }

}
