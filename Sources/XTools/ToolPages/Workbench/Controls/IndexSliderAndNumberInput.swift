import AppKit
import SwiftUI

// MARK: - IndexSlider

/// Pure-SwiftUI horizontal slider used in place of `SwiftUI.Slider`.
///
/// `SwiftUI.Slider` bridges AppKit `NSSlider`; instantiating one costs roughly
/// 230ms on this toolchain, so a page with three of them (the color tool) spent
/// ~700ms assembling the picker before its first visible frame — the measured
/// source of the color-page click lag. This control draws the track and knob
/// with SwiftUI primitives and drives the value from a `DragGesture`, keeping
/// the same `value`/`range`/`step` semantics without any AppKit bridge.
/// Track appearance for IndexSlider. `.fill` is the default progress-fill
/// track; gradient/alpha tracks span the full width (a progress fill over a
/// gradient would be meaningless).
enum IndexSliderTrack {
    case fill
    case gradient(LinearGradient)
    /// Checkerboard under a white→color gradient (alpha channels).
    case alpha(color: Color)
}

struct IndexSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var track: IndexSliderTrack = .fill

    private let knobDiameter: CGFloat = 16
    private let trackHeight: CGFloat = 4

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private var accessibilityText: String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// Drag-only sliders (step 0) still need a usable VoiceOver increment;
    /// fall back to a tenth of the range span.
    private var accessibilityStep: Double {
        if step > 0 { return step }
        let span = range.upperBound - range.lowerBound
        return span > 0 ? span / 10 : 0
    }

    var body: some View {
        GeometryReader { geometry in
            let usableWidth = max(geometry.size.width - knobDiameter, 1)
            let knobX = usableWidth * fraction

            ZStack(alignment: .leading) {
                trackView
                    .frame(height: trackHeight)
                    .frame(maxWidth: .infinity)

                if case .fill = track {
                    Capsule()
                        .fill(ToolTheme.accent)
                        .frame(width: knobX + knobDiameter / 2, height: trackHeight)
                }

                Circle()
                    .fill(ToolTheme.accent)
                    .overlay { Circle().strokeBorder(ToolTheme.onAccent.opacity(0.9), lineWidth: 1.5) }
                    .frame(width: knobDiameter, height: knobDiameter)
                    .offset(x: knobX)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        updateValue(atX: drag.location.x, usableWidth: usableWidth)
                    }
            )
        }
        .frame(height: knobDiameter)
        .accessibilityElement()
        .accessibilityValue(Text(accessibilityText))
        .accessibilityAdjustableAction { direction in
            guard accessibilityStep > 0 else { return }
            switch direction {
            case .increment: setValue(value + accessibilityStep)
            case .decrement: setValue(value - accessibilityStep)
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private var trackView: some View {
        switch track {
        case .fill:
            Capsule()
                .fill(ToolTheme.editorBackground)
                .overlay {
                    Capsule().strokeBorder(ToolTheme.border, lineWidth: 1)
                }
        case .gradient(let gradient):
            Capsule()
                .fill(gradient)
                .overlay {
                    Capsule().strokeBorder(ToolTheme.border, lineWidth: 1)
                }
        case .alpha(let color):
            ZStack {
                IndexCheckerboard()
                LinearGradient(
                    colors: [color.opacity(0), color],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .clipShape(Capsule(style: .continuous))
            .overlay {
                Capsule().strokeBorder(ToolTheme.border, lineWidth: 1)
            }
        }
    }

    private func updateValue(atX x: CGFloat, usableWidth: CGFloat) {
        let clampedFraction = min(max((x - knobDiameter / 2) / usableWidth, 0), 1)
        let raw = range.lowerBound + clampedFraction * (range.upperBound - range.lowerBound)
        setValue(raw)
    }

    private func setValue(_ raw: Double) {
        let stepped = step > 0 ? (raw / step).rounded() * step : raw
        let clamped = min(max(stepped, range.lowerBound), range.upperBound)
        if clamped != value {
            value = clamped
        }
    }
}

/// Tiny two-tone checkerboard used behind alpha sliders.
private struct IndexCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 3
            let rows = Int(ceil(size.height / side))
            let columns = Int(ceil(size.width / side))
            let light = Color(nsColor: .controlBackgroundColor)
            let dark = Color(nsColor: .controlBackgroundColor)
                .opacity(0.55)
            for row in 0..<max(rows, 1) {
                for column in 0..<max(columns, 1) {
                    let isLight = (row + column).isMultiple(of: 2)
                    let rect = CGRect(
                        x: CGFloat(column) * side,
                        y: CGFloat(row) * side,
                        width: side,
                        height: side
                    )
                    context.fill(Path(rect), with: .color(isLight ? light : dark))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Bare hit-testing style for page-local custom-chrome controls (dashed
/// pickers, anchor grids, inline toggles). Keeping the named style in the
/// shared library keeps `.buttonStyle(.plain)` out of page files.
struct IndexBareButtonStyle: ButtonStyle {
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - IndexNumberInput

struct IndexNumberInput: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var fieldWidth: CGFloat = 54
    var onCommit: (() -> Void)? = nil

    @State private var text = ""
    @State private var isFocused = false

    var body: some View {
        IndexTextInput(
            placeholder: "\(range.lowerBound)",
            text: $text,
            height: 30,
            alignment: .center,
            selectAllOnFocus: true,
            onSubmit: commitText,
            onFocusChange: { focused in
                isFocused = focused
                if focused {
                    text = "\(value)"
                } else {
                    commitText()
                }
            }
        )
        .frame(width: fieldWidth)
        .onAppear {
            setValue(value)
        }
        .onChange(of: text) { _ in
            sanitizeEditingText()
        }
        .onChange(of: value) { newValue in
            let normalized = normalizedValue(newValue)
            if normalized != newValue {
                value = normalized
            }
            if !isFocused {
                text = "\(normalized)"
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func commitText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let typedValue = Int(trimmed) else {
            text = "\(value)"
            return
        }

        setValue(typedValue)
        onCommit?()
    }

    private func sanitizeEditingText() {
        guard isFocused else { return }

        let digitsOnly = text.filter(\.isNumber)
        if digitsOnly != text {
            text = digitsOnly
            return
        }

        guard let typedValue = Int(digitsOnly), typedValue > range.upperBound else { return }
        setValue(range.upperBound)
    }

    private func setValue(_ newValue: Int) {
        let normalized = normalizedValue(newValue)
        value = normalized
        text = "\(normalized)"
    }

    private func normalizedValue(_ newValue: Int) -> Int {
        min(max(newValue, range.lowerBound), range.upperBound)
    }
}
