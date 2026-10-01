import AppKit
import SwiftUI

enum IndexImagePreviewReplacementMotion {
    case animated
    case immediate
}

/// Footer 泛型化：以 @ViewBuilder 存储替代 AnyView 擦除，避免每次 body
/// 重建 footer 的类型身份与 diff 开销；无 footer 的调用点由
/// `where Footer == EmptyView` 的便捷 init 覆盖，调用侧 API 不变。
/// 泛型类型不能携带存储型 static；默认尺寸收进非泛型命名空间，
/// 供 stage 与其只读图像面共享（ImageWorkflowSourceContractTests 锚定字面量）。
enum IndexImagePreviewStageMetrics {
    static let defaultMaxDisplayWidth: CGFloat = 720
    static let defaultMaxDisplayHeight: CGFloat = 480
}

struct IndexImagePreviewStage<Footer: View>: View {
    let image: NSImage?
    let accessibilityLabel: String
    var accessibilityValue = ""
    var placeholder = ""
    var maxDisplayWidth: CGFloat = IndexImagePreviewStageMetrics.defaultMaxDisplayWidth
    var maxDisplayHeight: CGFloat = IndexImagePreviewStageMetrics.defaultMaxDisplayHeight
    var fillsHeight = false
    var spacing: CGFloat = 8
    var replacementMotion: IndexImagePreviewReplacementMotion = .animated
    private let footer: Footer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 动画 identity 持 ObjectIdentifier 本体（Equatable）而非 hashValue：
    /// 哈希冲突会把「换图」误判为「未变」而静默吞掉替换动画。
    private enum ImagePreviewIdentity: Equatable {
        case placeholder(String)
        case image(ObjectIdentifier)
    }

    init(
        image: NSImage?,
        accessibilityLabel: String,
        accessibilityValue: String = "",
        placeholder: String = "",
        maxDisplayWidth: CGFloat = IndexImagePreviewStageMetrics.defaultMaxDisplayWidth,
        maxDisplayHeight: CGFloat = IndexImagePreviewStageMetrics.defaultMaxDisplayHeight,
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
        self.footer = footer()
    }

    private var imageIdentity: ImagePreviewIdentity {
        guard let image else {
            return .placeholder(placeholder)
        }

        return .image(ObjectIdentifier(image))
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

extension IndexImagePreviewStage where Footer == EmptyView {
    /// 无 footer 调用点的便捷入口（保持与旧非泛型 API 相同的调用形态）。
    init(
        image: NSImage?,
        accessibilityLabel: String,
        accessibilityValue: String = "",
        placeholder: String = "",
        maxDisplayWidth: CGFloat = IndexImagePreviewStageMetrics.defaultMaxDisplayWidth,
        maxDisplayHeight: CGFloat = IndexImagePreviewStageMetrics.defaultMaxDisplayHeight,
        fillsHeight: Bool = false,
        spacing: CGFloat = 8,
        replacementMotion: IndexImagePreviewReplacementMotion = .animated
    ) {
        self.init(
            image: image,
            accessibilityLabel: accessibilityLabel,
            accessibilityValue: accessibilityValue,
            placeholder: placeholder,
            maxDisplayWidth: maxDisplayWidth,
            maxDisplayHeight: maxDisplayHeight,
            fillsHeight: fillsHeight,
            spacing: spacing,
            replacementMotion: replacementMotion,
            footer: { EmptyView() }
        )
    }
}

struct IndexImagePreviewImage: View {
    let image: NSImage
    let accessibilityLabel: String
    var accessibilityValue = ""
    var maxDisplayWidth: CGFloat = IndexImagePreviewStageMetrics.defaultMaxDisplayWidth
    var maxDisplayHeight: CGFloat = IndexImagePreviewStageMetrics.defaultMaxDisplayHeight

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
