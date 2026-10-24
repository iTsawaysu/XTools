import XToolsCore
import SwiftUI
import XToolsDesign

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

/// 统一壳装配（page-rollout A1）：生成/解析分段是页面级模式（双向转移
/// 凭据），归标题行 titleAccessory（Base64File 编码/解码分段先例）；清空
/// 归输入 pane 尾部 ActionBar；「在解析中打开 / 用于生成」转移钮归输出
/// pane 头附件（Base64File pane 附件先例，动作带跨模式副作用不进
/// ActionBar 五种声明）；复制归输出 pane 尾部 ActionBar（首个 copy 同步
/// 壳级 actions 注册 ⇧⌘C）。语义本就是 fill 布局，保持不变。
private struct IndexBasicAuthWorkspaceContent: View {
    @Environment(\.toolPageEntryGeneration) private var entryGeneration
    @Binding var session: BasicAuthWorkspaceSession
    @State private var showsPassword = false
    @State private var showsParsedPassword = false

    private let credentialLabelWidth: CGFloat = 70

    private var isGenerating: Bool {
        modeBinding.wrappedValue == .generate
    }

    private var copyAction: WorkbenchActionBarAction {
        .copy(text: session.output)
    }

    var body: some View {
        IndexPage(
            "Basic Auth",
            subtitle: "生成或解析 Basic Auth 请求头；Base64 不是加密，请仅通过 HTTPS 使用。",
            workspaceSemantic: .securityTransformWorkspace
        ) {
            WorkbenchSurface(
                title: nil,
                primaryAction: nil,
                shape: .inputOutput,
                actions: isGenerating ? [copyAction] : [],
                titleAccessory: { modeSegmentedControl }
            ) {
                ioPair
            }
        }
        .onChange(of: entryGeneration) {
            if entryGeneration == 0 {
                showsPassword = false
                showsParsedPassword = false
            }
        }
        .onAppear {
            if !isGenerating { parse() }
        }
        .onChange(of: isGenerating) {
            if !isGenerating { parse() }
        }
    }

    /// 双栏装配：凭据/请求头 pane 与 Authorization/解析结果 pane，随模式
    /// 切换标题与内容（pane 内容投影见下方同名属性）。
    private var ioPair: some View {
        WorkbenchIOPair(
            leadingTitle: isGenerating ? "凭据" : "请求头",
            trailingTitle: isGenerating ? "Authorization 请求头" : "解析结果",
            leadingActions: [
                .clear(enabled: session.hasAnyContent, onPerform: clearAll)
            ],
            trailingActions: isGenerating ? [copyAction] : [],
            leadingAccessory: { EmptyView() },
            leading: {
                Group {
                    if isGenerating {
                        credentialsForm
                    } else {
                        parseField
                    }
                }
            },
            trailingAccessory: { resultTransferControls },
            trailing: {
                Group {
                    if isGenerating {
                        generateResult
                    } else {
                        parseResult
                    }
                }
            }
        )
    }

    private var credentialsForm: some View {
        VStack(spacing: ToolMetrics.Spacing.md) {
            credentialRow("用户名") {
                IndexTextInput(placeholder: "username", text: $session.username, autoFocus: true)
                    .workbenchFocusTarget()
            }
            credentialRow("密码") {
                passwordInput
            }
        }
    }

    private var parseField: some View {
        IndexWorkspaceTextArea(
            placeholder: "Authorization: Basic dXNlcjpwYXNz",
            text: $session.parseInput,
            minHeight: 84,
            fillsHeight: true,
            autoFocus: true,
            embedsFlat: true,
            workspaceSemantic: .longTextNaturalInput
        )
        .workbenchFocusTarget()
        .onChange(of: session.parseInput) { parse() }
        .indexWorkspaceDiagnostic(session.parseError)
    }

    /// 生成/解析分段（页面级模式，标题行承载）。
    private var modeSegmentedControl: some View {
        IndexSegmentedControl(
            items: IndexGenerateParseMode.segmentedItems,
            selection: modeSelection
        )
        .accessibilityLabel("操作模式")
    }

    private var generateResult: some View {
        IndexResultSurface(
            content: .code(text: session.output, placeholder: session.outputPlaceholder)
        )
    }

    @ViewBuilder
    private var parseResult: some View {
        if let credentials = session.parsedCredentials {
            VStack(spacing: 0) {
                parsedUsernameRow(credentials.username)
                parsedPasswordRow(credentials.password)
            }
            .background(ToolTheme.border)
            .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: ToolMetrics.Spacing.hairline)
            }
            .padding(ToolMetrics.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            IndexEmptyState(
                title: IndexEmptyStateCopy.noParsedResult,
                systemImage: "lock.shield",
                message: IndexEmptyStateCopy.autoParse("Basic Auth 请求头或 Base64 凭据"),
                density: .list
            )
            .frame(maxWidth: .infinity, minHeight: 140)
        }
    }

    /// 跨模式转移钮（原 resultControls 槽投影，pane 头附件承载）。
    @ViewBuilder
    private var resultTransferControls: some View {
        if isGenerating {
            Button(action: transferGeneratedToParse) {
                Label("在解析中打开", systemImage: "arrow.right.circle")
                    .font(ToolTypography.buttonSmall)
            }
            .buttonStyle(IndexButtonStyle(compact: true))
            .disabled(session.output.isEmpty)
        } else {
            Button(action: transferParsedToGenerate) {
                Label("用于生成", systemImage: "arrow.left.circle")
                    .font(ToolTypography.buttonSmall)
            }
            .buttonStyle(IndexButtonStyle(compact: true))
            .disabled(session.parsedCredentials == nil)
        }
    }

    private var modeSelection: Binding<String> {
        Binding(
            get: { modeBinding.wrappedValue.rawValue },
            set: { modeBinding.wrappedValue = IndexGenerateParseMode(rawValue: $0) ?? .generate }
        )
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

    private var passwordInput: some View {
        IndexSecureInput(
            placeholder: "password",
            text: $session.password,
            showsSecret: $showsPassword
        )
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
        HStack(alignment: .top, spacing: ToolMetrics.Spacing.md) {
            Text(title)
                .font(ToolTypography.monoLabel)
                .foregroundStyle(ToolTheme.accentHover)
                .frame(width: ToolMetrics.Control.labelColumn, alignment: .leading)
            content()
        }
        .padding(.horizontal, ToolMetrics.Control.labelInset)
        .padding(.vertical, ToolMetrics.Spacing.sm)
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
        HStack(spacing: ToolMetrics.Spacing.md) {
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
