import XToolsCore
import Testing

struct RomanNumeralTests {
    /// Simulates a failing conversion inside a `ConverterModeBackfill` probe closure.
    private struct ConversionProbeError: Error {}

    @Test func convertsValidRomanNumerals() throws {
        #expect(RomanNumeralConverter.toRoman(5) == "V")
        #expect(RomanNumeralConverter.toRoman(2024) == "MMXXIV")
        #expect(try RomanNumeralConverter.validatedNumber(fromRoman: "MMXXIV") == 2024)
        #expect(try RomanNumeralConverter.validatedNumber(fromRoman: "mmxxiv") == 2024)
    }

    @Test func modeBackfillUsesCurrentValidRomanOutput() throws {
        let backfill = ConverterModeBackfill.currentValidOutput(
            input: "5",
            currentMode: "toRoman",
            hasError: false,
            isEmptyInput: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        ) { input, mode in
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

            if mode == "toRoman",
               let number = Int(trimmed),
               let roman = RomanNumeralConverter.toRoman(number) {
                return roman
            }

            if let number = try? RomanNumeralConverter.validatedNumber(fromRoman: trimmed) {
                return String(number)
            }

            throw ConversionProbeError()
        }

        #expect(backfill == "V")
        #expect(try RomanNumeralConverter.validatedNumber(fromRoman: backfill ?? "") == 5)
    }

    @Test func rejectsNonCanonicalRomanNumerals() {
        #expect((try? RomanNumeralConverter.validatedNumber(fromRoman: "IIII")) == nil) // repeated I form
        #expect((try? RomanNumeralConverter.validatedNumber(fromRoman: "IC")) == nil) // invalid subtractive form
        #expect((try? RomanNumeralConverter.validatedNumber(fromRoman: "VX")) == nil)
    }

    @Test func rejectsValuesOutsideClassicRange() {
        #expect(RomanNumeralConverter.toRoman(0) == nil)
        #expect(RomanNumeralConverter.toRoman(4000) == nil)
        #expect((try? RomanNumeralConverter.validatedNumber(fromRoman: "")) == nil)
    }

    @Test func outOfRangeRomanReportsRangeNotArrangement() {
        // 合法字符但数值越界（MMMM = 4000）：问题在数值本身，不是排列写法。
        #expect(throws: RomanNumeralConverter.ValidationIssue.romanOutOfRange) {
            _ = try RomanNumeralConverter.validatedNumber(fromRoman: "MMMM")
        }
        #expect(throws: RomanNumeralConverter.ValidationIssue.romanOutOfRange) {
            _ = try RomanNumeralConverter.validatedNumber(fromRoman: "MMMMCMXCIX")
        }
        #expect(
            RomanNumeralConverter.ValidationIssue.romanOutOfRange.errorDescription
                == "数值超出 1–3999 支持范围。"
        )
        // 边界内最大值仍正常。
        #expect((try? RomanNumeralConverter.validatedNumber(fromRoman: "MMMCMXCIX")) == 3999)
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
            .invalidRomanCharacter, .nonCanonicalRoman, .romanOutOfRange,
        ]
        for issue in issues {
            ToolDiagnosticContract.expectFactual(issue.errorDescription ?? "")
        }
    }
}
