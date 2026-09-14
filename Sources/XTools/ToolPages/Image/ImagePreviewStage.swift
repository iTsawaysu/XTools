import AppKit
import SwiftUI

enum IndexImagePreviewReplacementMotion {
    case animated
    case immediate
}

struct IndexImagePreviewStage: View {
    static let defaultMaxDisplayWidth: CGFloat = 720
    static let defaultMaxDisplayHeight: CGFloat = 480

    let image: NSImage?
    let accessibilityLabel: String
    var accessibilityValue = ""
    var placeholder = ""
    var maxDisplayWidth: CGFloat = Self.defaultMaxDisplayWidth
    var maxDisplayHeight: CGFloat = Self.defaultMaxDisplayHeight
    var fillsHeight = false
    var spacing: CGFloat = 8
    var replacementMotion: IndexImagePreviewReplacementMotion = .animated
    private let footer: AnyView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        image: NSImage?,
        accessibilityLabel: String,
        accessibilityValue: String = "",
        placeholder: String = "",
        maxDisplayWidth: CGFloat = Self.defaultMaxDisplayWidth,
        maxDisplayHeight: CGFloat = Self.defaultMaxDisplayHeight,
        fillsHeight: Bool = false,
        spacing: CGFloat = 8,
        replacementMotion: IndexImagePreviewReplacementMotion = .animated
    ) {
        self.image = image
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.placeholder = placeholder
        self.maxDisplayWidth = maxDisplayWidth
        self.maxDisplayHeight = maxDisplayHeight
        self.fillsHeight = fillsHeight
        self.spacing = spacing
        self.replacementMotion = replacementMotion
        self.footer = AnyView(EmptyView())
    }

    init<Footer: View>(
        image: NSImage?,
        accessibilityLabel: String,
        accessibilityValue: String = "",
        placeholder: String = "",
        maxDisplayWidth: CGFloat = Self.defaultMaxDisplayWidth,
        maxDisplayHeight: CGFloat = Self.defaultMaxDisplayHeight,
        fillsHeight: Bool = false,
        spacing: CGFloat = 8,
        replacementMotion: IndexImagePreviewReplacementMotion = .animated,
        @ViewBuilder footer: () -> Footer
    ) {
        self.image = image
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.placeholder = placeholder
        self.maxDisplayWidth = maxDisplayWidth
        self.maxDisplayHeight = maxDisplayHeight
        self.fillsHeight = fillsHeight
        self.spacing = spacing
        self.replacementMotion = replacementMotion
        self.footer = AnyView(footer())
    }

    private var imageIdentity: String {
        guard let image else {
            return "placeholder:\(placeholder)"
        }

        return "image:\(ObjectIdentifier(image).hashValue)"
    }

    var body: some View {
        VStack(spacing: spacing) {
            if let image {
                IndexImagePreviewImage(
                    image: image,
                    accessibilityLabel: accessibilityLabel,
                    accessibilityValue: accessibilityValue,
                    maxDisplayWidth: maxDisplayWidth,
                    maxDisplayHeight: maxDisplayHeight
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)
            } else if !placeholder.isEmpty {
                Text(placeholder)
                    .font(ToolTypography.bodyPlain)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .center)
                    .toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)
            }

            footer
        }
        .padding(ToolMetrics.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
        .animation(
            replacementMotion == .animated
                ? ToolMotion.animation(ToolMotion.Preset.panelReveal, reduceMotion: reduceMotion)
                : nil,
            value: imageIdentity
        )
        .transaction { transaction in
            guard replacementMotion == .immediate else { return }
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}

struct IndexImagePreviewImage: View {
    let image: NSImage
    let accessibilityLabel: String
    var accessibilityValue = ""
    var maxDisplayWidth: CGFloat = IndexImagePreviewStage.defaultMaxDisplayWidth
    var maxDisplayHeight: CGFloat = IndexImagePreviewStage.defaultMaxDisplayHeight

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: maxDisplayWidth, maxHeight: maxDisplayHeight)
            .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
    }
}

private struct ImageInputDropDestinationModifier: ViewModifier {
    @Binding var isTargeted: Bool
    let onFile: (URL) -> Void
    let onMultipleFiles: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(
                isTargeted ? ToolTheme.selectionFill : Color.clear,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                    .strokeBorder(
                        isTargeted ? ToolTheme.accentBorder : Color.clear,
                        lineWidth: 1
                    )
            }
            .dropDestination(for: URL.self) { urls, _ in
                switch SingleFileDropResolver.resolve(urls) {
                case .unhandled:
                    return false
                case .accepted(let url):
                    onFile(url)
                    return true
                case .rejectedMultipleFiles:
                    onMultipleFiles()
                    return false
                }
            } isTargeted: { targeted in
                isTargeted = targeted
            }
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: isTargeted)
    }
}

extension View {
    func imageInputDropDestination(
        isTargeted: Binding<Bool>,
        onFile: @escaping (URL) -> Void,
        onMultipleFiles: @escaping () -> Void
    ) -> some View {
        modifier(
            ImageInputDropDestinationModifier(
                isTargeted: isTargeted,
                onFile: onFile,
                onMultipleFiles: onMultipleFiles
            )
        )
    }
}
