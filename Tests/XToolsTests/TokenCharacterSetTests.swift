import XToolsCore
import Testing

struct TokenCharacterSetTests {
    @Test func assemblesAllEnabledSetsInOrder() {
        let set = TokenGenerator.characterSet(lower: true, upper: true, numbers: true, symbols: true)
        #expect(set == "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*-_=+?")
    }

    @Test func usesTokenSpecificSymbolSet() {
        // The token symbol set differs from the password generator's.
        let symbolsOnly = TokenGenerator.characterSet(lower: false, upper: false, numbers: false, symbols: true)
        #expect(symbolsOnly == "!@#$%^&*-_=+?")
    }

    @Test func omitsDisabledSets() {
        let onlyNumbers = TokenGenerator.characterSet(lower: false, upper: false, numbers: true, symbols: false)
        #expect(onlyNumbers == "0123456789")

        let lowerUpper = TokenGenerator.characterSet(lower: true, upper: true, numbers: false, symbols: false)
        #expect(lowerUpper == "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    }

    @Test func returnsEmptyWhenNoSetEnabled() {
        #expect(TokenGenerator.characterSet(lower: false, upper: false, numbers: false, symbols: false).isEmpty)
    }

    @Test func doesNotExcludeAmbiguousCharacters() {
        // Unlike PasswordComposition, the token pool keeps l/o/I/O/0/1.
        let set = TokenGenerator.characterSet(lower: true, upper: true, numbers: true, symbols: false)
        #expect(set.contains("l"))
        #expect(set.contains("o"))
        #expect(set.contains("I"))
        #expect(set.contains("O"))
        #expect(set.contains("0"))
        #expect(set.contains("1"))
    }
}
