import Foundation
import Security

/// CSPRNG string draw with rejection sampling. Injectable `WordSource` for tests.
public enum SecureRandomString {
    public enum GenerationError: Error, Equatable {
        case emptyCharacterPool
        case requiredCharactersExceedLength
        case randomSourceUnavailable
    }

    public typealias WordSource = () throws -> UInt32

    /// Unbiased index in `0..<upperBound` via rejection sampling (not plain modulo).
    private static func randomIndex(
        upperBound: Int,
        nextWord: WordSource
    ) rethrows -> Int {
        precondition(upperBound > 0, "upperBound must be positive")

        let bound = UInt32(upperBound)
        let limit = UInt32.max - (UInt32.max % bound)
        var value: UInt32 = 0

        repeat {
            value = try nextWord()
        } while value >= limit

        return Int(value % bound)
    }

    public static func generate(
        length: Int,
        quantity: Int,
        characters: String,
        nextWord: WordSource
    ) throws -> [String] {
        guard !characters.isEmpty else { throw GenerationError.emptyCharacterPool }

        let pool = Array(characters)
        var results: [String] = []
        results.reserveCapacity(max(quantity, 0))

        for _ in 0..<max(quantity, 0) {
            var value = ""
            value.reserveCapacity(max(length, 0))
            for _ in 0..<max(length, 0) {
                let index = try randomIndex(upperBound: pool.count, nextWord: nextWord)
                value.append(pool[index])
            }
            results.append(value)
        }

        return results
    }

    public static func generate(
        length: Int,
        quantity: Int,
        characters: String,
        requiredCharacters: [String],
        nextWord: WordSource
    ) throws -> [String] {
        guard !characters.isEmpty else { throw GenerationError.emptyCharacterPool }

        let requiredPools = requiredCharacters
            .filter { !$0.isEmpty }
            .map { Array($0) }
        let targetLength = max(length, 0)
        guard targetLength >= requiredPools.count else {
            throw GenerationError.requiredCharactersExceedLength
        }

        let pool = Array(characters)
        var results: [String] = []
        results.reserveCapacity(max(quantity, 0))

        for _ in 0..<max(quantity, 0) {
            var value: [Character] = []
            value.reserveCapacity(targetLength)

            for requiredPool in requiredPools {
                let index = try randomIndex(upperBound: requiredPool.count, nextWord: nextWord)
                value.append(requiredPool[index])
            }

            while value.count < targetLength {
                let index = try randomIndex(upperBound: pool.count, nextWord: nextWord)
                value.append(pool[index])
            }

            try shuffle(&value, nextWord: nextWord)
            results.append(String(value))
        }

        return results
    }

    public static func generate(
        length: Int,
        quantity: Int,
        characters: String
    ) throws -> [String] {
        try generate(
            length: length,
            quantity: quantity,
            characters: characters,
            nextWord: systemWord
        )
    }

    public static func generate(
        length: Int,
        quantity: Int,
        characters: String,
        requiredCharacters: [String]
    ) throws -> [String] {
        try generate(
            length: length,
            quantity: quantity,
            characters: characters,
            requiredCharacters: requiredCharacters,
            nextWord: systemWord
        )
    }

    private static func shuffle(
        _ characters: inout [Character],
        nextWord: WordSource
    ) throws {
        guard characters.count > 1 else { return }

        for upperBound in stride(from: characters.count, through: 2, by: -1) {
            let sourceIndex = try randomIndex(upperBound: upperBound, nextWord: nextWord)
            characters.swapAt(sourceIndex, upperBound - 1)
        }
    }

    private static func systemWord() throws -> UInt32 {
        var value: UInt32 = 0
        let status = withUnsafeMutableBytes(of: &value) { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw GenerationError.randomSourceUnavailable
        }
        return value
    }
}
