import XToolsCore
import Testing

struct BasicAuthCodecTests {
    @Test func parsesCompleteHeaderHeaderValueAndBareToken() throws {
        let complete = try BasicAuthCodec.parse("Authorization: Basic dXNlcjpwYXNz")
        let value = try BasicAuthCodec.parse("basic dXNlcjpwYXNz")
        let bare = try BasicAuthCodec.parse("dXNlcjpwYXNz")

        #expect(complete == .init(username: "user", password: "pass"))
        #expect(value == complete)
        #expect(bare == complete)
    }

    @Test func headerAndSchemeAreASCIICaseInsensitive() throws {
        let credentials = try BasicAuthCodec.parse("aUtHoRiZaTiOn: bAsIc dXNlcjpwYXNz")
        #expect(credentials == .init(username: "user", password: "pass"))
    }

    @Test func splitsOnlyOnFirstColon() throws {
        let credentials = try BasicAuthCodec.parse("Basic dXNlcjpwQHNzOncwcmQh")
        #expect(credentials.username == "user")
        #expect(credentials.password == "p@ss:w0rd!")
    }

    @Test func acceptsEmptyUsernameOrPassword() throws {
        #expect(try BasicAuthCodec.parse("OnBhc3M=") == .init(username: "", password: "pass"))
        #expect(try BasicAuthCodec.parse("dXNlcjo=") == .init(username: "user", password: ""))
        #expect(try BasicAuthCodec.parse("Og==") == .init(username: "", password: ""))
    }

    @Test func rejectsUnsupportedOrMalformedWrappersWithoutBareFallback() {
        #expect(throws: BasicAuthCodec.ParseError.unsupportedScheme("Bearer")) {
            _ = try BasicAuthCodec.parse("Bearer dXNlcjpwYXNz")
        }
        #expect(throws: BasicAuthCodec.ParseError.unsupportedHeader("X-Auth")) {
            _ = try BasicAuthCodec.parse("X-Auth: Basic dXNlcjpwYXNz")
        }
        #expect(throws: BasicAuthCodec.ParseError.invalidHeader) {
            _ = try BasicAuthCodec.parse("Authorization: dXNlcjpwYXNz")
        }
    }

    @Test func rejectsInternalWhitespaceInvalidBase64InvalidUTF8AndMissingSeparator() {
        #expect(throws: BasicAuthCodec.ParseError.invalidBase64) {
            _ = try BasicAuthCodec.parse("Basic dXNl cjpwYXNz")
        }
        #expect(throws: BasicAuthCodec.ParseError.invalidBase64) {
            _ = try BasicAuthCodec.parse("***")
        }
        #expect(throws: BasicAuthCodec.ParseError.invalidUTF8) {
            _ = try BasicAuthCodec.parse("/w==")
        }
        #expect(throws: BasicAuthCodec.ParseError.missingSeparator) {
            _ = try BasicAuthCodec.parse("dXNlcg==")
        }
    }

    @Test func rejectsControlCharactersAfterDecoding() {
        #expect(throws: BasicAuthCodec.ParseError.credentialsContainControlCharacter) {
            _ = try BasicAuthCodec.parse("dXNlcgo6cGFzcw==")
        }
    }

    @Test func explicitEmptyCredentialsCanRoundTrip() throws {
        let header = try #require(BasicAuthCodec.authorizationHeader(
            credentials: .init(username: "", password: "")
        ))
        #expect(header == "Authorization: Basic Og==")
        #expect(try BasicAuthCodec.parse(header) == .init(username: "", password: ""))
    }

    @Test func generationAndParsingRoundTrip() throws {
        let header = try #require(BasicAuthCodec.authorizationHeader(username: "用户名", password: "密:码"))
        let parsed = try BasicAuthCodec.parse(header)

        #expect(parsed == .init(username: "用户名", password: "密:码"))
    }
}
