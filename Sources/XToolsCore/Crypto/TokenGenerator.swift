import Foundation

public enum TokenGenerationMode: String, CaseIterable, Equatable, Sendable {
    case base64URL
    case hex
    case characterSet
}

/// Keeps byte-oriented representations separate from the existing unbiased
/// character-pool recipe so changing a display format cannot change its source entropy.
public enum TokenGenerator {
    public enum Options: Equatable, Sendable {
        case base64URL(byteCount: Int, quantity: Int)
        case hex(byteCount: Int, quantity: Int)
        case characterSet(
            length: Int,
            quantity: Int,
            lower: Bool,
            upper: Bool,
            numbers: Bool,
            symbols: Bool
        )

        public init(
            length: Int,
            quantity: Int,
            lower: Bool,
            upper: Bool,
            numbers: Bool,
            symbols: Bool
        ) {
            self = .characterSet(
                length: length,
                quantity: quantity,
                lower: lower,
                upper: upper,
                numbers: numbers,
                symbols: symbols
            )
        }

    }

    public enum Entropy: Equatable, Sendable {
        case exact(bits: Int)
        case estimated(bits: Double)

        public var bits: Double {
            switch self {
            case .exact(let bits): return Double(bits)
            case .estimated(let bits): return bits
            }
        }

        public var isLow: Bool {
            bits < 64
        }
    }

    public typealias ByteSource = SecureRandomBytes.Source

    public enum Failure: LocalizedError, Equatable, Sendable {
        case emptyCharacterSet
        case randomSourceUnavailable

        public var errorDescription: String? {
            switch self {
            case .emptyCharacterSet:
                return "字符集不能为空。"
            case .randomSourceUnavailable:
                return "系统安全随机数生成器不可用。"
            }
        }
    }

    public enum Outcome: Equatable, Sendable {
        case produced([String])
        case failed(Failure)
    }

    public static func characterSet(
        lower: Bool,
        upper: Bool,
        numbers: Bool,
        symbols: Bool
    ) -> String {
        [
            lower ? "abcdefghijklmnopqrstuvwxyz" : "",
            upper ? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" : "",
            numbers ? "0123456789" : "",
            symbols ? "!@#$%^&*-_=+?" : ""
        ].joined()
    }

    public static func entropy(for options: Options) -> Entropy {
        switch options {
        case .base64URL(let byteCount, _), .hex(let byteCount, _):
            return .exact(bits: max(byteCount, 0) * 8)
        case .characterSet(let length, _, let lower, let upper, let numbers, let symbols):
            let poolCount = characterSet(
                lower: lower,
                upper: upper,
                numbers: numbers,
                symbols: symbols
            ).count
            guard poolCount > 0 else { return .estimated(bits: 0) }
            return .estimated(bits: Double(max(length, 0)) * log2(Double(poolCount)))
        }
    }

    public static func generate(
        _ options: Options,
        nextWord: SecureRandomString.WordSource? = nil,
        nextBytes: ByteSource? = nil
    ) -> Outcome {
        switch options {
        case .base64URL(let byteCount, let quantity):
            return generateBytes(
                count: byteCount,
                quantity: quantity,
                nextBytes: nextBytes,
                encode: base64URL
            )
        case .hex(let byteCount, let quantity):
            return generateBytes(
                count: byteCount,
                quantity: quantity,
                nextBytes: nextBytes,
                encode: hex
            )
        case .characterSet(let length, let quantity, let lower, let upper, let numbers, let symbols):
            let sets = characterSet(
                lower: lower,
                upper: upper,
                numbers: numbers,
                symbols: symbols
            )
            guard !sets.isEmpty else {
                return .failed(.emptyCharacterSet)
            }

            do {
                let values: [String]
                if let nextWord {
                    values = try SecureRandomString.generate(
                        length: length,
                        quantity: quantity,
                        characters: sets,
                        nextWord: nextWord
                    )
                } else {
                    values = try SecureRandomString.generate(
                        length: length,
                        quantity: quantity,
                        characters: sets
                    )
                }
                return .produced(values)
            } catch {
                return .failed(.randomSourceUnavailable)
            }
        }
    }

    private static func generateBytes(
        count: Int,
        quantity: Int,
        nextBytes: ByteSource?,
        encode: ([UInt8]) -> String
    ) -> Outcome {
        do {
            var values: [String] = []
            values.reserveCapacity(max(quantity, 0))
            for _ in 0..<max(quantity, 0) {
                let bytes = try SecureRandomBytes.generate(count: count, source: nextBytes)
                values.append(encode(bytes))
            }
            return .produced(values)
        } catch {
            return .failed(.randomSourceUnavailable)
        }
    }

    private static func base64URL(_ bytes: [UInt8]) -> String {
        Base64Conversion.encodeBase64URL(Data(bytes))
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.toHexStringLowercased()
    }
}
