import XToolsCore
import Foundation
import Testing

struct TokenGeneratorTests {
    private func constant(_ value: UInt32) -> SecureRandomString.WordSource {
        { value }
    }

    @Test func emptyCharsetYieldsChineseDiagnostic() {
        let outcome = TokenGenerator.generate(
            TokenGenerator.Options(
                length: 32,
                quantity: 1,
                lower: false,
                upper: false,
                numbers: false,
                symbols: false
            ),
            nextWord: constant(0)
        )
        #expect(outcome == .failed(.emptyCharacterSet))
    }

    @Test func characterSetUsesTokenSymbolPool() {
        let symbolsOnly = TokenGenerator.characterSet(lower: false, upper: false, numbers: false, symbols: true)
        #expect(symbolsOnly == "!@#$%^&*-_=+?")
        #expect(!symbolsOnly.contains("["))
        #expect(TokenGenerator.characterSet(lower: true, upper: false, numbers: false, symbols: false)
            == "abcdefghijklmnopqrstuvwxyz")
    }

    @Test func producesTokensWithInjectedSource() {
        let outcome = TokenGenerator.generate(
            TokenGenerator.Options(
                length: 8,
                quantity: 2,
                lower: true,
                upper: false,
                numbers: false,
                symbols: false
            ),
            nextWord: constant(0)
        )
        guard case .produced(let values) = outcome else {
            Issue.record("expected produced tokens")
            return
        }
        #expect(values == ["aaaaaaaa", "aaaaaaaa"])
    }

    @Test func randomSourceFailureMapsChineseDiagnostic() {
        let throwing: SecureRandomString.WordSource = {
            throw SecureRandomString.GenerationError.randomSourceUnavailable
        }
        let outcome = TokenGenerator.generate(
            TokenGenerator.Options(
                length: 8,
                quantity: 1,
                lower: true,
                upper: false,
                numbers: false,
                symbols: false
            ),
            nextWord: throwing
        )
        #expect(outcome == .failed(.randomSourceUnavailable))
    }

    @Test func base64URLUsesRandomBytesAndRemovesPadding() {
        var requestedCounts: [Int] = []
        let outcome = TokenGenerator.generate(
            .base64URL(byteCount: 3, quantity: 2),
            nextBytes: { count in
                requestedCounts.append(count)
                return [0xfb, 0xef, 0xff]
            }
        )

        #expect(requestedCounts == [3, 3])
        #expect(outcome == .produced(["--__", "--__"]))
    }

    @Test func base64URLStripsRequiredPaddingWithoutDroppingPayload() {
        let outcome = TokenGenerator.generate(
            .base64URL(byteCount: 2, quantity: 1),
            nextBytes: { _ in [0x01, 0x02] }
        )

        #expect(outcome == .produced(["AQI"]))
    }

    @Test func hexUsesTwoLowercaseCharactersPerRandomByte() {
        let outcome = TokenGenerator.generate(
            .hex(byteCount: 3, quantity: 1),
            nextBytes: { _ in [0x00, 0xab, 0xff] }
        )

        #expect(outcome == .produced(["00abff"]))
    }

    @Test func byteSourceFailureMapsToExistingFactualFailure() {
        let throwing: TokenGenerator.ByteSource = { _ in
            throw SecureRandomString.GenerationError.randomSourceUnavailable
        }

        #expect(TokenGenerator.generate(.hex(byteCount: 16, quantity: 1), nextBytes: throwing)
            == .failed(.randomSourceUnavailable))
        #expect(TokenGenerator.generate(.base64URL(byteCount: 16, quantity: 1), nextBytes: throwing)
            == .failed(.randomSourceUnavailable))
    }

    @Test func wrongByteCountFromSourceIsRejected() {
        let outcome = TokenGenerator.generate(
            .hex(byteCount: 3, quantity: 1),
            nextBytes: { _ in [0x00, 0x01] }
        )

        #expect(outcome == .failed(.randomSourceUnavailable))
    }

    @Test func byteModesReportExactRandomBits() {
        #expect(TokenGenerator.entropy(for: .base64URL(byteCount: 32, quantity: 1)) == .exact(bits: 256))
        #expect(TokenGenerator.entropy(for: .hex(byteCount: 16, quantity: 20)) == .exact(bits: 128))
    }

    @Test func characterModeReportsEstimatedEntropyFromItsActualPool() {
        let entropy = TokenGenerator.entropy(
            for: .characterSet(
                length: 32,
                quantity: 1,
                lower: true,
                upper: true,
                numbers: true,
                symbols: false
            )
        )

        guard case .estimated(let bits) = entropy else {
            Issue.record("expected estimated character-pool entropy")
            return
        }
        #expect(abs(bits - 32 * log2(62)) < 0.001)
        #expect(!entropy.isLow)
    }

    @Test func onlyRecipesBelowSixtyFourBitsAreLowEntropy() {
        #expect(TokenGenerator.entropy(for: .hex(byteCount: 7, quantity: 1)).isLow)
        #expect(!TokenGenerator.entropy(for: .hex(byteCount: 8, quantity: 1)).isLow)
        #expect(TokenGenerator.entropy(
            for: .characterSet(
                length: 8,
                quantity: 1,
                lower: true,
                upper: false,
                numbers: false,
                symbols: false
            )
        ).isLow)
    }

    @Test func failuresUseFactualMessages() {
        for failure in [TokenGenerator.Failure.emptyCharacterSet, .randomSourceUnavailable] {
            ToolDiagnosticContract.expectFactual(failure.errorDescription ?? "")
        }
    }
}
