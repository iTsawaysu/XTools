import SwiftUI

public struct IndexDropZoneModifier: ViewModifier {
    @Binding var isTargeted: Bool
    let onFile: (URL) -> Void
    let onMultipleFiles: (() -> Void)?

    public func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
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

public extension View {
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
