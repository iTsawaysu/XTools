import XToolsCore
import Foundation
import Testing

struct JWTParserTests {
    @Test func parsesValidToken() throws {
        // Valid JWT: {"alg":"HS256","typ":"JWT"}.{"sub":"1234567890","name":"John Doe","iat":1516239022}.signature
        // Header: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9
        // Payload: eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

        let decoded = try JWTParser.parse(token)

        // Header should contain "alg" and "typ"
        #expect(decoded.header.contains("alg"))
        #expect(decoded.header.contains("HS256"))
        #expect(decoded.header.contains("typ"))

        // Payload should contain claims
        #expect(decoded.payload.contains("sub"))
        #expect(decoded.payload.contains("1234567890"))
        #expect(decoded.payload.contains("name"))
        #expect(decoded.payload.contains("John Doe"))
    }

    @Test func rejectsInvalidSegmentCount() throws {
        #expect(throws: (any Error).self) {
            _ = try JWTParser.parse("header.payload")
        }

        #expect(throws: (any Error).self) {
            _ = try JWTParser.parse("a.b.c.d")
        }
    }

    @Test func rejectsEmptyHeader() throws {
        #expect(throws: JWTParser.ParseError.emptyHeader) {
            _ = try JWTParser.parse(".payload.signature")
        }
    }

    @Test func rejectsEmptyPayload() throws {
        #expect(throws: JWTParser.ParseError.emptyPayload) {
            _ = try JWTParser.parse("header..signature")
        }
    }

    @Test func rejectsInvalidBase64() throws {
        // Invalid Base64URL will fail decode, but might throw invalidJSON instead
        #expect(throws: (any Error).self) {
            _ = try JWTParser.parse("not-base64.not-base64.signature")
        }
    }

    @Test func rejectsInvalidJSON() throws {
        // Valid unpadded Base64URL but invalid JSON.
        let invalidJSON = "aGVsbG8" // "hello"
        #expect(throws: JWTParser.ParseError.invalidJSON) {
            _ = try JWTParser.parse("\(invalidJSON).\(invalidJSON).signature")
        }
    }

    @Test func rejectsNonBase64URLJWTSegments() throws {
        let object = Self.base64URL(#"{"sub":"1234"}"#)

        #expect(throws: JWTParser.ParseError.invalidBase64) {
            _ = try JWTParser.parse("\(object)=.\(object).signature")
        }

        #expect(throws: JWTParser.ParseError.invalidBase64) {
            _ = try JWTParser.parse("\(object)+.\(object).signature")
        }

        #expect(throws: JWTParser.ParseError.invalidBase64) {
            _ = try JWTParser.parse("\(object).\(object.prefix(4)) \n\(object.dropFirst(4)).signature")
        }
    }

    @Test func rejectsJSONArraysBecauseJWTSegmentsMustBeObjects() throws {
        let array = Self.base64URL("[1,2]")
        let object = Self.base64URL(#"{"sub":"1234"}"#)

        #expect(throws: JWTParser.ParseError.invalidJSON) {
            _ = try JWTParser.parse("\(array).\(object).signature")
        }

        #expect(throws: JWTParser.ParseError.invalidJSON) {
            _ = try JWTParser.parse("\(object).\(array).signature")
        }
    }

    @Test func decodesBase64URLPadding() throws {
        // Test Base64URL encoding (- instead of +, _ instead of /, no padding)
        // {"test":"value"} -> eyJ0ZXN0IjoidmFsdWUifQ (no padding)
        let token = "eyJ0ZXN0IjoidmFsdWUifQ.eyJ0ZXN0IjoidmFsdWUifQ.sig"
        let decoded = try JWTParser.parse(token)

        #expect(decoded.header.contains("test"))
        #expect(decoded.header.contains("value"))
        #expect(decoded.payload.contains("test"))
    }

    private static func base64URL(_ string: String) -> String {
        Data(string.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
