import AppKit
import SwiftUI
import XToolsDesign

/// Image compare presentation used by the image hub's re-encoding segments.
///
/// It is no longer a standalone shell: it renders inside
/// `IndexImageWorkbench` so the paper, the 44pt head and the paper-top
/// diagnostic slot are owned once for all five image segments.
struct IndexImageCompareContent<SourceFacts: View, ResultFacts: View>: View {
    let panelTitle: String
    let resultTitle: String
    let emptyTitle: String
    let placeholder: String
    let sourceAccessibilityLabel: String
    let sourceAccessibilityValue: String
    let resultAccessibilityLabel: String
    let resultAccessibilityValue: String
    let selectLabel: String
    let replaceLabel: String
    let clearLabel: String
    var badgeText: String? = nil
    var badgeTone: IndexBadgeTone = .neutral
    let sourceImage: NSImage?
    let resultImage: NSImage?
    let isProcessing: Bool
    let diagnostic: String?
    let canSave: Bool
    let saveLabel: String
    let onSelect: () -> Void
    let onDropURL: (URL) -> Void
    let onDropMultiple: () -> Void
    let onClear: () -> Void
    let onSave: () -> Void
    private let sourceFacts: SourceFacts
    private let resultFacts: ResultFacts

    @State private var isDropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        panelTitle: String,
        resultTitle: String,
        emptyTitle: String,
        placeholder: String,
        sourceAccessibilityLabel: String,
        sourceAccessibilityValue: String,
        resultAccessibilityLabel: String,
        resultAccessibilityValue: String,
        selectLabel: String,
        replaceLabel: String,
        clearLabel: String,
        badgeText: String? = nil,
        badgeTone: IndexBadgeTone = .neutral,
        sourceImage: NSImage?,
        resultImage: NSImage?,
        isProcessing: Bool,
        diagnostic: String?,
        canSave: Bool,
        saveLabel: String,
        onSelect: @escaping () -> Void,
        onDropURL: @escaping (URL) -> Void,
        onDropMultiple: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onSave: @escaping () -> Void,
        @ViewBuilder sourceFacts: () -> SourceFacts,
        @ViewBuilder resultFacts: () -> ResultFacts
    ) {
        self.panelTitle = panelTitle
        self.resultTitle = resultTitle
        self.emptyTitle = emptyTitle
        self.placeholder = placeholder
        self.sourceAccessibilityLabel = sourceAccessibilityLabel
        self.sourceAccessibilityValue = sourceAccessibilityValue
        self.resultAccessibilityLabel = resultAccessibilityLabel
        self.resultAccessibilityValue = resultAccessibilityValue
        self.selectLabel = selectLabel
        self.replaceLabel = replaceLabel
        self.clearLabel = clearLabel
        self.badgeText = badgeText
        self.badgeTone = badgeTone
        self.sourceImage = sourceImage
        self.resultImage = resultImage
        self.isProcessing = isProcessing
        self.diagnostic = diagnostic
        self.canSave = canSave
        self.saveLabel = saveLabel
        self.onSelect = onSelect
        self.onDropURL = onDropURL
        self.onDropMultiple = onDropMultiple
        self.onClear = onClear
        self.onSave = onSave
        self.sourceFacts = sourceFacts()
        self.resultFacts = resultFacts()
    }

    var body: some View {
        Group {
            if sourceImage == nil {
                ImageUploadPendingState(
                    isProcessing: isProcessing,
                    title: emptyTitle,
                    fillsHeight: true,
                    onSelect: onSelect
                )
                .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
            } else {
                comparisonPanel
                    .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
            }
        }
        .indexWorkspaceDiagnostic(diagnostic)
    }

    private var comparisonPanel: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
            ImageSelectionActionRow(
                hasSource: sourceImage != nil,
                selectAccessibilityLabel: selectLabel,
                replaceAccessibilityLabel: replaceLabel,
                clearAccessibilityLabel: clearLabel,
                onSelect: onSelect,
                onClear: onClear
            )

            IndexPairLayout(collapseWidth: 0) {
                IndexImageComparisonCard(
                    title: "原图",
                    image: sourceImage,
                    accessibilityLabel: sourceAccessibilityLabel,
                    accessibilityValue: sourceAccessibilityValue,
                    placeholder: "等待原图预览"
                ) {
                    sourceFacts
                }
            } trailing: {
                IndexImageComparisonCard(
                    title: resultTitle,
                    badgeText: badgeText,
                    badgeTone: badgeTone,
                    image: resultImage,
                    accessibilityLabel: resultAccessibilityLabel,
                    accessibilityValue: resultAccessibilityValue,
                    placeholder: placeholder,
                    isProcessing: isProcessing
                ) {
                    resultFacts
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .indexDropZone(
            isTargeted: $isDropTargeted,
            onFile: onDropURL,
            onMultipleFiles: onDropMultiple
        )
    }
}
