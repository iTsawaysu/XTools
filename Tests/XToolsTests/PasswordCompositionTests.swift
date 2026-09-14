import XToolsCore
import Testing

struct PasswordCompositionTests {
    // MARK: - Character set assembly

    @Test func assemblesEnabledSetsInOrder() {
        let set = PasswordComposition.characterSet(
            lower: true, upper: true, numbers: true, symbols: true, excludeAmbiguous: false
        )
        #expect(set == "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]|;:,.<>?")
    }

    @Test func returnsEnabledSetsAsSeparatePools() {
        let sets = PasswordComposition.enabledCharacterSets(
            lower: true, upper: false, numbers: true, symbols: true, excludeAmbiguous: true
        )

        #expect(sets == [
            "abcdefghijkmnpqrstuvwxyz",
            "23456789",
            "!@#$%^&*()_+-=[]|;:,.<>?"
        ])
    }

    @Test func omitsDisabledSets() {
        let onlyNumbers = PasswordComposition.characterSet(
            lower: false, upper: false, numbers: true, symbols: false, excludeAmbiguous: false
        )
        #expect(onlyNumbers == "0123456789")

        let lowerUpper = PasswordComposition.characterSet(
            lower: true, upper: true, numbers: false, symbols: false, excludeAmbiguous: false
        )
        #expect(lowerUpper == "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    }

    @Test func excludesAmbiguousCharacters() {
        // l/o dropped from lowercase, I/O from uppercase, 0/1 from digits.
        let set = PasswordComposition.characterSet(
            lower: true, upper: true, numbers: true, symbols: false, excludeAmbiguous: true
        )
        #expect(!set.contains("l"))
        #expect(!set.contains("o"))
        #expect(!set.contains("I"))
        #expect(!set.contains("O"))
        #expect(!set.contains("0"))
        #expect(!set.contains("1"))
        // Non-ambiguous characters survive.
        #expect(set.contains("a"))
        #expect(set.contains("Z"))
        #expect(set.contains("9"))
    }

    @Test func symbolsAreUnaffectedByAmbiguousExclusion() {
        let withExclusion = PasswordComposition.characterSet(
            lower: false, upper: false, numbers: false, symbols: true, excludeAmbiguous: true
        )
        #expect(withExclusion == "!@#$%^&*()_+-=[]|;:,.<>?")
    }

    @Test func returnsEmptyWhenNoSetEnabled() {
        let set = PasswordComposition.characterSet(
            lower: false, upper: false, numbers: false, symbols: false, excludeAmbiguous: true
        )
        #expect(set.isEmpty)
    }

    @Test func keepsSinglePoolCompositionAvailableForWebsiteCompatibility() {
        let set = PasswordComposition.characterSet(
            lower: true, upper: false, numbers: false, symbols: false, excludeAmbiguous: false
        )

        #expect(set == "abcdefghijklmnopqrstuvwxyz")
    }
}
