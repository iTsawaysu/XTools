import SwiftUI

struct IndexDropZoneModifier: ViewModifier {
    @Binding var isTargeted: Bool
    let onFile: (URL) -> Void
    let onMultipleFiles: (() -> Void)?

 func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            // targeted 微光吸附：accent 同色光晕画在描边层（形状描边 + blur，
            // 不是内容 .shadow），只随悬停出现，离开即撤销。
            .background {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                    .strokeBorder(ToolTheme.accent.opacity(0.24), lineWidth: 2)
                    .blur(radius: 3)
                    .opacity(isTargeted ? 1 : 0)
            }
            .background(
                isTargeted ? ToolTheme.selectionFill : Color.clear,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
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
                    onMultipleFiles?()
                    return false
                }
            } isTargeted: { targeted in
                withToolAnimation(ToolMotion.Preset.controlFeedback) {
                    isTargeted = targeted
                }
            }
    }
}

extension View {
    func indexDropZone(
        isTargeted: Binding<Bool>,
        onFile: @escaping (URL) -> Void,
        onMultipleFiles: (() -> Void)? = nil
    ) -> some View {
        modifier(
            IndexDropZoneModifier(
                isTargeted: isTargeted,
                onFile: onFile,
                onMultipleFiles: onMultipleFiles
            )
        )
    }
}
