import SwiftUI

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
    /// Bump per format attempt so a repeated identical error re-shakes.
    var formatAttempt = 0
    var outputLineNumbers = true
    var outputColorize: ((String) -> AttributedString)? = nil
    var outputPlaceholder = IndexEmptyStateCopy.outputWillShowHere
    var actionTitle = "格式化"
    var actionHint = "⌘↩"
    var autoFocus = true
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
    var workspaceSemantic: IndexWorkspaceSemantic = .structuredEditorTransform

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Designated memberwise-shape init (defining any init suppresses the
    /// implicit memberwise initializer).
    init(
        inputTitle: String,
        outputTitle: String,
        input: Binding<String>,
        output: String,
        inputPlaceholder: String = "",
        diagnostic: String? = nil,
        diagnosticTone: ToolFeedbackTone = .error,
        formatAttempt: Int = 0,
        outputLineNumbers: Bool = true,
        outputColorize: ((String) -> AttributedString)? = nil,
        outputPlaceholder: String = IndexEmptyStateCopy.outputWillShowHere,
        actionTitle: String = "格式化",
        actionHint: String = "⌘↩",
        autoFocus: Bool = true,
        clearDisabled: Bool = false,
        onFormat: (() -> Void)? = nil,
        onClear: @escaping () -> Void,
        outputPresentation: IndexTextConversionOutputPresentation = .standard,
        outputProcessingText: String? = nil,
        showsOutputSave: Bool = false,
        outputFileName: String = "output.txt",
        @ViewBuilder leadingControl: @escaping () -> LeadingControl,
        workspaceSemantic: IndexWorkspaceSemantic = .structuredEditorTransform
    ) {
        self.inputTitle = inputTitle
        self.outputTitle = outputTitle
        self._input = input
        self.output = output
        self.inputPlaceholder = inputPlaceholder
        self.diagnostic = diagnostic
        self.diagnosticTone = diagnosticTone
        self.formatAttempt = formatAttempt
        self.outputLineNumbers = outputLineNumbers
        self.outputColorize = outputColorize
        self.outputPlaceholder = outputPlaceholder
        self.actionTitle = actionTitle
        self.actionHint = actionHint
        self.autoFocus = autoFocus
        self.clearDisabled = clearDisabled
        self.onFormat = onFormat
        self.onClear = onClear
        self.outputPresentation = outputPresentation
        self.outputProcessingText = outputProcessingText
        self.showsOutputSave = showsOutputSave
        self.outputFileName = outputFileName
        self.leadingControl = leadingControl
        self.workspaceSemantic = workspaceSemantic
    }

    /// Convenience for workbenches without a leading control slot.
    init(
        inputTitle: String,
        outputTitle: String,
        input: Binding<String>,
        output: String,
        inputPlaceholder: String = "",
        diagnostic: String? = nil,
        diagnosticTone: ToolFeedbackTone = .error,
        formatAttempt: Int = 0,
        outputLineNumbers: Bool = true,
        outputColorize: ((String) -> AttributedString)? = nil,
        outputPlaceholder: String = IndexEmptyStateCopy.outputWillShowHere,
        actionTitle: String = "格式化",
        actionHint: String = "⌘↩",
        autoFocus: Bool = true,
        clearDisabled: Bool = false,
        onFormat: (() -> Void)? = nil,
        onClear: @escaping () -> Void,
        outputPresentation: IndexTextConversionOutputPresentation = .standard,
        outputProcessingText: String? = nil,
        showsOutputSave: Bool = false,
        outputFileName: String = "output.txt",
        workspaceSemantic: IndexWorkspaceSemantic = .structuredEditorTransform
    ) where LeadingControl == EmptyView {
        self.init(
            inputTitle: inputTitle,
            outputTitle: outputTitle,
            input: input,
            output: output,
            inputPlaceholder: inputPlaceholder,
            diagnostic: diagnostic,
            diagnosticTone: diagnosticTone,
            formatAttempt: formatAttempt,
            outputLineNumbers: outputLineNumbers,
            outputColorize: outputColorize,
            outputPlaceholder: outputPlaceholder,
            actionTitle: actionTitle,
            actionHint: actionHint,
            autoFocus: autoFocus,
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

    private var showsErrorState: Bool {
        diagnostic != nil && diagnosticTone == .error
    }

    /// Maximum width of the inline toolbar diagnostic; it compresses before
    /// the fixed action buttons when the output half runs out of room.
    private var diagnosticSlotWidth: CGFloat { 260 }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: ToolMetrics.Spacing.sm) {
                inputPane
                outputPane
            }
            .padding(.horizontal, ToolMetrics.Spacing.md)
            .padding(.bottom, ToolMetrics.Spacing.md)
            .padding(.top, ToolMetrics.Spacing.sm)
        }
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
        .toolErrorShake(trigger: errorShakeTrigger)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var errorShakeTrigger: String {
        showsErrorState ? "\(formatAttempt)" : ""
    }

    // MARK: Toolbar

    private var toolbar: some View {
        // Mirrors the 50/50 pane split below: each I/O identity left-aligns to
        // its own pane's leading edge (prototype: STDOUT pinned at left:50%),
        // and the actions right-align inside the output half.
        HStack(spacing: 0) {
            HStack(spacing: 8) {
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

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                IndexBadge("STDOUT", tone: .accent, isCapsule: true)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(10)
                Text(outputTitle)
                    .font(ToolTypography.panelTitle)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(9)

                inlineDiagnostic

                Spacer(minLength: 16)

                HStack(spacing: 6) {
                    IndexCopyButton(text: output, title: "复制", showsIcon: false, framed: true)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                        .help("复制全部输出（⇧⌘C）")
                    IndexClearButton(isDisabled: clearDisabled, showsIcon: false, framed: true, action: onClear)
                    if showsOutputSave {
                        IndexSaveTextButton(text: output, fileName: outputFileName, showsIcon: false, framed: true)
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
        if let diagnostic {
            HStack(spacing: 4) {
                Image(systemName: diagnosticTone.systemImage)
                    .font(.system(size: ToolMetrics.IconSize.small, weight: .semibold))
                Text(diagnostic)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(ToolTypography.caption)
            .foregroundStyle(diagnosticTone.tint)
            .frame(maxWidth: diagnosticSlotWidth, alignment: .leading)
            .layoutPriority(1)
            .help(diagnostic)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(diagnosticTone.accessibilityPrefix)：\(diagnostic)")
            .toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)
        }
    }

    @ViewBuilder
    private var formatButton: some View {
        if let onFormat {
            IndexPrimaryActionButton(title: actionTitle, hint: actionHint, help: "\(actionTitle)（⌘↩）", action: onFormat)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

    // MARK: Panes

    private var inputPane: some View {
        IndexWorkspaceTextArea(
            placeholder: inputPlaceholder,
            text: $input,
            fillsHeight: true,
            autoFocus: autoFocus,
            embedsFlat: false,
            lineNumbers: true,
            workspaceSemantic: workspaceSemantic
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel(inputTitle)
    }

    @ViewBuilder
    private var outputPane: some View {
        if let outputProcessingText {
            IndexTextConversionProcessingSurface(text: outputProcessingText)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityLabel(outputTitle)
        } else {
            switch outputPresentation {
            case .standard:
                IndexCodeViewerSurface(
                    text: output,
                    placeholder: outputPlaceholder,
                    lineNumbers: outputLineNumbers,
                    colorize: outputColorize,
                    fillsHeight: true,
                    embedsFlat: false
                )
                .accessibilityLabel(outputTitle)
            case .nativeReadOnlyText:
                IndexReadOnlyTextSurface(
                    text: output,
                    placeholder: outputPlaceholder,
                    fillsHeight: true
                )
                .accessibilityLabel(outputTitle)
            }
        }
    }
}
