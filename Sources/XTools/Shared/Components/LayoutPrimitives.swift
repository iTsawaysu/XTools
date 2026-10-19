import SwiftUI
import XToolsDesign

struct ToolDivider: View {
    var body: some View {
        Rectangle()
            .fill(ToolTheme.border)
            .frame(height: 0.5)
    }
}
