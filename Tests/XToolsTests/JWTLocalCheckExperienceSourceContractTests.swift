import Foundation
import Testing

struct JWTLocalCheckExperienceSourceContractTests {
    @Test func parsePrioritizesDecodedContentAndUsesLocalCheckLanguage() throws {
        let page = try readSource("Sources/XTools/ToolPages/Web/JWTParserPage.swift")
        let session = try readSource("Sources/XToolsCore/JWT/JWTLocalCheckPresentation.swift")
        let parse = sourceSlice(
            page,
            from: "private var parseContent",
            to: "private var parseSecretEncodingBinding"
        )

        contains(page, "生成、解析并执行有限的本地 JWT 检查", "JWT page subtitle must state the bounded local-check scope")
        contains(parse, "IndexPanel(\"解码结果\")", "Decoded Header and Payload must share one primary result panel")
        contains(page, "private var decodedHeaderPane", "Decoded Header must keep a compact pane subheader")
        contains(page, "private var decodedPayloadPane", "Decoded Payload must keep a compact pane subheader")
        contains(page, "IndexFieldHeader(\"Header\")", "Decoded Header must remain visibly labeled")
        contains(page, "IndexFieldHeader(\"Payload\")", "Decoded Payload must remain visibly labeled")
        contains(page, "IndexCopyButton(text: session.parsedHeader, iconOnly: true)", "Decoded Header must keep a compact copy action")
        contains(page, "IndexCopyButton(text: session.parsedPayload, iconOnly: true)", "Decoded Payload must keep a compact copy action")
        doesNotContain(parse, "IndexPanel(\"Header\")", "Decoded Header must not create a second full panel chrome")
        doesNotContain(parse, "IndexPanel(\"Payload\")", "Decoded Payload must not create a second full panel chrome")
        contains(parse, "localCheckDisclosure", "Parse must place one optional local-check disclosure after decoded content")
        contains(page, "本地检查（可选）", "Optional local-check disclosure must use bounded local-check wording")
        contains(page, "IndexDisclosure(", "Local check must reuse the shared disclosure component")
        contains(page, "IndexSegmentedControl(", "Payload must expose a compact JSON/claims view switch")
        contains(page, "(\"json\", \"JSON\")", "Payload view switch must keep JSON as the default view")
        contains(page, "(\"claims\", \"声明\")", "Payload view switch must expose registered claim interpretation")
        contains(page, "session.registeredClaimInsights", "Payload claims view must render the typed Core projection")
        contains(page, "session.localCheckPresentation", "Page must render the typed session presentation projection")
        contains(page, "presentation.scopeStatement", "Application-scope boundary must be rendered in the result")
        contains(session, "未检查 issuer、audience、subject、token type 和业务授权规则", "Session presentation must own the application-scope boundary copy")
        appearsBefore(parse, "IndexPanel(\"JWT\")", "IndexPanel(\"解码结果\")", "JWT input must precede decoded content")
        appearsBefore(parse, "decodedHeaderPane", "decodedPayloadPane", "Decoded Header must precede decoded Payload")
        appearsBefore(parse, "IndexPanel(\"解码结果\")", "localCheckDisclosure", "Decoded content must precede the optional local-check disclosure")

        let disclosureCount = page.components(separatedBy: "IndexDisclosure(").count - 1
        #expect(disclosureCount == 1, "JWT Parse must own exactly one page-level disclosure")

        doesNotContain(parse, "IndexPanel(\"本地检查配置（可选）\")", "Local-check configuration must not remain a separate panel")
        doesNotContain(parse, "IndexPanel(\"本地检查结果\")", "Local-check result must not remain a separate panel")
        doesNotContain(page, "IndexStatusBadge(", "Local-check axes must not be repeated as top-level status badges")
        doesNotContain(page, "JSONSerialization", "SwiftUI must not parse Payload JSON")
        doesNotContain(page, "DateFormatter", "SwiftUI must not interpret NumericDate values")
        doesNotContain(page, "验证通过", "JWT page must not claim application-level validity")
        doesNotContain(page, "验证失败", "JWT page must not claim application-level validity")
        doesNotContain(page, "Token 有效", "JWT page must not claim application-level validity")
    }

    @Test func parseKeepsGenerateModeAndSharedMotionBoundaries() throws {
        let page = try readSource("Sources/XTools/ToolPages/Web/JWTParserPage.swift")

        contains(page, "IndexGenerateParseModeContent", "JWT must keep the shared generate/parse mode content")
        contains(page, "IndexResultPresence", "Local-check details must keep bounded shared result presence")
        contains(page, "@State private var localCheckDisclosureState = JWTLocalCheckDisclosureState()", "Local-check expansion must remain ephemeral testable view state")
        contains(page, "@State private var payloadPresentation = \"json\"", "Payload presentation must default to JSON without changing the draft")
        contains(page, "localCheckDisclosureState.userToggle()", "Manual disclosure choice must enter the tested state machine")
        contains(page, "localCheckDisclosureState.revealForExplicitTransfer", "Generate transfer must explicitly reveal the destination local check")
        doesNotContain(page, "withAnimation", "JWT local-check reorder must not add page-local animation")
        doesNotContain(page, "Task.detached", "JWT presentation must not introduce background work")
    }
}
