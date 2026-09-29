import AppKit
import XToolsCore
import SwiftUI

struct IndexWorkspaceTextArea: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 220
    var maxHeightRatio: CGFloat? = nil
    var fillsHeight = false
    var autoFocus = false
    var caretPlacementRequestToken: Int? = nil
    var temporaryHighlights: IndexTextAreaTemporaryHighlights? = nil
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
        maxHeightRatio: CGFloat? = nil,
        fillsHeight: Bool = false,
        autoFocus: Bool = false,
        caretPlacementRequestToken: Int? = nil,
        temporaryHighlights: IndexTextAreaTemporaryHighlights? = nil,
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
        self.maxHeightRatio = maxHeightRatio
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
            maxHeightRatio: maxHeightRatio,
            fillsHeight: fillsHeight,
            expandsWithContent: resolution.textArea.expandsWithContent,
            renderingMode: inputRenderingMode ?? resolution.textArea.renderingMode,
            lineBreakMode: behavior.semanticLineBreakMode,
            autoFocus: autoFocus,
            caretPlacementRequestToken: caretPlacementRequestToken,
            temporaryHighlights: temporaryHighlights,
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

    var usesNaturalHeightSurface: Bool {
        fillBehavior == .naturalHeight && outputScrolling == .pageOuter
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

struct IndexInputHeaderAccessory<PrimaryControl: View, CompactControl: View>: View {
    var showsInputCount = true
    var clearDisabled = false
    var onClear: (() -> Void)?
    var usesCompactControl = false
    var iconOnlyClearFallback = false
    private let countText: String
    private let primaryControl: PrimaryControl
    private let compactControl: CompactControl

    init(
        count: Int,
        showsInputCount: Bool = true,
        clearDisabled: Bool = false,
        onClear: (() -> Void)? = nil,
        usesCompactControl: Bool = false,
        iconOnlyClearFallback: Bool = false,
        @ViewBuilder primaryControl: () -> PrimaryControl,
        @ViewBuilder compactControl: () -> CompactControl
    ) {
        self.init(
            countText: "\(count) 字符",
            showsInputCount: showsInputCount,
            clearDisabled: clearDisabled,
            onClear: onClear,
            usesCompactControl: usesCompactControl,
            iconOnlyClearFallback: iconOnlyClearFallback,
            primaryControl: primaryControl,
            compactControl: compactControl
        )
    }

    init(
        countText: String,
        showsInputCount: Bool = true,
        clearDisabled: Bool = false,
        onClear: (() -> Void)? = nil,
        usesCompactControl: Bool = false,
        iconOnlyClearFallback: Bool = false,
        @ViewBuilder primaryControl: () -> PrimaryControl,
        @ViewBuilder compactControl: () -> CompactControl
    ) {
        self.countText = countText
        self.showsInputCount = showsInputCount
        self.clearDisabled = clearDisabled
        self.onClear = onClear
        self.usesCompactControl = usesCompactControl
        self.iconOnlyClearFallback = iconOnlyClearFallback
        self.primaryControl = primaryControl()
        self.compactControl = compactControl()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(clearIconOnly: false) { primaryControl }

            if onClear != nil {
                row(clearIconOnly: true) { primaryControl }
            }

            if usesCompactControl {
                row(clearIconOnly: true) { compactControl }
            }

            if iconOnlyClearFallback, let onClear {
                IndexClearButton(isDisabled: clearDisabled, iconOnly: true, action: onClear)
            }
        }
    }

    private func row<Control: View>(
        clearIconOnly: Bool,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 8) {
            if showsInputCount {
                IndexInputCountLabel(text: countText)
            }

            control()

            if let onClear {
                IndexClearButton(isDisabled: clearDisabled, iconOnly: clearIconOnly, action: onClear)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

extension IndexInputHeaderAccessory where PrimaryControl == EmptyView, CompactControl == EmptyView {
    init(
        count: Int,
        showsInputCount: Bool = true,
        clearDisabled: Bool = false,
        onClear: (() -> Void)? = nil,
        iconOnlyClearFallback: Bool = true
    ) {
        self.init(
            count: count,
            showsInputCount: showsInputCount,
            clearDisabled: clearDisabled,
            onClear: onClear,
            usesCompactControl: false,
            iconOnlyClearFallback: iconOnlyClearFallback,
            primaryControl: { EmptyView() },
            compactControl: { EmptyView() }
        )
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
