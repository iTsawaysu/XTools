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

extension View {
    /// 批量工具（格式转换）的多文件拖放入口：1..N 个文件全部回调，
    /// 0 个文件交还系统（返回 false）。命中区可大于视觉高亮区：
    /// 整页命中时传 showsHighlight: false，高亮由输入区经
    /// imageDropHighlight 用同一份 isTargeted 呈现。
    func multiImageInputDropDestination(
        isTargeted: Binding<Bool>,
        onFiles: @escaping ([URL]) -> Void,
        showsHighlight: Bool = true
    ) -> some View {
        modifier(
            MultiImageInputDropDestinationModifier(
                isTargeted: isTargeted,
                onFiles: onFiles,
                showsHighlight: showsHighlight
            )
        )
    }

    /// 拖放命中高亮（填充 + 描边）：画在使用方内容层的背景上，因此使用方
    /// 自身表面必须透明。整页命中、输入区高亮的组合中，它挂在输入区内容上，
    /// 命中态由整页拖放目标共享下发。
    func imageDropHighlight(isActive: Bool) -> some View {
        modifier(ImageDropHighlightModifier(isActive: isActive))
    }
}

private struct ImageDropHighlightModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .background(
                isActive ? ToolTheme.selectionFill : Color.clear,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                    .strokeBorder(
                        isActive ? ToolTheme.accentBorder : Color.clear,
                        lineWidth: 1
                    )
            }
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: isActive)
    }
}

private struct MultiImageInputDropDestinationModifier: ViewModifier {
    @Binding var isTargeted: Bool
    let onFiles: ([URL]) -> Void
    var showsHighlight: Bool

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .imageDropHighlight(isActive: showsHighlight && isTargeted)
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty else {
                    return false
                }
                onFiles(urls)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: isTargeted)
    }
}
