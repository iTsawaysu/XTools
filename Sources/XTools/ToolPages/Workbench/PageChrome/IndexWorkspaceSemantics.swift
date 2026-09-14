import Foundation

enum IndexWorkspaceSemantic: Equatable {
    case unmigratedPageDefault
    case structuredOutputReading
    case structuredEditorTransform
    case copyTransformWorkspace
    case securityTransformWorkspace
    case fixedInputWorkspace
    case longTextNaturalInput
    case boundedLongTextInput
    case longSingleLineWrapping
    case naturalHeightShortResultPanel
    case imagePreviewStage
    case liveImagePreviewStage
    case queryListWorkspace
    case base64FileWorkspace
    case editableDiffWorkspace
    case regexResultWorkspace

    var resolvedWorkspace: IndexWorkspaceResolution {
        IndexWorkspaceResolution(
            behavior: behavior,
            pageShell: pageShell,
            textArea: IndexWorkspaceTextAreaContract(
                expandsWithContent: behavior.inputExpandsWithContent,
                renderingMode: textAreaRenderingMode
            )
        )
    }

    var behavior: IndexWorkspaceBehaviorContract {
        switch self {
        case .unmigratedPageDefault:
            return .init(
                scrollOwnership: .surfaceInternal,
                inputGrowth: .fixed,
                fillBehavior: .fillsAvailableSpace,
                outputScrolling: .surfaceInternal,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .protectsUnmigratedPages
            )
        case .structuredOutputReading:
            return .init(
                scrollOwnership: .pageOuter,
                inputGrowth: .natural,
                fillBehavior: .fillsThenExpands,
                outputScrolling: .pageOuter,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .explicitOptIn
            )
        case .structuredEditorTransform:
            return .init(
                scrollOwnership: .surfaceInternal,
                inputGrowth: .fixed,
                fillBehavior: .fillsAvailableSpace,
                outputScrolling: .surfaceInternal,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .protectedException
            )
        case .copyTransformWorkspace:
            return .init(
                scrollOwnership: .surfaceInternal,
                inputGrowth: .fixed,
                fillBehavior: .fillsAvailableSpace,
                outputScrolling: .surfaceInternal,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .protectedException
            )
        case .securityTransformWorkspace:
            return .init(
                scrollOwnership: .surfaceInternal,
                inputGrowth: .fixed,
                fillBehavior: .fillsAvailableSpace,
                outputScrolling: .surfaceInternal,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .protectedException
            )
        case .fixedInputWorkspace:
            return .init(
                scrollOwnership: .surfaceInternal,
                inputGrowth: .fixed,
                fillBehavior: .fillsAvailableSpace,
                outputScrolling: .pageOuter,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .protectedException
            )
        case .longTextNaturalInput:
            return .init(
                scrollOwnership: .pageOuter,
                inputGrowth: .natural,
                fillBehavior: .naturalHeight,
                outputScrolling: .pageOuter,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .explicitOptIn
            )
        case .boundedLongTextInput:
            return .init(
                scrollOwnership: .pageOuterWithBoundedInput,
                inputGrowth: .fixed,
                fillBehavior: .naturalHeight,
                outputScrolling: .pageOuter,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .explicitOptIn
            )
        case .longSingleLineWrapping:
            return .init(
                scrollOwnership: .surfaceInternal,
                inputGrowth: .fixed,
                fillBehavior: .fillsAvailableSpace,
                outputScrolling: .surfaceInternal,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .explicitOptIn
            )
        case .naturalHeightShortResultPanel:
            return .init(
                scrollOwnership: .pageOuter,
                inputGrowth: .fixed,
                fillBehavior: .naturalHeight,
                outputScrolling: .pageOuter,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .explicitOptIn
            )
        case .imagePreviewStage:
            return .init(
                scrollOwnership: .pageOuter,
                inputGrowth: .fixed,
                fillBehavior: .fillsAvailableSpace,
                outputScrolling: .none,
                longTokenWrapping: .preserveControlDefault,
                defaultSafety: .protectedException
            )
        case .liveImagePreviewStage:
            return .init(
                scrollOwnership: .fixedViewport,
                inputGrowth: .fixed,
                fillBehavior: .fillsAvailableSpace,
                outputScrolling: .none,
                longTokenWrapping: .preserveControlDefault,
                defaultSafety: .protectedException
            )
        case .queryListWorkspace:
            return .init(
                scrollOwnership: .surfaceInternal,
                inputGrowth: .fixed,
                fillBehavior: .fillsAvailableSpace,
                outputScrolling: .surfaceInternal,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .protectedException
            )
        case .base64FileWorkspace:
            return .init(
                scrollOwnership: .mixedBySurface,
                inputGrowth: .fixed,
                // Wide mode fills residual IndexPage height (min 398pt); stacked mode
                // keeps outer scroll. Matches other fill workbenches rather than a
                // fixed short slab under tall windows.
                fillBehavior: .fillsAvailableSpace,
                outputScrolling: .mixedBySurface,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .protectedException
            )
        case .editableDiffWorkspace:
            return .init(
                scrollOwnership: .diffWorkspaceUnified,
                inputGrowth: .natural,
                fillBehavior: .fillsThenExpands,
                outputScrolling: .diffWorkspaceUnified,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .protectedException
            )
        case .regexResultWorkspace:
            return .init(
                scrollOwnership: .pageOuter,
                inputGrowth: .natural,
                fillBehavior: .naturalHeight,
                outputScrolling: .pageOuter,
                longTokenWrapping: .wrapsToAvailableWidth,
                defaultSafety: .explicitOptIn
            )
        }
    }

    private var pageShell: IndexWorkspacePageShell {
        switch self {
        case .unmigratedPageDefault:
            return .init(layout: .fill, chrome: .standard)
        case .structuredOutputReading:
            return .init(layout: .scroll, chrome: .standard)
        case .structuredEditorTransform:
            return .init(layout: .fill, chrome: .compactWorkspace)
        case .copyTransformWorkspace:
            return .init(layout: .fill, chrome: .compactWorkspace)
        case .securityTransformWorkspace:
            return .init(layout: .fill, chrome: .compactWorkspace)
        case .fixedInputWorkspace:
            return .init(layout: .fill, chrome: .standard)
        case .longTextNaturalInput:
            return .init(layout: .scroll, chrome: .standard)
        case .boundedLongTextInput:
            return .init(layout: .scroll, chrome: .standard)
        case .longSingleLineWrapping:
            return .init(layout: .fill, chrome: .compactWorkspace)
        case .naturalHeightShortResultPanel:
            return .init(layout: .scroll, chrome: .standard)
        case .imagePreviewStage:
            return .init(layout: .scroll, chrome: .standard)
        case .liveImagePreviewStage:
            return .init(layout: .fill, chrome: .standard)
        case .queryListWorkspace:
            return .init(layout: .fill, chrome: .standard)
        case .base64FileWorkspace:
            return .init(layout: .fill, chrome: .compactWorkspace)
        case .editableDiffWorkspace:
            return .init(layout: .fill, chrome: .compactWorkspace)
        case .regexResultWorkspace:
            return .init(layout: .scroll, chrome: .standard)
        }
    }

    private var textAreaRenderingMode: IndexTextAreaRenderingMode {
        switch self {
        case .boundedLongTextInput, .base64FileWorkspace:
            return .textKit2Viewport
        default:
            return .measuredContent
        }
    }
}

struct IndexWorkspaceResolution: Equatable {
    let behavior: IndexWorkspaceBehaviorContract
    let pageShell: IndexWorkspacePageShell
    let textArea: IndexWorkspaceTextAreaContract
}

struct IndexWorkspacePageShell: Equatable {
    let layout: IndexPageLayout
    let chrome: IndexPageChrome
}

struct IndexWorkspaceTextAreaContract: Equatable {
    let expandsWithContent: Bool
    let renderingMode: IndexTextAreaRenderingMode
}

struct IndexWorkspaceBehaviorContract: Equatable {
    let scrollOwnership: IndexWorkspaceScrollOwnership
    let inputGrowth: IndexWorkspaceInputGrowth
    let fillBehavior: IndexWorkspaceFillBehavior
    let outputScrolling: IndexWorkspaceOutputScrolling
    let longTokenWrapping: IndexWorkspaceLongTokenWrapping
    let defaultSafety: IndexWorkspaceDefaultSafety

    var inputExpandsWithContent: Bool {
        inputGrowth == .natural
    }

    var outputScrollsInternally: Bool {
        outputScrolling == .surfaceInternal
    }

    var wrapsLongTokensToAvailableWidth: Bool {
        longTokenWrapping == .wrapsToAvailableWidth
    }
}

enum IndexWorkspaceScrollOwnership: Equatable {
    case pageOuter
    case pageOuterWithBoundedInput
    case surfaceInternal
    case fixedViewport
    case diffWorkspaceUnified
    case mixedBySurface
}

enum IndexWorkspaceInputGrowth: Equatable {
    case fixed
    case natural
}

enum IndexWorkspaceFillBehavior: Equatable {
    case fillsAvailableSpace
    case fillsThenExpands
    case naturalHeight
    case preserveCurrentLayout
}

enum IndexWorkspaceOutputScrolling: Equatable {
    case pageOuter
    case surfaceInternal
    case diffWorkspaceUnified
    case mixedBySurface
    case none
}

enum IndexWorkspaceLongTokenWrapping: Equatable {
    case preserveControlDefault
    case wrapsToAvailableWidth
}

enum IndexWorkspaceDefaultSafety: Equatable {
    case protectsUnmigratedPages
    case protectedException
    case explicitOptIn
}
