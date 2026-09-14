import XToolsCore
import Testing

struct SecureRandomStringTests {
    // MARK: - Unbiased index mapping

    /// A word below the rejection limit maps to `word % upperBound` — the plain
    /// modulo the two generator pages both relied on.
    @Test func mapsWordBelowLimitByModulo() throws {
        // upperBound 4 → limit is UInt32.max rounded down to a multiple of 4.
        // 6 is well below the limit, so 6 % 4 == 2 → the third character.
        let out = try SecureRandomString.generate(
            length: 1, quantity: 1, characters: "abcd",
            nextWord: constant(6)
        )
        #expect(out == ["c"])
    }

    // MARK: - Rejection sampling (the security-sensitive part)

    /// A word at or above the rejection limit is discarded and the next word is
    /// drawn — this is what keeps the sampling unbiased for non-power-of-two pools.
    @Test func rejectsWordsAtOrAboveLimit() throws {
        let upperBound: UInt32 = 4
        let limit = UInt32.max - (UInt32.max % upperBound)

        // First word sits exactly on the limit (must be rejected), second is valid.
        var words = [limit, 5] // 5 % 4 == 1 → the second character
        let out = try SecureRandomString.generate(
            length: 1, quantity: 1, characters: "abcd",
            nextWord: { words.removeFirst() }
        )
        #expect(out == ["b"])
    }

    // MARK: - Shape: quantity × length, every character from the pool

    @Test func producesRequestedQuantityAndLength() throws {
        var counter: UInt32 = 0
        let out = try SecureRandomString.generate(
            length: 8, quantity: 3, characters: "abcdef",
            nextWord: { defer { counter += 1 }; return counter }
        )
        #expect(out.count == 3)
        #expect(out.allSatisfy { $0.count == 8 })
        let pool = Set("abcdef")
        #expect(out.allSatisfy { $0.allSatisfy { pool.contains($0) } })
    }

    @Test func requiredCharacterPoolsAreRepresentedInEveryGeneratedString() throws {
        var counter: UInt32 = 0
        let out = try SecureRandomString.generate(
            length: 8,
            quantity: 3,
            characters: "abCD12!?",
            requiredCharacters: ["ab", "CD", "12", "!?"],
            nextWord: { defer { counter += 1 }; return counter }
        )

        #expect(out.count == 3)
        #expect(out.allSatisfy { $0.count == 8 })
        #expect(out.allSatisfy { value in value.contains { "ab".contains($0) } })
        #expect(out.allSatisfy { value in value.contains { "CD".contains($0) } })
        #expect(out.allSatisfy { value in value.contains { "12".contains($0) } })
        #expect(out.allSatisfy { value in value.contains { "!?".contains($0) } })
    }

    // MARK: - Error paths

    /// An empty character pool is rejected rather than dividing by zero.
    @Test func emptyPoolThrows() {
        #expect(throws: SecureRandomString.GenerationError.emptyCharacterPool) {
            _ = try SecureRandomString.generate(
                length: 4, quantity: 1, characters: "",
                nextWord: constant(0)
            )
        }
    }

    @Test func requiredPoolsCannotExceedLength() {
        #expect(throws: SecureRandomString.GenerationError.requiredCharactersExceedLength) {
            _ = try SecureRandomString.generate(
                length: 2,
                quantity: 1,
                characters: "abc",
                requiredCharacters: ["a", "b", "c"],
                nextWord: constant(0)
            )
        }
    }

    /// A failing random source propagates as `randomSourceUnavailable`, which is
    /// how both pages know to show "无法访问系统安全随机数生成器".
    @Test func randomSourceFailurePropagates() {
        #expect(throws: SecureRandomString.GenerationError.randomSourceUnavailable) {
            _ = try SecureRandomString.generate(
                length: 4, quantity: 1, characters: "abc",
                nextWord: { throw SecureRandomString.GenerationError.randomSourceUnavailable }
            )
        }
    }

    /// Zero length or zero quantity yields empty strings / an empty list without
    /// touching the random source.
    @Test func zeroLengthAndZeroQuantityAreBenign() throws {
        let emptyStrings = try SecureRandomString.generate(
            length: 0, quantity: 2, characters: "abc", nextWord: throwingSource
        )
        #expect(emptyStrings == ["", ""])

        let noRows = try SecureRandomString.generate(
            length: 8, quantity: 0, characters: "abc", nextWord: throwingSource
        )
        #expect(noRows == [])
    }

    // MARK: - Helpers

    private func constant(_ value: UInt32) -> SecureRandomString.WordSource {
        { value }
    }

    private var throwingSource: SecureRandomString.WordSource {
        { throw SecureRandomString.GenerationError.randomSourceUnavailable }
    }
}
