import XToolsCore
import SwiftUI
import XToolsDesign

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

    var body: some View {
        IndexArtifactWorkbench(
            title: "Favicon 部署包",
            emptyTitle: "选择图片开始生成 Favicon",
            hasSource: session.sourceImage != nil,
            isProcessing: session.isProcessing,
            diagnostic: session.error,
            canSaveAll: session.package != nil && !session.isProcessing,
            saveAccessibilityLabel: "保存全部五个 Favicon 部署文件",
            saveHelp: "选择文件夹保存五个部署文件",
            onSelect: selectImage,
            onDropURL: receiveImageURL,
            onDropMultiple: rejectMultipleImageDrop,
            onSaveAll: saveAll,
            source: { sourceStrip },
            content: { packageContent }
        )
    }

    private var sourceStrip: some View {
        HStack(alignment: .center, spacing: ToolMetrics.Spacing.md) {
            if let image = session.sourceImage {
                IndexImagePreviewImage(
                    image: image,
                    accessibilityLabel: "Favicon 源图片预览",
                    accessibilityValue: faviconSourceAccessibilityValue,
                    maxDisplayWidth: FaviconPackageMetrics.sourceThumbnailImage,
                    maxDisplayHeight: FaviconPackageMetrics.sourceThumbnailImage
                )
                .frame(
                    width: FaviconPackageMetrics.sourceThumbnailBox,
                    height: FaviconPackageMetrics.sourceThumbnailBox
                )
                .background(
                    ToolTheme.editorBackground,
                    in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                        .strokeBorder(ToolTheme.border, lineWidth: 0.5)
                }
            }

            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xs) {
                Text(session.sourceURL?.lastPathComponent ?? "源图片")
                    .font(ToolTypography.bodyPlain)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(faviconSourceSummary)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: ToolMetrics.Spacing.sm)

            ImageSelectionActionRow(
                hasSource: true,
                selectAccessibilityLabel: "更换 Favicon 源图片",
                replaceAccessibilityLabel: "更换 Favicon 源图片",
                clearAccessibilityLabel: "清除当前 Favicon 图片",
                onSelect: selectImage,
                onClear: clearImage
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var faviconSourceSummary: String {
        guard let metadata = session.source?.metadata else { return "" }
        return ImageOutputPresentation.sourceSummary(metadata)
    }

    private var faviconSourceAccessibilityValue: String {
        guard let metadata = session.source?.metadata else { return "" }
        return "尺寸 \(metadata.pixelWidth)×\(metadata.pixelHeight)，\(metadata.format?.displayName ?? "未知格式")，\(ByteSizeFormatter.format(bytes: metadata.byteCount))"
    }

    @ViewBuilder
    private var packageContent: some View {
        Group {
            if session.isProcessing {
                IndexProgressLabel(message: "正在生成部署包…", layout: .centered)
                    .accessibilityLabel("正在生成 Favicon 部署包")
                    .frame(maxWidth: .infinity, minHeight: FaviconPackageMetrics.statusMinHeight, alignment: .center)
            } else if let package = session.package {
                packageGroups(package)
            } else {
                IndexEmptyState(
                    title: "尚未生成部署包",
                    systemImage: "shippingbox",
                    message: "更换图片后会重新生成。",
                    density: .list
                )
                .frame(maxWidth: .infinity, minHeight: FaviconPackageMetrics.statusMinHeight, alignment: .center)
            }
        }
        .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
    }

    private func packageGroups(_ package: FaviconPackage) -> some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
            if let warning = session.sourceWarning {
                faviconReviewWarning(warning)
            }

            artifactGroup(.browser, package: package)
            artifactGroup(.apple, package: package)
            artifactGroup(.pwa, package: package)
            artifactGroup(.configuration, package: package)
            configurationGroup(package)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
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
        FaviconArtifactRow(artifact: artifact, package: package) {
            Task { @MainActor in
                handleSave(
                    await session.saveArtifact(
                        artifact.id,
                        filePanel: fileInputPanelClient,
                        outputPanel: fileOutputPanelClient
                    ),
                    filename: artifact.filename
                )
            }
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

    private func saveAll() {
        Task { @MainActor in
            guard let package = session.package else { return }
            let outcome = await session.savePackage(
                filePanel: fileInputPanelClient,
                outputPanel: fileOutputPanelClient
            )
            ImageSaveOutcomeToasts.presentCountedOutput(
                outcome,
                savedCount: package.saveableArtifacts.count,
                successNoun: "部署文件",
                partialNoun: "个部署文件",
                toastCenter: toastCenter
            )
        }
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

    private func clearImage() {
        withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
            session.reset()
        }
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
    let onSave: () -> Void

    var body: some View {
        IndexSurfaceRow(horizontalPadding: 10, verticalPadding: 8) {
            HStack(spacing: ToolMetrics.Spacing.md) {
                if !artifact.previewSizes.isEmpty {
                    FaviconPreviewStrip(artifact: artifact, package: package)
                }
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xs) {
                    Text(artifact.filename)
                        .font(ToolTypography.monoLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(artifact.purpose)
                        .font(ToolTypography.bodyPlain)
                        .foregroundStyle(ToolTheme.textSecondary)
                    Text(artifact.details)
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textTertiary)
                }
                Spacer(minLength: ToolMetrics.Spacing.sm)
                IndexIconButton(
                    systemImage: IndexActionSymbol.save,
                    help: "保存 \(artifact.filename)",
                    action: onSave
                )
                .accessibilityLabel("保存 \(artifact.filename)")
            }
        }
    }
}

private struct FaviconPreviewStrip: View {
    let artifact: FaviconArtifact
    let package: FaviconPackage

    var body: some View {
        HStack(alignment: .bottom, spacing: FaviconPackageMetrics.previewSpacing) {
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
        .frame(minWidth: previewStripeWidth, alignment: .leading)
    }

    private var previewStripeWidth: CGFloat {
        artifact.id == .faviconICO
            ? FaviconPackageMetrics.icoPreviewStripeWidth
            : FaviconPackageMetrics.pngPreviewStripeWidth
    }

    private func previewLength(_ size: Int) -> CGFloat {
        min(
            CGFloat(size),
            artifact.id == .faviconICO
                ? FaviconPackageMetrics.icoPreviewMaxLength
                : FaviconPackageMetrics.iconPreviewMaxLength
        )
    }
}

private struct FaviconConfigurationGroup: View {
    let manifestText: String
    let htmlSnippet: String

    var body: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
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
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
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

private enum FaviconPackageMetrics {
    static let sourceThumbnailBox: CGFloat = 64
    static let sourceThumbnailImage: CGFloat = 56
    static let statusMinHeight: CGFloat = 180
    static let previewSpacing: CGFloat = 4
    static let iconPreviewMaxLength: CGFloat = 56
    static let icoPreviewMaxLength: CGFloat = 48
    static let icoPreviewStripeWidth: CGFloat = 106
    static let pngPreviewStripeWidth: CGFloat = 58
}
