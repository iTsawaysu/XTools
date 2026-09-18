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
    var inputRenderingMode: IndexTextAreaRenderingMode? = nil
    var inputPolicy: IndexTextAreaInputPolicy? = nil
    /// Prototype v3 embedded-code presentation (owning panel supplies the
    /// surface) with an optional AppKit line-number gutter.
    var embedsFlat = false
    var lineNumbers = false
    var onFileDrop: ((String) -> Void)? = nil
    var workspaceSemantic: IndexWorkspaceSemantic = .unmigratedPageDefault

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
            inputPolicy: inputPolicy,
            embedsFlat: embedsFlat,
            lineNumbers: lineNumbers,
            onFileDrop: onFileDrop
        )
    }
}

struct IndexWorkspaceOutputSurface: View {
    let text: String
    let placeholder: String
    var minHeight: CGFloat = 220
    var large = false
    var centered = false
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
            large: large,
            centered: centered,
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

// MARK: - IndexIOPair

struct IndexIOPair: View {
    let inputTitle: String
    let outputTitle: String
    let placeholder: String
    @Binding var input: String
    let output: String
    var inputError: String? = nil
    /// Line-number gutter for multi-line code/markup output (JSON/XML/YAML/SQL);
    /// leave off for prose or values.
    var outputLineNumbers = false
    var outputColorize: ((String) -> AttributedString)? = nil
    var showsInputCount = true
    var onClear: (() -> Void)? = nil
    var clearDisabled: Bool? = nil
    var autoFocus = true
    var workspaceSemantic: IndexWorkspaceSemantic = .unmigratedPageDefault

    private var isClearDisabled: Bool {
        clearDisabled ?? (input.isEmpty && output.isEmpty && inputError == nil)
    }

    var body: some View {
        IndexPairLayout(collapseWidth: 0, fillsHeight: true) {
            IndexPanel(inputTitle) {
                IndexWorkspaceTextArea(
                    placeholder: placeholder,
                    text: $input,
                    fillsHeight: true,
                    autoFocus: autoFocus,
                    workspaceSemantic: workspaceSemantic
                )
                .indexWorkspaceDiagnostic(inputError, tone: .error)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } accessory: {
                IndexInputHeaderAccessory(
                    count: input.count,
                    showsInputCount: showsInputCount,
                    clearDisabled: isClearDisabled,
                    onClear: onClear
                )
            }
            .terminal("STDIN")
            .verticallyFilling()
        } trailing: {
            IndexPanel(outputTitle) {
                IndexWorkspaceOutputSurface(
                    text: output,
                    placeholder: IndexEmptyStateCopy.outputWillShowHere,
                    fillsHeight: true,
                    lineNumbers: outputLineNumbers,
                    colorize: outputColorize,
                    workspaceSemantic: workspaceSemantic
                )
            } accessory: {
                IndexCopyButton(text: output)
            }
            .terminal("STDOUT")
            .verticallyFilling()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    init(count: Int) {
        text = "\(count) 字符"
    }

    init(text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(ToolTypography.monoCaption)
            .foregroundStyle(ToolTheme.textTertiary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Value Motion Policy

