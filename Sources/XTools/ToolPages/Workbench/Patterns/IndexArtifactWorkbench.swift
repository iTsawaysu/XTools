import SwiftUI
import XToolsDesign

/// P5 artifact-package workbench.
///
/// One paper for tools whose output is a generated package of several files:
/// the header keeps the package title and save-all action pinned, the source
/// identity row stays visible underneath it, and the generated groups and
/// configuration surfaces scroll through the remaining paper height.
///
/// Pages own the source identity, artifact rows, configuration code and save
/// logic; this shell owns the paper, the diagnostic slot, the empty state,
/// the single-file drop target and the pinned save action.
struct IndexArtifactWorkbench<Source: View, Content: View>: View {
    let title: String
    let emptyTitle: String
    let hasSource: Bool
    let isProcessing: Bool
    let diagnostic: String?
    let canSaveAll: Bool
    let saveAccessibilityLabel: String
    let saveHelp: String
    let onSelect: () -> Void
    let onDropURL: (URL) -> Void
    let onDropMultiple: () -> Void
    let onSaveAll: () -> Void
    private let source: Source
    private let content: Content

    @State private var isDropTargeted = false
    @State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?
    @State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toolToastCenter) private var toastCenter

    init(
        title: String,
        emptyTitle: String,
        hasSource: Bool,
        isProcessing: Bool,
        diagnostic: String?,
        canSaveAll: Bool,
        saveAccessibilityLabel: String,
        saveHelp: String,
        onSelect: @escaping () -> Void,
        onDropURL: @escaping (URL) -> Void,
        onDropMultiple: @escaping () -> Void,
        onSaveAll: @escaping () -> Void,
        @ViewBuilder source: () -> Source,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.emptyTitle = emptyTitle
        self.hasSource = hasSource
        self.isProcessing = isProcessing
        self.diagnostic = diagnostic
        self.canSaveAll = canSaveAll
        self.saveAccessibilityLabel = saveAccessibilityLabel
        self.saveHelp = saveHelp
        self.onSelect = onSelect
        self.onDropURL = onDropURL
        self.onDropMultiple = onDropMultiple
        self.onSaveAll = onSaveAll
        self.source = source()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
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
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .indexWorkspaceDiagnostic(diagnostic)
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
        .indexDropZone(
            isTargeted: $isDropTargeted,
            onFile: onDropURL,
            onMultipleFiles: onDropMultiple
        )
    }

    private var header: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            Text(title)
                .font(ToolTypography.panelTitle)
                .foregroundStyle(ToolTheme.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: ToolMetrics.Spacing.sm)

            if canSaveAll {
                Button(action: onSaveAll) {
                    Label("全部保存", systemImage: IndexActionSymbol.save)
                        .font(ToolTypography.buttonSmall)
                }
                .buttonStyle(IndexSmallButtonStyle())
                .accessibilityLabel(saveAccessibilityLabel)
                .help(saveHelp)
            }
        }
        .padding(.horizontal, ToolMetrics.Spacing.md)
        .frame(height: ArtifactWorkbenchMetrics.headerHeight)
    }

    @ViewBuilder
    private var contentArea: some View {
        if hasSource {
            VStack(spacing: 0) {
                source
                    .padding(.horizontal, ToolMetrics.Spacing.panelInset)
                    .padding(.vertical, ToolMetrics.Spacing.sm)

                divider

                ScrollView {
                    content
                        .padding(ToolMetrics.Spacing.panelInset)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        } else {
            ImageUploadPendingState(
                isProcessing: isProcessing,
                title: emptyTitle,
                fillsHeight: true,
                onSelect: onSelect
            )
            .padding(ToolMetrics.Spacing.panelInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(ToolTheme.border)
            .frame(height: 0.5)
    }
}

private enum ArtifactWorkbenchMetrics {
    static let headerHeight: CGFloat = 44
}
