import XToolsCore
import Testing

struct RomanNumeralTests {
    /// Simulates a failing conversion inside a `ConverterModeBackfill` probe closure.
    private struct ConversionProbeError: Error {}

    @Test func convertsValidRomanNumerals() throws {
        #expect(RomanNumeralConverter.toRoman(5) == "V")
        #expect(RomanNumeralConverter.toRoman(2024) == "MMXXIV")
        #expect(RomanNumeralConverter.toNumber("MMXXIV") == 2024)
        #expect(RomanNumeralConverter.toNumber("mmxxiv") == 2024)
    }

    @Test func normalizesArabicInput() {
        #expect(
            RomanNumeralConverter.normalizedArabicInput(" 1 a2\n3 ")
            == "123"
        )
    }

    @Test func normalizesRomanInput() {
        #expect(
            RomanNumeralConverter.normalizedRomanInput(" i c z\nv ")
            == "ICV"
        )
    }

    @Test func modeBackfillUsesCurrentValidRomanOutput() throws {
        let backfill = ConverterModeBackfill.currentValidOutput(
            input: "5",
            currentMode: "toRoman",
            hasError: false,
            isEmptyInput: { RomanNumeralConverter.normalizedArabicInput($0).isEmpty }
        ) { input, mode in
            if mode == "toRoman",
               let number = Int(RomanNumeralConverter.normalizedArabicInput(input)),
               let roman = RomanNumeralConverter.toRoman(number) {
                return roman
            }

            if let number = RomanNumeralConverter.toNumber(RomanNumeralConverter.normalizedRomanInput(input)) {
                return String(number)
            }

            throw ConversionProbeError()
        }

        #expect(backfill == "V")
        #expect(RomanNumeralConverter.toNumber(backfill ?? "") == 5)
    }

    @Test func rejectsNonCanonicalRomanNumerals() {
        #expect(RomanNumeralConverter.toNumber("IIII") == nil) // repeated I form
        #expect(RomanNumeralConverter.toNumber("IC") == nil) // invalid subtractive form
        #expect(RomanNumeralConverter.toNumber("VX") == nil)
    }

    @Test func rejectsValuesOutsideClassicRange() {
        #expect(RomanNumeralConverter.toRoman(0) == nil)
        #expect(RomanNumeralConverter.toRoman(4000) == nil)
        #expect(RomanNumeralConverter.toNumber("") == nil)
    }

    @Test func strictConversionDoesNotSilentlyRemoveInvalidCharacters() {
        #expect(throws: RomanNumeralConverter.ValidationIssue.invalidArabicCharacter) {
            _ = try RomanNumeralConverter.validatedRoman(fromArabic: "12a3")
        }
        #expect(throws: RomanNumeralConverter.ValidationIssue.arabicOutOfRange) {
            _ = try RomanNumeralConverter.validatedRoman(fromArabic: "4000")
        }
        #expect(throws: RomanNumeralConverter.ValidationIssue.invalidRomanCharacter) {
            _ = try RomanNumeralConverter.validatedNumber(fromRoman: "abc")
        }
        #expect(throws: RomanNumeralConverter.ValidationIssue.nonCanonicalRoman) {
            _ = try RomanNumeralConverter.validatedNumber(fromRoman: "IC")
        }
        #expect((try? RomanNumeralConverter.validatedRoman(fromArabic: "2024")) == "MMXXIV")
        #expect((try? RomanNumeralConverter.validatedNumber(fromRoman: "mmxxiv")) == 2024)
    }

    @Test func validationIssuesUseFactualMessages() {
        let issues: [RomanNumeralConverter.ValidationIssue] = [
            .emptyInput, .invalidArabicCharacter, .arabicOutOfRange,
            .invalidRomanCharacter, .nonCanonicalRoman,
        ]
        for issue in issues {
            ToolDiagnosticContract.expectFactual(issue.errorDescription ?? "")
        }
    }
}
