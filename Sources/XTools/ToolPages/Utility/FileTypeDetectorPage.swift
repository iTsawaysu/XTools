import SwiftUI
import XToolsCore
import XToolsDesign

struct IndexFileTypeDetectorPage: View {
    var body: some View {
        ToolWorkspaceHost(key: FileTypeDetectorSession.workspaceKey) { session, _ in
            IndexFileTypeDetectorWorkspaceContent(session: session)
        }
    }
}

private struct IndexFileTypeDetectorWorkspaceContent: View {
    @Environment(\.fileInputPanelClient) private var fileInputPanelClient

    @ObservedObject var session: FileTypeDetectorSession
    @State private var isFileDropTargeted = false

    private var reportPresenceUpdateID: [String] {
        guard let report = session.report else {
            return []
        }
        return [
            report.fileName,
            report.fileExtension,
            report.extensionMIMEType,
            report.contentMIMEType,
            report.resolvedMIMEType,
            report.fileSize,
            report.headerBytes
        ]
    }

    private var rows: [IndexResultKVItem] {
        guard let report = session.report else { return [] }
        return [
            IndexResultKVItem(key: "文件名", value: report.fileName),
            IndexResultKVItem(key: "文件扩展名", value: report.fileExtension),
            IndexResultKVItem(key: "扩展名推断 MIME", value: report.extensionMIMEType),
            IndexResultKVItem(key: "内容签名 MIME", value: report.contentMIMEType),
            IndexResultKVItem(key: "最终判定 MIME", value: report.resolvedMIMEType),
            IndexResultKVItem(key: "文件大小", value: report.fileSize),
            IndexResultKVItem(key: "文件头（前 16 字节）", value: report.headerBytes)
        ]
    }

    var body: some View {
        IndexPage(
            "文件类型探测器",
            subtitle: "上传文件，对比扩展名与文件内容证据。",
            workspaceSemantic: .queryListWorkspace
        ) {
            // 统一壳装配（page-rollout A1）：清空归输入 pane 尾部 ActionBar；
            // 检测 KV 归输出 pane（行内复制由 KV 自带）。拖放区与诊断逐字
            // 保留；双栏需固定高度，语义切 queryList（DateTime 先例授权）。
            WorkbenchSurface(title: nil, shape: .inputOutput) {
                WorkbenchIOPair(
                    leadingTitle: "上传文件",
                    trailingTitle: "检测结果",
                    leadingActions: [
                        .clear(enabled: session.canReset, onPerform: { session.reset() })
                    ]
                ) {
                    fileDropPane
                } trailing: {
                    IndexResultSurface(
                        content: .kv(rows),
                        emptyText: "选择文件后显示检测结果"
                    )
                }
            }
        }
    }

    /// 输入 pane 内容（原 input 槽投影）：选择/拖放面 + 拖放高亮 + 诊断。
    private var fileDropPane: some View {
        VStack(spacing: ToolMetrics.Spacing.md) {
            Button {
                session.selectFile(filePanel: fileInputPanelClient)
            } label: {
                IndexProgressMotionLabel(
                    title: session.isInspecting ? "正在检测…" : "选择文件",
                    systemImage: "doc",
                    isProcessing: session.isInspecting,
                    id: session.isInspecting
                )
                .font(ToolTypography.buttonSmall)
            }
            .buttonStyle(IndexButtonStyle(compact: true))
            .disabled(session.isInspecting)

            if !session.fileName.isEmpty {
                Text(indexWrappingAttributedText(session.fileName, lineBreakMode: .byCharWrapping))
                    .font(ToolTypography.bodyMedium)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            } else {
                Text("也可拖入单个普通文件")
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
            }
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ToolMetrics.Spacing.sm)
        .padding(.vertical, ToolMetrics.Spacing.sm)
        .background(
            isFileDropTargeted ? ToolTheme.selectionFill : Color.clear,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                .strokeBorder(
                    isFileDropTargeted ? ToolTheme.accentBorder : Color.clear,
                    lineWidth: 1
                )
        }
        .indexDropZone(
            isTargeted: $isFileDropTargeted,
            onFile: { session.inspect($0) },
            onMultipleFiles: { session.rejectMultipleFileDrop() }
        )
        .indexWorkspaceDiagnostic(session.error)
    }
}
