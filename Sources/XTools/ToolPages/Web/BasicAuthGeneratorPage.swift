import XToolsCore
import SwiftUI

@MainActor
final class BasicAuthToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<BasicAuthToolWorkspaceModel>(toolID: "basic-auth-generator") { _ in
        BasicAuthToolWorkspaceModel()
    }

    @Published var session: BasicAuthWorkspaceSession

    init(session: BasicAuthWorkspaceSession = BasicAuthWorkspaceSession()) {
        self.session = session
    }
}

struct IndexBasicAuthPage: View {
    var body: some View {
        ToolWorkspaceHost(key: BasicAuthToolWorkspaceModel.key) { _, bindings in
            IndexBasicAuthWorkspaceContent(session: bindings.session)
        }
    }
}

private struct IndexBasicAuthWorkspaceContent: View {
    @Binding var session: BasicAuthWorkspaceSession
    @State private var showsPassword = false
    @State private var showsParsedPassword = false

    private let credentialLabelWidth: CGFloat = 70

    var body: some View {
        IndexPage(
            "Basic Auth",
            subtitle: "生成或解析 Basic Auth 请求头；Base64 不是加密，请仅通过 HTTPS 使用。",
            workspaceSemantic: .securityTransformWorkspace
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
    }

    private var modeBinding: Binding<IndexGenerateParseMode> {
        Binding(
            get: { IndexGenerateParseMode(rawValue: session.mode.rawValue) ?? .generate },
            set: { session.mode = BasicAuthWorkspaceSession.Mode(rawValue: $0.rawValue) ?? .generate }
        )
    }

    private var parsedCredentialsPresenceUpdateID: [String] {
        guard let credentials = session.parsedCredentials else {
            return []
        }
        return [credentials.username, credentials.password]
    }

    // MARK: - Generate

    @ViewBuilder
    private var generateContent: some View {
        IndexPanel("凭据") {
            VStack(spacing: 12) {
                credentialRow("用户名") {
                    IndexTextInput(placeholder: "username", text: $session.username, autoFocus: true)
                }
                credentialRow("密码") {
                    passwordInput
                }
            }
        }

        IndexPanel("Authorization 请求头") {
            IndexWorkspaceOutputSurface(
                text: session.output,
                placeholder: session.outputPlaceholder,
                minHeight: 70,
                workspaceSemantic: .naturalHeightShortResultPanel
            )
            .indexWorkspaceDiagnostic(session.outputDiagnostic)
        } accessory: {
            HStack(spacing: 6) {
                Button(action: transferGeneratedToParse) {
                    Label("在解析中打开", systemImage: "arrow.right.circle")
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
                .disabled(session.output.isEmpty)
                .help("送入解析模式")

                IndexCopyButton(text: session.output)
            }
        }
    }

    private var passwordInput: some View {
        IndexSecureInput(
            placeholder: "password",
            text: $session.password,
            showsSecret: $showsPassword
        )
    }

    // MARK: - Parse

    @ViewBuilder
    private var parseContent: some View {
        IndexPanel("Authorization 请求头") {
            IndexWorkspaceTextArea(
                placeholder: "Authorization: Basic dXNlcjpwYXNz",
                text: $session.parseInput,
                minHeight: 84,
                autoFocus: true,
                workspaceSemantic: .longTextNaturalInput
            )
            .onChange(of: session.parseInput) { _ in parse() }
            .indexWorkspaceDiagnostic(session.parseError)
        }

        IndexPanel("解析结果") {
            IndexWorkspaceResultSurface(workspaceSemantic: .naturalHeightShortResultPanel) {
                IndexResultPresence(
                    value: session.parsedCredentials,
                    updateID: parsedCredentialsPresenceUpdateID
                ) { parsedCredentials in
                    VStack(spacing: 1) {
                        parsedUsernameRow(parsedCredentials.username)
                        parsedPasswordRow(parsedCredentials.password)
                    }
                    .background(ToolTheme.border)
                    .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                            .strokeBorder(ToolTheme.border, lineWidth: 0.5)
                    }
                } empty: {
                    IndexEmptyState(
                        title: IndexEmptyStateCopy.noParsedResult,
                        systemImage: "lock.shield",
                        message: IndexEmptyStateCopy.autoParse("Basic Auth 请求头或 Base64 凭据"),
                        density: .list
                    )
                    .frame(minHeight: 70)
                }
            }
        } accessory: {
            Button(action: transferParsedToGenerate) {
                Label("用于生成", systemImage: "arrow.left.circle")
                    .font(ToolTypography.buttonSmall)
            }
            .buttonStyle(IndexSmallButtonStyle())
            .disabled(session.parsedCredentials == nil)
            .help("送入生成模式")
        }
    }

    private func parsedUsernameRow(_ value: String) -> some View {
        parsedResultRow(title: "用户名") {
            Text(value.isEmpty ? "（空）" : value)
                .font(ToolTypography.monoLabel)
                .foregroundStyle(ToolTheme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            IndexCopyButton(text: value, title: "复制", iconOnly: true)
        }
    }

    private func parsedPasswordRow(_ value: String) -> some View {
        parsedResultRow(title: "密码") {
            if showsParsedPassword {
                Text(value.isEmpty ? "（空）" : value)
                    .font(ToolTypography.monoLabel)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("••••••••")
                    .font(ToolTypography.monoLabel)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsParsedPassword {
                IndexCopyButton(text: value, title: "复制", iconOnly: true)
            }

            IndexIconButton(
                systemImage: showsParsedPassword ? "eye.slash" : "eye",
                help: showsParsedPassword ? "隐藏密码" : "显示密码"
            ) {
                showsParsedPassword.toggle()
            }
        }
    }

    private func parsedResultRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(ToolTypography.monoLabel)
                .foregroundStyle(ToolTheme.accentHover)
                .frame(width: 70, alignment: .leading)
            content()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(ToolTheme.panelBackground)
    }

    private func parse() {
        showsParsedPassword = false
        session.parse()
    }

    // MARK: - Shared controls and transitions

    private func credentialRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(title).fieldLabel(width: credentialLabelWidth)
            content()
                .frame(maxWidth: .infinity)
        }
    }

    private func clearAll() {
        showsPassword = false
        showsParsedPassword = false
        session.clearAll()
    }

    private func transferGeneratedToParse() {
        showsParsedPassword = false
        session.transferGeneratedToParse()
    }

    private func transferParsedToGenerate() {
        showsPassword = false
        session.transferParsedToGenerate()
    }
}

private extension Text {
    func fieldLabel(width: CGFloat = 70) -> some View {
        font(ToolTypography.label)
            .foregroundStyle(ToolTheme.textSecondary)
            .frame(width: width, alignment: .leading)
    }
}
