import XToolsCore
import SwiftUI

struct IndexImageFaviconSegment: View {
    var body: some View {
        ToolWorkspaceHost(key: FaviconOutputSetSession.workspaceKey) { session, _ in
            IndexFaviconGeneratorWorkspaceContent(session: session)
        }
    }
}

private struct IndexFaviconGeneratorWorkspaceContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.fileInputPanelClient) private var fileInputPanelClient
    @Environment(\.fileOutputPanelClient) private var fileOutputPanelClient
    @Environment(\.toolToastCenter) private var toastCenter

    @ObservedObject var session: FaviconOutputSetSession
    @State private var isImageDropTargeted = false

    var body: some View {
        if session.sourceImage == nil {
            ImageUploadEmptyPanel(
                isDropTargeted: $isImageDropTargeted,
                isProcessing: session.isProcessing,
                diagnostic: session.error,
                emptyStateTitle: "选择图片开始生成 Favicon",
                onSelect: selectImage,
                onDropFile: receiveImageURL,
                onDropMultipleFiles: rejectMultipleImageDrop
            )
        } else {
            IndexPairLayout(
                collapseWidth: ToolMetrics.Breakpoint.pairCollapseImageTools,
                fillsHeight: false,
                equalizesHeight: false,
                trailingWidth: 245
            ) {
                faviconOutputPanel
            } trailing: {
                IndexPanel("检查器") {
                    ImageWorkflowSettingsPanel(
                        primaryTitle: session.isSaving ? "正在保存…" : "全部保存",
                        primaryIcon: IndexActionSymbol.save,
                        primaryHelp: session.isSaving ? "正在保存全部 Favicon 部署文件" : "保存全部五个 Favicon 部署文件",
                        isPrimaryDisabled: session.package == nil || session.isSaving || session.isProcessing,
                        onPrimary: savePackage,
                        source: { sourceSection },
                        output: { outputSection }
                    )
                }
                .withoutDiagnosticStatusSlot()
            }
        }
    }

    /// 检查器「源文件」区：文件名、尺寸与格式，以及更换/清除动作。
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(session.sourceURL?.lastPathComponent ?? "—")
                .font(ToolTypography.bodyMedium)
                .foregroundStyle(ToolTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(faviconSourceSummary.isEmpty ? "—" : faviconSourceSummary)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
                .lineLimit(1)
                .padding(.top, 2)

            imageSelectionActions
                .padding(.top, ToolMetrics.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 检查器「输出」区：部署文件数量与总大小。
    private var outputSection: some View {
        VStack(spacing: 0) {
            ImageInspectorFactRow(label: "部署文件", value: packageFileCountText)
            ImageInspectorFactRow(label: "总大小", value: packageTotalSizeText)
        }
    }

    private var packageFileCountText: String {
        guard let package = session.package else { return "—" }
        return "\(package.saveableArtifacts.count) 个"
    }

    private var packageTotalSizeText: String {
        guard let package = session.package else { return "—" }
        let total = package.saveableArtifacts.reduce(0) { $0 + $1.data.count }
        return ByteSizeFormatter.format(bytes: total)
    }

    private func savePackage() {
        Task { @MainActor in
            guard let package = session.package else { return }
            let outcome = await session.savePackage(filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient)
            ImageSaveOutcomeToasts.presentCountedOutput(
                outcome,
                savedCount: package.saveableArtifacts.count,
                successNoun: "部署文件",
                partialNoun: "个部署文件",
                toastCenter: toastCenter
            )
        }
    }

    private var faviconOutputState: Int {
        if session.isProcessing { return 0 }
        return session.package == nil ? 2 : 1
    }

    private var faviconSourceSummary: String {
        guard let metadata = session.source?.metadata else { return "" }
        return ImageOutputPresentation.sourceSummary(metadata)
    }

    private var imageSelectionActions: ImageSelectionActionRow {
        ImageSelectionActionRow(
            hasSource: session.sourceImage != nil,
            selectAccessibilityLabel: "选择 Favicon 源图片",
            replaceAccessibilityLabel: "更换 Favicon 源图片",
            clearAccessibilityLabel: "清除当前 Favicon 图片",
            onSelect: selectImage,
            onClear: {
                withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
                    session.reset()
                }
            },
            framed: true
        )
    }

    private var faviconOutputPanel: some View {
        IndexPanel("Favicon 部署包") {
            VStack(spacing: ToolMetrics.Spacing.md) {
                IndexModeContent(id: faviconOutputState) { state in
                    if state == 0 {
                        IndexProgressLabel(message: "正在生成部署包…", layout: .centered)
                            .accessibilityLabel("正在生成 Favicon 部署包")
                    } else if state == 1, let package = session.package {
                        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.base) {
                            if let warning = session.sourceWarning {
                                faviconReviewWarning(warning)
                            }

                            artifactGroup(.browser, package: package)
                            artifactGroup(.apple, package: package)
                            artifactGroup(.pwa, package: package)
                            artifactGroup(.configuration, package: package)
                            configurationGroup(package)
                        }
                    }
                }
            }
            .indexWorkspaceDiagnostic(session.error)
            .indexDropZone(
                isTargeted: $isImageDropTargeted,
                onFile: receiveImageURL,
                onMultipleFiles: rejectMultipleImageDrop
            )
            .toolAnimation(ToolMotion.Preset.diagnostic, value: session.isProcessing)
            .padding(ToolMetrics.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .toolAnimation(ToolMotion.Preset.panelReveal, value: session.package != nil)
        }
        .verticallyFilling()
    }

    private func faviconReviewWarning(_ warning: String) -> some View {
        IndexSurfaceRow(horizontalPadding: 10, verticalPadding: 8) {
            HStack(alignment: .top, spacing: ToolMetrics.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ToolTheme.warning)
                Text(warning)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Favicon 外观检查提示")
            .accessibilityValue(warning)
        }
    }

    @ViewBuilder
    private func artifactGroup(_ group: FaviconArtifactGroup, package: FaviconPackage) -> some View {
        let artifacts = package.artifacts.filter { $0.group == group }
        if !artifacts.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(group.displayName)
                    .font(ToolTypography.sectionTitle)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(artifacts) { artifact in
                    faviconArtifactRow(artifact, package: package)
                }
            }
        }
    }

    private func faviconArtifactRow(_ artifact: FaviconArtifact, package: FaviconPackage) -> some View {
        FaviconArtifactRow(
            artifact: artifact,
            package: package,
            isSaving: session.isSaving
        ) {
            Task { @MainActor in handleSave(await session.saveArtifact(artifact.id, filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient), filename: artifact.filename) }
        }
    }

    private func configurationGroup(_ package: FaviconPackage) -> some View {
        let manifestText = package.artifact(.siteWebManifest)
            .map { String(decoding: $0.data, as: UTF8.self) } ?? ""
        return FaviconConfigurationGroup(
            manifestText: manifestText,
            htmlSnippet: package.htmlSnippet
        )
    }

    private func handleSave(_ outcome: ImageSaveOutcome, filename: String) {
        ImageSaveOutcomeToasts.presentSingleOutput(outcome, fileName: filename, toastCenter: toastCenter)
    }

    private var uploadInteractions: ImageUploadInteractions {
        ImageUploadInteractions(reduceMotion: reduceMotion)
    }

    private func selectImage() {
        session.selectImage(
            filePanel: fileInputPanelClient,
            selectionPublisher: uploadInteractions.publishSelection
        )
    }

    private func receiveImageURL(_ url: URL) {
        session.receiveImageURL(url, selectionPublisher: uploadInteractions.publishSelection)
    }

    private func rejectMultipleImageDrop() {
        uploadInteractions.rejectMultipleDrop {
            session.rejectImageInput(SingleFileDropResolver.multipleFilesDiagnostic)
        }
    }
}

private struct FaviconArtifactRow: View {
    let artifact: FaviconArtifact
    let package: FaviconPackage
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        IndexSurfaceRow(horizontalPadding: 10, verticalPadding: 8) {
            HStack(spacing: ToolMetrics.Spacing.md) {
                if !artifact.previewSizes.isEmpty {
                    FaviconPreviewStrip(artifact: artifact, package: package)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(artifact.filename)
                        .font(ToolTypography.monoLabel)
                    Text(artifact.purpose)
                        .font(ToolTypography.bodyPlain)
                        .foregroundStyle(ToolTheme.textSecondary)
                    Text(artifact.details)
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textTertiary)
                }
                Spacer(minLength: 8)
                IndexIconButton(
                    systemImage: IndexActionSymbol.save,
                    help: "保存 \(artifact.filename)",
                    action: onSave
                )
                    .disabled(isSaving)
                    .accessibilityLabel(isSaving ? "正在保存 \(artifact.filename)" : "保存 \(artifact.filename)")
            }
        }
    }
}

private struct FaviconPreviewStrip: View {
    let artifact: FaviconArtifact
    let package: FaviconPackage

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(artifact.previewSizes, id: \.self) { size in
                if let icon = package.icon(size: size), let image = NSImage(data: icon.data) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: previewLength(size), height: previewLength(size))
                        .overlay {
                            Rectangle().strokeBorder(ToolTheme.border, lineWidth: 0.5)
                        }
                        .accessibilityLabel("\(artifact.filename) 的 \(size)×\(size) 预览")
                }
            }
        }
        .frame(minWidth: artifact.id == .faviconICO ? 106 : 58, alignment: .leading)
    }

    private func previewLength(_ size: Int) -> CGFloat {
        min(CGFloat(size), artifact.id == .faviconICO ? 48 : 56)
    }
}

private struct FaviconConfigurationGroup: View {
    let manifestText: String
    let htmlSnippet: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            FaviconConfigurationCodeSurface(
                title: "site.webmanifest 内容",
                text: manifestText,
                copyTitle: "复制 site.webmanifest 内容"
            )
            FaviconConfigurationCodeSurface(
                title: "HTML 引用片段（假设文件位于站点根目录）",
                text: htmlSnippet,
                copyTitle: "复制 Favicon HTML 引用片段"
            )
            Text("该 manifest 只声明图标资源，不包含应用名称、启动地址等完整 PWA 安装配置。")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
        }
    }
}

private struct FaviconConfigurationCodeSurface: View {
    let title: String
    let text: String
    let copyTitle: String

    var body: some View {
        IndexSurfaceRow(horizontalPadding: 10, verticalPadding: 8) {
            VStack(alignment: .leading, spacing: 7) {
                IndexFieldHeader(title) {
                    IndexCopyButton(text: text, title: copyTitle, iconOnly: true)
                }
                Text(text)
                    .font(ToolTypography.monoCaption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(title)
                    .accessibilityValue(text)
            }
        }
    }
}
