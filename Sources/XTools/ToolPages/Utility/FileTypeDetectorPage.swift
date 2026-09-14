import SwiftUI
import XToolsCore

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

    var body: some View {
        IndexPage("文件类型探测器", subtitle: "上传文件，对比扩展名与文件内容证据。", layout: .scroll) {
            IndexPanel("上传文件") {
                VStack(spacing: 12) {
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
                    .buttonStyle(IndexSmallButtonStyle())
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
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
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
            } accessory: {
                IndexClearButton(
                    isDisabled: !session.canReset,
                    action: session.reset
                )
            }

            IndexPanel("检测结果") {
                VStack(alignment: .leading, spacing: 12) {
                    IndexWorkspaceResultSurface(workspaceSemantic: .naturalHeightShortResultPanel) {
                        IndexResultPresence(
                            value: session.report,
                            updateID: reportPresenceUpdateID,
                            motion: .immediate
                        ) { report in
                            VStack(alignment: .leading, spacing: 16) {
                                IndexKVRow(key: "文件名", value: report.fileName, valueLineBreakMode: .byCharWrapping, valueMotion: .immediate)
                                IndexKVRow(key: "文件扩展名", value: report.fileExtension, valueLineBreakMode: .byCharWrapping, valueMotion: .immediate)
                                IndexKVRow(key: "扩展名推断 MIME", value: report.extensionMIMEType, valueLineBreakMode: .byCharWrapping, valueMotion: .immediate)
                                IndexKVRow(key: "内容签名 MIME", value: report.contentMIMEType, valueLineBreakMode: .byCharWrapping, valueMotion: .immediate)
                                IndexKVRow(key: "最终判定 MIME", value: report.resolvedMIMEType, valueLineBreakMode: .byCharWrapping, valueMotion: .immediate)
                                IndexKVRow(key: "文件大小", value: report.fileSize, valueLineBreakMode: .byCharWrapping, valueMotion: .immediate)
                                IndexKVRow(key: "文件头（前 16 字节）", value: report.headerBytes, valueLineBreakMode: .byCharWrapping, valueMotion: .immediate)
                            }
                            .padding(ToolMetrics.Spacing.sm)
                        } empty: {
                            IndexEmptyState(
                                title: "尚未检测文件",
                                systemImage: "photo.on.rectangle.angled",
                                message: "选择文件后显示检测结果"
                            )
                        }
                    }
                    .indexWorkspaceDiagnostic(session.warning, tone: .warning)
                }
            }
        }
    }
}
