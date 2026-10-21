import SwiftUI
import XToolsDesign

/// P5 stacked workbench.
///
/// One natural-height paper for scroll-height pages whose workflow stacks
/// several working bands: parameters above, sibling preview columns in the
/// middle, the derived output below. The shell owns only the paper chrome;
/// every band is composed from the shared `IndexWorkbenchPane` (its 44pt
/// title row closes with a hairline), so stacked-band pages cannot drift
/// back into separate cards.
struct IndexStackedWorkbench<Bands: View>: View {
    @ViewBuilder private let bands: () -> Bands

    init(@ViewBuilder bands: @escaping () -> Bands) {
        self.bands = bands
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bands()
        }
        // Scroll pages still propose a finite viewport height, which would let
        // the panes' stretch frames grab a share of it and strand empty bands.
        // A stacked paper takes its ideal height and lets the page background
        // breathe underneath instead.
        .fixedSize(horizontal: false, vertical: true)
        .background(
            ToolTheme.panelBackground,
            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.panel, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
