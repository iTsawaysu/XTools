import XToolsCore
import Testing

struct DigestEncodingTests {
    // A small fixed digest exercising leading-zero bytes and high bytes.
    private let digest: [UInt8] = [0x00, 0x0F, 0xFF, 0xAB]

    // MARK: - Hex

    @Test func hexIsLowercaseTwoDigitsPerByte() {
        #expect(DigestEncoding.format(digest, mode: "hex") == "000fffab")
    }

    @Test func unknownModeFallsBackToHex() {
        // Any unrecognized mode string behaves like the view's `default: hex`.
        #expect(DigestEncoding.format(digest, mode: "something-else") == "000fffab")
        #expect(DigestEncoding.format(digest, mode: "") == "000fffab")
    }

    // MARK: - Binary

    @Test func binaryIsEightBitsPerByteSpaceSeparated() {
        #expect(DigestEncoding.format(digest, mode: "binary") == "00000000 00001111 11111111 10101011")
    }

    @Test func binaryPadsSingleByteToEightBits() {
        #expect(DigestEncoding.format([0x01], mode: "binary") == "00000001")
    }

    // MARK: - Base64

    @Test func base64MatchesFoundationEncoding() {
        // Data([0,15,255,171]).base64EncodedString() == "AA//qw=="
        #expect(DigestEncoding.format(digest, mode: "base64") == "AA//qw==")
    }

    @Test func base64urlStripsPaddingAndSwapsAlphabet() {
        // Standard base64 "AA//qw==" -> url-safe drops padding, +/ become -_.
        #expect(DigestEncoding.format(digest, mode: "base64url") == "AA__qw")
    }

    @Test func base64urlReplacesPlusWithDash() {
        // 0xFB,0xFF,0xBF -> standard base64 "+/+/" which must become "-_-_".
        let plusHeavy: [UInt8] = [0xFB, 0xFF, 0xBF]
        #expect(DigestEncoding.format(plusHeavy, mode: "base64") == "+/+/")
        #expect(DigestEncoding.format(plusHeavy, mode: "base64url") == "-_-_")
    }

    // MARK: - Empty digest

    @Test func emptyDigestEncodesToEmptyStrings() {
        #expect(DigestEncoding.format([], mode: "hex") == "")
        #expect(DigestEncoding.format([], mode: "binary") == "")
        #expect(DigestEncoding.format([], mode: "base64") == "")
        #expect(DigestEncoding.format([], mode: "base64url") == "")
    }
}
