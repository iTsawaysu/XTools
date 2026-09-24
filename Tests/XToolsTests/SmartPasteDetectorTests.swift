import Foundation
import Testing
import XToolsCore

struct SmartPasteDetectorTests {
    // MARK: - JSON

    @Test func detectsJSONObjectsAndArrays() {
        #expect(SmartPasteDetector.detect(#"{"name":"x","n":1}"#) == .json)
        #expect(SmartPasteDetector.detect("[1, 2, 3]") == .json)
        #expect(SmartPasteDetector.detect("  {\n  \"a\": true\n}  ") == .json)
    }

    @Test func rejectsBrokenJSON() {
        #expect(SmartPasteDetector.detect(#"{"name": }"#) == nil)
        #expect(SmartPasteDetector.detect("{\"a\": 1") == nil)
    }

    // MARK: - JWT

    @Test func detectsJWT() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
            + ".eyJzdWIiOiIxMjM0NTY3ODkwIn0"
            + ".SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        #expect(SmartPasteDetector.detect(token) == .jwt)
    }

    @Test func rejectsNonJWTWithTwoDots() {
        #expect(SmartPasteDetector.detect("a.b.c") == nil)
        #expect(SmartPasteDetector.detect("1.2.3.4") == nil)
    }

    // MARK: - HTML / XML

    @Test func detectsHTMLDocument() {
        #expect(SmartPasteDetector.detect("<html><body><p>hi</p></body></html>") == .html)
        #expect(SmartPasteDetector.detect("<!DOCTYPE html><p>x</p>") == .html)
        #expect(SmartPasteDetector.detect("<div class=\"a\">x</div>") == .html)
    }

    @Test func detectsXMLWithoutHTMLMarkers() {
        #expect(SmartPasteDetector.detect("<note><to>a</to></note>") == .xml)
        #expect(SmartPasteDetector.detect("<?xml version=\"1.0\"?><root/>") == .xml)
    }

    @Test func rejectsMalformedXMLLookingText() {
        #expect(SmartPasteDetector.detect("<not-xml") == nil)
        #expect(SmartPasteDetector.detect("<note><to>a</note>") == nil)
    }

    // MARK: - CSS color

    @Test func detectsCSSColors() {
        #expect(SmartPasteDetector.detect("#ff8800") == .cssColor)
        #expect(SmartPasteDetector.detect("#FFF") == .cssColor)
        #expect(SmartPasteDetector.detect("#ff8800cc") == .cssColor)
        #expect(SmartPasteDetector.detect("rgb(255, 136, 0)") == .cssColor)
        #expect(SmartPasteDetector.detect("rgba(255,136,0,0.5)") == .cssColor)
        #expect(SmartPasteDetector.detect("hsl(30, 100%, 50%)") == .cssColor)
    }

    @Test func rejectsNonColorHashesAndNames() {
        #expect(SmartPasteDetector.detect("#ff88") == .cssColor)  // valid 4-digit RGBA
        #expect(SmartPasteDetector.detect("#12345") == nil)       // 5 digits is not a CSS color
        #expect(SmartPasteDetector.detect("red") == nil)
        #expect(SmartPasteDetector.detect("#gggggg") == nil)
    }

    // MARK: - Unix timestamp

    @Test func detectsPlausibleTimestamps() {
        #expect(SmartPasteDetector.detect("1700000000") == .unixTimestamp)      // seconds
        #expect(SmartPasteDetector.detect("1700000000000") == .unixTimestamp)   // milliseconds
    }

    @Test func rejectsOutOfRangeOrAmbiguousNumbers() {
        #expect(SmartPasteDetector.detect("0") == nil)
        #expect(SmartPasteDetector.detect("12345") == nil)
        #expect(SmartPasteDetector.detect("17000000000") == nil)                // 11 digits
        #expect(SmartPasteDetector.detect("999999999999999") == nil)
        #expect(SmartPasteDetector.detect("3.14") == nil)
    }

    // MARK: - URL encoding

    @Test func detectsPercentEncodedStrings() {
        #expect(SmartPasteDetector.detect("hello%20world%21") == .urlEncoded)
        #expect(SmartPasteDetector.detect("%E4%B8%AD%E6%96%87") == .urlEncoded)
    }

    @Test func rejectsSingleEscapeAndMalformedEscapes() {
        #expect(SmartPasteDetector.detect("50%25 off") == nil)      // only one escape
        #expect(SmartPasteDetector.detect("100% sure %zz") == nil)  // no valid pairs
    }

    // MARK: - Data URL and base64

    @Test func detectsDataURLBeforeBase64() {
        #expect(SmartPasteDetector.detect("data:image/png;base64,iVBORw0KGgo=") == .dataURL)
    }

    @Test func rejectsMalformedDataURLPayloads() {
        #expect(SmartPasteDetector.detect("data:image/png;base64,not-base64") == nil)
        #expect(SmartPasteDetector.detect("data:image/png;base64,") == nil)
        #expect(SmartPasteDetector.detect("data:image/png,plain-text") == nil)
    }

    @Test func detectsBase64RoundTrip() {
        let payload = Base64Conversion.encode("Hello, XTools!")
        #expect(SmartPasteDetector.detect(payload) == .base64)
    }

    @Test func rejectsPlainWordsAndShortTokens() {
        #expect(SmartPasteDetector.detect("abcdefghijklmnop") == nil)   // 16 chars, decodes to garbage
        #expect(SmartPasteDetector.detect("hello world") == nil)
        #expect(SmartPasteDetector.detect("abc") == nil)
        #expect(SmartPasteDetector.detect("The quick brown fox jumps over") == nil)
    }

    // MARK: - Bounds and precedence

    @Test func ignoresOversizedInput() {
        let huge = String(repeating: "a", count: SmartPasteDetector.maxInspectedLength + 1)
        #expect(SmartPasteDetector.detect(huge) == nil)

        let hugeJSON = "[" + String(repeating: "1,", count: SmartPasteDetector.maxInspectedLength / 2) + "1]"
        #expect(SmartPasteDetector.detect(hugeJSON) == nil)
    }

    @Test func boundedCharacterLimitPreservesGraphemeSemantics() {
        let grapheme = "👨‍👩‍👧‍👦"
        let maximum = SmartPasteDetector.maxInspectedLength

        #expect(SmartPasteDetector.isWithinCharacterLimit(
            String(repeating: grapheme, count: maximum),
            limit: maximum
        ))
        #expect(!SmartPasteDetector.isWithinCharacterLimit(
            String(repeating: grapheme, count: maximum + 1),
            limit: maximum
        ))
        #expect(!SmartPasteDetector.isWithinCharacterLimit("a", limit: 0))
        #expect(SmartPasteDetector.isWithinCharacterLimit("", limit: 0))
    }

    @Test func ignoresEmptyAndWhitespace() {
        #expect(SmartPasteDetector.detect("") == nil)
        #expect(SmartPasteDetector.detect("   \n\t ") == nil)
    }

    @Test func jwtWinsOverBase64BecauseItIsMoreSpecific() {
        let token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abcdefghijklmnopqrstuvwxyz12"
        #expect(SmartPasteDetector.detect(token) == .jwt)
    }
}
