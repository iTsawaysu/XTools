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

// MARK: - IndexProgressHairline

/// Hairline linear progress: the sanctioned batch-work surface (multi-repo
/// scans and updates) where a spinner cannot express "how far along". A 2.5pt
/// accent fill rides a border-tone rail; determinate mode scales a
/// leading-anchored fill (transform-only), indeterminate mode sweeps a segment.
/// Reduce Motion keeps a static partial fill — a frozen loop reads as a hang,
/// so the still form preserves the "work is happening" signal.
struct IndexProgressHairline: View {
    var fraction: Double?
    var isIndeterminate: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweeping = false

    private static let railHeight: CGFloat = 2.5
    /// Indeterminate segment length as a fraction of the rail.
    private static let segmentRatio: CGFloat = 0.3

    init(isIndeterminate: Bool) {
        self.isIndeterminate = isIndeterminate
    }

    init(fraction: Double?) {
        self.fraction = fraction
    }

    private var clampedFraction: Double {
        guard let fraction else { return 0 }
        return min(max(fraction, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let railWidth = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ToolTheme.border)
                if isIndeterminate {
                    Capsule()
                        .fill(ToolTheme.accent)
                        .frame(width: railWidth * Self.segmentRatio)
                        .offset(x: sweeping ? railWidth * (1 - Self.segmentRatio) : 0)
                        .animation(
                            ToolMotion.animation(ToolMotion.Preset.hairlineSweep, reduceMotion: reduceMotion),
                            value: sweeping
                        )
                } else {
                    Capsule()
                        .fill(ToolTheme.accent)
                        .frame(width: railWidth)
                        .scaleEffect(x: clampedFraction, y: 1, anchor: .leading)
                        .toolAnimation(
                            ToolMotion.Curve.smoothOut(duration: ToolMotion.Duration.medium),
                            value: clampedFraction
                        )
                }
            }
        }
        .frame(height: Self.railHeight)
        .onAppear {
            // Under Reduce Motion the segment stays put: a still partial fill
            // instead of a frozen loop.
            guard !reduceMotion else { return }
            sweeping = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isIndeterminate ? "正在处理" : "处理进度")
        .accessibilityValue(isIndeterminate ? "进行中" : "\(Int((clampedFraction * 100).rounded()))%")
    }
}
