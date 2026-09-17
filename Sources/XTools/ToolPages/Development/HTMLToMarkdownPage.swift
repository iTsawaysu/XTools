import XToolsCore
import SwiftUI

@MainActor
final class HTMLToMarkdownToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<HTMLToMarkdownToolWorkspaceModel>(toolID: "html-to-markdown") { _ in
        HTMLToMarkdownToolWorkspaceModel()
    }

    let session = HTMLToMarkdownSession()
}

struct IndexHTMLToMarkdownPage: View {
    var body: some View {
        ToolWorkspaceHost(key: HTMLToMarkdownToolWorkspaceModel.key) { workspace, _ in
            IndexHTMLToMarkdownWorkspaceContent(
                session: workspace.session
            )
        }
    }
}

/// Prototype v3 body: the URL fetch rides the workbench toolbar's leading
/// control slot, conversion keeps its session-owned auto-run while typing,
/// and Markdown output keeps the native large-text surface with in-pane
/// processing state; the toolbar ends 清空 · 复制 · 保存 (no format action).
private struct IndexHTMLToMarkdownWorkspaceContent: View {
    @ObservedObject var session: HTMLToMarkdownSession

    var body: some View {
        IndexPage(
            "HTML → Markdown",
            subtitle: "粘贴 HTML 或获取 URL，转换为 Markdown。",
            workspaceSemantic: .structuredEditorTransform
        ) {
            IndexFormatWorkbench(
                inputTitle: "输入",
                outputTitle: "输出",
                input: inputBinding,
                output: session.markdown,
                inputPlaceholder: "<h1>标题</h1>\n<p>段落</p>",
                diagnostic: session.error ?? session.warning,
                diagnosticTone: session.error == nil ? .warning : .error,
                formatAttempt: session.formatAttempt,
                outputLineNumbers: false,
                clearDisabled: !session.canClear,
                onClear: session.clear,
                outputPresentation: .nativeReadOnlyText,
                outputProcessingText: session.processingText,
                showsOutputSave: true,
                outputFileName: "markdown-output.md",
                leadingControl: {
                    urlInput
                        .frame(width: 85)
                    fetchButton
                    IndexIconButton(
                        systemImage: "doc.plaintext",
                        help: "仅提取文章正文",
                        isActive: session.extractArticleOnly
                    ) {
                        session.extractArticleOnly.toggle()
                    }
                }
            )
        }
    }

    private var urlInput: some View {
        IndexTextInput(
            placeholder: "URL...",
            text: $session.urlText,
            height: 26,
            trailingInset: session.urlText.isEmpty ? 11 : 28,
            onSubmit: session.fetchURL
        )
        .disabled(session.isURLProcessing)
        .overlay(alignment: .trailing) {
            if !session.urlText.isEmpty && !session.isURLProcessing {
                Button {
                    session.urlText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textTertiary)
                }
                .buttonStyle(IndexBareButtonStyle())
                .padding(.trailing, 8)
                .help("清空 URL (Esc)")
                .accessibilityLabel("清空 URL 地址")
            }
        }
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
        .buttonStyle(IndexSmallButtonStyle(done: false, framed: true))
        .disabled(fetchDisabled)
        .accessibilityLabel(session.isURLProcessing ? "正在解析网页" : "获取网页")
        .help("获取网页 (↩)")
    }

    private var inputBinding: Binding<String> {
        Binding(
            get: { session.inputHTML },
            set: { session.userEditedHTML($0) }
        )
    }

    private var fetchDisabled: Bool {
        session.isURLProcessing
            || session.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
