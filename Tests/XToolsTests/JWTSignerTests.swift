import XToolsCore
import Foundation
import Testing

struct JWTSignerTests {
    private static let payload = #"{"sub":"1234567890"}"#

    @Test func signsKnownHS256Vector() throws {
        let result = try JWTSigner.sign(config: .init(
            algorithm: .hs256,
            payloadJSON: Self.payload,
            advancedHeaderJSON: "",
            secret: "0123456789abcdef0123456789abcdef",
            secretEncoding: .utf8
        ))

        #expect(result.token == "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.wvm6JJLIvt0yJ90RxqigjYXrn8cSJYBefBOhnTD7aDE")
    }

    @Test func signsKnownHS384Vector() throws {
        let result = try JWTSigner.sign(config: .init(
            algorithm: .hs384,
            payloadJSON: Self.payload,
            advancedHeaderJSON: "",
            secret: "0123456789abcdef0123456789abcdef0123456789abcdef",
            secretEncoding: .utf8
        ))

        #expect(result.token == "eyJhbGciOiJIUzM4NCIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.HQCQMl-zwpK_v0o-5pLX0oyD9aPswJkWoxlyQ0X9VdbTvkY04gy9jbGQ-n5Eb9Ww")
    }

    @Test func signsKnownHS512Vector() throws {
        let result = try JWTSigner.sign(config: .init(
            algorithm: .hs512,
            payloadJSON: Self.payload,
            advancedHeaderJSON: "",
            secret: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            secretEncoding: .utf8
        ))

        #expect(result.token == "eyJhbGciOiJIUzUxMiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.NCrr_JVfmk-h539SK_fQvl0057rL6oMVZAMfkgwFYh5UVSfEcWN_Yx32eKJo_ol3EkIetkcDRBp_WP74qIlpjg")
    }

    @Test func base64SecretUsesDecodedKeyBytes() throws {
        let key = "0123456789abcdef0123456789abcdef"
        let encoded = Data(key.utf8).base64EncodedString()

        let textResult = try JWTSigner.sign(config: .init(
            algorithm: .hs256,
            payloadJSON: Self.payload,
            advancedHeaderJSON: "",
            secret: key,
            secretEncoding: .utf8
        ))
        let base64Result = try JWTSigner.sign(config: .init(
            algorithm: .hs256,
            payloadJSON: Self.payload,
            advancedHeaderJSON: "",
            secret: encoded,
            secretEncoding: .base64
        ))

        #expect(textResult.token == base64Result.token)
    }

    @Test func rejectsInvalidBase64Secret() {
        #expect(throws: JWTSigner.SigningError.invalidBase64Secret) {
            _ = try JWTSigner.sign(config: .init(
                algorithm: .hs256,
                payloadJSON: Self.payload,
                advancedHeaderJSON: "",
                secret: "not base64!",
                secretEncoding: .base64
            ))
        }
    }

    @Test func unpaddedBase64SecretSignsAndRoundTrips() throws {
        // 43 字符无填充的 HS256 密钥（32 字节）是 API 输出的常见形态。
        let padded = Data((0..<32).map { UInt8($0) }).base64EncodedString()
        let unpadded = String(padded.dropLast())
        #expect(padded.count == 44)
        #expect(unpadded.count == 43)

        let paddedToken = try JWTSigner.sign(config: .init(
            algorithm: .hs256,
            payloadJSON: Self.payload,
            advancedHeaderJSON: "",
            secret: padded,
            secretEncoding: .base64
        ))
        let unpaddedToken = try JWTSigner.sign(config: .init(
            algorithm: .hs256,
            payloadJSON: Self.payload,
            advancedHeaderJSON: "",
            secret: unpadded,
            secretEncoding: .base64
        ))

        #expect(paddedToken.token == unpaddedToken.token)

        let verified = try JWTVerifier.verify(
            token: unpaddedToken.token,
            config: .init(secret: unpadded, secretEncoding: .base64)
        )
        #expect(verified.summary == .verified)
    }

    @Test func base64URLSecretMatchesStandardAlphabet() throws {
        // 32 字节密钥，标准字母表编码同时含 `+` 与 `/`。
        var key: [UInt8] = []
        for _ in 0..<10 {
            key.append(contentsOf: [0xFB, 0xFF, 0xEF])
        }
        key.append(contentsOf: [0xFB, 0xFF])
        let standard = Data(key).base64EncodedString()
        let urlForm = standard
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        #expect(standard.contains("+") && standard.contains("/"))

        let standardToken = try JWTSigner.sign(config: .init(
            algorithm: .hs256,
            payloadJSON: Self.payload,
            advancedHeaderJSON: "",
            secret: standard,
            secretEncoding: .base64
        ))
        let urlToken = try JWTSigner.sign(config: .init(
            algorithm: .hs256,
            payloadJSON: Self.payload,
            advancedHeaderJSON: "",
            secret: urlForm,
            secretEncoding: .base64
        ))

        #expect(standardToken.token == urlToken.token)
    }

    @Test func foldedBase64SecretMatchesSingleLine() throws {
        // openssl `base64` 输出按 64 字符折行，整段粘贴必须可用。
        var key: [UInt8] = []
        for index in 0..<64 {
            key.append(UInt8((index * 7 + 3) & 0xFF))
        }
        let encoded = Data(key).base64EncodedString()
        #expect(encoded.count == 88)
        let folded = "\(encoded.prefix(64))\n\(encoded.dropFirst(64))"
        #expect(!folded.isEmpty)

        let singleLine = try JWTSigner.sign(config: .init(
            algorithm: .hs256,
            payloadJSON: Self.payload,
            advancedHeaderJSON: "",
            secret: encoded,
            secretEncoding: .base64
        ))
        let wrapped = try JWTSigner.sign(config: .init(
            algorithm: .hs256,
            payloadJSON: Self.payload,
            advancedHeaderJSON: "",
            secret: folded,
            secretEncoding: .base64
        ))

        #expect(singleLine.token == wrapped.token)
    }

    @Test(arguments: [
        (JWTAlgorithm.hs256, 31, 32),
        (.hs384, 47, 48),
        (.hs512, 63, 64)
    ])
    func rejectsWeakSigningKeys(algorithm: JWTAlgorithm, actual: Int, required: Int) {
        #expect(throws: JWTSigner.SigningError.weakKey(actualBytes: actual, requiredBytes: required)) {
            _ = try JWTSigner.sign(config: .init(
                algorithm: algorithm,
                payloadJSON: Self.payload,
                advancedHeaderJSON: "",
                secret: String(repeating: "a", count: actual),
                secretEncoding: .utf8
            ))
        }
    }

    @Test(arguments: [
        (JWTAlgorithm.hs256, 32),
        (.hs384, 48),
        (.hs512, 64)
    ])
    func acceptsMinimumSigningKeyLength(algorithm: JWTAlgorithm, length: Int) throws {
        let result = try JWTSigner.sign(config: .init(
            algorithm: algorithm,
            payloadJSON: Self.payload,
            advancedHeaderJSON: "",
            secret: String(repeating: "a", count: length),
            secretEncoding: .utf8
        ))

        #expect(result.token.split(separator: ".").count == 3)
    }

    @Test func rejectsNonObjectAndDuplicatePayloadJSON() {
        #expect(throws: JWTSigner.SigningError.payloadMustBeObject) {
            _ = try JWTSigner.sign(config: .init(
                algorithm: .hs256,
                payloadJSON: "[1, 2]",
                advancedHeaderJSON: "",
                secret: String(repeating: "a", count: 32),
                secretEncoding: .utf8
            ))
        }

        #expect(throws: JWTSigner.SigningError.duplicatePayloadKey) {
            _ = try JWTSigner.sign(config: .init(
                algorithm: .hs256,
                payloadJSON: #"{"sub":"a","sub":"b"}"#,
                advancedHeaderJSON: "",
                secret: String(repeating: "a", count: 32),
                secretEncoding: .utf8
            ))
        }
    }

    @Test func controlledAlgorithmRejectsHeaderOverrideAndUnsupportedCriticalParameters() {
        let secret = String(repeating: "a", count: 32)

        #expect(throws: JWTSigner.SigningError.algorithmOverride) {
            _ = try JWTSigner.sign(config: .init(
                algorithm: .hs256,
                payloadJSON: Self.payload,
                advancedHeaderJSON: #"{"alg":"HS512"}"#,
                secret: secret,
                secretEncoding: .utf8
            ))
        }

        #expect(throws: JWTSigner.SigningError.unsupportedHeaderParameter("crit")) {
            _ = try JWTSigner.sign(config: .init(
                algorithm: .hs256,
                payloadJSON: Self.payload,
                advancedHeaderJSON: #"{"crit":["exp"]}"#,
                secret: secret,
                secretEncoding: .utf8
            ))
        }

        #expect(throws: JWTSigner.SigningError.unsupportedHeaderParameter("b64")) {
            _ = try JWTSigner.sign(config: .init(
                algorithm: .hs256,
                payloadJSON: Self.payload,
                advancedHeaderJSON: #"{"b64":false}"#,
                secret: secret,
                secretEncoding: .utf8
            ))
        }


        #expect(throws: JWTSigner.SigningError.invalidHeaderValue("kid")) {
            _ = try JWTSigner.sign(config: .init(
                algorithm: .hs256,
                payloadJSON: Self.payload,
                advancedHeaderJSON: #"{"kid":123}"#,
                secret: secret,
                secretEncoding: .utf8
            ))
        }
    }

    @Test func advancedHeaderCanOverrideTypeButNotAlgorithm() throws {
        let result = try JWTSigner.sign(config: .init(
            algorithm: .hs256,
            payloadJSON: Self.payload,
            advancedHeaderJSON: #"{"kid":"key-1","typ":"at+jwt"}"#,
            secret: String(repeating: "a", count: 32),
            secretEncoding: .utf8
        ))

        #expect(result.header.contains(#""alg" : "HS256""#))
        #expect(result.header.contains(#""kid" : "key-1""#))
        #expect(result.header.contains(#""typ" : "at+jwt""#))
    }

    @Test func generationDraftPreservesSupportedHeaderData() throws {
        let draft = try JWTSigner.generationDraft(
            headerJSON: #"{"alg":"HS384","kid":"key-1","typ":"JWT"}"#,
            payloadJSON: #"{"sub":"x"}"#
        )

        #expect(draft.algorithm == .hs384)
        #expect(draft.payloadJSON.contains("sub"))
        #expect(draft.advancedHeaderJSON.contains("kid"))
        #expect(!draft.advancedHeaderJSON.contains("alg"))
        #expect(!draft.advancedHeaderJSON.contains("typ"))

        #expect(throws: JWTSigner.SigningError.unsupportedAlgorithm("RS256")) {
            _ = try JWTSigner.generationDraft(
                headerJSON: #"{"alg":"RS256","typ":"JWT"}"#,
                payloadJSON: #"{"sub":"x"}"#
            )
        }
    }

    @Test func validatesNumericDateClaimsWithoutAddingThem() throws {
        let secret = String(repeating: "a", count: 32)
        let result = try JWTSigner.sign(config: .init(
            algorithm: .hs256,
            payloadJSON: #"{"sub":"x"}"#,
            advancedHeaderJSON: "",
            secret: secret,
            secretEncoding: .utf8
        ))
        let parsed = try JWTParser.parse(result.token)

        #expect(!parsed.payload.contains("iat"))
        #expect(!parsed.payload.contains("exp"))
        #expect(!parsed.payload.contains("nbf"))

        #expect(throws: JWTSigner.SigningError.invalidNumericDate("exp")) {
            _ = try JWTSigner.sign(config: .init(
                algorithm: .hs256,
                payloadJSON: #"{"exp":"tomorrow"}"#,
                advancedHeaderJSON: "",
                secret: secret,
                secretEncoding: .utf8
            ))
        }
    }

    @Test func acceptsZeroAndOneForEveryNumericDateClaim() throws {
        let secret = String(repeating: "a", count: 32)

        for name in ["exp", "nbf", "iat"] {
            for numeric in [0, 1] {
                let result = try JWTSigner.sign(config: .init(
                    algorithm: .hs256,
                    payloadJSON: "{\"\(name)\":\(numeric)}",
                    advancedHeaderJSON: "",
                    secret: secret,
                    secretEncoding: .utf8
                ))
                let parsed = try JWTParser.parse(result.token)
                let payload = try #require(JSONSerialization.jsonObject(with: Data(parsed.payload.utf8)) as? [String: Any])
                let value = try #require(payload[name] as? NSNumber)
                #expect(value.intValue == numeric)
            }
        }
    }

    @Test func rejectsBooleanValuesForEveryNumericDateClaim() {
        let secret = String(repeating: "a", count: 32)

        for name in ["exp", "nbf", "iat"] {
            for literal in ["true", "false"] {
                #expect(throws: JWTSigner.SigningError.invalidNumericDate(name)) {
                    _ = try JWTSigner.sign(config: .init(
                        algorithm: .hs256,
                        payloadJSON: "{\"\(name)\":\(literal)}",
                        advancedHeaderJSON: "",
                        secret: secret,
                        secretEncoding: .utf8
                    ))
                }
            }
        }
    }
}
