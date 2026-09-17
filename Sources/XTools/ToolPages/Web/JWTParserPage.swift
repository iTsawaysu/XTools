import XToolsCore
import SwiftUI

@MainActor
final class JWTToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<JWTToolWorkspaceModel>(toolID: "jwt-parser") { _ in
        JWTToolWorkspaceModel()
    }

    @Published var session: JWTWorkspaceSession

    init(session: JWTWorkspaceSession = JWTWorkspaceSession()) {
        self.session = session
    }
}

struct IndexJWTPage: View {
    var body: some View {
        ToolWorkspaceHost(key: JWTToolWorkspaceModel.key) { _, bindings in
            IndexJWTWorkspaceContent(session: bindings.session)
        }
    }
}

private struct IndexJWTWorkspaceContent: View {
    @Binding var session: JWTWorkspaceSession
    @State private var showsGenerateSecret = false
    @State private var showsParseSecret = false
    @State private var payloadPresentation = "json"
    @State private var localCheckDisclosureState = JWTLocalCheckDisclosureState()
    @State private var isLocalCheckHeaderHovering = false

    /// Align with formatters: large JSON output keeps full text but drops highlight.
    private static let maxHighlightedOutputCharacters = 200_000

    private static let secretEncodingItems = [
        (JWTSecretEncoding.utf8.rawValue, "普通文本"),
        (JWTSecretEncoding.base64.rawValue, "Base64")
    ]

    private static let payloadPresentationItems = [
        ("json", "JSON"),
        ("claims", "声明")
    ]

    private func jsonColorize(for text: String) -> ((String) -> AttributedString)? {
        if text.count > Self.maxHighlightedOutputCharacters {
            return nil
        }
        return JSONSyntaxHighlighter.highlight(line:)
    }

    var body: some View {
        IndexPage(
            "JWT",
            subtitle: "生成、解析并执行有限的本地 JWT 检查，所有处理均在本地完成。",
            // Mixed generate/parse workspace keeps page-level scrolling while
            // each input/output surface declares its own semantic contract.
            layout: .scroll
        ) {
            IndexGenerateParseModeBar(
                selection: modeBinding,
                clearAllDisabled: !session.hasAnyContent,
                onClearAll: clearAll
            )

            IndexGenerateParseModeContent(mode: modeBinding.wrappedValue) {
                generateContent
            } parse: {
                parseContent
            }
        }
        .onAppear(perform: refreshGeneration)
    }

    // MARK: - Generate

    @ViewBuilder
    private var generateContent: some View {
        IndexPanel("签名配置") {
            VStack(alignment: .leading, spacing: 12) {
                IndexFlowLayout(spacing: 8, lineSpacing: 8) {
                    IndexOptionGroup {
                        IndexOptionLabel("算法")
                        IndexOptionPicker(
                            items: JWTAlgorithm.allCases.map { ($0.rawValue, $0.rawValue) },
                            selection: generateAlgorithmBinding
                        )
                    }
                    IndexOptionGroup {
                        IndexOptionLabel("密钥格式")
                        IndexOptionPicker(
                            items: Self.secretEncodingItems,
                            selection: generateSecretEncodingBinding
                        )
                    }
                }

                IndexSecureInput(
                    placeholder: "输入 HMAC Secret",
                    text: $session.generateSecret,
                    showsSecret: $showsGenerateSecret,
                    secretNoun: "Secret"
                )
                .indexWorkspaceDiagnostic(session.generationSecretError)

                Text(secretEncodingHelp(session.generateSecretEncoding))
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        IndexPairLayout(collapseWidth: 0) {
            IndexPanel("Header") {
                IndexWorkspaceOutputSurface(
                    text: session.generatedHeader,
                    placeholder: "Header 将显示在这里",
                    minHeight: 84,
                    fillsHeight: true,
                    lineNumbers: true,
                    colorize: jsonColorize(for: session.generatedHeader),
                    workspaceSemantic: .structuredOutputReading
                )
                .indexWorkspaceDiagnostic(session.generationHeaderError)
            } accessory: {
                IndexCopyButton(text: session.generatedHeader)
            }
            .verticallyFilling()
        } trailing: {
            IndexPanel("Payload") {
                IndexWorkspaceTextArea(
                    placeholder: #"例如 {"sub":"1234567890"}"#,
                    text: $session.generatePayload,
                    minHeight: 84,
                    fillsHeight: true,
                    autoFocus: true,
                    workspaceSemantic: .longTextNaturalInput
                )
                .indexWorkspaceDiagnostic(session.generationPayloadError)
            }
            .verticallyFilling()
        }

        IndexPanel("JWT") {
            IndexWorkspaceOutputSurface(
                text: session.generatedToken,
                placeholder: "填写有效 Payload 和 Secret 后自动生成",
                minHeight: 84,
                workspaceSemantic: .structuredOutputReading
            )
        } accessory: {
            HStack(spacing: 6) {
                Button(action: transferGeneratedToParse) {
                    Label("在解析中检查", systemImage: "arrow.right.circle")
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
                .disabled(session.generatedToken.isEmpty)
                .help("送入解析模式")

                IndexCopyButton(text: session.generatedToken)
            }
        }
        .onChange(of: session.generateAlgorithm) { _ in refreshGeneration() }
        .onChange(of: session.generatePayload) { _ in refreshGeneration() }
        .onChange(of: session.generateSecret) { _ in refreshGeneration() }
        .onChange(of: session.generateSecretEncoding) { _ in refreshGeneration() }
    }

    private var generateAlgorithmBinding: Binding<String> {
        Binding(
            get: { session.generateAlgorithm.rawValue },
            set: { session.generateAlgorithm = JWTAlgorithm(rawValue: $0) ?? .hs256 }
        )
    }

    private var generateSecretEncodingBinding: Binding<String> {
        Binding(
            get: { session.generateSecretEncoding.rawValue },
            set: { session.generateSecretEncoding = JWTSecretEncoding(rawValue: $0) ?? .utf8 }
        )
    }

    private func refreshGeneration() {
        session.refreshGeneration()
    }

    // MARK: - Parse

    @ViewBuilder
    private var parseContent: some View {
        IndexPanel("JWT") {
            IndexWorkspaceTextArea(
                placeholder: "粘贴 JWT（eyJ...）",
                text: $session.parseInput,
                minHeight: 84,
                autoFocus: true,
                workspaceSemantic: .longTextNaturalInput
            )
            .onChange(of: session.parseInput) { _ in parse() }
            .indexWorkspaceDiagnostic(session.parseError)
        }

        IndexPanel("解码结果") {
            IndexPairLayout(collapseWidth: 0) {
                decodedHeaderPane
            } trailing: {
                decodedPayloadPane
            }
        }

        Text("Header 和 Payload 仅为解码内容，不代表可信输入或具体应用会接受此 Token。")
            .font(ToolTypography.caption)
            .foregroundStyle(ToolTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

        localCheckDisclosure
    }

    private var decodedHeaderPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            IndexFieldHeader("Header") {
                IndexCopyButton(text: session.parsedHeader, iconOnly: true)
            }

            IndexWorkspaceOutputSurface(
                text: session.parsedHeader,
                placeholder: IndexEmptyStateCopy.notAvailable,
                fillsHeight: true,
                lineNumbers: true,
                colorize: jsonColorize(for: session.parsedHeader),
                workspaceSemantic: .structuredOutputReading
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var decodedPayloadPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            IndexFieldHeader("Payload") {
                HStack(spacing: 6) {
                    IndexSegmentedControl(
                        items: Self.payloadPresentationItems,
                        selection: $payloadPresentation,
                        density: .compact
                    )
                    IndexCopyButton(text: session.parsedPayload, iconOnly: true)
                }
            }

            decodedPayloadContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var decodedPayloadContent: some View {
        if payloadPresentation == "claims" {
            registeredClaimsView
        } else {
            IndexWorkspaceOutputSurface(
                text: session.parsedPayload,
                placeholder: IndexEmptyStateCopy.notAvailable,
                fillsHeight: true,
                lineNumbers: true,
                colorize: jsonColorize(for: session.parsedPayload),
                workspaceSemantic: .structuredOutputReading
            )
        }
    }

    private var registeredClaimsView: some View {
        IndexWorkspaceResultSurface(workspaceSemantic: .naturalHeightShortResultPanel) {
            VStack(alignment: .leading, spacing: 8) {
                if session.registeredClaimInsights.isEmpty {
                    IndexEmptyState(
                        title: session.parsedPayload.isEmpty ? "等待解析" : "无注册声明",
                        systemImage: "doc.text.magnifyingglass",
                        message: session.parsedPayload.isEmpty
                            ? "解析 JWT 后将在此显示注册声明。"
                            : "当前 Payload 中没有可解释的注册声明。"
                    )
                    .frame(maxWidth: .infinity, minHeight: 164, alignment: .center)
                } else {
                    IndexKVSurface {
                        VStack(spacing: 1) {
                            ForEach(session.registeredClaimInsights) { insight in
                                registeredClaimRow(insight)
                            }
                        }
                    }

                    Text("时间状态按本机当前时间判断；iss、sub、aud、jti 仅解释原始值，不执行应用级验证。")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 192, alignment: .topLeading)
        }
    }

    private func registeredClaimRow(_ insight: JWTRegisteredClaimInsight) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: registeredClaimIcon(insight.status))
                .font(.system(size: ToolMetrics.IconSize.medium, weight: .semibold))
                .foregroundStyle(registeredClaimColor(insight.status))
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            HStack(spacing: 5) {
                Text(insight.kind.title)
                    .font(ToolTypography.label)
                    .foregroundStyle(ToolTheme.textPrimary)
                Text(insight.kind.rawValue)
                    .font(ToolTypography.monoCaption)
                    .foregroundStyle(ToolTheme.textTertiary)
            }
            .frame(width: 92, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(insight.displayValue)
                    .font(ToolTypography.monoLabel)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Text(insight.explanation)
                    .font(ToolTypography.caption)
                    .foregroundStyle(registeredClaimColor(insight.status))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(ToolTheme.panelBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.kind.title) \(insight.kind.rawValue)：\(insight.displayValue)，\(insight.explanation)")
    }

    private var localCheckDisclosure: some View {
        IndexDisclosure(
            title: "本地检查（可选）",
            isExpanded: localCheckExpansionBinding,
            collapsedSummary: localCheckCollapsedSummary
        ) {
            Button(action: transferParsedToGenerate) {
                Label("用于生成", systemImage: "arrow.left.circle")
                    .font(ToolTypography.buttonSmall)
            }
            .buttonStyle(IndexSmallButtonStyle())
            .disabled(session.parsedHeader.isEmpty || session.parsedPayload.isEmpty)
            .help("送入生成模式")
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    IndexOptionGroup {
                        IndexOptionLabel("密钥格式")
                        IndexOptionPicker(
                            items: Self.secretEncodingItems,
                            selection: parseSecretEncodingBinding
                        )
                    }

                    IndexSecureInput(
                        placeholder: "输入 HMAC Secret（用于 HS256/HS384/HS512）",
                        text: $session.parseSecret,
                        showsSecret: $showsParseSecret,
                        secretNoun: "Secret"
                    )
                    .onChange(of: session.parseSecret) { value in
                        verify()
                        localCheckDisclosureState.secretChanged(isEmpty: value.isEmpty)
                    }

                    Text(secretEncodingHelp(session.parseSecretEncoding))
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                localCheckResultView

            }
            .indexWorkspaceDiagnostic(session.transferError)
        }
        .onAppear(perform: prepareLocalCheckDisclosure)
        .onChange(of: localCheckAttentionUpdateID) { _ in
            localCheckDisclosureState.presentationChanged(
                isPresent: session.localCheckPresentation != nil,
                issueID: localCheckAttentionID
            )
        }
    }

    private var parseSecretEncodingBinding: Binding<String> {
        Binding(
            get: { session.parseSecretEncoding.rawValue },
            set: {
                session.parseSecretEncoding = JWTSecretEncoding(rawValue: $0) ?? .utf8
                verify()
            }
        )
    }

    private var localCheckPresenceUpdateID: [String] {
        guard let presentation = session.localCheckPresentation else {
            return []
        }

        return [
            presentation.summaryText,
            presentation.signature.message,
            presentation.timeClaims.message,
            presentation.scopeStatement
        ] + presentation.details.flatMap { detail in
            [detail.name, detail.message, String(reflecting: detail.status)]
        }
    }

    private var localCheckResultView: some View {
        IndexWorkspaceResultSurface(workspaceSemantic: .naturalHeightShortResultPanel) {
            IndexResultPresence(
                value: session.localCheckPresentation,
                updateID: localCheckPresenceUpdateID
            ) { presentation in
                VStack(alignment: .leading, spacing: 10) {
                    localCheckAxisRow(presentation.signature)
                    localCheckAxisRow(presentation.timeClaims)

                    if !presentation.details.isEmpty {
                        Divider()
                        Text("检查明细")
                            .font(ToolTypography.panelTitle)
                            .foregroundStyle(ToolTheme.textSecondary)

                        ForEach(Array(presentation.details.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: verificationIcon(item.status))
                                    .foregroundStyle(verificationColor(item.status))
                                Text("\(item.name)：\(item.message)")
                                    .font(ToolTypography.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Text(presentation.scopeStatement)
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("检查范围：\(presentation.scopeStatement)")
                }
            } empty: {
                IndexEmptyState(
                    title: "等待检查",
                    systemImage: "checklist",
                    message: "输入 JWT 后将在此显示本地检查结果。"
                )
            }
        }
    }

    private func localCheckAxisRow(
        _ axis: JWTWorkspaceSession.LocalCheckPresentation.Axis
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: localCheckIcon(axis.status))
                .foregroundStyle(localCheckColor(axis.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(axis.title)
                    .font(ToolTypography.label)
                    .foregroundStyle(ToolTheme.textPrimary)
                Text(axis.message)
                    .font(ToolTypography.body)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func parse() {
        session.parse()
    }

    private func verify() {
        session.verify()
    }

    private var localCheckCollapsedSummary: String {
        if let presentation = session.localCheckPresentation {
            return presentation.summaryText
        }
        if session.parseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "输入 JWT 后可检查签名与时间声明"
        }
        return "等待可解码的 JWT"
    }

    private var localCheckAttentionID: String? {
        guard let presentation = session.localCheckPresentation else {
            return nil
        }

        var components: [String] = []
        if localCheckNeedsAttention(presentation.signature.status) {
            components.append("signature:\(presentation.signature.title):\(presentation.signature.message)")
        }
        if localCheckNeedsAttention(presentation.timeClaims.status) {
            components.append("time:\(presentation.timeClaims.title):\(presentation.timeClaims.message)")
        }
        components.append(contentsOf: presentation.details.compactMap { detail in
            guard verificationNeedsAttention(detail.status) else { return nil }
            return "detail:\(detail.name):\(detail.message):\(String(reflecting: detail.status))"
        })
        return components.isEmpty ? nil : components.joined(separator: "|")
    }

    private var localCheckAttentionUpdateID: [String] {
        [
            session.localCheckPresentation == nil ? "absent" : "present",
            localCheckAttentionID ?? "no-issue"
        ]
    }

    /// Bridges the guarded disclosure state into an `IndexDisclosure` binding.
    private var localCheckExpansionBinding: Binding<Bool> {
        Binding(
            get: { localCheckDisclosureState.isExpanded },
            set: { newValue in
                if newValue != localCheckDisclosureState.isExpanded {
                    localCheckDisclosureState.userToggle()
                }
            }
        )
    }

    private func prepareLocalCheckDisclosure() {
        localCheckDisclosureState.prepare(
            hasSecret: !session.parseSecret.isEmpty,
            hasPresentation: session.localCheckPresentation != nil,
            issueID: localCheckAttentionID
        )
    }

    private func localCheckNeedsAttention(
        _ status: JWTWorkspaceSession.LocalCheckPresentation.Axis.Status
    ) -> Bool {
        status == .warning || status == .failed
    }

    private func verificationNeedsAttention(_ status: JWTVerifier.VerificationItem.Status) -> Bool {
        status == .warning || status == .failed
    }

    private func localCheckIcon(
        _ status: JWTWorkspaceSession.LocalCheckPresentation.Axis.Status
    ) -> String {
        jwtStatusChrome(status).symbol
    }

    private func localCheckColor(
        _ status: JWTWorkspaceSession.LocalCheckPresentation.Axis.Status
    ) -> Color {
        jwtStatusChrome(status).color
    }

    private func verificationIcon(_ status: JWTVerifier.VerificationItem.Status) -> String {
        jwtStatusChrome(status).symbol
    }

    private func verificationColor(_ status: JWTVerifier.VerificationItem.Status) -> Color {
        jwtStatusChrome(status).color
    }

    private func registeredClaimIcon(_ status: JWTRegisteredClaimInsight.Status) -> String {
        jwtStatusChrome(status).symbol
    }

    private func registeredClaimColor(_ status: JWTRegisteredClaimInsight.Status) -> Color {
        jwtStatusChrome(status).color
    }

    private func jwtStatusChrome(
        _ status: JWTWorkspaceSession.LocalCheckPresentation.Axis.Status
    ) -> (symbol: String, color: Color) {
        switch status {
        case .informational: return ("info.circle.fill", ToolTheme.info)
        case .passed: return ("checkmark.circle.fill", ToolTheme.success)
        case .warning: return ("exclamationmark.triangle.fill", ToolTheme.warning)
        case .failed: return ("xmark.circle.fill", ToolTheme.error)
        }
    }

    private func jwtStatusChrome(
        _ status: JWTVerifier.VerificationItem.Status
    ) -> (symbol: String, color: Color) {
        switch status {
        case .informational: return ("info.circle.fill", ToolTheme.info)
        case .passed: return ("checkmark.circle.fill", ToolTheme.success)
        case .warning: return ("exclamationmark.triangle.fill", ToolTheme.warning)
        case .failed: return ("xmark.circle.fill", ToolTheme.error)
        }
    }

    private func jwtStatusChrome(
        _ status: JWTRegisteredClaimInsight.Status
    ) -> (symbol: String, color: Color) {
        switch status {
        case .informational: return ("info.circle", ToolTheme.textSecondary)
        case .passed: return ("checkmark.circle.fill", ToolTheme.success)
        case .warning: return ("exclamationmark.triangle.fill", ToolTheme.warning)
        case .failed: return ("xmark.circle.fill", ToolTheme.error)
        }
    }

    // MARK: - Shared controls and state transitions

    private var modeBinding: Binding<IndexGenerateParseMode> {
        Binding(
            get: {
                IndexGenerateParseMode(rawValue: session.mode.rawValue) ?? .parse
            },
            set: {
                session.mode = JWTWorkspaceSession.Mode(rawValue: $0.rawValue) ?? .parse
            }
        )
    }

    private func secretEncodingHelp(_ encoding: JWTSecretEncoding) -> String {
        switch encoding {
        case .utf8:
            return "常用：直接使用输入文本的 UTF-8 字节作为密钥。"
        case .base64:
            return "仅当其他系统提供的是 Base64 密钥时使用；签名或本地检查前会先解码为原始字节。"
        }
    }

    private func clearAll() {
        session.clearAll()
        showsGenerateSecret = false
        showsParseSecret = false
        payloadPresentation = "json"
        localCheckDisclosureState.reset()
        isLocalCheckHeaderHovering = false
    }

    private func transferGeneratedToParse() {
        // Match pre-extraction: only mutate visibility after a real transfer starts.
        guard !session.generatedToken.isEmpty else { return }
        session.transferGeneratedToParse()
        showsParseSecret = false
        localCheckDisclosureState.revealForExplicitTransfer(issueID: localCheckAttentionID)
    }

    private func transferParsedToGenerate() {
        session.transferParsedToGenerate()
        // Match pre-extraction behavior: only hide Secret after a successful transfer.
        if session.mode == .generate {
            showsGenerateSecret = false
        } else if session.transferError != nil {
            localCheckDisclosureState.reveal()
        }
    }
}
