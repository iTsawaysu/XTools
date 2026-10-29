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
    @Environment(\.pageAvailableHeight) private var pageAvailableHeight

    @ObservedObject var session: FaviconOutputSetSession
    @State private var isImageDropTargeted = false
    @State private var showsManifest = false

    private var sourceFormatBadge: String? {
        session.source?.metadata.format?.displayName
    }

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
                IndexPanel("Favicon 设置", accessory: {
                    if let badge = sourceFormatBadge {
                        IndexBadge(badge, tone: .neutral, isCapsule: true)
                    }
                }) {
                    ImageWorkflowSettingsPanel(
                        primaryTitle: session.isSaving ? "正在保存…" : "全部保存",
                        primaryIcon: IndexActionSymbol.save,
                        primaryHelp: session.isSaving ? "正在保存全部 Favicon 部署文件" : "保存全部五个 Favicon 部署文件",
                        isPrimaryDisabled: session.package == nil || session.isSaving || session.isProcessing,
                        pinsActionToBottom: true,
                        onPrimary: savePackage,
                        source: { sourceSection },
                        output: { outputSection }
                    )
                }
                .withoutDiagnosticStatusSlot()
                .frame(maxHeight: stagePanelHeight)
            }
        }
    }

    /// 检查器「源文件」区：文件名与元信息一行，更换/清除收在行尾。
    private var sourceSection: some View {
        ImageInspectorSourceRow(
            title: session.sourceURL?.lastPathComponent ?? "—",
            subtitle: faviconSourceSummary.isEmpty ? "—" : faviconSourceSummary,
            replaceAccessibilityLabel: "更换 Favicon 源图片",
            clearAccessibilityLabel: "清除当前 Favicon 图片",
            onReplace: selectImage,
            onClear: {
                withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
                    session.reset()
                }
            }
        )
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

    /// 舞台固定占满首屏，部署包在舞台内滚动；检查器按内容收口、以舞台
    /// 高度为上限，超出时内部滚动并吸底。
    private var stagePanelHeight: CGFloat {
        max(420, pageAvailableHeight - 118)
    }

    private var faviconOutputPanel: some View {
        IndexPanel("Favicon 部署包") {
            ScrollView {
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.base) {
                    IndexModeContent(id: faviconOutputState) { state in
                        if state == 0 {
                            IndexProgressLabel(message: "正在生成部署包…", layout: .centered)
                                .accessibilityLabel("正在生成 Favicon 部署包")
                        } else if state == 1, let package = session.package {
                            if let warning = session.sourceWarning {
                                faviconReviewWarning(warning)
                            }

                            faviconHero(package)

                            VStack(spacing: 2) {
                                ForEach(package.artifacts) { artifact in
                                    faviconArtifactRow(artifact, package: package)
                                }
                            }

                            FaviconConfigurationCodeSurface(
                                title: "HTML 引用片段（假设文件位于站点根目录）",
                                text: package.htmlSnippet,
                                copyTitle: "复制 Favicon HTML 引用片段"
                            )

                            manifestDisclosure(package)
                        }
                    }
                }
                .padding(ToolMetrics.Spacing.panelInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .indexWorkspaceDiagnostic(session.error)
            .indexDropZone(
                isTargeted: $isImageDropTargeted,
                onFile: receiveImageURL,
                onMultipleFiles: rejectMultipleImageDrop
            )
            .toolAnimation(ToolMotion.Preset.diagnostic, value: session.isProcessing)
            .toolAnimation(ToolMotion.Preset.panelReveal, value: session.package != nil)
        }
        .contentInsets(EdgeInsets())
        .verticallyFilling()
        .frame(height: stagePanelHeight)
    }

    /// 结果预览：用包内最大的图标作为成品主视觉。
    private func faviconHero(_ package: FaviconPackage) -> some View {
        let largestSize = package.iconPreviews.map(\.size).max() ?? 180
        return Group {
            if let icon = package.icon(size: largestSize), let image = NSImage(data: icon.data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .background(
                        ToolTheme.editorBackground,
                        in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.card, style: .continuous)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.card, style: .continuous)
                            .strokeBorder(ToolTheme.border, lineWidth: 0.5)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, ToolMetrics.Spacing.xs)
                    .accessibilityLabel("Favicon 图标预览")
            }
        }
    }

    private func manifestDisclosure(_ package: FaviconPackage) -> some View {
        let manifestText = package.artifact(.siteWebManifest)
            .map { String(decoding: $0.data, as: UTF8.self) } ?? ""
        return IndexDisclosure(title: "site.webmanifest 内容", isExpanded: $showsManifest) {
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                HStack {
                    Text("site.webmanifest")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textSecondary)
                    Spacer(minLength: 8)
                    IndexCopyButton(text: manifestText, title: "复制 site.webmanifest 内容", iconOnly: true)
                }
                Text(manifestText)
                    .font(ToolTypography.monoCaption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .textSelection(.enabled)
                    .arrowCursorOnHover()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("site.webmanifest 内容")
                    .accessibilityValue(manifestText)
                Text("该 manifest 只声明图标资源，不包含应用名称、启动地址等完整 PWA 安装配置。")
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .inline()
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

    private func faviconArtifactRow(_ artifact: FaviconArtifact, package: FaviconPackage) -> some View {
        FaviconArtifactRow(
            artifact: artifact,
            package: package,
            isSaving: session.isSaving
        ) {
            Task { @MainActor in handleSave(await session.saveArtifact(artifact.id, filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient), filename: artifact.filename) }
        }
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
        IndexSurfaceRow(horizontalPadding: 10, verticalPadding: 7) {
            HStack(spacing: ToolMetrics.Spacing.md) {
                if let largest = artifact.previewSizes.max(),
                   let icon = package.icon(size: largest),
                   let image = NSImage(data: icon.data) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
                        }
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.filename)
                        .font(ToolTypography.monoLabel)
                        .lineLimit(1)
                    Text("\(artifact.purpose) · \(artifact.details)")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
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

private struct FaviconConfigurationCodeSurface: View {
    let title: String
    let text: String
    let copyTitle: String

    var body: some View {
        IndexSurfaceRow(horizontalPadding: 10, verticalPadding: 8) {
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                IndexFieldHeader(title) {
                    IndexCopyButton(text: text, title: copyTitle, iconOnly: true)
                }
                Text(text)
                    .font(ToolTypography.monoCaption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .textSelection(.enabled)
                    .arrowCursorOnHover()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(title)
                    .accessibilityValue(text)
            }
        }
    }
}
