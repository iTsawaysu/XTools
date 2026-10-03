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
        case .unmigratedPageDefault,
             .structuredEditorTransform,
             .copyTransformWorkspace,
             .securityTransformWorkspace,
             .longSingleLineWrapping,
             .queryListWorkspace:
            return .fixedHeightInternalScroll
        case .structuredOutputReading, .editableDiffWorkspace:
            return .naturalInputPageScrolling
        case .fixedInputWorkspace, .base64FileWorkspace:
            return .fixedHeightPageScrolling
        case .longTextNaturalInput, .regexResultWorkspace:
            return .naturalHeightPageScrolling
        case .boundedLongTextInput, .naturalHeightShortResultPanel:
            return .naturalHeightFixedInput
        case .imagePreviewStage, .liveImagePreviewStage:
            return .imageStageControlDefaults
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

/// 工作区行为契约：只保留生产实际读取的布尔维度（滚动归属由
/// pageShell 与 outputScrollsInternally 的组合表达，滚动/安全两维
/// 枚举从未被消费，已随坍缩删除）。
struct IndexWorkspaceBehaviorContract: Equatable {
    /// 输入随内容自然增高（否则固定高度）。
    let inputExpandsWithContent: Bool
    /// 输出面在自身内部滚动（否则交给页面级滚动）。
    let outputScrollsInternally: Bool
    /// 超长 token 按可用宽度逐字符换行（否则保留控件默认）。
    let wrapsLongTokensToAvailableWidth: Bool
    /// 结果面板按内容自然高度呈现（否则填充可用空间）。
    let usesNaturalHeightSurface: Bool

    /// 固定双栏工作台（结构化格式化 / 转换 / 查询族）：输入固定、
    /// 输出内部滚动、逐字符换行、不追求自然高度。
    static let fixedHeightInternalScroll = IndexWorkspaceBehaviorContract(
        inputExpandsWithContent: false,
        outputScrollsInternally: true,
        wrapsLongTokensToAvailableWidth: true,
        usesNaturalHeightSurface: false
    )

    /// 自然输入 + 页面级滚动的阅读型工作台（结构化阅读 / 可编辑对比）。
    static let naturalInputPageScrolling = IndexWorkspaceBehaviorContract(
        inputExpandsWithContent: true,
        outputScrollsInternally: false,
        wrapsLongTokensToAvailableWidth: true,
        usesNaturalHeightSurface: false
    )

    /// 固定输入、输出交给页面滚动的工作区（固定输入 / Base64 文件）。
    /// Wide mode fills residual IndexPage height (min 398pt); stacked mode
    /// keeps outer scroll.
    static let fixedHeightPageScrolling = IndexWorkspaceBehaviorContract(
        inputExpandsWithContent: false,
        outputScrollsInternally: false,
        wrapsLongTokensToAvailableWidth: true,
        usesNaturalHeightSurface: false
    )

    /// 自然高度 + 页面滚动的长文本输入工作区（长文本 / 正则结果）。
    static let naturalHeightPageScrolling = IndexWorkspaceBehaviorContract(
        inputExpandsWithContent: true,
        outputScrollsInternally: false,
        wrapsLongTokensToAvailableWidth: true,
        usesNaturalHeightSurface: true
    )

    /// 固定输入、结果面板自然高度的短结果工作区（有界长输入 / 短结果面板）。
    static let naturalHeightFixedInput = IndexWorkspaceBehaviorContract(
        inputExpandsWithContent: false,
        outputScrollsInternally: false,
        wrapsLongTokensToAvailableWidth: true,
        usesNaturalHeightSurface: true
    )

    /// 图片舞台：交给控件自身的默认行为（不内部滚动、不强制换行）。
    static let imageStageControlDefaults = IndexWorkspaceBehaviorContract(
        inputExpandsWithContent: false,
        outputScrollsInternally: false,
        wrapsLongTokensToAvailableWidth: false,
        usesNaturalHeightSurface: false
    )
}
