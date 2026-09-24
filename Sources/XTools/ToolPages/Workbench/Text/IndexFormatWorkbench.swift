import SwiftUI
import UniformTypeIdentifiers
import XToolsCore

/// Prototype v3 (Clay 收敛 + 轻量过渡) structured formatter workbench.
///
/// One framed panel carries the whole editor-transform workspace: a single
/// toolbar owns both I/O identities — the STDIN capsule, input label, and a
/// leading control slot on the left, a centered STDOUT cluster with the
/// inline diagnostic (anchored to the cluster so it never shifts), and the
/// framed copy/clear actions plus the primary format action on the right —
/// above a fixed two-pane code split with line-number gutters. A failed
/// format tints the panel outline, rings it in the error tone, and shakes
/// once per attempt; a warning shows the inline diagnostic only.
struct IndexFormatWorkbench<LeadingControl: View>: View {
    let inputTitle: String
    let outputTitle: String
    @Binding var input: String
    let output: String
    var inputPlaceholder = ""
    var diagnostic: String? = nil
    var diagnosticTone: ToolFeedbackTone = .error
    var diagnosticDetail: FormatDiagnostic? = nil
    /// Bump per format attempt so a repeated identical error re-shakes.
    var formatAttempt = 0
    var outputLineNumbers = true
    var outputSyntax: IndexSyntaxKind? = nil
    var outputPlaceholder = IndexEmptyStateCopy.outputWillShowHere
    var actionTitle = "格式化"
    var actionHint = "⌘↩"
    var autoFocus = true
    var isRunning = false
    var isOutputFresh = true
    var clearDisabled = false
    /// Pages that convert while the user types (HTML → Markdown) pass nil and
    /// the primary format action disappears; the toolbar then ends at 清空.
    var onFormat: (() -> Void)? = nil
    let onClear: () -> Void
    /// Markdown-scale output opts into the native read-only text surface and
    /// an in-pane processing state instead of the standard output surface.
    var outputPresentation = IndexTextConversionOutputPresentation.standard
    var outputProcessingText: String? = nil
    var showsOutputSave = false
    var outputFileName = "output.txt"
    @ViewBuilder var leadingControl: () -> LeadingControl
    /// Optional accessory row pinned to the top of the input pane (e.g. a
    /// URL fetch bar); the editor keeps the remaining height.
    var inputHeader: (() -> AnyView)? = nil
    var outputControl: (() -> AnyView)? = nil
    var workspaceSemantic: IndexWorkspaceSemantic = .structuredEditorTransform

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var droppedFile = IndexDroppedTextFile()

    init(
        inputTitle: String,
        outputTitle: String,
        input: Binding<String>,
        output: String,
        inputPlaceholder: String = "",
        diagnostic: String? = nil,
        diagnosticTone: ToolFeedbackTone = .error,
        diagnosticDetail: FormatDiagnostic? = nil,
        formatAttempt: Int = 0,
        outputLineNumbers: Bool = true,
        outputSyntax: IndexSyntaxKind? = nil,
        outputPlaceholder: String = IndexEmptyStateCopy.outputWillShowHere,
        actionTitle: String = "格式化",
        actionHint: String = "⌘↩",
        autoFocus: Bool = true,
        isRunning: Bool = false,
        isOutputFresh: Bool = true,
        clearDisabled: Bool = false,
        onFormat: (() -> Void)? = nil,
        onClear: @escaping () -> Void,
        outputPresentation: IndexTextConversionOutputPresentation = .standard,
        outputProcessingText: String? = nil,
        showsOutputSave: Bool = false,
        outputFileName: String = "output.txt",
        @ViewBuilder leadingControl: @escaping () -> LeadingControl,
        inputHeader: (() -> AnyView)? = nil,
        workspaceSemantic: IndexWorkspaceSemantic = .structuredEditorTransform
    ) {
        self.init(
            inputTitle: inputTitle,
            outputTitle: outputTitle,
            input: input,
            output: output,
            inputPlaceholder: inputPlaceholder,
            diagnostic: diagnostic,
            diagnosticTone: diagnosticTone,
            diagnosticDetail: diagnosticDetail,
            formatAttempt: formatAttempt,
            outputLineNumbers: outputLineNumbers,
            outputSyntax: outputSyntax,
            outputPlaceholder: outputPlaceholder,
            actionTitle: actionTitle,
            actionHint: actionHint,
            autoFocus: autoFocus,
            isRunning: isRunning,
            isOutputFresh: isOutputFresh,
            clearDisabled: clearDisabled,
            onFormat: onFormat,
            onClear: onClear,
            outputPresentation: outputPresentation,
            outputProcessingText: outputProcessingText,
            showsOutputSave: showsOutputSave,
            outputFileName: outputFileName,
            leadingControl: leadingControl,
            inputHeader: inputHeader,
            outputControlWrapper: nil,
            workspaceSemantic: workspaceSemantic
        )
    }

    init<Output: View>(
        inputTitle: String,
        outputTitle: String,
        input: Binding<String>,
        output: String,
        inputPlaceholder: String = "",
        diagnostic: String? = nil,
        diagnosticTone: ToolFeedbackTone = .error,
        diagnosticDetail: FormatDiagnostic? = nil,
        formatAttempt: Int = 0,
        outputLineNumbers: Bool = true,
        outputSyntax: IndexSyntaxKind? = nil,
        outputPlaceholder: String = IndexEmptyStateCopy.outputWillShowHere,
        actionTitle: String = "格式化",
        actionHint: String = "⌘↩",
        autoFocus: Bool = true,
        isRunning: Bool = false,
        isOutputFresh: Bool = true,
        clearDisabled: Bool = false,
        onFormat: (() -> Void)? = nil,
        onClear: @escaping () -> Void,
        outputPresentation: IndexTextConversionOutputPresentation = .standard,
        outputProcessingText: String? = nil,
        showsOutputSave: Bool = false,
        outputFileName: String = "output.txt",
        @ViewBuilder leadingControl: @escaping () -> LeadingControl,
        inputHeader: (() -> AnyView)? = nil,
        @ViewBuilder outputControl: @escaping () -> Output,
        workspaceSemantic: IndexWorkspaceSemantic = .structuredEditorTransform
    ) {
        self.init(
            inputTitle: inputTitle,
            outputTitle: outputTitle,
            input: input,
            output: output,
            inputPlaceholder: inputPlaceholder,
            diagnostic: diagnostic,
            diagnosticTone: diagnosticTone,
            diagnosticDetail: diagnosticDetail,
            formatAttempt: formatAttempt,
            outputLineNumbers: outputLineNumbers,
            outputSyntax: outputSyntax,
            outputPlaceholder: outputPlaceholder,
            actionTitle: actionTitle,
            actionHint: actionHint,
            autoFocus: autoFocus,
            isRunning: isRunning,
            isOutputFresh: isOutputFresh,
            clearDisabled: clearDisabled,
            onFormat: onFormat,
            onClear: onClear,
            outputPresentation: outputPresentation,
            outputProcessingText: outputProcessingText,
            showsOutputSave: showsOutputSave,
            outputFileName: outputFileName,
            leadingControl: leadingControl,
            inputHeader: inputHeader,
            outputControlWrapper: { AnyView(outputControl()) },
            workspaceSemantic: workspaceSemantic
        )
    }

    private init(
        inputTitle: String,
        outputTitle: String,
        input: Binding<String>,
        output: String,
        inputPlaceholder: String,
        diagnostic: String?,
        diagnosticTone: ToolFeedbackTone,
        diagnosticDetail: FormatDiagnostic?,
        formatAttempt: Int,
        outputLineNumbers: Bool,
        outputSyntax: IndexSyntaxKind?,
        outputPlaceholder: String,
        actionTitle: String,
        actionHint: String,
        autoFocus: Bool,
        isRunning: Bool,
        isOutputFresh: Bool,
        clearDisabled: Bool,
        onFormat: (() -> Void)?,
        onClear: @escaping () -> Void,
        outputPresentation: IndexTextConversionOutputPresentation,
        outputProcessingText: String?,
        showsOutputSave: Bool,
        outputFileName: String,
        @ViewBuilder leadingControl: @escaping () -> LeadingControl,
        inputHeader: (() -> AnyView)?,
        outputControlWrapper: (() -> AnyView)?,
        workspaceSemantic: IndexWorkspaceSemantic
    ) {
        self.inputTitle = inputTitle
        self.outputTitle = outputTitle
        self._input = input
        self.output = output
        self.inputPlaceholder = inputPlaceholder
        self.diagnostic = diagnostic
        self.diagnosticTone = diagnosticTone
        self.diagnosticDetail = diagnosticDetail
        self.formatAttempt = formatAttempt
        self.outputLineNumbers = outputLineNumbers
        self.outputSyntax = outputSyntax
        self.outputPlaceholder = outputPlaceholder
        self.actionTitle = actionTitle
        self.actionHint = actionHint
        self.autoFocus = autoFocus
        self.isRunning = isRunning
        self.isOutputFresh = isOutputFresh
        self.clearDisabled = clearDisabled
        self.onFormat = onFormat
        self.onClear = onClear
        self.outputPresentation = outputPresentation
        self.outputProcessingText = outputProcessingText
        self.showsOutputSave = showsOutputSave
        self.outputFileName = outputFileName
        self.leadingControl = leadingControl
        self.inputHeader = inputHeader
        self.outputControl = outputControlWrapper
        self.workspaceSemantic = workspaceSemantic
    }

    private var showsErrorState: Bool {
        !isRunning && isOutputFresh && diagnostic != nil && diagnosticTone == .error
    }

    private var hasDiagnostic: Bool {
        !isRunning && isOutputFresh && diagnostic != nil
    }

    private var hasStaleResult: Bool {
        !isOutputFresh && (!output.isEmpty || diagnostic != nil)
    }

    private var runningStatusText: String {
        actionTitle == "转换" ? "正在转换…" : "正在格式化…"
    }

    private var staleStatusText: String {
        actionTitle == "转换" ? "输入已更改，请重新转换。" : "输入已更改，请重新格式化。"
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if hasDiagnostic {
                IndexDiagnosticBanner(
                    diagnostic: diagnosticDetail,
                    message: diagnostic!,
                    tone: diagnosticTone
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity.combined(with: .move(edge: .top))
                ))
            }
            HStack(spacing: ToolMetrics.Spacing.sm) {
                inputPaneWithHeader
                outputPane
            }
            .padding(.horizontal, ToolMetrics.Spacing.md)
            .padding(.bottom, ToolMetrics.Spacing.md)
            .padding(.top, ToolMetrics.Spacing.sm)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: hasDiagnostic)
        .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous))
        .background(
            ToolTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
        )
        .overlay {
            if showsErrorState {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                    .strokeBorder(ToolTheme.error.opacity(0.55), lineWidth: 1)
            }
        }
        .toolShadow(
            showsErrorState
                ? ToolTheme.ShadowRecipe(color: ToolTheme.errorSoft, radius: 3, y: 0)
                : ToolTheme.Shadow.panel
        )
        .toolAnimation(ToolMotion.Preset.diagnostic, value: showsErrorState)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Toolbar

    private var toolbar: some View {
        // Mirrors the 50/50 pane split below: each I/O identity left-aligns to
        // its own pane's leading edge (prototype: STDOUT pinned at left:50%),
        // and the actions right-align inside the output half.
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                IndexBadge("STDIN", tone: .accent, isCapsule: true)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(10)
                Text(inputTitle)
                    .font(ToolTypography.panelTitle)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(9)

                leadingControl()

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                IndexBadge("STDOUT", tone: .accent, isCapsule: true)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(10)
                Text(outputTitle)
                    .font(ToolTypography.panelTitle)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(9)

                if let outputControl {
                    outputControl()
                }

                inlineDiagnostic

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    IndexClearButton(isDisabled: clearDisabled, showsIcon: false, framed: true, action: onClear)
                    IndexCopyButton(text: output, title: "复制", showsIcon: false, framed: true)
                        .disabled(!isOutputFresh)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                        .help("复制全部 (⇧⌘C)")
                    if showsOutputSave {
                        IndexSaveTextButton(text: output, fileName: outputFileName, showsIcon: false, framed: true)
                            .disabled(!isOutputFresh)
                    }
                    formatButton
                }
                .layoutPriority(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var inlineDiagnostic: some View {
        if isRunning {
            inlineDiagnosticContent(
                message: runningStatusText,
                tone: .info,
                showsSpinner: true
            )
        } else if hasStaleResult {
            inlineDiagnosticContent(
                message: staleStatusText,
                tone: .info,
                showsSpinner: false
            )
        }
    }

    private func inlineDiagnosticContent(
        message: String,
        tone: ToolFeedbackTone,
        showsSpinner: Bool
    ) -> some View {
            HStack(spacing: 4) {
                if showsSpinner {
                    IndexProgressSpinner()
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: tone.systemImage)
                        .font(.system(size: ToolMetrics.IconSize.small, weight: .semibold))
                }
                Text(message)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(ToolTypography.caption)
            .foregroundStyle(tone.tint)
            .frame(maxWidth: 240, alignment: .leading)
            .layoutPriority(1)
            .help(message)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(tone.accessibilityPrefix)：\(message)")
            .toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)
    }

    @ViewBuilder
    private var formatButton: some View {
        if let onFormat {
            IndexPrimaryActionButton(title: actionTitle, hint: actionHint, help: "\(actionTitle)（⌘↩）", action: onFormat)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isRunning || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: Panes

    @ViewBuilder
    private var inputPaneWithHeader: some View {
        if let inputHeader {
            // The header row (e.g. a URL bar) and the editor share one field
            // surface: single border, hairline divider, embedded editor.
            VStack(spacing: 0) {
                inputHeader()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                Rectangle()
                    .fill(ToolTheme.border)
                    .frame(height: 0.5)
                inputPane
            }
            .background(
                ToolTheme.editorBackground,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(ToolTheme.border, lineWidth: 0.5)
            }
        } else {
            inputPane
        }
    }

    private var inputPane: some View {
        IndexWorkspaceTextArea(
            placeholder: inputPlaceholder,
            text: $input,
            fillsHeight: true,
            autoFocus: autoFocus,
            embedsFlat: inputHeader != nil,
            lineNumbers: true,
            onFileDrop: { content in
                input = content
                onFormat?()
            },
            droppedFile: droppedFile,
            workspaceSemantic: workspaceSemantic
        )
        .onDrop(of: [.fileURL, .text], isTargeted: nil) { providers in
            guard let provider = providers.first,
                  provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return false }
            let token = droppedFile.invalidate()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in
                    guard let url, droppedFile.isCurrent(token) else { return }
                    droppedFile.start(url: url) { content in
                        input = content
                        onFormat?()
                    }
                }
            }
            return true
        }
        .onChange(of: input) { _ in droppedFile.invalidate() }
        .onDisappear { droppedFile.invalidate() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel(inputTitle)
    }

    @ViewBuilder
    private var outputPane: some View {
        if let outputProcessingText {
            IndexTextConversionProcessingSurface(text: outputProcessingText)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityLabel(outputTitle)
        } else {
            switch outputPresentation {
            case .standard:
                IndexCodeViewerSurface(
                    text: output,
                    placeholder: outputPlaceholder,
                    lineNumbers: outputLineNumbers,
                    syntax: outputSyntax,
                    fillsHeight: true,
                    embedsFlat: false
                )
                .accessibilityLabel(hasStaleResult ? "\(outputTitle)，结果已过期" : outputTitle)
            case .nativeReadOnlyText:
                IndexReadOnlyTextSurface(
                    text: output,
                    placeholder: outputPlaceholder,
                    fillsHeight: true
                )
                .accessibilityLabel(hasStaleResult ? "\(outputTitle)，结果已过期" : outputTitle)
            case .markdownPreview:
                IndexMarkdownPreviewSurface(
                    text: output,
                    placeholder: outputPlaceholder,
                    fillsHeight: true,
                    accessibilityTitle: outputTitle
                )
            }
        }
    }
}

extension IndexFormatWorkbench where LeadingControl == EmptyView {
    /// Convenience for workbenches without leading or output control slots.
    init(
        inputTitle: String,
        outputTitle: String,
        input: Binding<String>,
        output: String,
        inputPlaceholder: String = "",
        diagnostic: String? = nil,
        diagnosticTone: ToolFeedbackTone = .error,
        diagnosticDetail: FormatDiagnostic? = nil,
        formatAttempt: Int = 0,
        outputLineNumbers: Bool = true,
        outputSyntax: IndexSyntaxKind? = nil,
        outputPlaceholder: String = IndexEmptyStateCopy.outputWillShowHere,
        actionTitle: String = "格式化",
        actionHint: String = "⌘↩",
        autoFocus: Bool = true,
        isRunning: Bool = false,
        isOutputFresh: Bool = true,
        clearDisabled: Bool = false,
        onFormat: (() -> Void)? = nil,
        onClear: @escaping () -> Void,
        outputPresentation: IndexTextConversionOutputPresentation = .standard,
        outputProcessingText: String? = nil,
        showsOutputSave: Bool = false,
        outputFileName: String = "output.txt",
        workspaceSemantic: IndexWorkspaceSemantic = .structuredEditorTransform
    ) {
        self.init(
            inputTitle: inputTitle,
            outputTitle: outputTitle,
            input: input,
            output: output,
            inputPlaceholder: inputPlaceholder,
            diagnostic: diagnostic,
            diagnosticTone: diagnosticTone,
            diagnosticDetail: diagnosticDetail,
            formatAttempt: formatAttempt,
            outputLineNumbers: outputLineNumbers,
            outputSyntax: outputSyntax,
            outputPlaceholder: outputPlaceholder,
            actionTitle: actionTitle,
            actionHint: actionHint,
            autoFocus: autoFocus,
            isRunning: isRunning,
            isOutputFresh: isOutputFresh,
            clearDisabled: clearDisabled,
            onFormat: onFormat,
            onClear: onClear,
            outputPresentation: outputPresentation,
            outputProcessingText: outputProcessingText,
            showsOutputSave: showsOutputSave,
            outputFileName: outputFileName,
            leadingControl: { EmptyView() },
            workspaceSemantic: workspaceSemantic
        )
    }

    /// Convenience for workbenches with an output control slot but without leading control slots.
    init<Output: View>(
        inputTitle: String,
        outputTitle: String,
        input: Binding<String>,
        output: String,
        inputPlaceholder: String = "",
        diagnostic: String? = nil,
        diagnosticTone: ToolFeedbackTone = .error,
        diagnosticDetail: FormatDiagnostic? = nil,
        formatAttempt: Int = 0,
        outputLineNumbers: Bool = true,
        outputSyntax: IndexSyntaxKind? = nil,
        outputPlaceholder: String = IndexEmptyStateCopy.outputWillShowHere,
        actionTitle: String = "格式化",
        actionHint: String = "⌘↩",
        autoFocus: Bool = true,
        isRunning: Bool = false,
        isOutputFresh: Bool = true,
        clearDisabled: Bool = false,
        onFormat: (() -> Void)? = nil,
        onClear: @escaping () -> Void,
        outputPresentation: IndexTextConversionOutputPresentation = .standard,
        outputProcessingText: String? = nil,
        showsOutputSave: Bool = false,
        outputFileName: String = "output.txt",
        @ViewBuilder outputControl: @escaping () -> Output,
        workspaceSemantic: IndexWorkspaceSemantic = .structuredEditorTransform
    ) {
        self.init(
            inputTitle: inputTitle,
            outputTitle: outputTitle,
            input: input,
            output: output,
            inputPlaceholder: inputPlaceholder,
            diagnostic: diagnostic,
            diagnosticTone: diagnosticTone,
            diagnosticDetail: diagnosticDetail,
            formatAttempt: formatAttempt,
            outputLineNumbers: outputLineNumbers,
            outputSyntax: outputSyntax,
            outputPlaceholder: outputPlaceholder,
            actionTitle: actionTitle,
            actionHint: actionHint,
            autoFocus: autoFocus,
            isRunning: isRunning,
            isOutputFresh: isOutputFresh,
            clearDisabled: clearDisabled,
            onFormat: onFormat,
            onClear: onClear,
            outputPresentation: outputPresentation,
            outputProcessingText: outputProcessingText,
            showsOutputSave: showsOutputSave,
            outputFileName: outputFileName,
            leadingControl: { EmptyView() },
            outputControl: outputControl,
            workspaceSemantic: workspaceSemantic
        )
    }
}
