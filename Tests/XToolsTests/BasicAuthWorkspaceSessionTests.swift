import XToolsCore
import Testing

struct BasicAuthWorkspaceSessionTests {
    // MARK: - Defaults

    @Test func defaultsToGenerateModeWithEmptyDrafts() {
        let session = BasicAuthWorkspaceSession()
        #expect(session.mode == .generate)
        #expect(session.username.isEmpty)
        #expect(session.password.isEmpty)
        #expect(session.generateHasImportedCredentials == false)
        #expect(session.parseInput.isEmpty)
        #expect(session.parsedCredentials == nil)
        #expect(session.parseError == nil)
        #expect(session.output.isEmpty)
        #expect(session.outputPlaceholder == "填写凭据后自动生成")
    }

    // MARK: - Output derivation

    @Test func generatesAuthorizationHeaderFromCredentials() {
        var session = BasicAuthWorkspaceSession()
        session.username = "user"
        session.password = "pass"
        #expect(session.output == "Authorization: Basic dXNlcjpwYXNz")
        #expect(session.outputDiagnostic == nil)
    }

    @Test func colonUsernameSuppressesOutputWithDiagnostic() {
        var session = BasicAuthWorkspaceSession()
        session.username = "a:b"
        session.password = "pass"
        #expect(session.output.isEmpty)
        #expect(session.outputDiagnostic == "用户名不能包含冒号。")
        #expect(session.outputPlaceholder == "用户名不能包含冒号。")
    }

    @Test func controlCharacterCredentialsSuppressOutputWithDiagnostic() {
        var session = BasicAuthWorkspaceSession()
        session.username = "user"
        session.password = "pa\u{0007}ss"
        #expect(session.output.isEmpty)
        #expect(session.outputDiagnostic == "凭据不能包含控制字符。")
    }

    // MARK: - Imported-empty-credentials boundary

    @Test func importedEmptyCredentialsStillProduceEmptyPairHeader() {
        var session = BasicAuthWorkspaceSession()
        session.generateHasImportedCredentials = true
        // Empty username + empty password, but imported flag set → explicit empty header.
        #expect(session.output == "Authorization: Basic Og==")
    }

    @Test func emptyCredentialsWithoutImportFlagProduceNoOutput() {
        let session = BasicAuthWorkspaceSession()
        #expect(session.output.isEmpty)
    }

    // MARK: - Parse diagnostic buckets (golden Chinese)

    @Test func parseSucceedsOnValidHeader() {
        var session = BasicAuthWorkspaceSession()
        session.parseInput = "Authorization: Basic dXNlcjpwYXNz"
        session.parse()
        #expect(session.parsedCredentials == .init(username: "user", password: "pass"))
        #expect(session.parseError == nil)
    }

    @Test func parseEmptyInputClearsWithoutError() {
        var session = BasicAuthWorkspaceSession()
        session.parseInput = "   "
        session.parse()
        #expect(session.parsedCredentials == nil)
        #expect(session.parseError == nil)
    }

    @Test func parseUnsupportedSchemeBucket() {
        var session = BasicAuthWorkspaceSession()
        session.parseInput = "Bearer dXNlcjpwYXNz"
        session.parse()
        #expect(session.parsedCredentials == nil)
        #expect(session.parseError == "认证方式不是 Basic。")
    }

    @Test func parseUnsupportedHeaderBucket() {
        var session = BasicAuthWorkspaceSession()
        session.parseInput = "X-Auth: Basic dXNlcjpwYXNz"
        session.parse()
        #expect(session.parseError == "只支持 Authorization 请求头。")
    }

    @Test func parseInvalidHeaderBucket() {
        var session = BasicAuthWorkspaceSession()
        session.parseInput = "Authorization: dXNlcjpwYXNz"
        session.parse()
        #expect(session.parseError == "Basic Auth 请求头格式无效。")
    }

    @Test func parseInvalidBase64Bucket() {
        var session = BasicAuthWorkspaceSession()
        session.parseInput = "***"
        session.parse()
        #expect(session.parseError == "凭据不是有效的 Base64。")
    }

    @Test func parseInvalidUTF8Bucket() {
        var session = BasicAuthWorkspaceSession()
        session.parseInput = "/w=="
        session.parse()
        #expect(session.parseError == "凭据不是有效的 UTF-8 文本。")
    }

    @Test func parseMissingSeparatorBucket() {
        var session = BasicAuthWorkspaceSession()
        session.parseInput = "dXNlcg=="
        session.parse()
        #expect(session.parseError == "解码后的凭据缺少用户名与密码之间的冒号。")
    }

    @Test func parseControlCharacterBucket() {
        var session = BasicAuthWorkspaceSession()
        session.parseInput = "dXNlcgo6cGFzcw=="
        session.parse()
        #expect(session.parseError == "凭据不能包含控制字符。")
    }

    @Test func diagnosticsDoNotEchoHeaderSchemeOrPassword() {
        let sensitiveHeader = "X-Private-Password-Header"
        var session = BasicAuthWorkspaceSession()
        session.parseInput = "\(sensitiveHeader): Basic dXNlcjpwYXNz"
        session.parse()
        ToolDiagnosticContract.expectFactual(
            session.parseError ?? "",
            sensitiveInputs: [sensitiveHeader]
        )

        let sensitiveScheme = "PrivatePasswordScheme"
        session.parseInput = "\(sensitiveScheme) dXNlcjpwYXNz"
        session.parse()
        ToolDiagnosticContract.expectFactual(
            session.parseError ?? "",
            sensitiveInputs: [sensitiveScheme]
        )
    }

    // MARK: - Transfer

    @Test func transferGeneratedToParsePreparesResultThenRevealsParseMode() {
        var session = BasicAuthWorkspaceSession()
        session.username = "user"
        session.password = "pass"
        session.transferGeneratedToParse()
        #expect(session.parseInput == "Authorization: Basic dXNlcjpwYXNz")
        #expect(session.parsedCredentials == .init(username: "user", password: "pass"))
        #expect(session.mode == .parse)
    }

    @Test func transferGeneratedToParseNoOpWhenOutputEmpty() {
        var session = BasicAuthWorkspaceSession()
        session.transferGeneratedToParse()
        #expect(session.parseInput.isEmpty)
        #expect(session.mode == .generate)
    }

    @Test func transferParsedToGenerateImportsCredentialsThenRevealsGenerateMode() {
        var session = BasicAuthWorkspaceSession(mode: .parse)
        session.parseInput = "Authorization: Basic dXNlcjpwYXNz"
        session.parse()
        session.transferParsedToGenerate()
        #expect(session.username == "user")
        #expect(session.password == "pass")
        #expect(session.generateHasImportedCredentials == true)
        #expect(session.mode == .generate)
    }

    @Test func transferParsedToGenerateNoOpWhenNoCredentials() {
        var session = BasicAuthWorkspaceSession(mode: .parse)
        session.transferParsedToGenerate()
        #expect(session.generateHasImportedCredentials == false)
        #expect(session.mode == .parse)
    }

    // MARK: - Clear

    @Test func clearGenerateResetsGenerateDraftsIncludingImportFlag() {
        var session = BasicAuthWorkspaceSession()
        session.username = "user"
        session.password = "pass"
        session.generateHasImportedCredentials = true
        session.clearGenerate()
        #expect(session.username.isEmpty)
        #expect(session.password.isEmpty)
        #expect(session.generateHasImportedCredentials == false)
    }

    @Test func clearParseResetsParseDrafts() {
        var session = BasicAuthWorkspaceSession()
        session.parseInput = "Authorization: Basic dXNlcjpwYXNz"
        session.parse()
        session.clearParse()
        #expect(session.parseInput.isEmpty)
        #expect(session.parsedCredentials == nil)
        #expect(session.parseError == nil)
    }

    @Test func clearAllResetsBothSides() {
        var session = BasicAuthWorkspaceSession()
        session.username = "user"
        session.password = "pass"
        session.generateHasImportedCredentials = true
        session.parseInput = "Bearer x"
        session.parse()
        session.clearAll()
        #expect(session.username.isEmpty)
        #expect(session.password.isEmpty)
        #expect(session.generateHasImportedCredentials == false)
        #expect(session.parseInput.isEmpty)
        #expect(session.parsedCredentials == nil)
        #expect(session.parseError == nil)
    }

    // MARK: - Content flags

    @Test func hasContentFlagsTrackDrafts() {
        var session = BasicAuthWorkspaceSession()
        #expect(session.hasAnyContent == false)

        session.username = "u"
        #expect(session.hasGenerateContent == true)
        #expect(session.hasAnyContent == true)

        session.clearAll()
        session.parseInput = "x"
        #expect(session.hasParseContent == true)
        #expect(session.hasAnyContent == true)
    }

    @Test func importFlagAloneCountsAsGenerateContent() {
        var session = BasicAuthWorkspaceSession()
        session.generateHasImportedCredentials = true
        #expect(session.hasGenerateContent == true)
    }
}
