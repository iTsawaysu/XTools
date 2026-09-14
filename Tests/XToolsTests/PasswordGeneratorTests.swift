import XToolsCore
import Testing

struct PasswordGeneratorTests {
    private func constant(_ value: UInt32) -> SecureRandomString.WordSource {
        { value }
    }

    @Test func emptyCharsetYieldsChineseDiagnostic() {
        let outcome = PasswordGenerator.generate(
            PasswordGenerator.Options(
                length: 16,
                quantity: 1,
                lower: false,
                upper: false,
                numbers: false,
                symbols: false,
                excludeAmbiguous: true
            ),
            nextWord: constant(0)
        )
        #expect(outcome == .failed(.emptyCharacterSet))
    }

    @Test func producesRequiredClassPasswordsWithInjectedSource() {
        let outcome = PasswordGenerator.generate(
            PasswordGenerator.Options(
                length: 16,
                quantity: 3,
                lower: true,
                upper: true,
                numbers: true,
                symbols: false,
                excludeAmbiguous: true
            ),
            nextWord: constant(0)
        )
        guard case .produced(let values) = outcome else {
            Issue.record("expected produced passwords")
            return
        }
        #expect(values.count == 3)
        for value in values {
            #expect(value.count == 16)
            #expect(value.contains(where: { "abcdefghijklmnopqrstuvwxyz".contains($0) }))
            #expect(value.contains(where: { "ABCDEFGHIJKLMNOPQRSTUVWXYZ".contains($0) }))
            #expect(value.contains(where: { "23456789".contains($0) }))
        }
    }

    @Test func singlePoolPasswordsRemainValidWithoutStrengthClassification() {
        let outcome = PasswordGenerator.generate(
            PasswordGenerator.Options(
                length: 16,
                quantity: 1,
                lower: true,
                upper: false,
                numbers: false,
                symbols: false,
                excludeAmbiguous: false
            ),
            nextWord: constant(0)
        )

        guard case .produced(let values) = outcome else {
            Issue.record("expected produced passwords")
            return
        }

        #expect(values.count == 1)
        #expect(values[0].count == 16)
        #expect(values[0].allSatisfy { "abcdefghijklmnopqrstuvwxyz".contains($0) })
    }

    @Test func randomSourceFailureMapsChineseDiagnostic() {
        let throwing: SecureRandomString.WordSource = {
            throw SecureRandomString.GenerationError.randomSourceUnavailable
        }
        let outcome = PasswordGenerator.generate(
            PasswordGenerator.Options(
                length: 16,
                quantity: 1,
                lower: true,
                upper: false,
                numbers: false,
                symbols: false,
                excludeAmbiguous: false
            ),
            nextWord: throwing
        )
        #expect(outcome == .failed(.randomSourceUnavailable))
    }

    @Test func enabledClassesCannotExceedPasswordLength() {
        let outcome = PasswordGenerator.generate(
            PasswordGenerator.Options(
                length: 2,
                quantity: 1,
                lower: true,
                upper: true,
                numbers: true,
                symbols: true,
                excludeAmbiguous: false
            ),
            nextWord: constant(0)
        )
        #expect(outcome == .failed(.requiredCharactersExceedLength))
    }

    @Test func failuresUseFactualMessages() {
        let failures: [PasswordGenerator.Failure] = [
            .emptyCharacterSet, .requiredCharactersExceedLength, .randomSourceUnavailable,
        ]
        for failure in failures {
            ToolDiagnosticContract.expectFactual(failure.errorDescription ?? "")
        }
    }
}
