import SwiftUI

enum ToolFieldHeight: Equatable {
    case field38
    case inlineNumber28
    case bar44

    var value: CGFloat {
        switch self {
        case .field38: return ToolMetrics.ControlHeight.field38
        case .inlineNumber28: return ToolMetrics.ControlHeight.compact28
        case .bar44: return ToolMetrics.ControlHeight.bar44
        }
    }
}

enum ToolFieldSurfaceKind: Equatable {
    case editor
    case panel
    case readOnly

    var fill: Color {
        switch self {
        case .editor: return ToolTheme.editorBackground
        case .panel, .readOnly: return ToolTheme.panelBackground
        }
    }

    var border: Color {
        switch self {
        case .editor, .panel, .readOnly: return ToolTheme.border
        }
    }
}

extension View {
    /// v9 field surface: one fill, one hairline, one focus width. No field
    /// shadow. Pages pass the height role instead of writing frame(height:).
    func toolFieldSurface(
        focused: Bool = false,
        height: ToolFieldHeight = .field38,
        surface: ToolFieldSurfaceKind = .editor
    ) -> some View {
        self
            .frame(height: height.value)
            .background(
                surface.fill,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(
                        focused ? ToolTheme.focusRing : surface.border,
                        lineWidth: focused ? ToolMetrics.BorderWidth.focus : ToolMetrics.BorderWidth.hairline
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
    }
}
