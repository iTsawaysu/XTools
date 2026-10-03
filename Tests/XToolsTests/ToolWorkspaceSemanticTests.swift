@testable import XTools
import SwiftUI
import Testing

struct ToolWorkspaceSemanticTests {
    /// 语义目录 → 坍缩后的四布尔行为契约（生产实际读取的维度）。
    @Test func semanticCatalogMatchesGlossaryBehaviorContracts() {
        assertContract(
            .unmigratedPageDefault,
            inputExpandsWithContent: false,
            outputScrollsInternally: true,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: false
        )
        assertContract(
            .structuredOutputReading,
            inputExpandsWithContent: true,
            outputScrollsInternally: false,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: false
        )
        assertContract(
            .structuredEditorTransform,
            inputExpandsWithContent: false,
            outputScrollsInternally: true,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: false
        )
        assertContract(
            .copyTransformWorkspace,
            inputExpandsWithContent: false,
            outputScrollsInternally: true,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: false
        )
        assertContract(
            .securityTransformWorkspace,
            inputExpandsWithContent: false,
            outputScrollsInternally: true,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: false
        )
        assertContract(
            .fixedInputWorkspace,
            inputExpandsWithContent: false,
            outputScrollsInternally: false,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: false
        )
        assertContract(
            .longTextNaturalInput,
            inputExpandsWithContent: true,
            outputScrollsInternally: false,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: true
        )
        assertContract(
            .boundedLongTextInput,
            inputExpandsWithContent: false,
            outputScrollsInternally: false,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: true
        )
        assertContract(
            .longSingleLineWrapping,
            inputExpandsWithContent: false,
            outputScrollsInternally: true,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: false
        )
        assertContract(
            .naturalHeightShortResultPanel,
            inputExpandsWithContent: false,
            outputScrollsInternally: false,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: true
        )
        assertContract(
            .imagePreviewStage,
            inputExpandsWithContent: false,
            outputScrollsInternally: false,
            wrapsLongTokensToAvailableWidth: false,
            usesNaturalHeightSurface: false
        )
        assertContract(
            .liveImagePreviewStage,
            inputExpandsWithContent: false,
            outputScrollsInternally: false,
            wrapsLongTokensToAvailableWidth: false,
            usesNaturalHeightSurface: false
        )
        assertContract(
            .queryListWorkspace,
            inputExpandsWithContent: false,
            outputScrollsInternally: true,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: false
        )
        assertContract(
            .base64FileWorkspace,
            inputExpandsWithContent: false,
            outputScrollsInternally: false,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: false
        )
        assertContract(
            .editableDiffWorkspace,
            inputExpandsWithContent: true,
            outputScrollsInternally: false,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: false
        )
        assertContract(
            .regexResultWorkspace,
            inputExpandsWithContent: true,
            outputScrollsInternally: false,
            wrapsLongTokensToAvailableWidth: true,
            usesNaturalHeightSurface: true
        )
    }

    @Test func defaultSemanticProtectsUnmigratedPages() {
        let behavior = IndexWorkspaceSemantic.unmigratedPageDefault.behavior

        #expect(!behavior.inputExpandsWithContent)
        #expect(behavior.outputScrollsInternally)
        #expect(behavior.wrapsLongTokensToAvailableWidth)
        #expect(!behavior.usesNaturalHeightSurface)
    }

    @Test func defaultSemanticDoesNotAutoMigrateUnmigratedPagesToReadingBehavior() {
        let defaultBehavior = IndexWorkspaceSemantic.unmigratedPageDefault.behavior
        let readingBehavior = IndexWorkspaceSemantic.structuredOutputReading.behavior

        #expect(!defaultBehavior.inputExpandsWithContent)
        #expect(defaultBehavior.outputScrollsInternally)
        #expect(defaultBehavior.inputExpandsWithContent != readingBehavior.inputExpandsWithContent)
        #expect(defaultBehavior.outputScrollsInternally != readingBehavior.outputScrollsInternally)
    }

    @Test func structuredOutputReadingResolvesToPageLevelReadingContract() {
        let behavior = IndexWorkspaceSemantic.structuredOutputReading.behavior

        #expect(behavior.inputExpandsWithContent)
        #expect(!behavior.outputScrollsInternally)
        #expect(behavior.wrapsLongTokensToAvailableWidth)
        #expect(!behavior.usesNaturalHeightSurface)
    }

    @Test func copyTransformWorkspaceKeepsFixedInternalScrollingButWrapsLongTokens() {
        let behavior = IndexWorkspaceSemantic.copyTransformWorkspace.behavior

        #expect(!behavior.inputExpandsWithContent)
        #expect(behavior.outputScrollsInternally)
        #expect(behavior.wrapsLongTokensToAvailableWidth)
        #expect(!behavior.usesNaturalHeightSurface)
    }

    @Test func naturalHeightShortResultPanelUsesPageOuterNaturalHeightContract() {
        let behavior = IndexWorkspaceSemantic.naturalHeightShortResultPanel.behavior

        #expect(!behavior.inputExpandsWithContent)
        #expect(!behavior.outputScrollsInternally)
        #expect(behavior.wrapsLongTokensToAvailableWidth)
        #expect(behavior.usesNaturalHeightSurface)
    }

    @Test @MainActor func shortResultEntrypointsDefaultToNaturalHeightAndLongTokenWrapping() {
        let kv = IndexShortResultKV(rows: [("文件", "very-long-token-without-natural-breaks", nil)])
        let cards = IndexShortResultCardList(
            items: [
                IndexResultCardItem(
                    id: "sha256",
                    label: "SHA256",
                    value: "very-long-token-without-natural-breaks"
                )
            ]
        )
        let surface = IndexWorkspaceResultSurface {
            EmptyView()
        }

        #expect(kv.workspaceSemantic == .naturalHeightShortResultPanel)
        #expect(kv.valueLineBreakMode == .byCharWrapping)
        #expect(cards.workspaceSemantic == .naturalHeightShortResultPanel)
        #expect(surface.workspaceSemantic == .naturalHeightShortResultPanel)
        #expect(!kv.workspaceSemantic.behavior.outputScrollsInternally)
        #expect(!cards.workspaceSemantic.behavior.outputScrollsInternally)
        #expect(kv.workspaceSemantic.behavior.wrapsLongTokensToAvailableWidth)
        #expect(cards.workspaceSemantic.behavior.wrapsLongTokensToAvailableWidth)
    }

    @Test @MainActor func contentTextSurfacesWrapLongTokensByDefault() {
        let textArea = IndexTextArea(placeholder: "输入", text: .constant(""))
        let outputSurface = IndexOutputSurface(text: "very-long-token-without-natural-breaks", placeholder: "输出")
        let kv = IndexKV(rows: [("值", "very-long-token-without-natural-breaks", nil)])
        let scrollableKV = IndexScrollableKV(rows: [
            IndexScrollableKVRow(
                id: "value",
                key: "值",
                value: "very-long-token-without-natural-breaks",
                color: nil
            )
        ])
        let resultRow = IndexKVRow(key: "值", value: "very-long-token-without-natural-breaks", valueLineBreakMode: .byCharWrapping)

        #expect(textArea.lineBreakMode == .byCharWrapping)
        #expect(outputSurface.lineBreakMode == .byCharWrapping)
        #expect(kv.valueLineBreakMode == .byCharWrapping)
        #expect(scrollableKV.valueLineBreakMode == .byCharWrapping)
        #expect(resultRow.valueLineBreakMode == .byCharWrapping)
        #expect(IndexWorkspaceSemantic.fixedInputWorkspace.behavior.wrapsLongTokensToAvailableWidth)
        #expect(IndexWorkspaceSemantic.queryListWorkspace.behavior.wrapsLongTokensToAvailableWidth)
    }

    @Test func inputGrowthRemainsTaskSemanticSpecificRatherThanControlTypeDefault() {
        let fixedInputSemantics: [IndexWorkspaceSemantic] = [
            .unmigratedPageDefault,
            .structuredEditorTransform,
            .copyTransformWorkspace,
            .securityTransformWorkspace,
            .fixedInputWorkspace,
            .boundedLongTextInput,
            .naturalHeightShortResultPanel,
            .imagePreviewStage,
            .liveImagePreviewStage,
            .queryListWorkspace,
            .base64FileWorkspace
        ]

        for semantic in fixedInputSemantics {
            #expect(!semantic.behavior.inputExpandsWithContent)
        }

        #expect(IndexWorkspaceSemantic.structuredOutputReading.behavior.inputExpandsWithContent)
        #expect(!IndexWorkspaceSemantic.structuredEditorTransform.behavior.inputExpandsWithContent)
        #expect(IndexWorkspaceSemantic.longTextNaturalInput.behavior.inputExpandsWithContent)
        #expect(!IndexWorkspaceSemantic.boundedLongTextInput.behavior.inputExpandsWithContent)
        #expect(IndexWorkspaceSemantic.editableDiffWorkspace.behavior.inputExpandsWithContent)
        #expect(IndexWorkspaceSemantic.regexResultWorkspace.behavior.inputExpandsWithContent)
    }

    @Test func exceptionSemanticsStayDistinctFromReadingDefaults() {
        #expect(IndexWorkspaceSemantic.copyTransformWorkspace.behavior.outputScrollsInternally)
        #expect(IndexWorkspaceSemantic.securityTransformWorkspace.behavior.outputScrollsInternally)
        #expect(IndexWorkspaceSemantic.structuredEditorTransform.behavior.outputScrollsInternally)
        #expect(!IndexWorkspaceSemantic.structuredOutputReading.behavior.outputScrollsInternally)
        #expect(IndexWorkspaceSemantic.imagePreviewStage.behavior == .imageStageControlDefaults)
        #expect(!IndexWorkspaceSemantic.imagePreviewStage.behavior.wrapsLongTokensToAvailableWidth)
        #expect(IndexWorkspaceSemantic.liveImagePreviewStage.behavior == .imageStageControlDefaults)
        #expect(!IndexWorkspaceSemantic.liveImagePreviewStage.behavior.wrapsLongTokensToAvailableWidth)
        #expect(IndexWorkspaceSemantic.editableDiffWorkspace.behavior == IndexWorkspaceSemantic.structuredOutputReading.behavior)
    }

    @Test func exceptionSemanticsKeepTheirDistinctScrollAndFillOwners() {
        #expect(IndexWorkspaceSemantic.copyTransformWorkspace.behavior == .fixedHeightInternalScroll)
        #expect(IndexWorkspaceSemantic.securityTransformWorkspace.behavior == .fixedHeightInternalScroll)
        #expect(IndexWorkspaceSemantic.structuredEditorTransform.behavior == .fixedHeightInternalScroll)
        #expect(IndexWorkspaceSemantic.fixedInputWorkspace.behavior.outputScrollsInternally == false)
        #expect(IndexWorkspaceSemantic.fixedInputWorkspace.behavior.usesNaturalHeightSurface == false)
        #expect(IndexWorkspaceSemantic.queryListWorkspace.behavior.outputScrollsInternally)
        #expect(IndexWorkspaceSemantic.base64FileWorkspace.behavior == .fixedHeightPageScrolling)
        #expect(IndexWorkspaceSemantic.boundedLongTextInput.behavior.usesNaturalHeightSurface)
        #expect(IndexWorkspaceSemantic.naturalHeightShortResultPanel.behavior.usesNaturalHeightSurface)
        #expect(IndexWorkspaceSemantic.longTextNaturalInput.behavior == .naturalHeightPageScrolling)
        #expect(IndexWorkspaceSemantic.regexResultWorkspace.behavior == .naturalHeightPageScrolling)
    }

    @Test @MainActor func textConversionWorkbenchDefaultsToCopyTransformSemantic() {
        let workbench = IndexTextConversionWorkbench(
            inputTitle: "输入",
            outputTitle: "输出",
            placeholder: "输入",
            input: .constant(""),
            output: ""
        )

        #expect(workbench.workspaceSemantic == .copyTransformWorkspace)
        #expect(workbench.outputFileName == "output.txt")
    }

    @Test @MainActor func jwtMixedSurfacesComposeDistinctWorkspaceSemantics() {
        let tokenInput = IndexWorkspaceTextArea(
            placeholder: "粘贴 JWT（eyJ...）",
            text: .constant(""),
            minHeight: 84,
            workspaceSemantic: .longTextNaturalInput
        )
        let headerSurface = IndexWorkspaceOutputSurface(
            text: "{}",
            placeholder: "解析后显示 Header",
            workspaceSemantic: .structuredOutputReading
        )
        let payloadSurface = IndexWorkspaceOutputSurface(
            text: "{}",
            placeholder: "解析后显示 Payload",
            workspaceSemantic: .structuredOutputReading
        )
        let verificationSurface = IndexWorkspaceResultSurface(workspaceSemantic: .naturalHeightShortResultPanel) {
            EmptyView()
        }

        #expect(tokenInput.workspaceSemantic.behavior == IndexWorkspaceSemantic.longTextNaturalInput.behavior)
        #expect(headerSurface.workspaceSemantic.behavior == IndexWorkspaceSemantic.structuredOutputReading.behavior)
        #expect(payloadSurface.workspaceSemantic.behavior == IndexWorkspaceSemantic.structuredOutputReading.behavior)
        #expect(verificationSurface.workspaceSemantic.behavior == IndexWorkspaceSemantic.naturalHeightShortResultPanel.behavior)
        #expect(tokenInput.workspaceSemantic.behavior.inputExpandsWithContent)
        #expect(!headerSurface.workspaceSemantic.behavior.outputScrollsInternally)
        #expect(!payloadSurface.workspaceSemantic.behavior.outputScrollsInternally)
        #expect(verificationSurface.workspaceSemantic.behavior.usesNaturalHeightSurface)
    }

    @Test @MainActor func sharedTextConversionWorkbenchUsesStructuredEditorTransformSemantic() {
        let workbench = IndexTextConversionWorkbench(
            inputTitle: "输入 SQL",
            outputTitle: "格式化结果",
            placeholder: "select * from users",
            input: .constant("select * from users"),
            output: "SELECT\n  *\nFROM users",
            workspaceSemantic: .structuredEditorTransform
        )

        #expect(workbench.workspaceSemantic == .structuredEditorTransform)
        #expect(workbench.workspaceSemantic.behavior == IndexWorkspaceSemantic.structuredEditorTransform.behavior)
        #expect(!workbench.workspaceSemantic.behavior.inputExpandsWithContent)
        #expect(workbench.workspaceSemantic.behavior.outputScrollsInternally)
    }

    @Test func workspaceResolutionOwnsPageShellForRepresentativeSemantics() {
        assertResolvedPageShell(.unmigratedPageDefault, layout: .fill, chrome: .standard)
        assertResolvedPageShell(.structuredEditorTransform, layout: .fill, chrome: .compactWorkspace)
        assertResolvedPageShell(.copyTransformWorkspace, layout: .fill, chrome: .compactWorkspace)
        assertResolvedPageShell(.securityTransformWorkspace, layout: .fill, chrome: .compactWorkspace)
        assertResolvedPageShell(.longSingleLineWrapping, layout: .fill, chrome: .compactWorkspace)
        assertResolvedPageShell(.fixedInputWorkspace, layout: .fill, chrome: .standard)
        assertResolvedPageShell(.boundedLongTextInput, layout: .scroll, chrome: .standard)
        assertResolvedPageShell(.base64FileWorkspace, layout: .fill, chrome: .compactWorkspace)
        assertResolvedPageShell(.imagePreviewStage, layout: .scroll, chrome: .standard)
        assertResolvedPageShell(.liveImagePreviewStage, layout: .fill, chrome: .standard)
        assertResolvedPageShell(.queryListWorkspace, layout: .fill, chrome: .standard)
    }

    @Test func workspaceResolutionOwnsTextAreaGrowth() {
        let fixedSemantics: [IndexWorkspaceSemantic] = [
            .unmigratedPageDefault,
            .structuredEditorTransform,
            .copyTransformWorkspace,
            .securityTransformWorkspace,
            .fixedInputWorkspace,
            .boundedLongTextInput,
            .base64FileWorkspace,
            .liveImagePreviewStage,
            .queryListWorkspace
        ]

        for semantic in fixedSemantics {
            #expect(!semantic.resolvedWorkspace.textArea.expandsWithContent)
        }

        #expect(IndexWorkspaceSemantic.structuredOutputReading.resolvedWorkspace.textArea.expandsWithContent)
        #expect(IndexWorkspaceSemantic.longTextNaturalInput.resolvedWorkspace.textArea.expandsWithContent)
        #expect(IndexWorkspaceSemantic.regexResultWorkspace.resolvedWorkspace.textArea.expandsWithContent)
    }

    @Test func boundedLongTextInputSelectsTextKit2ViewportWithoutMigratingNaturalInputs() {
        let bounded = IndexWorkspaceSemantic.boundedLongTextInput.resolvedWorkspace.textArea
        let base64File = IndexWorkspaceSemantic.base64FileWorkspace.resolvedWorkspace.textArea
        let natural = IndexWorkspaceSemantic.longTextNaturalInput.resolvedWorkspace.textArea

        #expect(bounded.renderingMode == .textKit2Viewport)
        #expect(!bounded.expandsWithContent)
        #expect(base64File.renderingMode == .textKit2Viewport)
        #expect(!base64File.expandsWithContent)
        #expect(natural.renderingMode == .measuredContent)
        #expect(natural.expandsWithContent)
    }

    @Test @MainActor func lowLevelTextAreaDoesNotInferNaturalGrowthFromMissingBounds() {
        let defaultTextArea = IndexTextArea(placeholder: "输入", text: .constant(""))
        let fillingTextArea = IndexTextArea(placeholder: "输入", text: .constant(""), fillsHeight: true)
        let explicitNaturalTextArea = IndexTextArea(
            placeholder: "输入",
            text: .constant(""),
            expandsWithContent: true
        )

        #expect(!defaultTextArea.growsWithContent)
        #expect(!fillingTextArea.growsWithContent)
        #expect(explicitNaturalTextArea.growsWithContent)
    }

    private func assertContract(
        _ semantic: IndexWorkspaceSemantic,
        inputExpandsWithContent: Bool,
        outputScrollsInternally: Bool,
        wrapsLongTokensToAvailableWidth: Bool,
        usesNaturalHeightSurface: Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let behavior = semantic.behavior

        #expect(behavior.inputExpandsWithContent == inputExpandsWithContent, sourceLocation: sourceLocation)
        #expect(behavior.outputScrollsInternally == outputScrollsInternally, sourceLocation: sourceLocation)
        #expect(behavior.wrapsLongTokensToAvailableWidth == wrapsLongTokensToAvailableWidth, sourceLocation: sourceLocation)
        #expect(behavior.usesNaturalHeightSurface == usesNaturalHeightSurface, sourceLocation: sourceLocation)
    }

    private func assertResolvedPageShell(
        _ semantic: IndexWorkspaceSemantic,
        layout: IndexPageLayout,
        chrome: IndexPageChrome,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let shell = semantic.resolvedWorkspace.pageShell

        #expect(shell.layout == layout, sourceLocation: sourceLocation)
        #expect(shell.chrome == chrome, sourceLocation: sourceLocation)
    }
}
