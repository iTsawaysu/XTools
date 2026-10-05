import XToolsCore
@testable import XTools
import Testing

struct ASCIIBinaryConversionTests {
    private struct ConversionProbeError: Error {}

    // MARK: - Text to binary

    @Test func encodesTextAsEightBitBinary() {
        // "A" is 0x41 = 0b01000001
        #expect(ASCIIBinaryConversion.textToBinary("A") == "01000001")
        // "AB" -> two space-separated bytes
        #expect(ASCIIBinaryConversion.textToBinary("AB") == "01000001 01000010")
    }

    @Test func encodesMultibyteUTF8PerByte() {
        // "é" is U+00E9 -> UTF-8 0xC3 0xA9 -> two 8-bit groups
        #expect(ASCIIBinaryConversion.textToBinary("é") == "11000011 10101001")
    }

    @Test func pageTreatsWhitespaceAsTextOnlyInEncodingModes() throws {
        #expect(!IndexASCIIBinarySegment.isEmptyInput(" ", mode: "bin"))
        #expect(!IndexASCIIBinarySegment.isEmptyInput(" ", mode: "ascii"))
        #expect(IndexASCIIBinarySegment.isEmptyInput(" \n\t", mode: "debin"))
        #expect(IndexASCIIBinarySegment.isEmptyInput(" \n\t", mode: "deascii"))
        #expect(ASCIIBinaryConversion.textToBinary(" ") == "00100000")
        #expect(try ASCIIBinaryConversion.validatedTextToASCII(" ") == "32")
    }

    // MARK: - Text to ASCII (decimal scalar values)

    @Test func encodesTextAsDecimalScalarValues() throws {
        #expect(try ASCIIBinaryConversion.validatedTextToASCII("A") == "65")
        #expect(try ASCIIBinaryConversion.validatedTextToASCII("ABC") == "65 66 67")
        #expect(try ASCIIBinaryConversion.validatedTextToASCII("\n") == "10")
    }

    @Test func rejectsNonASCIITextForASCIIValues() {
        #expect((try? ASCIIBinaryConversion.validatedTextToASCII("é")) == nil)
        #expect((try? ASCIIBinaryConversion.validatedTextToASCII("你好")) == nil)
    }

    @Test func decodesDecimalASCIIValuesBackToText() throws {
        #expect(try ASCIIBinaryConversion.validatedASCIIToText("65 66 67") == "ABC")
        #expect(try ASCIIBinaryConversion.validatedASCIIToText("65,66,67") == "ABC")
        #expect(try ASCIIBinaryConversion.validatedASCIIToText("65\n66\t67") == "ABC")
        #expect(try ASCIIBinaryConversion.validatedASCIIToText("10") == "\n")
    }

    @Test func rejectsInvalidDecimalASCIIValues() {
        #expect((try? ASCIIBinaryConversion.validatedASCIIToText("")) == nil)
        #expect((try? ASCIIBinaryConversion.validatedASCIIToText("   ,, ")) == nil)
        #expect((try? ASCIIBinaryConversion.validatedASCIIToText("128")) == nil)
        #expect((try? ASCIIBinaryConversion.validatedASCIIToText("-1")) == nil)
        #expect((try? ASCIIBinaryConversion.validatedASCIIToText("65.0")) == nil)
        #expect((try? ASCIIBinaryConversion.validatedASCIIToText("0x41")) == nil)
        #expect((try? ASCIIBinaryConversion.validatedASCIIToText("A")) == nil)
    }

    // MARK: - Binary to text

    @Test func decodesBinaryBackToText() throws {
        #expect(try ASCIIBinaryConversion.validatedBinaryToText("01000001") == "A")
        #expect(try ASCIIBinaryConversion.validatedBinaryToText("01000001 01000010") == "AB")
        #expect(try ASCIIBinaryConversion.validatedBinaryToText("0100000101000010") == "AB")
        #expect(try ASCIIBinaryConversion.validatedBinaryToText("0100 0001 0100 0010") == "AB")
        // 逗号与空白同为分隔符：与 ASCII 十进制方向（"65,66,67"）规则统一。
        #expect(try ASCIIBinaryConversion.validatedBinaryToText("01000001,01000010") == "AB")
        #expect(try ASCIIBinaryConversion.validatedBinaryToText("01000001, 01000010,01000011") == "ABC")
        // Round-trips multibyte UTF-8.
        #expect(try ASCIIBinaryConversion.validatedBinaryToText("11000011 10101001") == "é")
    }

    @Test func decodesWhitespaceOnlyInputToEmptyString() throws {
        // No tokens -> empty byte array -> empty string (not nil).
        #expect(try ASCIIBinaryConversion.validatedBinaryToText("") == "")
        #expect(try ASCIIBinaryConversion.validatedBinaryToText("   ") == "")
        #expect(try ASCIIBinaryConversion.validatedBinaryToText(" , , ") == "")
    }

    @Test func returnsNilForMalformedBinary() {
        // Token not exactly 8 digits.
        #expect((try? ASCIIBinaryConversion.validatedBinaryToText("0100000")) == nil)
        #expect((try? ASCIIBinaryConversion.validatedBinaryToText("010000012")) == nil)
        // Non-binary digit.
        #expect((try? ASCIIBinaryConversion.validatedBinaryToText("01000002")) == nil)
    }

    @Test func returnsNilForInvalidUTF8ByteSequence() {
        // 0xFF (11111111) is not a valid standalone UTF-8 byte.
        #expect((try? ASCIIBinaryConversion.validatedBinaryToText("11111111")) == nil)
    }

    @Test func strictConversionsClassifyEveryInvalidInputKind() {
        #expect(throws: ASCIIBinaryConversion.ConversionError.nonASCIIText) {
            _ = try ASCIIBinaryConversion.validatedTextToASCII("中文")
        }
        #expect(throws: ASCIIBinaryConversion.ConversionError.emptyASCIIInput) {
            _ = try ASCIIBinaryConversion.validatedASCIIToText(", ,")
        }
        #expect(throws: ASCIIBinaryConversion.ConversionError.invalidASCIIToken) {
            _ = try ASCIIBinaryConversion.validatedASCIIToText("65 A")
        }
        #expect(throws: ASCIIBinaryConversion.ConversionError.asciiOutOfRange) {
            _ = try ASCIIBinaryConversion.validatedASCIIToText("128")
        }
        #expect(throws: ASCIIBinaryConversion.ConversionError.invalidBinaryCharacter) {
            _ = try ASCIIBinaryConversion.validatedBinaryToText("01000002")
        }
        #expect(throws: ASCIIBinaryConversion.ConversionError.incompleteBinaryByte) {
            _ = try ASCIIBinaryConversion.validatedBinaryToText("0100000")
        }
        #expect(throws: ASCIIBinaryConversion.ConversionError.invalidUTF8) {
            _ = try ASCIIBinaryConversion.validatedBinaryToText("11111111")
        }
    }

    @Test func conversionErrorsUseFactualMessages() {
        let errors: [ASCIIBinaryConversion.ConversionError] = [
            .nonASCIIText, .emptyASCIIInput, .invalidASCIIToken, .asciiOutOfRange,
            .invalidBinaryCharacter, .incompleteBinaryByte, .invalidUTF8,
        ]
        for error in errors {
            ToolDiagnosticContract.expectFactual(error.errorDescription ?? "")
        }
    }

    @Test func modeBackfillUsesCurrentValidBinaryOrASCIIOutput() throws {
        let binaryBackfill = ConverterModeBackfill.currentValidOutput(
            input: "A",
            currentMode: "bin",
            hasError: false
        ) { input, mode in
            switch mode {
            case "bin":
                return ASCIIBinaryConversion.textToBinary(input)
            case "debin":
                guard let text = try? ASCIIBinaryConversion.validatedBinaryToText(input) else {
                    throw ConversionProbeError()
                }
                return text
            default:
                throw ConversionProbeError()
            }
        }

        let asciiBackfill = ConverterModeBackfill.currentValidOutput(
            input: "A",
            currentMode: "ascii",
            hasError: false
        ) { input, mode in
            switch mode {
            case "ascii":
                guard let ascii = try? ASCIIBinaryConversion.validatedTextToASCII(input) else {
                    throw ConversionProbeError()
                }
                return ascii
            case "deascii":
                guard let text = try? ASCIIBinaryConversion.validatedASCIIToText(input) else {
                    throw ConversionProbeError()
                }
                return text
            default:
                throw ConversionProbeError()
            }
        }

        #expect(binaryBackfill == "01000001")
        #expect(try ASCIIBinaryConversion.validatedBinaryToText(binaryBackfill ?? "") == "A")
        #expect(asciiBackfill == "65")
        #expect(try ASCIIBinaryConversion.validatedASCIIToText(asciiBackfill ?? "") == "A")
    }
}
