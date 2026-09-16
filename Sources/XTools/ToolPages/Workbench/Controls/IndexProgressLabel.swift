import SwiftUI

// MARK: - IndexProgressLabel

/// The only sanctioned processing indicator. Two layouts, one grammar:
/// - `inline` — spinner + caption in a text row (parameter changes, hashing,
///   file reads).
/// - `centered` — large centered spinner + caption for card/preview bodies
///   replaced by ongoing work.
///
/// Pages must not drop a bare `ProgressView()` outside this component or
/// `IndexProgressMotionLabel`.
struct IndexProgressLabel: View {
    enum Layout {
        case inline
        case centered
    }

    var message: String
    var layout: Layout = .inline

    var body: some View {
        switch layout {
        case .inline:
            HStack(spacing: 8) {
                spinner
                Text(message)
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .centered:
            VStack(spacing: 10) {
                spinner
                Text(message)
                    .font(ToolTypography.label)
                    .foregroundStyle(ToolTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private var spinner: some View {
        ProgressView()
            .controlSize(.small)
            .accessibilityLabel(message)
    }
}

/// Bare small spinner for in-control slots (button labels, status icons).
/// `ProgressView()` may only be constructed here and in
/// `IndexProgressMotionLabel` — pages pick one of the three sanctioned forms.
struct IndexProgressSpinner: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
    }
}
