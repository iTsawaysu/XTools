import SwiftUI

/// Unified surface treatment for cards, fields, panels, and floating layers.
///
/// All tool-page "card" backgrounds (fill + border stroke + continuous corner)
/// must go through `.indexSurface` so corner radius stays on the
/// `ToolMetrics.CornerRadius` ladder instead of scattering magic values.
enum IndexSurfaceShape {
    /// Dense workbench panels (3pt).
    case panel
    /// Small controls: buttons, chips, segment items (6pt).
    case control
    /// Input fields, KV rows, and large buttons (8pt).
    case field
    /// Resting content cards: a quiet surface with a small, intentional lift.
    /// Use this for dashboard cards and other persistent content containers;
    /// reserve `.modal` for transient layers such as palettes and sheets.
    case card
    /// Floating layers: command palette, toast, popover, empty-state tiles (10pt).
    case modal
    /// Fully rounded (Capsule).
    case pill
    /// Explicit radius — escape hatch for one-off shapes (e.g. nested radii).
    case custom(CGFloat)

    var radius: CGFloat {
        switch self {
        case .panel: return ToolMetrics.CornerRadius.panel
        case .control: return ToolMetrics.CornerRadius.control
        case .field: return ToolMetrics.CornerRadius.field
        case .card: return ToolMetrics.CornerRadius.card
        case .modal: return ToolMetrics.CornerRadius.modal
        case .pill: return 999
        case .custom(let radius): return radius
        }
    }
}

extension View {
    /// Fills the view's background with `fill` inside a continuous rounded
    /// rectangle and strokes the same shape with `border`.
    func indexSurface(
        _ shape: IndexSurfaceShape = .field,
        fill: Color = ToolTheme.panelBackground,
        border: Color = ToolTheme.border,
        borderWidth: CGFloat = 0.5
    ) -> some View {
        modifier(IndexSurfaceModifier(shape: shape, fill: fill, border: border, borderWidth: borderWidth))
    }
}

private struct IndexSurfaceModifier: ViewModifier {
    let shape: IndexSurfaceShape
    let fill: Color
    let border: Color
    let borderWidth: CGFloat

    func body(content: Content) -> some View {
        if case .pill = shape {
            content
                .background(fill, in: Capsule(style: .continuous))
                .overlay { Capsule(style: .continuous).strokeBorder(border, lineWidth: borderWidth) }
                .contentShape(Capsule(style: .continuous))
        } else {
            content
                .background(fill, in: RoundedRectangle(cornerRadius: shape.radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: shape.radius, style: .continuous)
                        .strokeBorder(border, lineWidth: borderWidth)
                }
                .contentShape(RoundedRectangle(cornerRadius: shape.radius, style: .continuous))
                .modifier(IndexSurfaceElevation(shape: shape))
        }
    }
}

private struct IndexSurfaceElevation: ViewModifier {
    let shape: IndexSurfaceShape

    func body(content: Content) -> some View {
        switch shape {
        case .modal:
            content.toolShadow(ToolTheme.Shadow.modal)
        case .card:
            content.toolShadow(ToolTheme.Shadow.card)
        case .field:
            content.toolShadow(ToolTheme.Shadow.panel)
        default:
            content
        }
    }
}
