import XToolsCore
import Foundation
import Testing

struct JWTWorkspaceSessionTests {
    private static let strongSecret = "0123456789abcdef0123456789abcdef"
    private static let knownToken =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.wvm6JJLIvt0yJ90RxqigjYXrn8cSJYBefBOhnTD7aDE"
    private static let knownPayload = #"{"sub":"1234567890"}"#
    private static let weakSecret = "my$ecret-key"
    private static let weakHS256 =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.5Qf4NyBaMBSHc_OqsArJez4vuJQUmDW42X4Zf1L78T0"

    @Test func defaultsMatchPageBaseline() {
        let session = JWTWorkspaceSession()
        #expect(session.mode == .parse)
        #expect(session.generateAlgorithm == .hs256)
        #expect(session.generateSecretEncoding == .utf8)
        #expect(session.generatePayload == JWTWorkspaceSession.defaultGeneratePayload)
        #expect(session.generatePayload.contains("John Doe"))
        #expect(session.parseInput.isEmpty)
        #expect(session.registeredClaimInsights.isEmpty)
        #expect(session.hasGenerateContent)
        #expect(!session.hasParseContent)
        #expect(session.hasAnyContent)
    }

    @Test func emptyParseInputClearsOutputsWithoutError() {
        var session = JWTWorkspaceSession()
        session.parseInput = "   "
        session.parsedHeader = "stale"
        session.parsedPayload = "stale"
        session.parseError = "stale"
        session.parse()
        #expect(session.parsedHeader.isEmpty)
        #expect(session.parsedPayload.isEmpty)
        #expect(session.verificationResult == nil)
        #expect(session.registeredClaimInsights.isEmpty)
        #expect(session.parseError == nil)
    }

    @Test func invalidSegmentCountMapsChineseDiagnostic() {
        var session = JWTWorkspaceSession()
        session.parseInput = "only.two"
        session.parse()
        #expect(session.parseError == "JWT 必须包含 header.payload.signature 三段。")
        #expect(session.parsedHeader.isEmpty)
        #expect(session.parsedPayload.isEmpty)
        #expect(session.verificationResult == nil)
        #expect(session.registeredClaimInsights.isEmpty)
    }

    @Test func tooManySegmentsReportActualCountThroughSession() {
        var session = JWTWorkspaceSession()
        session.parseInput = "a.b.c.d"
        session.parse()
        #expect(session.parseError == "JWT 只能包含 header.payload.signature 三段（当前有 4 段）。")
        #expect(session.parsedHeader.isEmpty)
    }

    @Test func emptyPayloadSegmentReportsEmptyPayloadNotSegmentCount() {
        var session = JWTWorkspaceSession()
        session.parseInput = "eyJhbGciOiJIUzI1NiJ9..sig"
        session.parse()
        #expect(session.parseError == "JWT Payload 不能为空。")
    }

    @Test func successfulParseBuildsRegisteredClaimProjection() throws {
        var session = JWTWorkspaceSession()
        session.parseInput = Self.knownToken

        session.parse()

        let subject = try #require(session.registeredClaimInsights.first { $0.kind == .subject })
        #expect(subject.displayValue == "1234567890")
        #expect(subject.status == .informational)
    }

    @Test func failedParseClearsPreviousRegisteredClaims() {
        var session = JWTWorkspaceSession()
        session.parseInput = Self.knownToken
        session.parse()
        #expect(!session.registeredClaimInsights.isEmpty)

        session.parseInput = "only.two"
        session.parse()

        #expect(session.registeredClaimInsights.isEmpty)
    }

    @Test func invalidPayloadJSONBucketsToPayloadError() {
        var session = JWTWorkspaceSession()
        session.generatePayload = "{not json"
        session.generateSecret = Self.strongSecret
        session.refreshGeneration()
        #expect(session.generationPayloadError == "Payload 不是有效的 JSON。")
        #expect(session.generatedToken.isEmpty)
        #expect(session.generationSecretError == nil)
    }

    @Test func weakKeyBucketsToSecretErrorWithAlgorithmName() {
        var session = JWTWorkspaceSession()
        session.generatePayload = Self.knownPayload
        session.generateSecret = "short"
        session.refreshGeneration()
        #expect(session.generationSecretError == "当前密钥为 5 字节，HS256 至少需要 32 字节。")
        #expect(session.generatedToken.isEmpty)
        #expect(session.generationPayloadError == nil)
    }

    @Test func invalidBase64SecretBucketsToSecretError() {
        var session = JWTWorkspaceSession()
        session.generatePayload = Self.knownPayload
        session.generateSecretEncoding = .base64
        session.generateSecret = "not base64!"
        session.refreshGeneration()
        #expect(session.generationSecretError == "Secret 不是有效的 Base64。")
        #expect(session.generatedToken.isEmpty)
    }

    @Test func successfulGenerationProducesTokenAndHeader() {
        var session = JWTWorkspaceSession()
        session.generatePayload = Self.knownPayload
        session.generateSecret = Self.strongSecret
        session.refreshGeneration()
        #expect(session.generatedToken == Self.knownToken)
        #expect(!session.generatedHeader.isEmpty)
        #expect(session.generationHeaderError == nil)
        #expect(session.generationPayloadError == nil)
        #expect(session.generationSecretError == nil)
    }

    @Test func localCheckPresentationSeparatesUncheckedSignatureNoTimeAndScope() throws {
        var session = JWTWorkspaceSession()
        session.parseInput = Self.knownToken
        session.parse()

        let presentation = try #require(session.localCheckPresentation)
        #expect(presentation.signature.title == "签名未检查")
        #expect(presentation.signature.status == .informational)
        #expect(presentation.timeClaims.title == "没有时间声明")
        #expect(presentation.timeClaims.status == .informational)
        #expect(presentation.scopeStatement.contains("issuer"))
        #expect(presentation.scopeStatement.contains("audience"))
        #expect(!presentation.summaryText.contains("验证通过"))
        #expect(!presentation.summaryText.contains("Token 有效"))
    }

    @Test func localCheckPresentationShowsMatchedSignatureWithoutApplicationValidity() throws {
        var session = JWTWorkspaceSession()
        session.parseInput = Self.knownToken
        session.parseSecret = Self.strongSecret
        session.parse()

        let presentation = try #require(session.localCheckPresentation)
        #expect(presentation.signature.title == "签名匹配")
        #expect(presentation.signature.status == .passed)
        #expect(presentation.signature.message == "匹配 (HS256)")
        #expect(presentation.timeClaims.title == "没有时间声明")
        #expect(!presentation.summaryText.contains("验证通过"))
    }

    @Test func localCheckPresentationKeepsWeakKeyWarningSeparateFromSignatureMatch() throws {
        var session = JWTWorkspaceSession()
        session.parseInput = Self.weakHS256
        session.parseSecret = Self.weakSecret
        session.parse()

        let presentation = try #require(session.localCheckPresentation)
        #expect(presentation.signature.title == "签名匹配 · 密钥有警告")
        #expect(presentation.signature.status == .warning)
        #expect(presentation.details.contains {
            $0.category == .security && $0.status == .warning
        })
    }

    @Test func localCheckPresentationDistinguishesWrongUnsupportedAndInvalidSecrets() throws {
        var session = JWTWorkspaceSession()
        session.parseInput = Self.knownToken
        session.parseSecret = "wrong-secret"
        session.parse()
        let wrongSecret = try #require(session.localCheckPresentation)
        #expect(wrongSecret.signature.title == "签名不匹配")
        #expect(wrongSecret.signature.status == .failed)

        session.clearParse()
        session.parseInput = Self.compactToken(algorithm: "RS256")
        session.parseSecret = Self.strongSecret
        session.parse()
        let unsupported = try #require(session.localCheckPresentation)
        #expect(unsupported.signature.title == "签名算法不支持")
        #expect(unsupported.signature.status == .failed)

        session.clearParse()
        session.parseInput = Self.knownToken
        session.parseSecret = "not base64!"
        session.parseSecretEncoding = .base64
        session.parse()
        let invalidSecret = try #require(session.localCheckPresentation)
        #expect(invalidSecret.signature.title == "Secret 格式错误")
        #expect(invalidSecret.signature.status == .failed)
    }

    @Test func localCheckPresentationSeparatesTimeClaimOutcomes() throws {
        var session = JWTWorkspaceSession()
        let now = Int(Date().timeIntervalSince1970)
        session.parseInput = Self.compactToken(
            algorithm: "HS256",
            payload: "{\"exp\":\(now + 3600),\"nbf\":\(now - 60),\"iat\":\(now - 60)}"
        )
        session.parse()
        let passed = try #require(session.localCheckPresentation)
        #expect(passed.timeClaims.title == "时间声明通过")
        #expect(passed.timeClaims.status == .passed)

        session.parseInput = Self.compactToken(
            algorithm: "HS256",
            payload: "{\"exp\":\(now - 3600)}"
        )
        session.parse()
        let expired = try #require(session.localCheckPresentation)
        #expect(expired.timeClaims.title == "时间声明有问题")
        #expect(expired.timeClaims.status == .failed)
        #expect(expired.details.contains { $0.message.contains("已过期") })
    }

    @Test func parseKnownTokenWithoutSecretIsNotVerified() throws {
        var session = JWTWorkspaceSession()
        session.parseInput = Self.knownToken
        session.parse()
        #expect(!session.parsedHeader.isEmpty)
        #expect(!session.parsedPayload.isEmpty)
        #expect(session.parseError == nil)
        let result = try #require(session.verificationResult)
        #expect(result.summary == .notVerified)
        #expect(session.verificationSummaryText(result) == "签名未检查 · 没有时间声明")
    }

    @Test func parseKnownTokenWithSecretVerifies() throws {
        var session = JWTWorkspaceSession()
        session.parseInput = Self.knownToken
        session.parseSecret = Self.strongSecret
        session.parse()
        let result = try #require(session.verificationResult)
        #expect(result.summary == .verified)
        #expect(session.verificationSummaryText(result) == "签名匹配 · 没有时间声明")
    }

    @Test func transferGeneratedToParsePreparesParseBeforeModeSwitch() {
        var session = JWTWorkspaceSession()
        session.mode = .generate
        session.generatePayload = Self.knownPayload
        session.generateSecret = Self.strongSecret
        session.refreshGeneration()
        #expect(!session.generatedToken.isEmpty)

        session.transferGeneratedToParse()

        #expect(session.mode == .parse)
        #expect(session.parseInput == session.generatedToken)
        #expect(session.parseSecret == Self.strongSecret)
        #expect(!session.parsedHeader.isEmpty)
        #expect(!session.parsedPayload.isEmpty)
        #expect(session.parseError == nil)
        #expect(session.verificationResult != nil)
        #expect(session.registeredClaimInsights.contains { $0.kind == .subject })
    }

    @Test func forwardTransferReplacesStaleRegisteredClaims() {
        var session = JWTWorkspaceSession()
        session.parseInput = Self.compactToken(
            algorithm: "HS256",
            payload: #"{"iss":"stale-issuer"}"#
        )
        session.parse()
        #expect(session.registeredClaimInsights.contains { $0.kind == .issuer })

        session.mode = .generate
        session.generatePayload = Self.knownPayload
        session.generateSecret = Self.strongSecret
        session.refreshGeneration()
        session.transferGeneratedToParse()

        #expect(!session.registeredClaimInsights.contains { $0.kind == .issuer })
        #expect(session.registeredClaimInsights.contains { $0.kind == .subject })
    }

    @Test func transferParsedToGeneratePreparesGenerateBeforeModeSwitch() {
        var session = JWTWorkspaceSession()
        session.parseInput = Self.knownToken
        session.parseSecret = Self.strongSecret
        session.parse()
        #expect(session.mode == .parse)

        session.transferParsedToGenerate()

        #expect(session.mode == .generate)
        #expect(session.generateAlgorithm == .hs256)
        #expect(!session.generatePayload.isEmpty)
        #expect(session.generateSecret == Self.strongSecret)
        #expect(!session.generatedToken.isEmpty)
        #expect(session.transferError == nil)
    }

    @Test func transferParsedToGenerateFailureKeepsModeAndSetsTransferError() {
        var session = JWTWorkspaceSession()
        session.mode = .parse
        session.parsedHeader = "{not-json"
        session.parsedPayload = Self.knownPayload

        session.transferParsedToGenerate()

        #expect(session.mode == .parse)
        #expect(session.transferError == "Header 不是有效的 JSON。")
        #expect(session.generatedToken.isEmpty)
    }

    @Test func clearGenerateEmptiesPayloadInsteadOfRestoringSample() {
        var session = JWTWorkspaceSession()
        session.generatePayload = Self.knownPayload
        session.generateSecret = Self.strongSecret
        session.refreshGeneration()
        #expect(!session.generatedToken.isEmpty)

        session.clearGenerate()

        #expect(session.generatePayload == "")
        #expect(session.generatePayload != JWTWorkspaceSession.defaultGeneratePayload)
        #expect(session.generateAlgorithm == .hs256)
        #expect(session.generateSecret.isEmpty)
        #expect(session.generatedToken.isEmpty)
    }

    @Test func clearAllResetsBothSides() {
        var session = JWTWorkspaceSession()
        session.mode = .generate
        session.generatePayload = Self.knownPayload
        session.generateSecret = Self.strongSecret
        session.refreshGeneration()
        session.transferGeneratedToParse()
        #expect(session.hasParseContent)

        session.clearAll()

        #expect(session.generatePayload == "")
        #expect(session.parseInput.isEmpty)
        #expect(session.parsedHeader.isEmpty)
        #expect(session.parsedPayload.isEmpty)
        #expect(session.verificationResult == nil)
        #expect(session.registeredClaimInsights.isEmpty)
        #expect(session.transferError == nil)
        #expect(session.generateSecret.isEmpty)
        #expect(session.parseSecret.isEmpty)
    }

    @Test func emptySecretAndEmptyPayloadDoNotSurfaceDiagnosticStrings() {
        var session = JWTWorkspaceSession()
        session.generatePayload = ""
        session.generateSecret = ""
        session.refreshGeneration()
        #expect(session.generationPayloadError == nil)
        #expect(session.generationSecretError == nil)
        #expect(session.generatedToken.isEmpty)
        // Header preview can still succeed with default algorithm.
        #expect(session.generationHeaderError == nil)
    }

    @Test func diagnosticsDoNotEchoTokenSecretHeaderOrAlgorithmValues() throws {
        let terminalLog = "osascript System Events /tmp/private-token.mov execution error"
        var session = JWTWorkspaceSession()
        session.parseInput = terminalLog
        session.parse()
        ToolDiagnosticContract.expectFactual(
            session.parseError ?? "",
            sensitiveInputs: [terminalLog]
        )

        let privateHeaderName = "privatePasswordHeader"
        session.generatePayload = Self.knownPayload
        session.generateSecret = Self.strongSecret
        session.generateAdditionalHeaderJSON = "{\"crit\":[\"\(privateHeaderName)\"]}"
        session.refreshGeneration()
        #expect(session.generationHeaderError == "JWT Header 包含当前不支持的参数。")
        ToolDiagnosticContract.expectFactual(
            session.generationHeaderError ?? "",
            sensitiveInputs: [privateHeaderName, "secret-value"]
        )

        let privateAlgorithm = "PrivateSecretAlgorithm"
        session.clearParse()
        session.parseInput = Self.compactToken(algorithm: privateAlgorithm)
        session.parseSecret = Self.strongSecret
        session.parse()
        let result = try #require(session.verificationResult)
        let messages = result.details.map(\.message)
        #expect(messages.contains("JWT 使用了当前不支持的签名算法。"))
        for message in messages {
            ToolDiagnosticContract.expectFactual(message, sensitiveInputs: [privateAlgorithm])
        }
    }

    private static func compactToken(algorithm: String, payload: String = "{}") -> String {
        let header = "{\"alg\":\"\(algorithm)\",\"typ\":\"JWT\"}"
        return "\(base64URL(header)).\(base64URL(payload)).AA"
    }

    private static func base64URL(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
