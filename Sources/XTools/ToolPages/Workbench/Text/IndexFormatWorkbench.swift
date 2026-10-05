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
/// above a fixed two-pane code split with line-number gutters (plain-text
/// workbenches like the shared converter opt out of the gutters). A failed
/// format tints the panel outline; a status row appears only for a current
/// diagnostic or import rejection. Its details open without changing editor
/// geometry, and the native editors retain their identity as the row changes.
/// 泛型化说明：inputHeader / outputControl 以 @ViewBuilder 闭包的泛型存储
/// 替代 `(() -> AnyView)?` 擦除——每次 body 重建不再经 AnyView 丢类型身份；
/// 「缺席」用对应泛型 == EmptyView 的约束扩展表达，各调用形态的 API 形状不变。
struct IndexFormatWorkbench<LeadingControl: View, InputHeader: View, OutputControl: View>: View {
    let inputTitle: String
    let outputTitle: String
    @Binding var input: String
    private let exactInputIdentity: JSONExactTextIdentity
    let output: String
    var inputPlaceholder = ""
    var diagnostic: String? = nil
    var diagnosticTone: ToolFeedbackTone = .error
    var diagnosticDetail: FormatDiagnostic? = nil
    var diagnosticMarker: IndexTextAreaDiagnosticMarker? = nil
    var outputLineNumbers = true
    /// Structured code keeps the editor gutter; plain-text workbenches
    /// (text encoding, like the diff workspace) opt out.
    var inputLineNumbers = true
    /// One-shot caret placement seam for programmatic input backfills
    /// (converter mode switches); interactive typing never needs it.
    var inputCaretPlacementRequestToken: Int? = nil
    /// Opt-in live input metric in the toolbar's STDIN cluster. The structured
    /// formatter family ships without it; conversion callers pass `.characters`.
    var inputCountPresentation: IndexInputCountPresentation? = nil
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
    var inputHeader: (() -> InputHeader)?
    var outputControl: (() -> OutputControl)?
    var workspaceSemantic: IndexWorkspaceSemantic = .structuredEditorTransform

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var droppedFile = IndexDroppedTextFile()
    @State private var diagnosticNavigationToken = 0
    /// Output-breath generation: bumps once per explicit run that lands a
    /// fresh, non-empty, error-free result — each bump pulses the output
    /// pane's accent border exactly once (see `toolOutputBreath`).
    @State private var outputBreathGeneration = 0

    /// 全参 init：完整槽位调用点（输入头行 + 输出控件同时在场，如
    /// HTML → Markdown）两个可选泛型槽从闭包推断；缺席槽位传 nil。
    /// 结构化格式化工具族走下方 EmptyView 约束的便捷入口。
    init(
        inputTitle: String,
        outputTitle: String,
        input: Binding<String>,
        output: String,
        inputPlaceholder: String = "",
        diagnostic: String? = nil,
        diagnosticTone: ToolFeedbackTone = .error,
        diagnosticDetail: FormatDiagnostic? = nil,
        diagnosticMarker: IndexTextAreaDiagnosticMarker? = nil,
        outputLineNumbers: Bool = true,
        inputLineNumbers: Bool = true,
        inputCaretPlacementRequestToken: Int? = nil,
        inputCountPresentation: IndexInputCountPresentation? = nil,
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
        inputHeader: (() -> InputHeader)? = nil,
        outputControl: (() -> OutputControl)? = nil,
        workspaceSemantic: IndexWorkspaceSemantic = .structuredEditorTransform
    ) {
        self.inputTitle = inputTitle
        self.outputTitle = outputTitle
        self._input = input
        self.exactInputIdentity = JSONExactTextIdentity(input.wrappedValue)
        self.output = output
        self.inputPlaceholder = inputPlaceholder
        self.diagnostic = diagnostic
        self.diagnosticTone = diagnosticTone
        self.diagnosticDetail = diagnosticDetail
        self.diagnosticMarker = diagnosticMarker
        self.outputLineNumbers = outputLineNumbers
        self.inputLineNumbers = inputLineNumbers
        self.inputCaretPlacementRequestToken = inputCaretPlacementRequestToken
        self.inputCountPresentation = inputCountPresentation
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
        self.outputControl = outputControl
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
            IndexDiagnosticStatusSlot(isActive: hasDiagnostic || droppedFile.rejection != nil) {
                if let rejection = droppedFile.rejection {
                    HStack(spacing: 0) {
                        IndexDiagnosticBanner(diagnostic: nil, message: rejection.message)
                        IndexIconButton(systemImage: "xmark", help: "关闭导入提示", action: droppedFile.dismissRejection)
                            .padding(.trailing, 8)
                    }
                } else if hasDiagnostic, let diagnostic {
                    IndexDiagnosticBanner(
                        diagnostic: diagnosticDetail,
                        message: diagnostic,
                        tone: diagnosticTone,
                        onLocate: diagnosticMarker == nil ? nil : { diagnosticNavigationToken &+= 1 }
                    )
                }
            }
            HStack(spacing: ToolMetrics.Spacing.sm) {
                inputPaneWithHeader
                    .toolPaneHoverChrome()
                outputPane
                    .toolPaneHoverChrome()
                    .toolOutputBreath(generation: outputBreathGeneration)
            }
            .padding(.horizontal, ToolMetrics.Spacing.md)
            .padding(.bottom, ToolMetrics.Spacing.md)
            .padding(.top, ToolMetrics.Spacing.sm)
            .onChange(of: isOutputFresh) { isFresh in
                guard isFresh, onFormat != nil, !output.isEmpty, diagnosticTone != .error else {
                    return
                }
                outputBreathGeneration += 1
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous))
        .background(
            ToolTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
        )
        .toolErrorTint(active: showsErrorState, cornerRadius: ToolMetrics.CornerRadius.panel)
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

                // Opt-in live input metric (text encoding keeps the counter the
                // structured family dropped). Collapses first when the toolbar
                // runs out of width instead of squeezing the fixed controls.
                if let inputCountPresentation {
                    ViewThatFits(in: .horizontal) {
                        IndexInputCountLabel(text: inputCountPresentation.label(for: input))
                        EmptyView()
                    }
                    .layoutPriority(1)
                }

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
        // Anchored toolbar menus (IndexOptionsMenu) drop below the 44pt row and
        // over the panes; the toolbar subtree must draw above the later pane
        // siblings or the editors would paint over the open menu.
        .zIndex(1)
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
        Group {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                inputPane
            }
        }
        .overlay {
            dropTargetHover
        }
    }

    /// 文件拖拽悬停反馈：状态由认领拖拽会话的 `IndexCaretTextView` 经
    /// `droppedFile.isDropTargeted` 发布（SwiftUI 外层 onDrop 收不到回调）。
    /// 编辑器面不透明，wash 与描边必须画在上层 overlay（ToolOutputBreath 同法）。
    private var dropTargetHover: some View {
        let shape = RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
        return ZStack {
            shape.fill(ToolTheme.selectionFill)
            shape.strokeBorder(ToolTheme.accentBorder, lineWidth: 1)
        }
        .opacity(droppedFile.isDropTargeted ? 1 : 0)
        .allowsHitTesting(false)
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: droppedFile.isDropTargeted)
    }

    private var inputPane: some View {
        IndexWorkspaceTextArea(
            placeholder: inputPlaceholder,
            text: $input,
            fillsHeight: true,
            autoFocus: autoFocus,
            caretPlacementRequestToken: inputCaretPlacementRequestToken,
            diagnosticMarker: hasDiagnostic ? diagnosticMarker : nil,
            diagnosticNavigationToken: diagnosticNavigationToken,
            embedsFlat: inputHeader != nil,
            lineNumbers: inputLineNumbers,
            onFileDrop: { content in
                input = content
                onFormat?()
            },
            droppedFile: droppedFile,
            workspaceSemantic: workspaceSemantic
        )
        .onChange(of: JSONExactTextIdentity(input)) { _ in
            droppedFile.invalidate()
            droppedFile.dismissRejection()
        }
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

/// 带 leadingControl、无头行/输出控件的形态（结构化格式化工具族）：
/// 两个缺席槽位约束为 EmptyView，调用点签名与泛型化前一致。
extension IndexFormatWorkbench where InputHeader == EmptyView, OutputControl == EmptyView {
    init(
        inputTitle: String,
        outputTitle: String,
        input: Binding<String>,
        output: String,
        inputPlaceholder: String = "",
        diagnostic: String? = nil,
        diagnosticTone: ToolFeedbackTone = .error,
        diagnosticDetail: FormatDiagnostic? = nil,
        diagnosticMarker: IndexTextAreaDiagnosticMarker? = nil,
        outputLineNumbers: Bool = true,
        inputLineNumbers: Bool = true,
        inputCaretPlacementRequestToken: Int? = nil,
        inputCountPresentation: IndexInputCountPresentation? = nil,
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
            diagnosticMarker: diagnosticMarker,
            outputLineNumbers: outputLineNumbers,
            inputLineNumbers: inputLineNumbers,
            inputCaretPlacementRequestToken: inputCaretPlacementRequestToken,
            inputCountPresentation: inputCountPresentation,
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
            inputHeader: nil,
            outputControl: nil,
            workspaceSemantic: workspaceSemantic
        )
    }
}

/// 无 leading / 头行 / 输出控件槽的便捷入口：三个缺席槽位都落到 EmptyView。
extension IndexFormatWorkbench where LeadingControl == EmptyView, InputHeader == EmptyView, OutputControl == EmptyView {
    init(
        inputTitle: String,
        outputTitle: String,
        input: Binding<String>,
        output: String,
        inputPlaceholder: String = "",
        diagnostic: String? = nil,
        diagnosticTone: ToolFeedbackTone = .error,
        diagnosticDetail: FormatDiagnostic? = nil,
        diagnosticMarker: IndexTextAreaDiagnosticMarker? = nil,
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
            diagnosticMarker: diagnosticMarker,
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
            inputHeader: nil,
            outputControl: nil,
            workspaceSemantic: workspaceSemantic
        )
    }
}
