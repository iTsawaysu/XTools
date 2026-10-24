import XToolsCore
import SwiftUI
import XToolsDesign

@MainActor
final class HTMLToMarkdownToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<HTMLToMarkdownToolWorkspaceModel>(toolID: "html-to-markdown") { preferences in
        HTMLToMarkdownToolWorkspaceModel(preferences: preferences)
    }

    let session = HTMLToMarkdownSession()

    /// Renders the Markdown output through the Clay preview theme; the
    /// monospaced source view stays one toggle away. Persisted per tool.
    @Published var showsRenderedPreview: Bool {
        didSet {
            guard showsRenderedPreview != oldValue else { return }
            preferences.set(showsRenderedPreview, for: TextDevelopmentToolPreferenceKeys.htmlMarkdownRenderedPreview)
        }
    }

    private let preferences: ToolPreferenceStore

    init(preferences: ToolPreferenceStore = ToolPreferenceStore(defaults: .standard)) {
        self.preferences = preferences
        showsRenderedPreview = preferences.value(for: TextDevelopmentToolPreferenceKeys.htmlMarkdownRenderedPreview)
    }
}

struct IndexHTMLToMarkdownPage: View {
    var body: some View {
        ToolWorkspaceHost(key: HTMLToMarkdownToolWorkspaceModel.key) { workspace, _ in
            IndexHTMLToMarkdownWorkspaceContent(
                workspace: workspace,
                session: workspace.session
            )
        }
    }
}

/// Prototype v3 body, page-rollout B2 统一壳形态：URL 获取行与「仅提取正文」
/// 收进弹性参数区（搜索字段独占一行配方），输出呈现切换（源码/预览）归
/// 输出 pane 头附件；清空归输入 pane 尾 ActionBar，复制/保存归输出 pane 尾
/// ActionBar（⇧⌘C 由 IOPair 代理持有、页面只在 IOPair 声明一次）；转换由
/// 会话自持的边输入边跑，无主操作（旧壳 onFormat == nil 等价）；诊断走
/// preference 单轨到纸顶 banner（详情随载荷保留；会话无源标记，「定位」缺席）。
private struct IndexHTMLToMarkdownWorkspaceContent: View {
    /// 输出 pane 标题（AX 与 pane 头同源）。
    private let outputTitle = "输出"

    @ObservedObject var workspace: HTMLToMarkdownToolWorkspaceModel
    @ObservedObject var session: HTMLToMarkdownSession
    /// 输入 pane 的文本文件拖入会话（旧壳能力随行）。
    @StateObject private var droppedFile = IndexDroppedTextFile()

    var body: some View {
        IndexPage(
            "HTML → Markdown",
            subtitle: "粘贴 HTML 或获取 URL，转换为 Markdown。",
            workspaceSemantic: .structuredEditorTransform
        ) {
            WorkbenchSurface(
                title: nil,
                shape: .inputOutput,
                parameters: { parameterFlow },
                content: {
                    WorkbenchIOPair(
                        leadingTitle: "输入",
                        trailingTitle: outputTitle,
                        leadingActions: [
                            .clear(enabled: session.canClear, onPerform: session.clear)
                        ],
                        trailingActions: [
                            .copy(text: session.markdown, help: "复制全部 (⇧⌘C)"),
                            .save(payload: session.markdown, fileName: "markdown-output.md")
                        ],
                        leadingAccessory: { stdinBadge },
                        leading: { inputPane },
                        trailingAccessory: { stdoutCluster },
                        trailing: { outputPane }
                    )
                    // 诊断单轨：拖入拒判优先，其后是会话错误/警告；详情随
                    // 载荷透传给纸顶 banner。
                    .indexWorkspaceDiagnostic(
                        droppedFile.rejection?.message ?? (session.error ?? session.warning),
                        tone: droppedFile.rejection == nil ? (session.error == nil ? .warning : .error) : .error,
                        detail: droppedFile.rejection == nil ? session.diagnostic : nil
                    )
                }
            )
            .environment(
                \.markdownPreviewAuthorizationGeneration,
                session.previewAuthorizationGeneration
            )
        }
    }

    // MARK: - 弹性参数区

    /// URL 获取行（独占一行，字段占余宽）与「仅提取正文」开关：即时参数
    /// 进参数区（搜索字段独占一行配方；旧 inputHeader 收纳）。
    private var parameterFlow: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterItem {
                urlRow
            }
            WorkbenchParameterItem {
                IndexOptionSwitch(
                    title: "仅提取正文",
                    style: .button,
                    isOn: $session.extractArticleOnly
                )
            }
        }
    }

    /// URL 输入行：回车即获取、Esc 清空；解析中禁用整行并可停止。
    private var urlRow: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(ToolTypography.icon(ToolMetrics.IconSize.small, .regular))
                .foregroundStyle(ToolTheme.textTertiary)
                .accessibilityHidden(true)
            IndexTextInput(
                placeholder: "URL...",
                text: $session.urlText,
                height: ToolMetrics.Control.row,
                trailingInset: session.urlText.isEmpty ? 11 : 28,
                onSubmit: session.fetchURL,
                onEscape: clearURL
            )
            .overlay(alignment: .trailing) {
                if !session.urlText.isEmpty && !session.isURLProcessing {
                    Button {
                        clearURL()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textTertiary)
                    }
                    .buttonStyle(IndexQuietChromeStyle(look: .bare))
                    .padding(.trailing, ToolMetrics.Spacing.sm)
                    .arrowCursorOnHover()
                    .help("清空 URL (Esc)")
                    .accessibilityLabel("清空 URL 地址")
                }
            }
            fetchButton
                .fixedSize(horizontal: true, vertical: false)
            if session.isURLProcessing {
                Button {
                    session.cancelURLFetch()
                } label: {
                    Label("停止", systemImage: IndexActionSymbol.stop)
                }
                .buttonStyle(IndexButtonStyle(compact: true, framed: true))
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("停止解析网页")
                .help("停止解析网页")
            }
        }
        .disabled(session.isURLProcessing)
    }

    private func clearURL() {
        guard !session.urlText.isEmpty, !session.isURLProcessing else { return }
        session.urlText = ""
    }

    private var fetchButton: some View {
        Button {
            session.fetchURL()
        } label: {
            IndexProgressMotionLabel(
                title: session.isURLProcessing ? "正在解析…" : "获取",
                systemImage: "arrow.down.doc",
                isProcessing: session.isURLProcessing,
                id: session.isURLProcessing
            )
        }
        .buttonStyle(IndexButtonStyle(compact: true, framed: true))
        .disabled(fetchDisabled)
        .accessibilityLabel(session.isURLProcessing ? "正在解析网页" : "获取网页")
        .help("获取网页 (↩)")
    }

    private var fetchDisabled: Bool {
        session.isURLProcessing
            || session.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - 内容区 pane

    private var stdinBadge: some View {
        IndexBadge("STDIN", tone: .neutral, isCapsule: true)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// 输出 pane 头附件：STDOUT 徽章 + 源码/预览切换（旧 outputControl 槽）。
    private var stdoutCluster: some View {
        HStack(spacing: ToolMetrics.Spacing.fine) {
            IndexBadge("STDOUT", tone: .neutral, isCapsule: true)
                .fixedSize(horizontal: true, vertical: false)
            IndexSegmentedControl(
                items: [("source", "源码"), ("preview", "预览")],
                selection: Binding(
                    get: { workspace.showsRenderedPreview ? "preview" : "source" },
                    set: { workspace.showsRenderedPreview = $0 == "preview" }
                ),
                density: .compact
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// 输入 pane 内容：受控 AppKit 编辑器填满 pane；拖入 HTML 文本后由会话
    /// 自持的边输入边跑接管（旧壳 onFormat == nil 分支等价）。
    private var inputPane: some View {
        IndexWorkspaceTextArea(
            placeholder: "<h1>标题</h1>\n<p>段落</p>",
            text: inputBinding,
            fillsHeight: true,
            autoFocus: true,
            embedsFlat: true,
            lineNumbers: true,
            onFileDrop: { content in
                session.userEditedHTML(content)
            },
            droppedFile: droppedFile,
            workspaceSemantic: .structuredEditorTransform
        )
        .workbenchInputDropSupport(text: inputBinding, droppedFile: droppedFile)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("输入")
        // 焦点契约（阶段③ C3）：页面首个输入 = 输入编辑器。
        .workbenchFocusTarget()
    }

    @ViewBuilder
    private var outputPane: some View {
        if let processingText = session.processingText {
            IndexTextConversionProcessingSurface(text: processingText)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityLabel(outputTitle)
        } else {
            switch workspace.showsRenderedPreview ? IndexTextConversionOutputPresentation.markdownPreview : .nativeReadOnlyText {
            case .markdownPreview:
                IndexMarkdownPreviewSurface(
                    text: session.markdown,
                    fillsHeight: true,
                    accessibilityTitle: outputTitle
                )
            default:
                IndexOutputSurface(
                    text: session.markdown,
                    presentation: .plain,
                    lineNumbers: false,
                    fillsHeight: true,
                    embedsFlat: true
                )
                .accessibilityLabel(outputTitle)
            }
        }
    }

    private var inputBinding: Binding<String> {
        Binding(
            get: { session.inputHTML },
            set: { session.userEditedHTML($0) }
        )
    }
}
