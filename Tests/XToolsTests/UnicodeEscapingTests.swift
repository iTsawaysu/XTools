import XToolsCore
import Testing

struct UnicodeEscapingTests {
    private struct ConversionProbeError: Error {}

    // MARK: - Encoding

    @Test func encodesAsciiToFourDigitEscapes() {
        // 'A' is U+0041, 'i' is U+0069.
        #expect(UnicodeEscaping.encode("Ai") == "\\u0041\\u0069")
    }

    @Test func padsShortCodePointsToFourDigits() {
        // newline is U+000A -> zero-padded to four digits.
        #expect(UnicodeEscaping.encode("\n") == "\\u000a")
    }

    @Test func usesLowercaseHex() {
        // '~' is U+007E; the hex digits are lowercase.
        #expect(UnicodeEscaping.encode("~") == "\\u007e")
    }

    @Test func encodesEmptyStringToEmpty() {
        #expect(UnicodeEscaping.encode("") == "")
    }

    @Test func encodesSupplementaryScalarsAsSurrogatePairs() {
        #expect(UnicodeEscaping.encode("😀") == "\\ud83d\\ude00")
        #expect(UnicodeEscaping.encode("A😀中") == "\\u0041\\ud83d\\ude00\\u4e2d")
    }

    // MARK: - Decoding

    @Test func decodesEscapesToCharacters() {
        #expect(UnicodeEscaping.decode("\\u0041\\u0069") == "Ai")
    }

    @Test func leavesNonEscapeTextUntouched() {
        #expect(UnicodeEscaping.decode("hello") == "hello")
        // Mixed escape + literal text: only the escape is decoded.
        #expect(UnicodeEscaping.decode("a\\u0042c") == "aBc")
    }

    @Test func roundTripsAsciiText() {
        let original = "Hello, World!"
        #expect(UnicodeEscaping.decode(UnicodeEscaping.encode(original)) == original)
    }

    @Test func decodesSurrogatePairsToSupplementaryScalars() {
        #expect(UnicodeEscaping.decode("\\ud83d\\ude00") == "😀")
        #expect(UnicodeEscaping.decode("x\\uD83D\\uDE00y") == "x😀y")
    }

    @Test func roundTripsMixedUnicodeText() {
        let original = "Hello, 中文 😀"
        #expect(UnicodeEscaping.decode(UnicodeEscaping.encode(original)) == original)
    }

    @Test func ignoresIncompleteEscapes() {
        // Fewer than four hex digits after \u is not a valid escape; left as-is.
        #expect(UnicodeEscaping.decode("\\u12") == "\\u12")
    }

    @Test func leavesIsolatedSurrogatesUntouched() {
        #expect(UnicodeEscaping.decode("\\ud83d") == "\\ud83d")
        #expect(UnicodeEscaping.decode("\\ude00") == "\\ude00")
        #expect(UnicodeEscaping.decode("\\ud83dA") == "\\ud83dA")
    }

    @Test func strictDecodeClassifiesMalformedEscapes() {
        #expect(throws: UnicodeEscaping.DecodingError.incompleteEscape) {
            _ = try UnicodeEscaping.decodeValidated("\\u12")
        }
        #expect(throws: UnicodeEscaping.DecodingError.invalidHexEscape) {
            _ = try UnicodeEscaping.decodeValidated("\\u12G4")
        }
        #expect(throws: UnicodeEscaping.DecodingError.isolatedHighSurrogate) {
            _ = try UnicodeEscaping.decodeValidated("\\ud83d")
        }
        #expect(throws: UnicodeEscaping.DecodingError.isolatedLowSurrogate) {
            _ = try UnicodeEscaping.decodeValidated("\\ude00")
        }
        #expect((try? UnicodeEscaping.decodeValidated("text \\u0041 \\ud83d\\ude00")) == "text A 😀")
    }

    @Test func decodingErrorsUseFactualMessages() {
        let errors: [UnicodeEscaping.DecodingError] = [
            .incompleteEscape, .invalidHexEscape, .isolatedHighSurrogate, .isolatedLowSurrogate,
        ]
        for error in errors {
            ToolDiagnosticContract.expectFactual(error.errorDescription ?? "")
        }
    }

    @Test func modeBackfillUsesCurrentValidUnicodeOutput() throws {
        let encodedBackfill = ConverterModeBackfill.currentValidOutput(
            input: "A😀",
            currentMode: "enc",
            hasError: false
        ) { input, mode in
            if mode == "enc" {
                return UnicodeEscaping.encode(input)
            }
            if mode == "dec" {
                return UnicodeEscaping.decode(input)
            }
            throw ConversionProbeError()
        }

        let decodedBackfill = ConverterModeBackfill.currentValidOutput(
            input: "\\u0041\\ud83d\\ude00",
            currentMode: "dec",
            hasError: false
        ) { input, mode in
            if mode == "enc" {
                return UnicodeEscaping.encode(input)
            }
            if mode == "dec" {
                return UnicodeEscaping.decode(input)
            }
            throw ConversionProbeError()
        }

        #expect(encodedBackfill == "\\u0041\\ud83d\\ude00")
        #expect(UnicodeEscaping.decode(encodedBackfill ?? "") == "A😀")
        #expect(decodedBackfill == "A😀")
        #expect(UnicodeEscaping.encode(decodedBackfill ?? "") == "\\u0041\\ud83d\\ude00")
    }
}
