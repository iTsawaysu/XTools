import XToolsCore
import Foundation
import Testing

struct BasicAuthGeneratorTests {
    @Test func generatesValidHeader() {
        let header = BasicAuthCodec.authorizationHeader(username: "user", password: "pass")
        #expect(header != nil)
        #expect(header == "Authorization: Basic dXNlcjpwYXNz")
    }

    @Test func handlesEmptyUsername() {
        let header = BasicAuthCodec.authorizationHeader(username: "", password: "pass")
        #expect(header != nil)
        #expect(header == "Authorization: Basic OnBhc3M=") // :pass
    }

    @Test func handlesEmptyPassword() {
        let header = BasicAuthCodec.authorizationHeader(username: "user", password: "")
        #expect(header != nil)
        #expect(header == "Authorization: Basic dXNlcjo=") // user:
    }

    @Test func handlesBothEmpty() {
        let header = BasicAuthCodec.authorizationHeader(username: "", password: "")
        #expect(header == nil)
    }

    @Test func encodesSpecialCharacters() {
        let header = BasicAuthCodec.authorizationHeader(username: "user@example.com", password: "p@ss:w0rd!")
        #expect(header != nil)
        // user@example.com:p@ss:w0rd! -> dXNlckBleGFtcGxlLmNvbTpwQHNzOncwcmQh
        #expect(header == "Authorization: Basic dXNlckBleGFtcGxlLmNvbTpwQHNzOncwcmQh")
    }

    @Test func rejectsColonInUsername() {
        let header = BasicAuthCodec.authorizationHeader(username: "user:name", password: "pass")
        #expect(header == nil) // Basic Auth usernames cannot contain the credential separator
        #expect(BasicAuthCodec.validationIssue(username: "user:name", password: "pass") == .usernameContainsColon)
    }

    @Test func rejectsControlCharactersInCredentials() {
        #expect(BasicAuthCodec.authorizationHeader(username: "user\nname", password: "pass") == nil)
        #expect(BasicAuthCodec.authorizationHeader(username: "user", password: "pass\u{7F}") == nil)
        #expect(BasicAuthCodec.validationIssue(username: "user", password: "pass\u{7F}") == .credentialsContainControlCharacter)
    }
}
