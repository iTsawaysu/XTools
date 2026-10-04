import AppKit
import XToolsCore
import SwiftUI

struct IndexWorkspaceTextArea: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 220
    var fillsHeight = false
    var autoFocus = false
    var caretPlacementRequestToken: Int? = nil
    var temporaryHighlights: IndexTextAreaTemporaryHighlights? = nil
    var scrollRequest: IndexTextAreaScrollRequest? = nil
    var diagnosticMarker: IndexTextAreaDiagnosticMarker? = nil
    var diagnosticNavigationToken = 0
    var inputRenderingMode: IndexTextAreaRenderingMode? = nil
    var inputPolicy: IndexTextAreaInputPolicy? = nil
    /// Prototype v3 embedded-code presentation (owning panel supplies the
    /// surface) with an optional AppKit line-number gutter.
    var embedsFlat = false
    var lineNumbers = false
    var onFileDrop: ((String) -> Void)? = nil
    var droppedFile: IndexDroppedTextFile? = nil
    var workspaceSemantic: IndexWorkspaceSemantic = .unmigratedPageDefault

    private let exactTextIdentity: JSONExactTextIdentity

    init(
        placeholder: String,
        text: Binding<String>,
        minHeight: CGFloat = 220,
        fillsHeight: Bool = false,
        autoFocus: Bool = false,
        caretPlacementRequestToken: Int? = nil,
        temporaryHighlights: IndexTextAreaTemporaryHighlights? = nil,
        scrollRequest: IndexTextAreaScrollRequest? = nil,
        diagnosticMarker: IndexTextAreaDiagnosticMarker? = nil,
        diagnosticNavigationToken: Int = 0,
        inputRenderingMode: IndexTextAreaRenderingMode? = nil,
        inputPolicy: IndexTextAreaInputPolicy? = nil,
        embedsFlat: Bool = false,
        lineNumbers: Bool = false,
        onFileDrop: ((String) -> Void)? = nil,
        droppedFile: IndexDroppedTextFile? = nil,
        workspaceSemantic: IndexWorkspaceSemantic = .unmigratedPageDefault
    ) {
        self.placeholder = placeholder
        self._text = text
        self.minHeight = minHeight
        self.fillsHeight = fillsHeight
        self.autoFocus = autoFocus
        self.caretPlacementRequestToken = caretPlacementRequestToken
        self.temporaryHighlights = temporaryHighlights
        self.diagnosticMarker = diagnosticMarker
        self.diagnosticNavigationToken = diagnosticNavigationToken
        self.inputRenderingMode = inputRenderingMode
        self.inputPolicy = inputPolicy
        self.embedsFlat = embedsFlat
        self.lineNumbers = lineNumbers
        self.onFileDrop = onFileDrop
        self.droppedFile = droppedFile
        self.workspaceSemantic = workspaceSemantic
        self.exactTextIdentity = JSONExactTextIdentity(text.wrappedValue)
    }

    private var resolution: IndexWorkspaceResolution {
        workspaceSemantic.resolvedWorkspace
    }

    private var behavior: IndexWorkspaceBehaviorContract {
        resolution.behavior
    }

    var body: some View {
        IndexTextArea(
            placeholder: placeholder,
            text: $text,
            minHeight: minHeight,
            fillsHeight: fillsHeight,
            expandsWithContent: resolution.textArea.expandsWithContent,
            renderingMode: inputRenderingMode ?? resolution.textArea.renderingMode,
            lineBreakMode: behavior.semanticLineBreakMode,
            autoFocus: autoFocus,
            caretPlacementRequestToken: caretPlacementRequestToken,
            temporaryHighlights: temporaryHighlights,
            scrollRequest: scrollRequest,
            diagnosticMarker: diagnosticMarker,
            diagnosticNavigationToken: diagnosticNavigationToken,
            inputPolicy: inputPolicy,
            embedsFlat: embedsFlat,
            lineNumbers: lineNumbers,
            onFileDrop: onFileDrop,
            droppedFile: droppedFile
        )
    }
}

struct IndexWorkspaceOutputSurface: View {
    let text: String
    let placeholder: String
    var minHeight: CGFloat = 220
    var fillsHeight = false
    var lineNumbers = false
    var colorize: ((String) -> AttributedString)? = nil
    /// Prototype v3 embedded-code presentation: drop the surface's own field
    /// box so the owning workbench panel supplies the surface edge to edge.
    var embedsFlat = false
    var workspaceSemantic: IndexWorkspaceSemantic = .unmigratedPageDefault

    private var behavior: IndexWorkspaceBehaviorContract {
        workspaceSemantic.behavior
    }

    var body: some View {
        IndexOutputSurface(
            text: text,
            placeholder: placeholder,
            minHeight: minHeight,
            fillsHeight: fillsHeight,
            scrollsInternally: behavior.outputScrollsInternally,
            lineBreakMode: behavior.semanticLineBreakMode,
            lineNumbers: lineNumbers,
            colorize: colorize,
            embedsFlat: embedsFlat
        )
    }
}

struct IndexWorkspaceResultSurface<Content: View>: View {
    var workspaceSemantic: IndexWorkspaceSemantic = .naturalHeightShortResultPanel
    let content: Content

    init(
        workspaceSemantic: IndexWorkspaceSemantic = .naturalHeightShortResultPanel,
        @ViewBuilder content: () -> Content
    ) {
        self.workspaceSemantic = workspaceSemantic
        self.content = content()
    }

    private var behavior: IndexWorkspaceBehaviorContract {
        workspaceSemantic.behavior
    }

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: behavior.usesNaturalHeightSurface)
    }
}

private extension IndexWorkspaceBehaviorContract {
    var semanticLineBreakMode: NSLineBreakMode {
        wrapsLongTokensToAvailableWidth ? .byCharWrapping : .byWordWrapping
    }
}

// MARK: - IndexInputHeaderAccessory

enum IndexInputCountPresentation: Equatable {
    case characters
    case charactersOrUTF8Size(largeTextByteLimit: Int)

    func label(for text: String) -> String {
        switch self {
        case .characters:
            return "\(text.count) 字符"
        case let .charactersOrUTF8Size(largeTextByteLimit):
            let byteCount = text.utf8.count
            guard byteCount > max(0, largeTextByteLimit) else {
                return "\(text.count) 字符"
            }
            return "\(ByteSizeFormatter.format(bytes: byteCount)) UTF-8"
        }
    }
}

/// 输入面板头部附件：字符计数 + 清空按钮。宽度不足时清空按钮降级为
/// 纯图标形态（ViewThatFits 两个候选），两者都固定尺寸不挤压面板标题。
struct IndexInputHeaderAccessory: View {
    var showsInputCount = true
    var clearDisabled = false
    var onClear: (() -> Void)?
    private let countText: String

    init(
        countText: String,
        showsInputCount: Bool = true,
        clearDisabled: Bool = false,
        onClear: (() -> Void)? = nil
    ) {
        self.countText = countText
        self.showsInputCount = showsInputCount
        self.clearDisabled = clearDisabled
        self.onClear = onClear
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(clearIconOnly: false)

            if let onClear {
                row(clearIconOnly: true)
            }
        }
    }

    private func row(clearIconOnly: Bool) -> some View {
        HStack(spacing: 8) {
            if showsInputCount {
                IndexInputCountLabel(text: countText)
            }

            if let onClear {
                IndexClearButton(isDisabled: clearDisabled, iconOnly: clearIconOnly, action: onClear)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - IndexInputCountLabel

struct IndexInputCountLabel: View {
    let text: String
    /// Drives the digit-roll tween; nil for free-form status strings.
    private let numericCount: Int?

    init(count: Int) {
        text = "\(count) 字符"
        numericCount = count
    }

    init(text: String) {
        self.text = text
        numericCount = nil
    }

    var body: some View {
        Text(text)
            .font(ToolTypography.monoCaption)
            .foregroundStyle(ToolTheme.textTertiary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .toolNumericTransition(value: numericCount ?? 0)
    }
}

// MARK: - Value Motion Policy
