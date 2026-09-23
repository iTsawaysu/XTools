@testable import XTools
import SwiftUI
import Testing

struct ToolWorkspaceSemanticTests {
    @Test func semanticCatalogMatchesGlossaryBehaviorContracts() {
        assertContract(
            .unmigratedPageDefault,
            scrollOwnership: .surfaceInternal,
            inputGrowth: .fixed,
            fillBehavior: .fillsAvailableSpace,
            outputScrolling: .surfaceInternal,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .protectsUnmigratedPages
        )
        assertContract(
            .structuredOutputReading,
            scrollOwnership: .pageOuter,
            inputGrowth: .natural,
            fillBehavior: .fillsThenExpands,
            outputScrolling: .pageOuter,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .explicitOptIn
        )
        assertContract(
            .structuredEditorTransform,
            scrollOwnership: .surfaceInternal,
            inputGrowth: .fixed,
            fillBehavior: .fillsAvailableSpace,
            outputScrolling: .surfaceInternal,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .protectedException
        )
        assertContract(
            .copyTransformWorkspace,
            scrollOwnership: .surfaceInternal,
            inputGrowth: .fixed,
            fillBehavior: .fillsAvailableSpace,
            outputScrolling: .surfaceInternal,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .protectedException
        )
        assertContract(
            .securityTransformWorkspace,
            scrollOwnership: .surfaceInternal,
            inputGrowth: .fixed,
            fillBehavior: .fillsAvailableSpace,
            outputScrolling: .surfaceInternal,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .protectedException
        )
        assertContract(
            .fixedInputWorkspace,
            scrollOwnership: .surfaceInternal,
            inputGrowth: .fixed,
            fillBehavior: .fillsAvailableSpace,
            outputScrolling: .pageOuter,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .protectedException
        )
        assertContract(
            .longTextNaturalInput,
            scrollOwnership: .pageOuter,
            inputGrowth: .natural,
            fillBehavior: .naturalHeight,
            outputScrolling: .pageOuter,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .explicitOptIn
        )
        assertContract(
            .boundedLongTextInput,
            scrollOwnership: .pageOuterWithBoundedInput,
            inputGrowth: .fixed,
            fillBehavior: .naturalHeight,
            outputScrolling: .pageOuter,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .explicitOptIn
        )
        assertContract(
            .longSingleLineWrapping,
            scrollOwnership: .surfaceInternal,
            inputGrowth: .fixed,
            fillBehavior: .fillsAvailableSpace,
            outputScrolling: .surfaceInternal,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .explicitOptIn
        )
        assertContract(
            .naturalHeightShortResultPanel,
            scrollOwnership: .pageOuter,
            inputGrowth: .fixed,
            fillBehavior: .naturalHeight,
            outputScrolling: .pageOuter,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .explicitOptIn
        )
        assertContract(
            .imagePreviewStage,
            scrollOwnership: .pageOuter,
            inputGrowth: .fixed,
            fillBehavior: .fillsAvailableSpace,
            outputScrolling: .none,
            longTokenWrapping: .preserveControlDefault,
            defaultSafety: .protectedException
        )
        assertContract(
            .liveImagePreviewStage,
            scrollOwnership: .fixedViewport,
            inputGrowth: .fixed,
            fillBehavior: .fillsAvailableSpace,
            outputScrolling: .none,
            longTokenWrapping: .preserveControlDefault,
            defaultSafety: .protectedException
        )
        assertContract(
            .queryListWorkspace,
            scrollOwnership: .surfaceInternal,
            inputGrowth: .fixed,
            fillBehavior: .fillsAvailableSpace,
            outputScrolling: .surfaceInternal,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .protectedException
        )
        assertContract(
            .base64FileWorkspace,
            scrollOwnership: .mixedBySurface,
            inputGrowth: .fixed,
            fillBehavior: .fillsAvailableSpace,
            outputScrolling: .mixedBySurface,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .protectedException
        )
        assertContract(
            .editableDiffWorkspace,
            scrollOwnership: .diffWorkspaceUnified,
            inputGrowth: .natural,
            fillBehavior: .fillsThenExpands,
            outputScrolling: .diffWorkspaceUnified,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .protectedException
        )
        assertContract(
            .regexResultWorkspace,
            scrollOwnership: .pageOuter,
            inputGrowth: .natural,
            fillBehavior: .naturalHeight,
            outputScrolling: .pageOuter,
            longTokenWrapping: .wrapsToAvailableWidth,
            defaultSafety: .explicitOptIn
        )
    }

    @Test func defaultSemanticProtectsUnmigratedPages() {
        let behavior = IndexWorkspaceSemantic.unmigratedPageDefault.behavior

        #expect(behavior.scrollOwnership == .surfaceInternal)
        #expect(behavior.inputGrowth == .fixed)
        #expect(behavior.fillBehavior == .fillsAvailableSpace)
        #expect(behavior.outputScrolling == .surfaceInternal)
        #expect(behavior.longTokenWrapping == .wrapsToAvailableWidth)
        #expect(behavior.defaultSafety == .protectsUnmigratedPages)
        #expect(!behavior.inputExpandsWithContent)
        #expect(behavior.outputScrollsInternally)
        #expect(behavior.wrapsLongTokensToAvailableWidth)
    }

    @Test func defaultSafetyDoesNotAutoMigrateUnmigratedPagesToReadingBehavior() {
        let defaultBehavior = IndexWorkspaceSemantic.unmigratedPageDefault.behavior
        let readingBehavior = IndexWorkspaceSemantic.structuredOutputReading.behavior

        #expect(defaultBehavior.defaultSafety == .protectsUnmigratedPages)
        #expect(defaultBehavior.scrollOwnership == .surfaceInternal)
        #expect(defaultBehavior.outputScrolling == .surfaceInternal)
        #expect(defaultBehavior.inputGrowth == .fixed)
        #expect(defaultBehavior.scrollOwnership != readingBehavior.scrollOwnership)
        #expect(defaultBehavior.outputScrolling != readingBehavior.outputScrolling)
        #expect(defaultBehavior.inputGrowth != readingBehavior.inputGrowth)
    }

    @Test func structuredOutputReadingResolvesToPageLevelReadingContract() {
        let behavior = IndexWorkspaceSemantic.structuredOutputReading.behavior

        #expect(behavior.scrollOwnership == .pageOuter)
        #expect(behavior.inputGrowth == .natural)
        #expect(behavior.fillBehavior == .fillsThenExpands)
        #expect(behavior.outputScrolling == .pageOuter)
        #expect(behavior.longTokenWrapping == .wrapsToAvailableWidth)
        #expect(behavior.defaultSafety == .explicitOptIn)
        #expect(behavior.inputExpandsWithContent)
        #expect(!behavior.outputScrollsInternally)
        #expect(behavior.wrapsLongTokensToAvailableWidth)
    }

    @Test func copyTransformWorkspaceKeepsFixedInternalScrollingButWrapsLongTokens() {
        let behavior = IndexWorkspaceSemantic.copyTransformWorkspace.behavior

        #expect(behavior.scrollOwnership == .surfaceInternal)
        #expect(behavior.inputGrowth == .fixed)
        #expect(behavior.fillBehavior == .fillsAvailableSpace)
        #expect(behavior.outputScrolling == .surfaceInternal)
        #expect(behavior.longTokenWrapping == .wrapsToAvailableWidth)
        #expect(behavior.defaultSafety == .protectedException)
        #expect(!behavior.inputExpandsWithContent)
        #expect(behavior.outputScrollsInternally)
        #expect(behavior.wrapsLongTokensToAvailableWidth)
    }

    @Test func naturalHeightShortResultPanelUsesPageOuterNaturalHeightContract() {
        let behavior = IndexWorkspaceSemantic.naturalHeightShortResultPanel.behavior

        #expect(behavior.scrollOwnership == .pageOuter)
        #expect(behavior.inputGrowth == .fixed)
        #expect(behavior.fillBehavior == .naturalHeight)
        #expect(behavior.outputScrolling == .pageOuter)
        #expect(behavior.longTokenWrapping == .wrapsToAvailableWidth)
        #expect(behavior.defaultSafety == .explicitOptIn)
        #expect(!behavior.inputExpandsWithContent)
        #expect(!behavior.outputScrollsInternally)
        #expect(behavior.wrapsLongTokensToAvailableWidth)
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
            #expect(semantic.behavior.inputGrowth == .fixed)
            #expect(!semantic.behavior.inputExpandsWithContent)
        }

        #expect(IndexWorkspaceSemantic.structuredOutputReading.behavior.inputGrowth == .natural)
        #expect(IndexWorkspaceSemantic.structuredEditorTransform.behavior.inputGrowth == .fixed)
        #expect(IndexWorkspaceSemantic.longTextNaturalInput.behavior.inputGrowth == .natural)
        #expect(IndexWorkspaceSemantic.boundedLongTextInput.behavior.inputGrowth == .fixed)
        #expect(IndexWorkspaceSemantic.editableDiffWorkspace.behavior.inputGrowth == .natural)
        #expect(IndexWorkspaceSemantic.regexResultWorkspace.behavior.inputGrowth == .natural)
    }

    @Test func exceptionSemanticsAreExplicitlyProtectedFromReadingDefaults() {
        #expect(IndexWorkspaceSemantic.copyTransformWorkspace.behavior.defaultSafety == .protectedException)
        #expect(IndexWorkspaceSemantic.securityTransformWorkspace.behavior.defaultSafety == .protectedException)
        #expect(IndexWorkspaceSemantic.structuredEditorTransform.behavior.defaultSafety == .protectedException)
        #expect(IndexWorkspaceSemantic.fixedInputWorkspace.behavior.defaultSafety == .protectedException)
        #expect(IndexWorkspaceSemantic.base64FileWorkspace.behavior.defaultSafety == .protectedException)
        #expect(IndexWorkspaceSemantic.queryListWorkspace.behavior.defaultSafety == .protectedException)
        #expect(IndexWorkspaceSemantic.imagePreviewStage.behavior.defaultSafety == .protectedException)
        #expect(IndexWorkspaceSemantic.imagePreviewStage.behavior.outputScrolling == .none)
        #expect(IndexWorkspaceSemantic.liveImagePreviewStage.behavior.defaultSafety == .protectedException)
        #expect(IndexWorkspaceSemantic.liveImagePreviewStage.behavior.outputScrolling == .none)
        #expect(IndexWorkspaceSemantic.editableDiffWorkspace.behavior.defaultSafety == .protectedException)
    }

    @Test func exceptionSemanticsKeepTheirDistinctScrollAndFillOwners() {
        #expect(IndexWorkspaceSemantic.copyTransformWorkspace.behavior.scrollOwnership == .surfaceInternal)
        #expect(IndexWorkspaceSemantic.copyTransformWorkspace.behavior.outputScrolling == .surfaceInternal)
        #expect(IndexWorkspaceSemantic.securityTransformWorkspace.behavior.scrollOwnership == .surfaceInternal)
        #expect(IndexWorkspaceSemantic.securityTransformWorkspace.behavior.outputScrolling == .surfaceInternal)
        #expect(IndexWorkspaceSemantic.structuredEditorTransform.behavior.scrollOwnership == .surfaceInternal)
        #expect(IndexWorkspaceSemantic.structuredEditorTransform.behavior.outputScrolling == .surfaceInternal)
        #expect(IndexWorkspaceSemantic.fixedInputWorkspace.behavior.scrollOwnership == .surfaceInternal)
        #expect(IndexWorkspaceSemantic.fixedInputWorkspace.behavior.fillBehavior == .fillsAvailableSpace)
        #expect(IndexWorkspaceSemantic.queryListWorkspace.behavior.outputScrolling == .surfaceInternal)
        #expect(IndexWorkspaceSemantic.base64FileWorkspace.behavior.scrollOwnership == .mixedBySurface)
        #expect(IndexWorkspaceSemantic.base64FileWorkspace.behavior.fillBehavior == .fillsAvailableSpace)
        #expect(IndexWorkspaceSemantic.imagePreviewStage.behavior.scrollOwnership == .pageOuter)
        #expect(IndexWorkspaceSemantic.imagePreviewStage.behavior.outputScrolling == .none)
        #expect(IndexWorkspaceSemantic.liveImagePreviewStage.behavior.scrollOwnership == .fixedViewport)
        #expect(IndexWorkspaceSemantic.liveImagePreviewStage.behavior.outputScrolling == .none)
        #expect(IndexWorkspaceSemantic.editableDiffWorkspace.behavior.scrollOwnership == .diffWorkspaceUnified)
        #expect(IndexWorkspaceSemantic.editableDiffWorkspace.behavior.outputScrolling == .diffWorkspaceUnified)
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
        #expect(verificationSurface.workspaceSemantic.behavior.fillBehavior == .naturalHeight)
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
        let ratioBoundedTextArea = IndexTextArea(placeholder: "输入", text: .constant(""), maxHeightRatio: 0.4)
        let fillingTextArea = IndexTextArea(placeholder: "输入", text: .constant(""), fillsHeight: true)
        let explicitNaturalTextArea = IndexTextArea(
            placeholder: "输入",
            text: .constant(""),
            expandsWithContent: true
        )

        #expect(!defaultTextArea.growsWithContent)
        #expect(!ratioBoundedTextArea.growsWithContent)
        #expect(!fillingTextArea.growsWithContent)
        #expect(explicitNaturalTextArea.growsWithContent)
    }

    private func assertContract(
        _ semantic: IndexWorkspaceSemantic,
        scrollOwnership: IndexWorkspaceScrollOwnership,
        inputGrowth: IndexWorkspaceInputGrowth,
        fillBehavior: IndexWorkspaceFillBehavior,
        outputScrolling: IndexWorkspaceOutputScrolling,
        longTokenWrapping: IndexWorkspaceLongTokenWrapping,
        defaultSafety: IndexWorkspaceDefaultSafety,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let behavior = semantic.behavior

        #expect(behavior.scrollOwnership == scrollOwnership, sourceLocation: sourceLocation)
        #expect(behavior.inputGrowth == inputGrowth, sourceLocation: sourceLocation)
        #expect(behavior.fillBehavior == fillBehavior, sourceLocation: sourceLocation)
        #expect(behavior.outputScrolling == outputScrolling, sourceLocation: sourceLocation)
        #expect(behavior.longTokenWrapping == longTokenWrapping, sourceLocation: sourceLocation)
        #expect(behavior.defaultSafety == defaultSafety, sourceLocation: sourceLocation)
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
