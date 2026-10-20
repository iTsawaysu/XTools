import AppKit
import SwiftUI

// MARK: - IndexSegmentedControl

struct IndexSegmentedControl<Value: Hashable>: View {
    enum Density {
        case regular
        case compact

        fileprivate var itemHeight: CGFloat {
            switch self {
            case .regular: ToolMetrics.ControlHeight.small
            case .compact: ToolMetrics.ControlHeight.compact
            }
        }

        fileprivate var itemHorizontalPadding: CGFloat {
            switch self {
            case .regular: 13
            case .compact: 7
            }
        }
    }

    /// How the selected segment renders: the shared floating spring cursor,
    /// or the inline matched-geometry fill the compact option pickers use
    /// (nested pill, control-label typography, tone-aware tray border).
    enum SelectionStyle {
        case cursor
        case filled
    }

    let items: [(Value, String)]
    @Binding var selection: Value
    let density: Density
    let selectionStyle: SelectionStyle
    var tone: ToolFeedbackTone? = nil

    /// Segment bounds published to the shared cursor layer (same anchor
    /// family as the command-palette selection highlight).
    @State private var segmentAnchors: [Value: Anchor<CGRect>] = [:]
    @Namespace private var filledSelectionNamespace

    init(
        items: [(Value, String)],
        selection: Binding<Value>,
        density: Density = .regular,
        selectionStyle: SelectionStyle = .cursor,
        tone: ToolFeedbackTone? = nil
    ) {
        self.items = items
        self._selection = selection
        self.density = density
        self.selectionStyle = selectionStyle
        self.tone = tone
    }

    var body: some View {
        if selectionStyle == .filled {
            filledBody
        } else {
            cursorBody
        }
    }

    // MARK: Filled selection (the former IndexOptionPicker)

    private var filledBody: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                FilledItem(
                    label: item.1,
                    isSelected: selection == item.0,
                    namespace: filledSelectionNamespace
                ) {
                    selection = item.0
                }
            }
        }
        .padding(2)
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(tone?.tint.opacity(0.7) ?? ToolTheme.border, lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .toolAnimation(ToolMotion.Preset.settle, value: selection)
    }

    /// One filled-selection segment: selected fill springs between segments
    /// through matched geometry inside the tray.
    private struct FilledItem: View {
        let label: String
        let isSelected: Bool
        let namespace: Namespace.ID
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(label)
                    .font(ToolTypography.controlLabel(weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? ToolTheme.accentHover : ToolTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 11)
                    .frame(height: ToolMetrics.ControlHeight.small)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                                .fill(ToolTheme.selectionFill)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                                .strokeBorder(ToolTheme.selectionStroke, lineWidth: 1)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Floating cursor selection

    private var cursorBody: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                Item(label: item.1, isSelected: selection == item.0, density: density) {
                    selection = item.0
                }
                .anchorPreference(
                    key: IndexSegmentedCursorAnchorKey<Value>.self,
                    value: .bounds
                ) { [item.0: $0] }
            }
        }
        .padding(2)
        // 分段控件是一个 AX 组：子段保持各自可达，但组有统一标签语义
        //（调用方可用 .accessibilityLabel 命名，同 EmojiPickerPage 先例）。
        .accessibilityElement(children: .contain)
        // Wave 2 sliding cursor: the selected fill floats behind the segments
        // but ABOVE the tray's opaque editorBackground — stacking it outside
        // that background would hide it completely.
        .background {
            GeometryReader { proxy in
                IndexSegmentedCursorLayer(
                    activeFrame: segmentAnchors[selection].map { proxy[$0] },
                    selection: selection
                )
            }
        }
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .onPreferenceChange(IndexSegmentedCursorAnchorKey<Value>.self) { segmentAnchors = $0 }
    }

    /// A single segment. Holds its own hover state so unselected segments give
    /// feedback on pointer-over; the selected fill belongs to the shared
    /// cursor layer, so a selected segment keeps a transparent background.
    private struct Item: View {
        let label: String
        let isSelected: Bool
        let density: Density
        let action: () -> Void

        @State private var isHovering = false

        private var background: Color {
            if isSelected { return Color.clear }
            return isHovering ? ToolTheme.hoverFill : Color.clear
        }

        var body: some View {
            Button(action: action) {
                Text(label)
                    .font(ToolTypography.label)
                    .foregroundStyle(isSelected ? ToolTheme.textPrimary : ToolTheme.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, density.itemHorizontalPadding)
                    .frame(height: density.itemHeight)
                    .background(background, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .onHover { isHovering = $0 }
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: isHovering)
            .toolAnimation(ToolMotion.SegmentedCursor.labelXfade, value: isSelected)
        }
    }
}

/// Segment bounds, published once per segment and resolved by the cursor
/// layer in tray coordinates (command-palette row-anchor family).
private struct IndexSegmentedCursorAnchorKey<Value: Hashable>: PreferenceKey {
    static var defaultValue: [Value: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [Value: Anchor<CGRect>],
        nextValue: () -> [Value: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// One cursor flight snapshot: the horizontal travel the cursor springs
/// across, sampled for the mid-flight stretch envelope.
private struct IndexSegmentedCursorFlight: Equatable {
    let fromX: CGFloat
    let toX: CGFloat

    /// Flight progress at a sampled cursor position, clamped to [0, 1].
    func progress(at x: CGFloat) -> CGFloat {
        let travel = toX - fromX
        guard travel != 0 else { return 1 }
        return min(max((x - fromX) / travel, 0), 1)
    }
}

/// Springs the cursor horizontally; mid-flight the capsule stretches to
/// `ToolMotion.SegmentedCursor.stretchPeak` through the same 4p(1-p)
/// envelope as the sidebar pill and palette highlight, settling to 1 on
/// arrival. `x` is the animatable channel (driven by the shared spring).
@MainActor
private struct IndexSegmentedCursorFlightEffect: GeometryEffect {
    let flight: IndexSegmentedCursorFlight?
    var x: CGFloat

    var animatableData: CGFloat {
        get { x }
        set { x = newValue }
    }

    nonisolated func effectValue(size: CGSize) -> ProjectionTransform {
        var transform = CGAffineTransform(translationX: x, y: 0)
        if let flight {
            let progress = flight.progress(at: x)
            let stretch = (ToolMotion.SegmentedCursor.stretchPeak - 1) * 4 * progress * (1 - progress)
            transform = transform.translatedBy(x: size.width / 2, y: 0)
            transform = transform.scaledBy(x: 1 + stretch, y: 1)
            transform = transform.translatedBy(x: -size.width / 2, y: 0)
        }
        return ProjectionTransform(transform)
    }
}

/// The floating selected-segment fill behind the segments. Selection changes
/// spring the cursor to the new segment on the fast selection spring (width
/// follows the target segment on the same arc); first placement and Reduce
/// Motion drop it in place without motion. Pure geometry changes (live resize,
/// font metric swaps) glue the cursor to the new frame instantly — the same
/// selection-keyed intent gating the palette highlight uses, so the stretch
/// envelope never replays while the window is being dragged.
private struct IndexSegmentedCursorLayer<Value: Hashable>: View {
    let activeFrame: CGRect?
    let selection: Value

    @State private var flight: IndexSegmentedCursorFlight?
    @State private var settledFrame: CGRect?
    @State private var settledSelection: Value?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Settled selection still holds the previous segment during the render
    /// pass where a tap lands, so this flips true exactly once per selection
    /// change and stays false across geometry-only frame changes.
    private var selectionChanged: Bool {
        selection != settledSelection
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let activeFrame {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                    .fill(ToolTheme.elevatedBackground)
                    .frame(width: activeFrame.width, height: activeFrame.height)
                    .modifier(IndexSegmentedCursorFlightEffect(
                        flight: flight,
                        x: activeFrame.minX
                    ))
                    .offset(y: activeFrame.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(
            !reduceMotion && settledFrame != nil
                ? ToolMotion.SegmentedCursor.slide
                : nil,
            value: selection
        )
        .onChange(of: activeFrame) { newFrame in
            if !reduceMotion,
               selectionChanged,
               let previousFrame = settledFrame,
               let newFrame {
                flight = IndexSegmentedCursorFlight(
                    fromX: previousFrame.minX,
                    toX: newFrame.minX
                )
            } else {
                flight = nil
            }
            settledFrame = newFrame
            settledSelection = selection
        }
    }
}


/// Structural content ownership for a segmented mode switch.
///
/// The old content fades out, swaps while hidden, then the new content fades
/// in with a 3pt rise. A plain cross-fade would overlap two dense control
/// bars at partial opacity and read as a double-exposure. Intra-mode value
/// updates do not change `id`, so they stay immediate (or use their own
/// value/text transition).
struct IndexModeContent<ID: Hashable, Content: View>: View {
    let id: ID
    var fillsHeight = false
    private let content: (ID) -> Content
    @State private var displayedID: ID
    @State private var isVisible = true
    @State private var handoffTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        id: ID,
        fillsHeight: Bool = false,
        @ViewBuilder content: @escaping (ID) -> Content
    ) {
        self.id = id
        self.fillsHeight = fillsHeight
        self.content = content
        _displayedID = State(initialValue: id)
    }

    var body: some View {
        content(displayedID)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : ToolMotion.Distance.modeContentRise)
            .frame(
                maxWidth: fillsHeight ? .infinity : nil,
                maxHeight: fillsHeight ? .infinity : nil,
                alignment: .topLeading
            )
            .onChange(of: id) { newID in
                guard newID != displayedID else { return }
                handoffTask?.cancel()

                guard !reduceMotion else {
                    displayedID = newID
                    isVisible = true
                    return
                }

                withAnimation(ToolMotion.ModeContent.exit) {
                    isVisible = false
                }
                handoffTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(ToolMotion.ModeContent.handoffDelay * 1_000_000_000))
                    guard !Task.isCancelled else { return }

                    let transaction = ToolMotion.disabledTransaction
                    withTransaction(transaction) {
                        displayedID = newID
                        isVisible = false
                    }

                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    withAnimation(ToolMotion.ModeContent.enter) {
                        isVisible = true
                    }
                }
            }
            .onDisappear {
                handoffTask?.cancel()
            }
    }
}
