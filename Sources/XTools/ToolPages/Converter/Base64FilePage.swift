import XToolsCore
import SwiftUI

private enum Base64FileLayout {
    static let primaryContentMinHeight: CGFloat = 136
    static let decodedPreviewHeight: CGFloat = 118
    static let footerTopSpacing: CGFloat = 11
    static let inlinePreviewCharacterLimit = 512
    static let fileReadProgressDelay: Duration = .milliseconds(150)
}

enum Base64FileWorkbenchLayoutMode: Equatable {
    case stacked
    case horizontal
}

struct Base64FileWorkbenchColumnWidths: Equatable {
    let leading: CGFloat
    let trailing: CGFloat
}

struct Base64FileWorkbenchLayoutPolicy: Equatable {
    static let minimumHorizontalWidth: CGFloat = 900
    static let columnSpacing: CGFloat = 14
    static let leadingWeight: CGFloat = 1
    static let trailingWeight: CGFloat = 1.05
    static let minimumStackedPaneHeight: CGFloat = 280
    static let minimumHorizontalHeight: CGFloat = 398

    func mode(for availableWidth: CGFloat) -> Base64FileWorkbenchLayoutMode {
        availableWidth >= Self.minimumHorizontalWidth ? .horizontal : .stacked
    }

    func columnWidths(for availableWidth: CGFloat) -> Base64FileWorkbenchColumnWidths? {
        guard mode(for: availableWidth) == .horizontal else { return nil }

        let distributableWidth = max(0, availableWidth - Self.columnSpacing)
        let totalWeight = Self.leadingWeight + Self.trailingWeight
        let leading = distributableWidth * Self.leadingWeight / totalWeight
        return Base64FileWorkbenchColumnWidths(
            leading: leading,
            trailing: distributableWidth - leading
        )
    }
}

struct IndexBase64FilePage: View {
    var body: some View {
        ToolWorkspaceHost(key: Base64FileWorkflowSession.workspaceKey) { session, _ in
            IndexBase64FileWorkspaceContent(session: session)
        }
    }
}

private struct IndexBase64FileWorkspaceContent: View {
    @Environment(\.toolToastCenter) private var toastCenter
    @Environment(\.fileInputPanelClient) private var fileInputPanelClient
    @Environment(\.fileOutputPanelClient) private var fileOutputPanelClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var session: Base64FileWorkflowSession
    @State private var isFileDropTargeted = false
    @State private var isShowingFileReadProgress = false

    private var projection: Base64FileWorkspaceProjection {
        Base64FileWorkspaceProjection.make(
            selectedFile: session.selectedFile,
            outputMode: session.outputMode,
            outputPreview: session.outputPreview,
            isReadingFile: session.isReadingFile,
            isPreparingOutput: session.isPreparingOutput,
            fileError: session.fileError,
            reverseInput: session.reverseInput,
            decodedPayload: session.decodedPayload,
            reverseError: session.reverseError,
            isDecoding: session.isDecoding,
            hasPreviewImage: session.previewImage != nil,
            inlinePreviewCharacterLimit: Base64FileLayout.inlinePreviewCharacterLimit,
            previewImageByteLimit: Base64FileWorkflow.previewImageByteLimit
        )
    }

    private func workbenchStatus(_ status: Base64FilePanelStatusProjection) -> Base64FileWorkbenchStatus {
        Base64FileWorkbenchStatus(text: status.text, tone: color(for: status.tone))
    }

    private func color(for tone: Base64FileStatusToneKind) -> Color? {
        switch tone {
        case .none:
            return nil
        case .accent:
            return ToolTheme.accent
        case .success:
            return ToolTheme.success
        case .failure:
            return ToolTheme.error
        }
    }

    private func metadataRows(_ rows: [Base64FileMetadataRowProjection]) -> [(String, String, Color?)] {
        rows.map { ($0.label, $0.value, color(for: $0.tone)) }
    }

    var body: some View {
        IndexPage("Base64 文件", subtitle: "将文件编码为 Base64 / Data URL，或从 Base64 解码回文件。", workspaceSemantic: .base64FileWorkspace) {
            IndexActionBar {
                IndexSegmentedControl(
                    items: [("encode", "编码"), ("decode", "解码")],
                    selection: directionBinding
                )
            }

            if session.direction == .encode {
                forwardWorkflow
            } else {
                reverseWorkflow
            }
        }
    }

    private var directionBinding: Binding<String> {
        Binding(
            get: { session.direction.rawValue },
            set: { value in
                session.changeDirection(to: Base64FileWorkflowDirection(rawValue: value) ?? .encode)
            }
        )
    }

    private var outputModeBinding: Binding<String> {
        Binding(
            get: { session.outputMode.rawValue },
            set: { value in
                session.changeOutputMode(to: Base64Conversion.FileOutputMode(rawValue: value) ?? .dataURL)
            }
        )
    }

    private var reverseInputBinding: Binding<String> {
        Binding(
            get: { session.reverseInput },
            set: { session.updateReverseInput($0) }
        )
    }

    private var forwardWorkflow: some View {
        Base64FileWorkbench {
            sourceFilePanel
        } trailing: {
            encodedOutputPanel
        }
    }

    private var reverseWorkflow: some View {
        Base64FileWorkbench {
            decodeInputPanel
        } trailing: {
            decodedResultPanel
        }
    }

    private var sourceFilePanel: some View {
        IndexPanel("源文件") {
            VStack(alignment: .leading, spacing: 0) {
                filePickerButton
                    .frame(maxHeight: .infinity)
                    .indexWorkspaceDiagnostic(session.fileError)

                Base64FileWorkbenchFooter(
                    status: workbenchStatus(projection.sourceStatus),
                    trailingText: "源文件不会被修改"
                )
                .padding(.top, Base64FileLayout.footerTopSpacing)
            }
        } accessory: {
            if !projection.fileClearDisabled {
                IndexClearButton(isDisabled: projection.fileClearDisabled, iconOnly: true) {
                    session.clearSelection()
                }
            }
        }
        .verticallyFilling()
    }

    private var encodedOutputPanel: some View {
        IndexPanel("编码输出") {
            VStack(alignment: .leading, spacing: 0) {
                encodedOutputPreviewSurface
                    .frame(maxHeight: .infinity)

                Base64FileWorkbenchFooter(
                    status: workbenchStatus(projection.encodedOutputStatus),
                    trailingText: projection.encodedOutputSizeSummary
                )
                .padding(.top, Base64FileLayout.footerTopSpacing)
            }
        } accessory: {
            encodedOutputHeaderActions
        }
        .withoutDiagnosticStatusSlot()
        .verticallyFilling()
    }

    private var encodedOutputPreviewSurface: some View {
        Base64EncodedOutputPreviewSurface(
            text: session.outputPreview?.visibleText ?? "",
            placeholder: session.selectedFile == nil ? "选择文件后生成" : "输出预览将显示在这里",
            isTruncated: session.outputPreview?.isTruncated == true,
            scrollsInternally: projection.encodedOutputUsesBoundedScrolling
        )
        .scrollIndicators(.automatic)
        .frame(
            maxWidth: .infinity,
            minHeight: Base64FileLayout.primaryContentMinHeight,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var decodeInputPanel: some View {
        IndexPanel("Base64 输入") {
            VStack(alignment: .leading, spacing: 0) {
                IndexWorkspaceTextArea(
                    placeholder: "粘贴 Base64 或 Data URL",
                    text: reverseInputBinding,
                    minHeight: Base64FileLayout.primaryContentMinHeight,
                    fillsHeight: true,
                    inputPolicy: .init(
                        maxUTF8Bytes: Base64FileWorkflowSession.editableReverseInputByteLimit,
                        undoLevels: Base64FileWorkflowSession.reverseInputUndoLevels,
                        onRejectedInput: { rejection in
                            session.rejectReverseInputLimit(maxBytes: rejection.maxUTF8Bytes)
                        }
                    ),
                    workspaceSemantic: .base64FileWorkspace
                )
                .indexWorkspaceDiagnostic(session.reverseError)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Base64FileWorkbenchFooter(
                    status: Base64FileWorkbenchStatus(
                        text: "自动检测 Base64 与 Data URL",
                        tone: nil
                    ),
                    trailingText: "支持导入编码文本文件"
                )
                .padding(.top, Base64FileLayout.footerTopSpacing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } accessory: {
            decodeInputHeaderActions
        }
        .verticallyFilling()
    }

    private var decodedResultPanel: some View {
        IndexPanel("解码结果") {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 11) {
                    reversePreview
                    if session.decodedPayload != nil {
                        Base64DecodedMetadataList(rows: metadataRows(projection.reverseRows))
                        decodedFileNameEditor
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Base64FileWorkbenchFooter(
                    status: workbenchStatus(projection.decodedResultStatus),
                    trailingText: session.decodedPayload == nil ? "解码后显示文件信息" : "保存前可修改文件名"
                )
                .padding(.top, Base64FileLayout.footerTopSpacing)
            }
        } accessory: {
            if session.decodedPayload != nil {
                saveDecodedButton
            }
        }
        .verticallyFilling()
    }

    private var filePickerButton: some View {
        Button {
            session.selectSourceFile(filePanel: fileInputPanelClient)
        } label: {
            filePickerContent
                .frame(
                    maxWidth: .infinity,
                    minHeight: Base64FileLayout.primaryContentMinHeight,
                    maxHeight: .infinity
                )
                .padding(.horizontal, 14)
                .background(isFileDropTargeted ? ToolTheme.selectionFill : ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                        .strokeBorder(isFileDropTargeted ? ToolTheme.accentBorder : ToolTheme.strongBorder, style: StrokeStyle(lineWidth: 0.75, dash: [4, 4]))
                }
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: isFileDropTargeted)
        }
        .buttonStyle(IndexBareButtonStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help(filePickerHelp)
        .accessibilityHint(filePickerHelp)
        .disabled(session.isReadingFile)
        .task(id: session.isReadingFile) {
            isShowingFileReadProgress = false
            guard session.isReadingFile else { return }

            do {
                try await Task.sleep(for: Base64FileLayout.fileReadProgressDelay)
            } catch {
                return
            }

            guard !Task.isCancelled, session.isReadingFile else { return }
            isShowingFileReadProgress = true
        }
        .onDisappear {
            isShowingFileReadProgress = false
        }
        .indexDropZone(
            isTargeted: $isFileDropTargeted,
            onFile: { session.readSelectedFile(from: $0) },
            onMultipleFiles: { session.rejectMultipleSourceFileDrop() }
        )
    }

    @ViewBuilder
    private var filePickerContent: some View {
        VStack(spacing: 6) {
            filePickerStatusIcon

            if let selectedFile = session.selectedFile {
                Text(indexWrappingAttributedText(selectedFile.fileName, lineBreakMode: .byCharWrapping))
                    .font(ToolTypography.bodyMedium)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                Text(indexWrappingAttributedText(
                    "\(ByteSizeFormatter.format(bytes: selectedFile.byteCount)) · \(selectedFile.mimeType)",
                    lineBreakMode: .byCharWrapping
                ))
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textTertiary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                Text("点击更换，或拖入另一个 50 MB 以内的文件")
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            } else {
                Text("选择或拖入文件")
                    .font(ToolTypography.bodyMedium)
                    .foregroundStyle(ToolTheme.textPrimary)
                Text("普通文件 · 50 MB 以内")
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
            }
        }
    }

    private var filePickerStatusIcon: some View {
        Group {
            if session.isReadingFile && isShowingFileReadProgress {
                IndexProgressSpinner()
            } else if session.selectedFile != nil {
                Image(systemName: "doc.fill")
                    .font(.system(size: ToolMetrics.IconSize.display, weight: .semibold))
                    .foregroundStyle(ToolTheme.accent)
            } else {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: ToolMetrics.IconSize.display, weight: .semibold))
                    .foregroundStyle(ToolTheme.accent)
            }
        }
        .frame(width: 32, height: 32)
        .indexSurface(.field, fill: ToolTheme.panelBackground, border: ToolTheme.border)
    }

    private var copyFullOutputButton: some View {
        Button {
            session.copyFullOutput {
                toastCenter?.show(ToolFeedbackCopy.copied, tone: .success)
            }
        } label: {
            Base64FileActivityLabel(
                systemImage: IndexActionSymbol.copy,
                isProcessing: session.outputAction == .copying
            )
        }
        .buttonStyle(IndexIconActionButtonStyle())
        .disabled(session.selectedFile == nil || session.outputPreview == nil || session.outputAction != nil || session.isPreparingOutput || session.isReadingFile)
        .help("复制完整输出")
        .accessibilityLabel(session.outputAction == .copying ? "正在复制完整输出" : "复制完整输出")
    }

    private var viewDecodeResultButton: some View {
        Button {
            session.sendCurrentOutputToDecodeResult()
        } label: {
            Base64FileActivityLabel(
                systemImage: "eye",
                isProcessing: session.outputAction == .sending
            )
        }
        .buttonStyle(IndexIconActionButtonStyle())
        .disabled(session.selectedFile == nil || session.outputPreview == nil || session.outputAction != nil || session.isPreparingOutput || session.isReadingFile)
        .help("在解码结果中预览")
        .accessibilityLabel(session.outputAction == .sending ? "正在准备解码预览" : "在解码结果中预览")
    }

    private var saveEncodedOutputButton: some View {
        Button {
            session.saveEncodedOutput(client: .sheet(outputPanel: fileOutputPanelClient)) {
                toastCenter?.show(ToolFeedbackCopy.savedOutput, tone: .success)
            }
        } label: {
            Base64FileActivityLabel(
                systemImage: IndexActionSymbol.save,
                isProcessing: session.outputAction == .saving
            )
        }
        .buttonStyle(IndexIconActionButtonStyle())
        .disabled(session.selectedFile == nil || session.outputPreview == nil || session.outputAction != nil || session.isPreparingOutput || session.isReadingFile)
        .help("保存完整输出")
        .accessibilityLabel(session.outputAction == .saving ? "正在保存完整输出" : "保存完整输出")
    }

    private var encodedOutputHeaderActions: some View {
        HStack(spacing: 4) {
            encodedOutputFormatControls
            if session.selectedFile != nil {
                encodedOutputActionButtons
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var encodedOutputFormatControls: some View {
        HStack(spacing: 4) {
            IndexSegmentedControl(
                items: [("base64", "Base64"), ("dataURL", "Data URL")],
                selection: outputModeBinding,
                density: .compact
            )
                .disabled(session.isReadingFile)
            if session.selectedFile != nil {
                outputLengthLabel
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var encodedOutputActionButtons: some View {
        HStack(spacing: 4) {
            viewDecodeResultButton
            copyFullOutputButton
            saveEncodedOutputButton
        }
    }

    private var decodeInputHeaderActions: some View {
        HStack(spacing: 8) {
            IndexInputCountLabel(count: session.reverseInput.count)
            decodeActionButton
            importEncodedTextFileButton
            clearReverseInputButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var decodeActionButton: some View {
        Button {
            session.decodeReverseInput()
        } label: {
            Base64FileActivityLabel(
                title: "解码",
                systemImage: "arrow.down.doc",
                isProcessing: session.decodeActivity == .manualInput
            )
        }
        .buttonStyle(IndexSmallButtonStyle())
        .disabled(session.reverseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isDecoding)
        .help("解析并解码输入")
        .accessibilityLabel(session.decodeActivity == .manualInput ? "正在解码输入" : "解码输入")
    }

    private var importEncodedTextFileButton: some View {
        Button {
            session.importEncodedTextFile(filePanel: fileInputPanelClient)
        } label: {
            Base64FileActivityLabel(
                title: "导入",
                systemImage: "doc.badge.plus",
                isProcessing: session.decodeActivity == .encodedTextImport
            )
        }
        .buttonStyle(IndexSmallButtonStyle())
        .disabled(session.isDecoding)
        .help("导入编码文本文件")
        .accessibilityLabel(session.decodeActivity == .encodedTextImport ? "正在导入编码文本文件" : "导入编码文本文件")
    }

    private var clearReverseInputButton: some View {
        IndexClearButton(
            isDisabled: projection.reverseClearDisabled,
            title: "清空 Base64 输入和解码结果"
        ) {
            session.clearReverse()
        }
    }

    private var decodedFileNameEditor: some View {
        HStack(spacing: 9) {
            Text("文件名")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
                .fixedSize(horizontal: true, vertical: false)

            IndexTextInput(
                placeholder: "文件名",
                text: $session.outputFileName,
                height: 30
            )
            .frame(maxWidth: .infinity)

            resetOutputFileNameButton
        }
        .disabled(session.decodedPayload == nil)
    }

    private var outputLengthLabel: some View {
        Base64OutputCountBadge(
            characterCount: projection.outputCharacterCount,
            isTruncated: session.outputPreview?.isTruncated == true
        )
    }

    private var filePickerHelp: String {
        projection.filePickerHelp
    }

    private var saveDecodedButton: some View {
        Button {
            session.saveDecodedPayload(client: .sheet(outputPanel: fileOutputPanelClient)) {
                toastCenter?.show(ToolFeedbackCopy.savedFile, tone: .success)
            }
        } label: {
            Base64FileActivityLabel(
                systemImage: IndexActionSymbol.save,
                isProcessing: session.isSavingDecoded
            )
        }
        .buttonStyle(IndexIconActionButtonStyle())
        .disabled(session.decodedPayload == nil || session.isSavingDecoded)
        .help("保存解码后的文件")
        .accessibilityLabel(session.isSavingDecoded ? "正在保存解码后的文件" : "保存解码后的文件")
    }

    private var resetOutputFileNameButton: some View {
        Button { session.resetOutputFileName() } label: {
            Image(systemName: IndexActionSymbol.reset)
                .font(.system(size: ToolMetrics.IconSize.small, weight: .medium))
        }
        .buttonStyle(IndexIconActionButtonStyle())
        .disabled(session.outputFileName == session.defaultOutputFileName)
        .help("重置文件名")
        .accessibilityLabel("重置文件名")
    }

    @ViewBuilder
    private var reversePreview: some View {
        if session.isDecoding {
            Base64ProcessingSurface(
                text: "正在解析输入…",
                minHeight: Base64FileLayout.decodedPreviewHeight
            )
        } else if let previewImage = session.previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .scaledToFit()
                .frame(
                    maxWidth: .infinity,
                    minHeight: Base64FileLayout.decodedPreviewHeight,
                    maxHeight: Base64FileLayout.decodedPreviewHeight
                )
                .padding(10)
                .indexSurface(.field, fill: ToolTheme.editorBackground, border: ToolTheme.border)
                .toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)
                .toolAnimation(ToolMotion.Preset.panelReveal, value: ObjectIdentifier(previewImage).hashValue)
        } else if let decodedPreviewNoticeText = projection.decodedPreviewNoticeText {
            Base64DecodedNoticeSurface(
                text: decodedPreviewNoticeText,
                systemImage: "photo",
                minHeight: Base64FileLayout.decodedPreviewHeight
            )
        } else if session.decodedPayload != nil {
            Base64DecodedFilePreview(
                fileName: session.outputFileName,
                detail: projection.decodedPreviewDetail ?? ""
            )
        } else {
            Base64DecodedFilePreview(
                fileName: "解码后显示文件预览",
                detail: "支持 Base64 与 Data URL"
            )
        }
    }
}

private struct Base64FileWorkbench<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing
    private let policy = Base64FileWorkbenchLayoutPolicy()

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        // GeometryReader owns the residual IndexPage height. Horizontal mode fills
        // that band (min 398pt); stacked mode keeps one outer ScrollView so both
        // complete panes remain reachable. ScrollView alone cannot propose a finite
        // height, which previously pinned wide panes to the 398pt floor and left a
        // large empty slab under the workbench.
        GeometryReader { proxy in
            let isHorizontal = policy.mode(for: proxy.size.width) == .horizontal
            let horizontalHeight = max(
                Base64FileWorkbenchLayoutPolicy.minimumHorizontalHeight,
                proxy.size.height
            )

            Group {
                if isHorizontal {
                    workbenchLayout
                        .frame(
                            maxWidth: .infinity,
                            minHeight: horizontalHeight,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )
                } else {
                    ScrollView {
                        workbenchLayout
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.automatic)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var workbenchLayout: some View {
        Base64FileWorkbenchLayout() {
            Base64FileWorkbenchPane {
                leading
            }
            Base64FileWorkbenchPane {
                trailing
            }
        }
    }
}

private struct Base64FileWorkbenchPane<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct Base64FileWorkbenchLayout: Layout {
    private let policy = Base64FileWorkbenchLayoutPolicy()

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = resolvedWidth(proposal: proposal, subviews: subviews)

        if policy.mode(for: availableWidth) == .horizontal, subviews.count == 2 {
            // Prefer the container's finite height (GeometryReader / fill parent).
            // Fall back to the approved 398pt minimum when the proposal is unbounded.
            let proposedHeight = proposal.height.flatMap { $0.isFinite ? $0 : nil }
            return CGSize(
                width: availableWidth,
                height: max(
                    Base64FileWorkbenchLayoutPolicy.minimumHorizontalHeight,
                    proposedHeight ?? Base64FileWorkbenchLayoutPolicy.minimumHorizontalHeight
                )
            )
        }

        let sizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: availableWidth, height: nil))
        }
        let contentHeight = sizes
            .map { max(Base64FileWorkbenchLayoutPolicy.minimumStackedPaneHeight, $0.height) }
            .reduce(0, +)
        let spacingHeight = Base64FileWorkbenchLayoutPolicy.columnSpacing
            * CGFloat(max(0, sizes.count - 1))
        return CGSize(
            width: availableWidth,
            height: contentHeight + spacingHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        if let widths = policy.columnWidths(for: bounds.width), subviews.count == 2 {
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: widths.leading, height: bounds.height)
            )
            subviews[1].place(
                at: CGPoint(
                    x: bounds.minX + widths.leading + Base64FileWorkbenchLayoutPolicy.columnSpacing,
                    y: bounds.minY
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: widths.trailing, height: bounds.height)
            )
            return
        }

        var y = bounds.minY
        for subview in subviews {
            let size = subview.sizeThatFits(
                ProposedViewSize(width: bounds.width, height: nil)
            )
            let paneHeight = max(
                Base64FileWorkbenchLayoutPolicy.minimumStackedPaneHeight,
                size.height
            )
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: paneHeight)
            )
            y += paneHeight + Base64FileWorkbenchLayoutPolicy.columnSpacing
        }
    }

    private func resolvedWidth(proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite {
            return max(0, width)
        }

        return subviews
            .map { $0.sizeThatFits(.unspecified).width }
            .max() ?? 0
    }
}

private struct Base64FileWorkbenchStatus {
    let text: String
    let tone: Color?
}

private struct Base64FileWorkbenchFooter: View {
    let status: Base64FileWorkbenchStatus
    let trailingText: String

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                if let tone = status.tone {
                    Circle()
                        .fill(tone)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(status.text)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(trailingText)
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.trailing)
        }
        .font(ToolTypography.caption)
        .foregroundStyle(ToolTheme.textTertiary)
        .frame(maxWidth: .infinity, minHeight: 16)
        .accessibilityElement(children: .combine)
    }
}

private struct Base64EncodedOutputPreviewSurface: View {
    let text: String
    let placeholder: String
    let isTruncated: Bool
    let scrollsInternally: Bool

    var body: some View {
        Group {
            if scrollsInternally {
                ScrollView {
                    previewBody
                }
            } else {
                previewBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .indexSurface(.field, fill: ToolTheme.editorBackground, border: ToolTheme.border)
    }

    private var previewBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if text.isEmpty {
                IndexEmptyState(
                    title: "等待输入",
                    systemImage: "doc.fill",
                    message: placeholder
                )
            } else {
                Text(indexWrappingAttributedText(text, lineBreakMode: .byCharWrapping))
                    .foregroundStyle(ToolTheme.textSecondary)
                    .textSelection(.enabled)

                if isTruncated {
                    Text("这里只显示有界预览，复制和保存会读取完整输出。")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textTertiary)
                }
            }
        }
        .font(ToolTypography.monoCaption)
        .lineSpacing(3)
        .frame(
            maxWidth: .infinity,
            minHeight: Base64FileLayout.primaryContentMinHeight,
            alignment: .topLeading
        )
        .padding(ToolMetrics.Spacing.md)
    }
}

private struct Base64DecodedMetadataList: View {
    let rows: [(String, String, Color?)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(row.0)
                        .foregroundStyle(ToolTheme.textTertiary)
                    Spacer(minLength: 8)
                    Text(indexWrappingAttributedText(row.1, lineBreakMode: .byCharWrapping))
                        .fontWeight(.medium)
                        .foregroundStyle(row.2 ?? ToolTheme.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .font(ToolTypography.caption)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 34)

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(ToolTheme.border)
                        .frame(height: 0.5)
                }
            }
        }
        .indexSurface(.field, fill: ToolTheme.editorBackground, border: ToolTheme.border)
    }
}

private struct Base64DecodedFilePreview: View {
    let fileName: String
    let detail: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "doc.fill")
                .font(.system(size: ToolMetrics.IconSize.display, weight: .medium))
                .foregroundStyle(ToolTheme.accent)
                .frame(width: 32, height: 32)
        .indexSurface(.field, fill: ToolTheme.panelBackground, border: ToolTheme.border)

            Text(indexWrappingAttributedText(fileName, lineBreakMode: .byCharWrapping))
                .font(ToolTypography.bodyMedium)
                .foregroundStyle(ToolTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            Text(detail)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .frame(
            maxWidth: .infinity,
            minHeight: Base64FileLayout.decodedPreviewHeight,
            alignment: .center
        )
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(ToolTheme.strongBorder, style: StrokeStyle(lineWidth: 0.75, dash: [4, 4]))
        }
    }
}

private struct Base64OutputCountBadge: View {
    let characterCount: Int
    let isTruncated: Bool

    private var text: String {
        "\(characterCount) 字符" + (isTruncated ? " · 截断" : "")
    }

    private var accessibilityText: String {
        if isTruncated {
            return "输出共 \(characterCount) 字符，当前为截断预览，复制或保存会使用完整输出"
        }
        return "输出共 \(characterCount) 字符"
    }

    var body: some View {
        Text(text)
            .font(ToolTypography.monoCaption)
            .foregroundStyle(isTruncated ? ToolTheme.warning : ToolTheme.textSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 5)
            .frame(height: 20)
            .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                    .strokeBorder(isTruncated ? ToolTheme.warning.opacity(0.22) : ToolTheme.border, lineWidth: 0.5)
            }
            .help(isTruncated ? "当前只显示前后片段，复制或保存会使用完整输出" : "输出字符数")
            .accessibilityLabel(accessibilityText)
    }
}

private struct Base64FileActivityLabel: View {
    var title: String?
    let systemImage: String
    let isProcessing: Bool

    init(
        title: String? = nil,
        systemImage: String,
        isProcessing: Bool
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isProcessing = isProcessing
    }

    var body: some View {
        IndexProgressMotionLabel(
            title: title ?? "",
            systemImage: systemImage,
            isProcessing: isProcessing,
            id: isProcessing
        )
    }
}

private struct Base64ProcessingSurface: View {
    let text: String
    var minHeight: CGFloat = 74

    var body: some View {
        IndexProgressLabel(message: text)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
            .indexSurface(.field, fill: ToolTheme.editorBackground, border: ToolTheme.border)
            .toolAnimation(ToolMotion.Preset.textSwap, value: text)
    }
}

private struct Base64DecodedNoticeSurface: View {
    let text: String
    let systemImage: String
    var minHeight: CGFloat = 74

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: ToolMetrics.IconSize.large, weight: .semibold))
                .foregroundStyle(ToolTheme.warning)
                .frame(width: 18, height: 18)
            Text(text)
                .font(ToolTypography.bodyPlain)
                .foregroundStyle(ToolTheme.textSecondary)
                .toolMotionTextSwap(id: text)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
        .indexSurface(.field, fill: ToolTheme.editorBackground, border: ToolTheme.border)
        .toolAnimation(ToolMotion.Preset.textSwap, value: text)
    }
}
