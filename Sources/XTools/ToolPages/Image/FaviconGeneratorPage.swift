import XToolsCore
import SwiftUI

struct IndexFaviconGeneratorPage: View {
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
        IndexPage("Favicon 生成器", subtitle: "上传图片，生成可直接放入站点根目录的五文件 Favicon 部署包。", workspaceSemantic: .imagePreviewStage) {
            IndexPanel("上传图片", fillsHeight: session.sourceImage == nil) {
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
                    imageSelectionActions

                    if let image = session.sourceImage {
                        HStack(alignment: .center, spacing: 14) {
                            IndexImagePreviewStage(
                                image: image,
                                accessibilityLabel: "Favicon 源图片预览",
                                accessibilityValue: faviconSourceAccessibilityValue,
                                maxDisplayWidth: 120,
                                maxDisplayHeight: 96,
                                spacing: 0
                            )
                            .frame(width: 140)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.sourceURL?.lastPathComponent ?? "源图片")
                                    .font(ToolTypography.bodyMedium)
                                    .foregroundStyle(ToolTheme.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Text(faviconSourceSummary)
                                    .font(ToolTypography.caption)
                                    .foregroundStyle(ToolTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if session.isProcessing {
                        IndexProgressLabel(message: "正在读取图片…")
                            .foregroundStyle(ToolTheme.textSecondary)
                            .accessibilityLabel("正在读取图片")
                    } else {
                        IndexEmptyState(
                            title: "选择图片开始生成 Favicon",
                            systemImage: "photo.on.rectangle.angled",
                            message: IndexEmptyStateCopy.autoGenerate("图片"),
                            density: .list
                        )
                        .frame(maxWidth: .infinity, minHeight: 128)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ToolMetrics.Spacing.sm)
                .indexDropZone(
                    isTargeted: $isImageDropTargeted,
                    onFile: receiveImageURL,
                    onMultipleFiles: rejectMultipleImageDrop
                )
            }

            Group {
                if session.sourceImage != nil {
                    faviconOutputPanel
                        .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
                }
            }
        }
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
    private var imageSelectionActions: some View {
        HStack(spacing: 8) {
            Button {
                session.selectImage(
                    filePanel: fileInputPanelClient,
                    selectionPublisher: publishSelectedImage
                )
            } label: {
                Label(session.sourceImage == nil ? "选择图片" : "更换图片", systemImage: "photo")
                    .font(ToolTypography.buttonSmall)
            }
            .buttonStyle(IndexSmallButtonStyle())
            .accessibilityLabel(session.sourceImage == nil ? "选择 Favicon 源图片" : "更换 Favicon 源图片")

            if session.sourceImage != nil {
                Button {
                    withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
                        session.reset()
                    }
                } label: {
                    Label("清除图片", systemImage: IndexActionSymbol.removeResource)
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
                .accessibilityLabel("清除当前 Favicon 图片")
                .help("清除当前 Favicon 图片")
            }
        }
    }

    private var faviconOutputPanel: some View {
        IndexPanel("Favicon 部署包") {
            VStack(spacing: 12) {
                if session.isProcessing {
                    IndexProgressLabel(message: "正在生成部署包…")
                        .foregroundStyle(ToolTheme.textSecondary)
                        .accessibilityLabel("正在生成 Favicon 部署包")
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
                } else if let package = session.package {
                    VStack(alignment: .leading, spacing: 14) {
                        if let warning = session.sourceWarning {
                            faviconReviewWarning(warning)
                        }

                        artifactGroup(.browser, package: package)
                        artifactGroup(.apple, package: package)
                        artifactGroup(.pwa, package: package)
                        artifactGroup(.configuration, package: package)
                        configurationGroup(package)
                    }
                    .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
                }
            }
            .indexWorkspaceDiagnostic(session.error)
            .toolAnimation(ToolMotion.Preset.diagnostic, value: session.isProcessing)
            .padding(ToolMetrics.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .toolAnimation(ToolMotion.Preset.panelReveal, value: session.package != nil)
        } accessory: {
            if session.package != nil {
                Button {
                    Task { @MainActor in
                        switch await session.savePackage(filePanel: fileInputPanelClient, outputPanel: fileOutputPanelClient) {
                        case .saved:
                            toastCenter?.show(ToolFeedbackCopy.saved(count: 5, noun: "部署文件"), tone: .success)
                        case let .partiallySaved(savedCount, totalCount):
                            toastCenter?.show(
                                "已保存 \(savedCount)/\(totalCount) 个部署文件。",
                                tone: .warning
                            )
                        case let .failed(message):
                            toastCenter?.show(message, tone: .error)
                        case .cancelled, .blocked:
                            break
                        }
                    }
                } label: {
                    Label("全部保存", systemImage: IndexActionSymbol.save)
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
                .accessibilityLabel("保存全部五个 Favicon 部署文件")
                .help("保存全部 Favicon")
            }
        }
        .verticallyFilling()
    }

    private func faviconReviewWarning(_ warning: String) -> some View {
        IndexSurfaceRow(horizontalPadding: 10, verticalPadding: 8) {
            HStack(alignment: .top, spacing: 8) {
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
        FaviconArtifactRow(artifact: artifact, package: package) {
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
        switch outcome {
        case .saved:
            toastCenter?.show(ToolFeedbackCopy.saved(fileName: filename), tone: .success)
        case let .failed(message):
            toastCenter?.show(message, tone: .error)
        case .cancelled, .blocked, .partiallySaved:
            break
        }
    }

    private func receiveImageURL(_ url: URL) {
        session.receiveImageURL(url, selectionPublisher: publishSelectedImage)
    }

    private func rejectMultipleImageDrop() {
        withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
            session.rejectImageInput(SingleFileDropResolver.multipleFilesDiagnostic)
        }
    }

    private func publishSelectedImage(_ selection: ImageInputSelection, _ publish: () -> Void) {
        withToolAnimation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion) {
            publish()
        }
    }
}

private struct FaviconArtifactRow: View {
    let artifact: FaviconArtifact
    let package: FaviconPackage
    let onSave: () -> Void

    var body: some View {
        IndexSurfaceRow(horizontalPadding: 10, verticalPadding: 8) {
            HStack(spacing: 12) {
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
                    .accessibilityLabel("保存 \(artifact.filename)")
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
