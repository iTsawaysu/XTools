import SwiftUI
import XToolsDesign

/// P4 generator workbench: one parameter card with the primary generate
/// action, above the generated value rows.
///
/// Pages own the parameter controls, copy text and generation logic; this
/// shell owns the card, action cluster, meta slot and row-list frame so the
/// three generator tools cannot drift apart again.
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
        VStack(spacing: ToolMetrics.Spacing.md) {
            parameterCard

            IndexGeneratedValueRowList(
                rows: rows,
                emptyText: emptyText,
                motionGeneration: motionGeneration,
                wrapsValues: wrapsValues
            )
            .indexSurface(.card, fill: ToolTheme.panelBackground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var parameterCard: some View {
        HStack(alignment: .top, spacing: ToolMetrics.Spacing.md) {
            parameters
                .frame(maxWidth: .infinity, alignment: .leading)

            if let metaText {
                Text(metaText)
                    .font(ToolTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(ToolTheme.textTertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            actions
        }
        .padding(.horizontal, ToolMetrics.Spacing.md)
        .padding(.vertical, ToolMetrics.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .indexSurface(.card, fill: ToolTheme.panelBackground)
    }

    private var actions: some View {
        HStack(spacing: 6) {
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
        .frame(height: 30, alignment: .center)
    }
}
