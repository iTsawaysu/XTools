import AppKit
import SwiftUI
import XToolsDesign

/// P5 single-preview workbench.
///
/// One paper for workflows whose output is a single rendered image while the
/// source stays a compact identity row: the top strip carries the recipe
/// parameters and the save action, the content switches between the shared
/// upload empty state and one filling result stage.
///
/// Pages own the parameter controls, the custom text input, the source/result
/// facts, the renderer and the save logic; this shell owns the paper, the
/// diagnostic slot, the single-file drop target and the empty/result
/// composition so single-preview pages cannot grow a second panel again.
struct IndexSinglePreviewWorkbench<
    Parameters: View,
    Input: View,
    SourceFacts: View,
    ResultFacts: View
>: View {
    let title: String
    let emptyTitle: String
    let previewAccessibilityLabel: String
    let previewPlaceholder: String
    let selectLabel: String
    let replaceLabel: String
    let clearLabel: String
    let sourceImage: NSImage?
    let previewImage: NSImage?
    let isProcessing: Bool
    let diagnostic: String?
    let canSave: Bool
    let saveLabel: String
    let saveAccessibilityLabel: String
    let saveHelp: String
    let onSelect: () -> Void
    let onDropURL: (URL) -> Void
    let onDropMultiple: () -> Void
    let onClear: () -> Void
    let onSave: () -> Void
    private let parameters: Parameters
    private let input: Input
    private let sourceFacts: SourceFacts
    private let resultFacts: ResultFacts

    @State private var isDropTargeted = false
    @State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?
    @State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()
    @State private var parameterBarWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toolToastCenter) private var toastCenter

    init(
        title: String,
        emptyTitle: String,
        previewAccessibilityLabel: String,
        previewPlaceholder: String,
        selectLabel: String,
        replaceLabel: String,
        clearLabel: String,
        sourceImage: NSImage?,
        previewImage: NSImage?,
        isProcessing: Bool,
        diagnostic: String?,
        canSave: Bool,
        saveLabel: String,
        saveAccessibilityLabel: String,
        saveHelp: String,
        onSelect: @escaping () -> Void,
        onDropURL: @escaping (URL) -> Void,
        onDropMultiple: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onSave: @escaping () -> Void,
        @ViewBuilder parameters: () -> Parameters,
        @ViewBuilder input: () -> Input,
        @ViewBuilder sourceFacts: () -> SourceFacts,
        @ViewBuilder resultFacts: () -> ResultFacts
    ) {
        self.title = title
        self.emptyTitle = emptyTitle
        self.previewAccessibilityLabel = previewAccessibilityLabel
        self.previewPlaceholder = previewPlaceholder
        self.selectLabel = selectLabel
        self.replaceLabel = replaceLabel
        self.clearLabel = clearLabel
        self.sourceImage = sourceImage
        self.previewImage = previewImage
        self.isProcessing = isProcessing
        self.diagnostic = diagnostic
        self.canSave = canSave
        self.saveLabel = saveLabel
        self.saveAccessibilityLabel = saveAccessibilityLabel
        self.saveHelp = saveHelp
        self.onSelect = onSelect
        self.onDropURL = onDropURL
        self.onDropMultiple = onDropMultiple
        self.onClear = onClear
        self.onSave = onSave
        self.parameters = parameters()
        self.input = input()
        self.sourceFacts = sourceFacts()
        self.resultFacts = resultFacts()
    }

    var body: some View {
        VStack(spacing: 0) {
            parameterBar
            divider
            IndexDiagnosticStatusSlot(isActive: workspaceDiagnostic != nil) {
                if let diagnostic = workspaceDiagnostic {
                    IndexDiagnosticBanner(
                        diagnostic: nil,
                        message: diagnostic.text,
                        tone: diagnostic.tone
                    )
                }
            }
            content
                .padding(ToolMetrics.Spacing.panelInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(
            ToolTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous))
        .toolAnimation(ToolMotion.Preset.diagnostic, value: workspaceDiagnostic != nil)
        .onPreferenceChange(IndexWorkspaceDiagnosticPreferenceKey.self) { diagnostic in
            if let announcement = diagnosticPresentation.update(to: diagnostic) {
                toastCenter?.show(announcement.text, tone: announcement.tone)
            }
            workspaceDiagnostic = diagnostic
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Wide windows keep the recipe strip, title and save action on one line.
    /// Narrow windows split it into a title/save row and a full-width recipe
    /// row: keeping the save action beside a clipped colour control made the
    /// top-right edge look broken when switching white/black.
    private var parameterBar: some View {
        Group {
            if Self.stacksParameterBar(forWidth: parameterBarWidth) {
                stackedParameterBar
            } else {
                inlineParameterBar
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ParameterBarWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(ParameterBarWidthKey.self) { parameterBarWidth = $0 }
    }

    private static func stacksParameterBar(forWidth width: CGFloat) -> Bool {
        width > 0 && width < ParameterBarMetrics.inlineMinimumWidth
    }

    private var inlineParameterBar: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ToolMetrics.Spacing.md) {
                    parameterTitle
                    parameters
                }
                .padding(.leading, ToolMetrics.Spacing.md)
                .padding(.trailing, ToolMetrics.Spacing.sm)
                .frame(height: ParameterBarMetrics.rowHeight)
            }
            .scrollBounceBehavior(.basedOnSize)

            if canSave {
                saveButton
                    .padding(.trailing, ToolMetrics.Spacing.md)
            }
        }
        .frame(height: ParameterBarMetrics.rowHeight)
    }

    /// The recipe row drops to an 8pt group gap so all four groups fit inside
    /// the minimum-width paper without clipping the colour or position control.
    private var stackedParameterBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: ToolMetrics.Spacing.sm) {
                parameterTitle
                Spacer(minLength: ToolMetrics.Spacing.sm)
                if canSave {
                    saveButton
                }
            }
            .padding(.horizontal, ToolMetrics.Spacing.md)
            .frame(height: ParameterBarMetrics.stackedHeaderRowHeight)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ToolMetrics.Spacing.sm) {
                    parameters
                }
                .padding(.horizontal, ToolMetrics.Spacing.md)
                .frame(height: ParameterBarMetrics.stackedHeaderRowHeight)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var parameterTitle: some View {
        Text(title)
            .font(ToolTypography.panelTitle)
            .foregroundStyle(ToolTheme.textPrimary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Label(saveLabel, systemImage: IndexActionSymbol.save)
                .font(ToolTypography.buttonSmall)
        }
        .buttonStyle(IndexSmallButtonStyle())
        .accessibilityLabel(saveAccessibilityLabel)
        .help(saveHelp)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if sourceImage == nil {
                emptyState
                    .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
            } else {
                resultContent
                    .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
            }
        }
        .indexWorkspaceDiagnostic(diagnostic)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .indexDropZone(
            isTargeted: $isDropTargeted,
            onFile: onDropURL,
            onMultipleFiles: onDropMultiple
        )
    }

    /// Empty state keeps the custom input visible (it is part of the recipe)
    /// while the shared pending state owns the primary select action.
    private var emptyState: some View {
        VStack(spacing: ToolMetrics.Spacing.lg) {
            input
                .frame(maxWidth: 360)

            ImageUploadPendingState(
                isProcessing: isProcessing,
                title: emptyTitle,
                onSelect: onSelect
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
            ImageSelectionActionRow(
                hasSource: true,
                selectAccessibilityLabel: selectLabel,
                replaceAccessibilityLabel: replaceLabel,
                clearAccessibilityLabel: clearLabel,
                onSelect: onSelect,
                onClear: onClear
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: ToolMetrics.Spacing.lg) {
                    input
                    sourceFacts
                }

                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                    input
                    sourceFacts
                }
            }

            IndexImagePreviewStage(
                image: previewImage,
                accessibilityLabel: previewAccessibilityLabel,
                placeholder: previewPlaceholder,
                fillsHeight: true,
                replacementMotion: .immediate
            ) {
                resultFacts
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, ToolMetrics.Spacing.sm)
    }

    private var divider: some View {
        Rectangle()
            .fill(ToolTheme.border)
            .frame(height: 0.5)
    }
}

private enum ParameterBarMetrics {
    /// Below this paper width the title/save row and recipe row stack, so the
    /// colour and position controls never get clipped by the pinned save action.
    static let inlineMinimumWidth: CGFloat = 820
    static let rowHeight: CGFloat = 44
    static let stackedHeaderRowHeight: CGFloat = 40
}

private struct ParameterBarWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
