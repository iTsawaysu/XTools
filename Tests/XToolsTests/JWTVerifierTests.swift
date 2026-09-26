import XToolsCore
import Foundation
import Testing

/// Behavior tests for `JWTVerifier`. The test target can only import
/// `XToolsCore` (not CryptoSwift), so HMAC signature cases use fixed
/// vectors produced out-of-band with a known secret, while claims cases build
/// tokens on the fly and skip signature checking by passing a nil secret.
struct JWTVerifierTests {
    /// Shared secret used to produce the signed fixtures below.
    private static let secret = "my$ecret-key"

    /// Real tokens signed with `secret`, payload `{"sub":"1234567890","name":"John Doe"}`.
    private static let hs256 = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.5Qf4NyBaMBSHc_OqsArJez4vuJQUmDW42X4Zf1L78T0"
    private static let hs384 = "eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.-j6DTWEQfuLU5HqBwXj1YNTHfdD55j5kmiSda26yt89H25hffj4_pCAvv-0O0USZ"
    private static let hs512 = "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.AX_0AcJ2Txumkc9RVyDr6DYc9s86tp0I1ZU0JFBNi8O-PIYvrHeyf63TqxFWaJB4G7vpzEK2MxPKPGuZI_LGpA"

    // MARK: - Signature verification

    @Test func validHS256SignaturePasses() throws {
        let result = try JWTVerifier.verify(
            token: Self.hs256,
            config: .init(secret: Self.secret)
        )

        let signature = try #require(result.details.first { $0.category == .signature })
        #expect(signature.passed)
        #expect(result.signatureStatus == .verified)
        #expect(result.summary == .verified)
        #expect(result.isValid)
    }

    @Test func trimsTokenBeforeVerifyingSignature() throws {
        let result = try JWTVerifier.verify(
            token: " \n\(Self.hs256)\n ",
            config: .init(secret: Self.secret)
        )

        let signature = try #require(result.details.first { $0.category == .signature })
        #expect(signature.passed)
        #expect(result.isValid)
    }

    @Test func validHS384SignaturePasses() throws {
        let result = try JWTVerifier.verify(
            token: Self.hs384,
            config: .init(secret: Self.secret)
        )

        let signature = try #require(result.details.first { $0.category == .signature })
        #expect(signature.passed)
    }

    @Test func validHS512SignaturePasses() throws {
        let result = try JWTVerifier.verify(
            token: Self.hs512,
            config: .init(secret: Self.secret)
        )

        let signature = try #require(result.details.first { $0.category == .signature })
        #expect(signature.passed)
    }

    @Test func wrongSecretFailsSignature() throws {
        let result = try JWTVerifier.verify(
            token: Self.hs256,
            config: .init(secret: "not-the-secret")
        )

        let signature = try #require(result.details.first { $0.category == .signature })
        #expect(!signature.passed)
        #expect(result.signatureStatus == .failed)
        #expect(result.summary == .failed)
        #expect(!result.isValid)
    }

    @Test func tamperedPayloadFailsSignature() throws {
        // Swap the payload for a differently-signed token's payload; the original
        // signature no longer matches the recomputed HMAC.
        let parts = Self.hs256.split(separator: ".").map(String.init)
        let tampered = "\(parts[0]).\(Self.encodeJSON(#"{"sub":"evil"}"#)).\(parts[2])"

        let result = try JWTVerifier.verify(
            token: tampered,
            config: .init(secret: Self.secret)
        )

        let signature = try #require(result.details.first { $0.category == .signature })
        #expect(!signature.passed)
        #expect(!result.isValid)
    }

    @Test func malformedSignatureSegmentFailsSignatureWithoutThrowing() throws {
        let parts = Self.hs256.split(separator: ".").map(String.init)
        let malformed = "\(parts[0]).\(parts[1]).not-a-valid-@@@"

        let result = try JWTVerifier.verify(
            token: malformed,
            config: .init(secret: Self.secret)
        )

        let signature = try #require(result.details.first { $0.category == .signature })
        #expect(!signature.passed)
        #expect(!result.isValid)
    }

    @Test func noSecretSkipsSignatureVerification() throws {
        let result = try JWTVerifier.verify(
            token: Self.hs256,
            config: .init(secret: nil)
        )

        let signature = try #require(result.details.first { $0.category == .signature })
        #expect(signature.status == .warning)
        #expect(signature.message.contains("未验证"))
        #expect(result.signatureStatus == .notVerified)
        #expect(result.summary == .notVerified)
        #expect(!result.isValid)
    }

    @Test func emptySecretSkipsSignatureVerification() throws {
        let result = try JWTVerifier.verify(
            token: Self.hs256,
            config: .init(secret: "")
        )

        let signature = try #require(result.details.first { $0.category == .signature })
        #expect(signature.status == .warning)
        #expect(signature.message.contains("未验证"))
        #expect(result.signatureStatus == .notVerified)
        #expect(!result.isValid)
    }

    @Test func unsupportedAlgorithmFailsSignatureButDoesNotThrow() throws {
        // A well-formed token whose header advertises RS256 (unsupported).
        let token = Self.makeToken(header: #"{"alg":"RS256","typ":"JWT"}"#, payload: #"{"sub":"x"}"#)

        let result = try JWTVerifier.verify(
            token: token,
            config: .init(secret: Self.secret)
        )

        let signature = try #require(result.details.first { $0.category == .signature })
        #expect(!signature.passed)
        #expect(signature.message == "JWT 使用了当前不支持的签名算法。")
        #expect(!result.isValid)
    }

    @Test func weakVerificationKeyWarnsWithoutChangingSignatureMatch() throws {
        let result = try JWTVerifier.verify(
            token: Self.hs256,
            config: .init(secret: Self.secret)
        )

        let strength = try #require(result.details.first { $0.category == .security })
        #expect(strength.status == .warning)
        ToolDiagnosticContract.expectFactual(strength.message, sensitiveInputs: [Self.secret])
        #expect(result.signatureStatus == .verified)
        #expect(result.summary == .verified)
        #expect(result.hasSecurityWarning)
    }

    @Test func base64SecretIsDecodedBeforeVerification() throws {
        let encodedSecret = Data(Self.secret.utf8).base64EncodedString()
        let result = try JWTVerifier.verify(
            token: Self.hs256,
            config: .init(secret: encodedSecret, secretEncoding: .base64)
        )

        #expect(result.signatureStatus == .verified)
    }

    @Test func invalidBase64SecretFailsVerification() throws {
        let result = try JWTVerifier.verify(
            token: Self.hs256,
            config: .init(secret: "not base64!", secretEncoding: .base64)
        )

        #expect(result.signatureStatus == .failed)
        #expect(result.summary == .failed)
        #expect(result.details.first { $0.category == .signature }?.message.contains("Base64") == true)
    }

    // MARK: - Claims verification

    @Test func expiredTokenIsInvalid() throws {
        let past = Date().timeIntervalSince1970 - 3600
        let token = Self.makeToken(
            header: #"{"alg":"HS256","typ":"JWT"}"#,
            payload: #"{"exp":\#(Int(past))}"#
        )

        let result = try JWTVerifier.verify(token: token, config: .init(secret: nil))

        let exp = try #require(result.details.first { $0.name.contains("exp") })
        #expect(!exp.passed)
        #expect(exp.message.contains("已过期"))
        #expect(!result.isValid)
    }

    @Test func unexpiredTokenPassesExpiration() throws {
        let future = Date().timeIntervalSince1970 + 3600
        let token = Self.makeToken(
            header: #"{"alg":"HS256","typ":"JWT"}"#,
            payload: #"{"exp":\#(Int(future))}"#
        )

        let result = try JWTVerifier.verify(token: token, config: .init(secret: nil))

        let exp = try #require(result.details.first { $0.name.contains("exp") })
        #expect(exp.passed)
        #expect(exp.message.contains("未过期"))
        #expect(result.summary == .notVerified)
        #expect(!result.isValid)
    }

    @Test func notYetValidTokenFailsNotBefore() throws {
        let future = Date().timeIntervalSince1970 + 3600
        let token = Self.makeToken(
            header: #"{"alg":"HS256","typ":"JWT"}"#,
            payload: #"{"nbf":\#(Int(future))}"#
        )

        let result = try JWTVerifier.verify(token: token, config: .init(secret: nil))

        let nbf = try #require(result.details.first { $0.name.contains("nbf") })
        #expect(!nbf.passed)
        #expect(!result.isValid)
    }

    @Test func activeNotBeforePasses() throws {
        let past = Date().timeIntervalSince1970 - 3600
        let token = Self.makeToken(
            header: #"{"alg":"HS256","typ":"JWT"}"#,
            payload: #"{"nbf":\#(Int(past))}"#
        )

        let result = try JWTVerifier.verify(token: token, config: .init(secret: nil))

        let nbf = try #require(result.details.first { $0.name.contains("nbf") })
        #expect(nbf.passed)
    }

    @Test func issuedAtIsInformationalAndDoesNotAffectValidity() throws {
        let token = Self.makeToken(
            header: #"{"alg":"HS256","typ":"JWT"}"#,
            payload: #"{"iat":1516239022}"#
        )

        let result = try JWTVerifier.verify(token: token, config: .init(secret: nil))

        let iat = try #require(result.details.first { $0.name.contains("iat") })
        #expect(iat.passed)
        #expect(iat.category == .claims)
        #expect(iat.status == .informational)
        #expect(result.summary == .notVerified)
        #expect(!result.isValid)
    }

    @Test func invalidNumericDateClaimsFailPredictably() throws {
        let token = Self.makeToken(
            header: #"{"alg":"HS256","typ":"JWT"}"#,
            payload: #"{"exp":"tomorrow"}"#
        )

        let result = try JWTVerifier.verify(token: token, config: .init(secret: nil))

        let exp = try #require(result.details.first { $0.name.contains("exp") })
        #expect(!exp.passed)
        #expect(exp.message.contains("NumericDate"))
        #expect(!result.isValid)
    }

    @Test func invalidIssuedAtTypeFailsClaimsValidation() throws {
        let token = Self.makeToken(
            header: #"{"alg":"HS256","typ":"JWT"}"#,
            payload: #"{"iat":false}"#
        )

        let result = try JWTVerifier.verify(token: token, config: .init(secret: nil))

        let iat = try #require(result.details.first { $0.name.contains("iat") })
        #expect(!iat.passed)
        #expect(iat.category == .claims)
        #expect(!result.isValid)
    }

    @Test func zeroAndOneAreNumericDatesForEveryClaim() throws {
        for numeric in [0, 1] {
            let token = Self.makeToken(
                header: #"{"alg":"HS256","typ":"JWT"}"#,
                payload: "{\"exp\":\(numeric),\"nbf\":\(numeric),\"iat\":\(numeric)}"
            )
            let result = try JWTVerifier.verify(token: token, config: .init(secret: nil))
            let exp = try #require(result.details.first { $0.name.contains("exp") })
            let nbf = try #require(result.details.first { $0.name.contains("nbf") })
            let iat = try #require(result.details.first { $0.name.contains("iat") })

            #expect(exp.status == .failed)
            #expect(exp.message.contains("已过期"))
            #expect(nbf.status == .passed)
            #expect(nbf.message == "已生效")
            #expect(iat.status == .informational)
            #expect(!iat.message.contains("NumericDate"))
        }
    }

    @Test func booleansAreNotNumericDatesForEveryClaim() throws {
        for name in ["exp", "nbf", "iat"] {
            for literal in ["true", "false"] {
                let token = Self.makeToken(
                    header: #"{"alg":"HS256","typ":"JWT"}"#,
                    payload: "{\"\(name)\":\(literal)}"
                )
                let result = try JWTVerifier.verify(token: token, config: .init(secret: nil))
                let item = try #require(result.details.first { $0.name.contains(name) })
                #expect(item.status == .failed)
                #expect(item.message.contains("NumericDate"))
                #expect(result.summary == .failed)
            }
        }
    }

    // MARK: - Structural errors

    @Test func wrongSegmentCountThrowsParseError() throws {
        #expect(throws: JWTVerifier.VerificationError.parseError) {
            _ = try JWTVerifier.verify(token: "only.two", config: .init(secret: nil))
        }
    }

    @Test func missingAlgorithmThrows() throws {
        let token = Self.makeToken(header: #"{"typ":"JWT"}"#, payload: #"{"sub":"x"}"#)

        #expect(throws: JWTVerifier.VerificationError.missingAlgorithm) {
            _ = try JWTVerifier.verify(token: token, config: .init(secret: nil))
        }
    }

    @Test func nonJSONPayloadThrowsParseError() throws {
        let token = "\(Self.encodeJSON(#"{"alg":"HS256"}"#)).\(Self.base64URL("not json")).sig"

        #expect(throws: JWTVerifier.VerificationError.parseError) {
            _ = try JWTVerifier.verify(token: token, config: .init(secret: nil))
        }
    }

    @Test func paddedOrStandardBase64SegmentsThrowParseError() throws {
        let header = Self.encodeJSON(#"{"alg":"HS256"}"#)
        let payload = Self.encodeJSON(#"{"sub":"x"}"#)

        #expect(throws: JWTVerifier.VerificationError.parseError) {
            _ = try JWTVerifier.verify(token: "\(header)=.\(payload).sig", config: .init(secret: nil))
        }

        #expect(throws: JWTVerifier.VerificationError.parseError) {
            _ = try JWTVerifier.verify(token: "\(header).\(payload)+.sig", config: .init(secret: nil))
        }
    }

    // MARK: - Helpers

    /// Assemble a 3-part token from raw header/payload JSON with a dummy signature.
    private static func makeToken(header: String, payload: String) -> String {
        "\(encodeJSON(header)).\(encodeJSON(payload)).signature"
    }

    private static func encodeJSON(_ json: String) -> String {
        base64URL(json)
    }

    /// Base64URL-encode a UTF-8 string (no padding), matching JWT segment encoding.
    private static func base64URL(_ string: String) -> String {
        Data(string.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
