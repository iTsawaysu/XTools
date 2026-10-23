import SwiftUI
import XToolsDesign

/// P4 generator workbench: one paper whose 44pt head carries the parameters
/// and the primary generate action, followed by the paper-top diagnostic slot
/// and the generated value rows.
///
/// Pages own the parameter controls, copy text and generation logic; this
/// shell owns the paper, head row, action cluster, meta slot and row-list
/// frame so the three generator tools cannot drift apart again.
struct IndexGeneratorWorkbench<Parameters: View>: View {
    var metaText: String? = nil
    let copyText: String
    let copySuccessToast: String?
    let rows: [IndexGeneratedValueRow]
    let emptyText: String
    var motionGeneration: Int = 0
    var wrapsValues: Bool = true
    let generateHelp: String
    let shortcutEnabled: Bool
    let generate: () -> Void
    private let parameters: Parameters

    @State private var workspaceDiagnostic: IndexWorkspaceDiagnosticPayload?
    @State private var diagnosticPresentation = IndexWorkspaceDiagnosticPresentationState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.toolToastCenter) private var toastCenter

    init(
        metaText: String? = nil,
        copyText: String,
        copySuccessToast: String?,
        rows: [IndexGeneratedValueRow],
        emptyText: String,
        motionGeneration: Int = 0,
        wrapsValues: Bool = true,
        generateHelp: String,
        shortcutEnabled: Bool,
        generate: @escaping () -> Void,
        @ViewBuilder parameters: () -> Parameters
    ) {
        self.metaText = metaText
        self.copyText = copyText
        self.copySuccessToast = copySuccessToast
        self.rows = rows
        self.emptyText = emptyText
        self.motionGeneration = motionGeneration
        self.wrapsValues = wrapsValues
        self.generateHelp = generateHelp
        self.shortcutEnabled = shortcutEnabled
        self.generate = generate
        self.parameters = parameters()
    }

    var body: some View {
        VStack(spacing: 0) {
            parameterHead
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
            IndexGeneratedValueRowList(
                rows: rows,
                emptyText: emptyText,
                motionGeneration: motionGeneration,
                wrapsValues: wrapsValues
            )
            .padding(ToolMetrics.Spacing.panelInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// The 44pt paper head scrolls its parameter cluster horizontally on
    /// narrow windows instead of wrapping or squeezing the generate action.
    private var parameterHead: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: ToolMetrics.Spacing.md) {
                    HStack(spacing: ToolMetrics.Spacing.sm) { parameters }
                    if let metaText {
                        Text(metaText)
                            .font(ToolTypography.caption)
                            .monospacedDigit()
                            .foregroundStyle(ToolTheme.textTertiary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.leading, ToolMetrics.Spacing.panelInset)
            }
            .scrollBounceBehavior(.basedOnSize)

            actions
                .padding(.trailing, ToolMetrics.Spacing.panelInset)
        }
        .frame(height: ToolMetrics.Workbench.paperHeadHeight)
    }

    private var actions: some View {
        HStack(spacing: ToolMetrics.Spacing.sm) {
            IndexCopyButton(
                text: copyText,
                title: "全部复制",
                showsIcon: false,
                framed: true,
                successToast: copySuccessToast
            )

            IndexPrimaryActionButton(
                title: "生成",
                hint: "⌘↩",
                help: generateHelp,
                action: generate
            )
            .keyboardShortcut(shortcutEnabled ? KeyboardShortcut(.return, modifiers: .command) : nil)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var divider: some View {
        Rectangle()
            .fill(ToolTheme.border)
            .frame(height: 0.5)
    }
}
