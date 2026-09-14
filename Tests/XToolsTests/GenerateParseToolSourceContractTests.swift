import Foundation
import Testing

struct GenerateParseToolSourceContractTests {
    @Test func sharedModeBarKeepsStableOrderAndSafeResponsiveFallback() throws {
        let source = try readSource("Sources/XTools/ToolPages/Workbench/Controls/IndexGenerateParseMode.swift")

        appearsBefore(source, "case generate", "case parse", "Generate/parse mode order must stay stable")
        contains(source, "case .generate: return \"生成\"", "Shared mode must own the generate label")
        contains(source, "case .parse: return \"解析\"", "Shared mode must own the parse label")
        contains(source, "IndexSegmentedControl(", "Shared mode bar must reuse the existing segmented control")
        contains(source, "ViewThatFits(in: .horizontal)", "Shared mode bar must provide a narrow-width fallback")
        contains(source, "Label(\"清空\", systemImage: IndexActionSymbol.clear)", "Shared mode bar must expose one concise content-clear action")
        doesNotContain(source, "Label(\"清空\", systemImage: \"trash\")", "Content clear must not use the resource deletion symbol")
        doesNotContain(source, "全部清空", "Shared mode bar must not expose the old over-specified reset label")
        contains(source, "struct IndexGenerateParseModeContent<GenerateContent: View, ParseContent: View>: View", "Shared generate/parse UI must own one reusable mode-content container")
        contains(source, "ZStack(alignment: .topLeading)", "Mode transition content must overlap outgoing and incoming branches instead of stacking them vertically")
        contains(source, "ToolMetrics.Spacing.base", "Mode-specific panels must retain the standard page section spacing")
        contains(source, "ToolMotion.Transition.orderedContent(direction)", "Mode-specific content must use the shared directional ordered-content transition")
        contains(source, "ToolMotion.Preset.orderedContent", "Mode-specific content must use the shared ordered-content animation preset")
        contains(source, "@Environment(\\.accessibilityReduceMotion) private var reduceMotion", "Mode-content animation must honor Reduce Motion")

        let compact = sourceSlice(source, from: "VStack(alignment: .leading, spacing: 9)", to: ".frame(maxWidth: .infinity, alignment: .leading)")
        doesNotContain(compact, "Spacer(", "Vertical mode-bar fallback must not contain an expanding spacer")
    }

    @Test func jwtAndBasicAuthUseStructuredModeSpecificWorkflows() throws {
        let jwt = try readSource("Sources/XTools/ToolPages/Web/JWTParserPage.swift")
        let basic = try readSource("Sources/XTools/ToolPages/Web/BasicAuthGeneratorPage.swift")
        let session = try readSource("Sources/XToolsCore/JWT/JWTWorkspaceSession.swift")
        let basicSession = try readSource("Sources/XToolsCore/Web/BasicAuthWorkspaceSession.swift")

        contains(jwt, "ToolWorkspaceHost(key: JWTToolWorkspaceModel.key)", "JWT page must resolve its retained per-tool workspace")
        contains(jwt, "@Binding var session: JWTWorkspaceSession", "JWT workspace content must keep binding the Core value session")
        contains(session, "mode: Mode = .parse", "JWT session must default to parse")
        contains(basic, "ToolWorkspaceHost(key: BasicAuthToolWorkspaceModel.key)", "Basic Auth page must resolve its retained per-tool workspace")
        contains(basic, "@Binding var session: BasicAuthWorkspaceSession", "Basic Auth workspace content must keep binding the Core value session")
        contains(basicSession, "mode: Mode = .generate", "Basic Auth session must default to generate")
        contains(jwt, "IndexGenerateParseModeBar(", "JWT must use the shared mode bar")
        contains(basic, "IndexGenerateParseModeBar(", "Basic Auth must use the shared mode bar")
        doesNotContain(jwt, "IndexConverterPage(", "JWT must not use the symmetric string converter")
        doesNotContain(basic, "IndexConverterPage(", "Basic Auth must not use the symmetric string converter")
        doesNotContain(jwt, "NSPasteboard", "JWT in-app transfer must not route secrets through the system pasteboard")
        doesNotContain(basic, "NSPasteboard", "Basic Auth in-app transfer must not route passwords through the system pasteboard")
        contains(jwt, "IndexGenerateParseModeContent(mode: modeBinding.wrappedValue)", "JWT must use the shared lightweight mode-content transition")
        contains(basic, "IndexGenerateParseModeContent(mode: modeBinding.wrappedValue)", "Basic Auth must use the shared lightweight mode-content transition")
        doesNotContain(jwt, ".alert(item: $pendingConfirmation", "JWT explicit transfers must not present replacement alerts")
        doesNotContain(basic, ".alert(item: $pendingConfirmation", "Basic Auth explicit transfers must not present replacement alerts")
        doesNotContain(jwt, "PendingConfirmation", "JWT must not retain transfer-confirmation state")
        doesNotContain(basic, "PendingConfirmation", "Basic Auth must not retain transfer-confirmation state")
        doesNotContain(jwt, "requestGeneratedToParseTransfer", "JWT generated-to-parse action must transfer directly")
        doesNotContain(jwt, "requestParsedToGenerateTransfer", "JWT parsed-to-generate action must transfer directly")
        doesNotContain(basic, "requestGeneratedToParseTransfer", "Basic Auth generated-to-parse action must transfer directly")
        doesNotContain(basic, "requestParsedToGenerateTransfer", "Basic Auth parsed-to-generate action must transfer directly")
        contains(jwt, "Button(action: transferGeneratedToParse)", "JWT verify transfer button must invoke the direct transfer")
        contains(jwt, "Button(action: transferParsedToGenerate)", "JWT generate transfer button must invoke the direct transfer")
        contains(basic, "Button(action: transferGeneratedToParse)", "Basic Auth parse transfer button must invoke the direct transfer")
        contains(basic, "Button(action: transferParsedToGenerate)", "Basic Auth generate transfer button must invoke the direct transfer")
        contains(jwt, "private func clearAll()", "JWT must clear both mode drafts")
        contains(basic, "private func clearAll()", "Basic Auth must clear both mode drafts")
        contains(jwt, "onClearAll: clearAll", "JWT top-level clear must immediately reset the whole tool")
        contains(basic, "onClearAll: clearAll", "Basic Auth top-level clear must immediately reset the whole tool")
        contains(jwt, "session.clearAll()", "JWT clear must delegate to the Core workspace session")
        contains(jwt, "session.transferGeneratedToParse()", "JWT forward transfer must delegate to the Core workspace session")
        contains(jwt, "session.transferParsedToGenerate()", "JWT reverse transfer must delegate to the Core workspace session")
        contains(basic, "session.clearAll()", "Basic Auth clear must delegate to the Core workspace session")
        contains(basic, "session.parse()", "Basic Auth parse must delegate to the Core workspace session")
        contains(basic, "session.transferGeneratedToParse()", "Basic Auth forward transfer must delegate to the Core workspace session")
        contains(basic, "session.transferParsedToGenerate()", "Basic Auth reverse transfer must delegate to the Core workspace session")
        doesNotContain(basic, "func parseErrorMessage", "Basic Auth diagnostic maps must live in the Core session")
        doesNotContain(jwt, "localClearButton", "JWT must not expose competing mode-local clear actions")
        doesNotContain(basic, "localClearButton", "Basic Auth must not expose competing mode-local clear actions")
        doesNotContain(jwt, "hasGenerateReplacementContent", "JWT no longer needs replacement-draft classification when transfers are direct")
        contains(session, "generatePayload = \"\"", "JWT clear must remove the editable Payload instead of restoring the sample")
        doesNotContain(jwt, "generationErrorMessage", "JWT diagnostic maps must live in the Core session")
        doesNotContain(jwt, "verificationFailureMessage", "JWT verification diagnostics must live in the Core session")
        contains(jwt, "maxHighlightedOutputCharacters = 200_000", "JWT must share the formatter highlight budget for large JSON panels")
        contains(jwt, "if text.count > Self.maxHighlightedOutputCharacters", "JWT must degrade highlighting on oversized decoded JSON without truncating body text")
        contains(jwt, "jsonColorize(for:", "JWT colorize sites must route through the shared budget helper")
        doesNotContain(jwt, "colorize: JSONSyntaxHighlighter.highlight(line:)", "JWT must not pass uncapped JSON highlighting into output surfaces")

        // Transfer order is behavior-tested on JWTWorkspaceSession; page only delegates.
        let jwtForward = sourceSlice(jwt, from: "private func transferGeneratedToParse()", to: "private func transferParsedToGenerate()")
        contains(jwtForward, "session.transferGeneratedToParse()", "JWT forward transfer body must call the session")
        let jwtReverse = sourceSlice(jwt, from: "private func transferParsedToGenerate()", to: "\n}\n")
        contains(jwtReverse, "session.transferParsedToGenerate()", "JWT reverse transfer body must call the session")
        appearsBefore(session, "parse()", "mode = .parse", "Session forward transfer must parse before revealing parse mode")
        appearsBefore(session, "refreshGeneration()", "mode = .generate", "Session reverse transfer must refresh generation before revealing generate mode")

        // Transfer order is behavior-tested on BasicAuthWorkspaceSession; page only delegates.
        contains(basic, "session.clearAll()", "Basic Auth clear must delegate to the Core workspace session")
        contains(basic, "session.transferGeneratedToParse()", "Basic Auth forward transfer must delegate to the Core workspace session")
        contains(basic, "session.transferParsedToGenerate()", "Basic Auth reverse transfer must delegate to the Core workspace session")
        contains(basic, "session.parse()", "Basic Auth parse must delegate to the Core workspace session")
        doesNotContain(basic, "parseErrorMessage", "Basic Auth diagnostic maps must live in the Core session")
        appearsBefore(basicSession, "parse()", "mode = .parse", "Basic Auth session forward transfer must parse before revealing parse mode")
        let basicReverse = sourceSlice(basic, from: "private func transferParsedToGenerate()", to: "\n}\n")
        contains(basicReverse, "showsPassword = false", "Basic Auth reverse transfer must reset credential visibility before delegating")
    }


    @Test func webToolRegistryRenamesJWTWithoutChangingStableIDs() throws {
        let registry = try readSource("Sources/XTools/ToolRegistry/ToolRegistry.swift")

        contains(registry, "id: \"jwt-parser\"", "JWT stable ID must not change")
        contains(registry, "title: \"JWT\"", "JWT visible title must use the bidirectional name")
        contains(registry, "id: \"basic-auth-generator\"", "Basic Auth stable ID must not change")
        contains(registry, "\"generate\", \"sign\", \"encode\", \"parse\", \"decode\"", "JWT search metadata must cover both directions")
    }

    @Test func protocolRulesStayInCore() throws {
        let signing = try readSource("Sources/XToolsCore/JWT/JWTSigning.swift")
        let verifier = try readSource("Sources/XToolsCore/JWT/JWTVerifier.swift")
        let basic = try readSource("Sources/XToolsCore/Web/BasicAuthGenerator.swift")

        contains(signing, "public enum JWTAlgorithm", "Core must own the JWT HMAC algorithm allowlist")
        contains(signing, "public enum JWTSecretEncoding", "Core must own secret representation")
        contains(signing, "public enum JWTSigner", "Core must own compact JWT signing")
        contains(signing, "minimumKeyByteCount", "Core must own signing key minimums")
        contains(signing, "JSONFormatting.minifyResult", "JWT signing must use strict project JSON validation")
        contains(verifier, "public enum SignatureStatus", "Core verifier must expose explicit signature status")
        contains(verifier, "case notVerified", "Core verifier must distinguish skipped verification")
        contains(verifier, "JWTHMAC.digest", "Signer and verifier must share the HMAC path")
        contains(basic, "public enum BasicAuthCodec", "Core must expose a bidirectional Basic Auth contract")
        contains(basic, "public static func parse(_ input: String)", "Core must own Basic Auth parsing")
        contains(basic, "public typealias BasicAuthGenerator = BasicAuthCodec", "Existing Basic Auth generation API must remain compatible")
    }
}
