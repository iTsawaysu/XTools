import AppKit
import SwiftUI

enum IndexActionSymbol {
    static let clear = "xmark.circle"
    static let searchClear = "xmark.circle.fill"
    static let removeResource = "trash"
    static let reset = "arrow.counterclockwise"
    static let refresh = "arrow.clockwise"
    static let save = "square.and.arrow.down"
    static let copy = "doc.on.doc"
}

// MARK: - IndexButtonStyle

struct IndexButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, primary: primary)
    }

    /// Extracted into a `View` so we can hold `@State` for hover — `ButtonStyle.Configuration`
    /// exposes `isPressed` but not hover. `@Environment(\.isEnabled)` gates the hover visual
    /// so disabled buttons don't light up.
    private struct StyleBody: View {
        let configuration: Configuration
        let primary: Bool

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var hovering: Bool { isHovering && isEnabled }

        private var background: Color {
            if primary {
                return (configuration.isPressed || hovering) ? ToolTheme.accentHover : ToolTheme.accent
            }
            if configuration.isPressed { return ToolTheme.activeFill }
            // Quiet controls stay on the page surface until interaction. This
            // keeps action rows closer to Linear/Craft's low-noise grammar and
            // avoids a sea of bordered system buttons.
            return hovering ? ToolTheme.hoverFill : Color.clear
        }

        var body: some View {
            configuration.label
                .font(ToolTypography.bodyMedium)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(primary ? ToolTheme.onAccent : ToolTheme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(background, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                        .strokeBorder(primary ? ToolTheme.accent : (hovering ? ToolTheme.strongBorder : Color.clear), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
                .scaleEffect(!reduceMotion && configuration.isPressed ? ToolMotion.Scale.modal : 1)
                .onHover { isHovering = $0 }
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: hovering)
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: configuration.isPressed)
        }
    }
}

// MARK: - IndexSmallButtonStyle

struct IndexSmallButtonStyle: ButtonStyle {
    var done = false
    /// Framed secondary treatment (prototype v3 workbench actions): the button
    /// rests on `utilityBackground` inside a hairline instead of staying quiet
    /// on the page surface until hover.
    var framed = false

    init(done: Bool = false, framed: Bool = false) {
        self.done = done
        self.framed = framed
    }

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, done: done, framed: framed)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let done: Bool
        let framed: Bool

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var hovering: Bool { isHovering && isEnabled }

        private var background: Color {
            if done { return ToolTheme.successSoft }
            if configuration.isPressed { return ToolTheme.activeFill }
            if hovering { return framed ? ToolTheme.activeFill : ToolTheme.hoverFill }
            return framed ? ToolTheme.utilityBackground : Color.clear
        }

        private var border: Color {
            if done { return ToolTheme.successSoft }
            if hovering || configuration.isPressed { return ToolTheme.strongBorder }
            return framed ? ToolTheme.border : Color.clear
        }

        var body: some View {
            configuration.label
                .font(ToolTypography.buttonSmall)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(done ? ToolTheme.success : ToolTheme.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(background, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .scaleEffect(!reduceMotion && configuration.isPressed ? ToolMotion.Scale.pressed : 1)
                .onHover { isHovering = $0 }
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: hovering)
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: configuration.isPressed)
        }
    }
}

struct IndexIconActionButtonStyle: ButtonStyle {
    var isActive = false
    var activeTint: Color = ToolTheme.accent
    var tint: Color = ToolTheme.textSecondary
    var activeBackground: Color = ToolTheme.selectionFill

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(
            configuration: configuration,
            isActive: isActive,
            activeTint: activeTint,
            tint: tint,
            activeBackground: activeBackground
        )
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let isActive: Bool
        let activeTint: Color
        let tint: Color
        let activeBackground: Color

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var hovering: Bool { isHovering && isEnabled }

        private var foreground: Color {
            if isActive { return activeTint }
            return isEnabled ? tint : ToolTheme.textTertiary
        }

        private var background: Color {
            if configuration.isPressed && isEnabled { return ToolTheme.activeFill }
            if hovering { return ToolTheme.hoverFill }
            if isActive { return activeBackground }
            return Color.clear
        }

        var body: some View {
            configuration.label
                .font(ToolTypography.buttonSmall)
                .foregroundStyle(foreground)
                .frame(width: 24, height: 24)
                .background(background, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                .scaleEffect(configuration.isPressed ? ToolMotion.Scale.pressed : 1)
                .onHover { isHovering = $0 }
                .toolAnimation(
                    ToolMotion.Preset.controlFeedback,
                    value: [hovering, configuration.isPressed, isActive]
                )
                .transaction { transaction in
                    if reduceMotion { transaction.disablesAnimations = true }
                }
        }
    }
}

// MARK: - IndexCopyButton

struct IndexCopyButton: View {
    let text: String
    var title = "复制"
    var iconOnly = false
    /// Text-only label (prototype v3 workbench/params rows render actions
    /// without leading glyphs).
    var showsIcon = true
    var framed = false
    /// Overrides the canonical copied toast for batch actions (全部复制).
    var successToast: String? = nil

    @State private var feedback = IndexEphemeralActionFeedbackState()
    @Environment(\.toolToastCenter) private var toastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var copied: Bool { feedback.isPresented }

    var body: some View {
        Group {
            if iconOnly {
                copyButton.buttonStyle(IndexIconActionButtonStyle(
                    isActive: copied,
                    activeTint: ToolTheme.success,
                    activeBackground: ToolTheme.successSoft
                ))
            } else {
                copyButton.buttonStyle(IndexSmallButtonStyle(done: copied, framed: framed))
            }
        }
        .disabled(text.isEmpty)
        .help(copied ? "已复制" : title)
        .accessibilityLabel(copied ? "已复制" : title)
        .task(id: feedback.generation) {
            let generation = feedback.generation
            guard feedback.isPresented else { return }

            do {
                try await Task.sleep(for: IndexEphemeralActionFeedbackState.holdDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            feedback.finish(generation: generation)
        }
    }

    private var copyButton: some View {
        Button {
            guard !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            // setString 返回写入是否成功；忽略它会在剪贴板不可写时误报“已复制”。
            guard NSPasteboard.general.setString(text, forType: .string) else {
                toastCenter?.show("剪贴板写入失败。", tone: .error)
                return
            }
            toastCenter?.show(successToast ?? ToolFeedbackCopy.copied, tone: .success)
            feedback.trigger()
        } label: {
            if iconOnly {
                // Reduce Motion cuts directly between the SF Symbols; otherwise
                // the Wave 2 tick draws the checkmark (no label/width change).
                Group {
                    if reduceMotion {
                        Image(systemName: copied ? "checkmark" : IndexActionSymbol.copy)
                    } else {
                        IndexCopyTickIconSlot(generation: feedback.generation)
                    }
                }
                .font(ToolTypography.buttonSmall)
                .frame(width: 16, height: 16)
            } else {
                Label {
                    // Zero-deformation copy feedback: the visible title never
                    // changes (Wave 2 复制确认 tick); only the accessibility
                    // label/help announces 已复制.
                    Text(title)
                } icon: {
                    if showsIcon {
                        Group {
                            if reduceMotion {
                                Image(systemName: copied ? "checkmark" : IndexActionSymbol.copy)
                            } else {
                                IndexCopyTickIconSlot(generation: feedback.generation)
                            }
                        }
                    }
                }
                .font(ToolTypography.buttonSmall)
            }
        }
    }
}

// MARK: - IndexCopyTickIconSlot (Wave 2 copy-confirmation tick)

/// Fixed icon slot for the shared copy button (Wave 2 candidate d1): the copy
/// glyph fades out while a checkmark stroke-draws in (`Shape.trim` mirrors the
/// prototype's stroke-dashoffset), the icon box settles 0.94→1 once, the state
/// dwells 1400ms, then both glyphs cross-fade back symmetrically. Repeat clicks
/// during the dwell only reset the dwell timer — the draw never replays while
/// active. Reduce Motion stays at the call site (plain symbol cut, no draw,
/// no scale).
private struct IndexCopyTickIconSlot: View {
    let generation: Int

    @State private var isDwelling = false
    @State private var checkDraw: CGFloat = 0
    @State private var boxScale: CGFloat = 1
    @State private var dwellTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Image(systemName: IndexActionSymbol.copy)
                .opacity(isDwelling ? 0 : 1)

            IndexCopyTickCheckGlyph()
                .trim(from: 0, to: checkDraw)
                .stroke(.foreground, style: IndexCopyTickCheckGlyph.strokeStyle)
                .opacity(isDwelling ? 1 : 0)
        }
        .scaleEffect(boxScale)
        .onChange(of: generation) { _ in
            guard generation > 0 else { return }
            if isDwelling {
                resetDwell()
            } else {
                startDwell()
            }
        }
        .onDisappear {
            dwellTask?.cancel()
        }
    }

    /// First copy of a cycle: park at the pre-draw frame (check undrawn, box
    /// at 0.94) for one committed render — the SwiftUI analogue of the
    /// prototype keyframe `from` values — then run the enter choreography.
    private func startDwell() {
        dwellTask?.cancel()
        withTransaction(ToolMotion.disabledTransaction) {
            checkDraw = 0
            boxScale = ToolMotion.CopyTick.boxFrom
        }
        runDwell {
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(ToolMotion.CopyTick.fade) { isDwelling = true }
            withAnimation(ToolMotion.CopyTick.drawCurve) { checkDraw = 1 }
            withAnimation(ToolMotion.CopyTick.boxSettle) { boxScale = 1 }
        }
    }

    /// Repeat click while the dwell is active: only the hold timer restarts;
    /// the draw and the box settle never replay.
    private func resetDwell() {
        runDwell {}
    }

    /// One task owns the dwell tail: run `open`, hold for
    /// `ToolMotion.CopyTick.hold`, then fade both glyphs back symmetrically.
    private func runDwell(_ open: @escaping @MainActor () async -> Void) {
        dwellTask?.cancel()
        dwellTask = Task { @MainActor in
            await open()
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(ToolMotion.CopyTick.hold))
            guard !Task.isCancelled else { return }
            withAnimation(ToolMotion.CopyTick.fadeBack) { isDwelling = false }
        }
    }
}

/// Checkmark stroke glyph (prototype 16-unit check path), normalized to the
/// icon slot so `.trim` can draw it as one continuous stroke.
private struct IndexCopyTickCheckGlyph: Shape {
    /// Prototype icon stroke: 1.5 units in the 16-unit glyph box, round caps.
    static let strokeStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

    func path(in rect: CGRect) -> Path {
        // Prototype check path `M3 8.6l3.2 3L13 4.4` in a 16×16 viewBox.
        let scaleX = rect.width / 16
        let scaleY = rect.height / 16
        var path = Path()
        path.move(to: CGPoint(x: 3 * scaleX, y: 8.6 * scaleY))
        path.addLine(to: CGPoint(x: 6.2 * scaleX, y: 11.6 * scaleY))
        path.addLine(to: CGPoint(x: 13 * scaleX, y: 4.4 * scaleY))
        return path
    }
}

// MARK: - IndexPrimaryActionButton

/// Primary action with an optional keycap hint (prototype v3 `⌘↩` chip).
/// The key equivalent itself stays at the call site so pages keep one place
/// to look for shortcut wiring.
struct IndexPrimaryActionButton: View {
    let title: String
    var hint: String? = nil
    var help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title)
                if let hint {
                    IndexKeyboardHintLabel(hint: hint)
                }
            }
            // Toolbar halves can run tight; the prototype action must keep its
            // label and shed width through the compressible diagnostic slot
            // instead of collapsing into an empty accent pill.
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(IndexButtonStyle(primary: true))
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Tiny keycap chip rendered inside primary actions.
struct IndexKeyboardHintLabel: View {
    let hint: String

    var body: some View {
        Text(hint)
            .font(ToolTypography.keycap)
            .tracking(0.6)
            .foregroundStyle(ToolTheme.onAccent.opacity(0.95))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                ToolTheme.onAccent.opacity(0.20),
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

struct IndexProgressMotionLabel<ID: Hashable>: View {
    let title: String
    let systemImage: String
    let isProcessing: Bool
    let id: ID

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
            }
            .frame(width: 14, height: 14)
            .toolMotionIconSwap(id: id)

            Text(title)
                .toolMotionTextSwap(id: id)
        }
    }
}

// MARK: - IndexFieldHeader

/// Field/pane header row: small secondary label on the leading side, trailing
/// quick actions (copy, segmented options, menus). Single home for the
/// `HStack { Text(label); Spacer; actions }` pattern so every pane header in
/// the app shares one type scale and color.
struct IndexFieldHeader<Accessory: View>: View {
    let title: String
    let accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(ToolTypography.label)
                .foregroundStyle(ToolTheme.textSecondary)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            accessory
                .layoutPriority(2)
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

extension IndexFieldHeader where Accessory == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - IndexClearButton

struct IndexClearButton: View {
    let isDisabled: Bool
    var title = "清空"
    var iconOnly = false
    var showsIcon = true
    var framed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if iconOnly {
                Image(systemName: IndexActionSymbol.clear)
                    .font(ToolTypography.buttonSmall)
            } else if showsIcon {
                Label(title, systemImage: IndexActionSymbol.clear)
                    .font(ToolTypography.buttonSmall)
            } else {
                Text(title)
                    .font(ToolTypography.buttonSmall)
            }
        }
        .buttonStyle(IndexSmallButtonStyle(framed: framed))
        .disabled(isDisabled)
        .help(title)
        .accessibilityLabel(title)
    }
}

// MARK: - IndexIconButton

struct IndexIconButton: View {
    let systemImage: String
    let help: String
    /// `nil` models a momentary action. Passing a Boolean opts the control
    /// into toggle semantics for both styling and assistive technologies.
    var isActive: Bool? = nil
    var activeTint: Color = ToolTheme.accent
    var tint: Color = ToolTheme.textSecondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .toolMotionIconSwap(id: systemImage)
        }
        .buttonStyle(IndexIconActionButtonStyle(
            isActive: isActive ?? false,
            activeTint: activeTint,
            tint: tint
        ))
        .help(help)
        .accessibilityLabel(help)
        .modifier(IndexIconButtonActiveAccessibility(isActive: isActive))
    }
}

private struct IndexIconButtonActiveAccessibility: ViewModifier {
    let isActive: Bool?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let isActive {
            content
                .accessibilityAddTraits(isActive ? .isSelected : [])
                .accessibilityValue(isActive ? "已开启" : "已关闭")
        } else {
            content
        }
    }
}

// MARK: - IndexSegmentedControl

struct IndexSegmentedControl: View {
    enum Density {
        case regular
        case compact

        fileprivate var itemHeight: CGFloat {
            switch self {
            case .regular: 26
            case .compact: 22
            }
        }

        fileprivate var itemHorizontalPadding: CGFloat {
            switch self {
            case .regular: 13
            case .compact: 7
            }
        }
    }

    let items: [(String, String)]
    @Binding var selection: String
    let density: Density

    /// Segment bounds published to the shared cursor layer (same anchor
    /// family as the command-palette selection highlight).
    @State private var segmentAnchors: [String: Anchor<CGRect>] = [:]

    init(
        items: [(String, String)],
        selection: Binding<String>,
        density: Density = .regular
    ) {
        self.items = items
        self._selection = selection
        self.density = density
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                Item(label: item.1, isSelected: selection == item.0, density: density) {
                    selection = item.0
                }
                .anchorPreference(
                    key: IndexSegmentedCursorAnchorKey.self,
                    value: .bounds
                ) { [item.0: $0] }
            }
        }
        .padding(2)
        // Wave 2 sliding cursor: the selected fill floats behind the segments
        // but ABOVE the tray's opaque editorBackground — stacking it outside
        // that background would hide it completely.
        .background {
            GeometryReader { proxy in
                IndexSegmentedCursorLayer(
                    activeFrame: segmentAnchors[selection].map { proxy[$0] }
                )
            }
        }
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(ToolTheme.border, lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .onPreferenceChange(IndexSegmentedCursorAnchorKey.self) { segmentAnchors = $0 }
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
private struct IndexSegmentedCursorAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
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
/// Motion drop it in place without motion.
private struct IndexSegmentedCursorLayer: View {
    let activeFrame: CGRect?

    @State private var flight: IndexSegmentedCursorFlight?
    @State private var settledFrame: CGRect?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            value: activeFrame
        )
        .onChange(of: activeFrame) { newFrame in
            if !reduceMotion,
               let previousFrame = settledFrame,
               let newFrame,
               previousFrame.minX != newFrame.minX {
                flight = IndexSegmentedCursorFlight(
                    fromX: previousFrame.minX,
                    toX: newFrame.minX
                )
            } else {
                flight = nil
            }
            settledFrame = newFrame
        }
    }
}

// MARK: - IndexSwitch

struct IndexSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
        }
        .toggleStyle(IndexSwitchToggleStyle())
        .help(title)
        .accessibilityValue(isOn ? "已开启" : "已关闭")
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct IndexSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 9) {
                IndexSwitchTrack(
                    isOn: configuration.isOn,
                    offBackground: ToolTheme.editorBackground,
                    offBorder: ToolTheme.border,
                    offThumb: ToolTheme.textSecondary
                )

                configuration.label
                    .font(ToolTypography.bodyPlain)
                    .foregroundStyle(ToolTheme.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct IndexSwitchTrack: View {
    let isOn: Bool
    let offBackground: Color
    let offBorder: Color
    let offThumb: Color

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? ToolTheme.accentSoft : offBackground)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(isOn ? ToolTheme.accentBorder : offBorder, lineWidth: 1)
                }

            Circle()
                .fill(isOn ? ToolTheme.accent : offThumb)
                .frame(width: 14, height: 14)
                .padding(3)
        }
        .frame(width: 34, height: 20)
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isOn)
        .accessibilityHidden(true)
    }
}

// MARK: - IndexOptionGroup

struct IndexOptionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(ToolTypography.bodyPlain)
            .foregroundStyle(ToolTheme.textSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct IndexOptionGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(ToolTheme.utilityBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(ToolTheme.strongBorder, lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct IndexOptionDivider: View {
    var body: some View {
        Rectangle()
            .fill(ToolTheme.strongBorder)
            .frame(width: 0.5, height: 20)
    }
}

struct IndexOptionSwitch: View {
    enum Style: Sendable {
        case switchToggle
        case embeddedSwitch
        case button
    }

    let title: String
    var help: String?
    var style: Style = .switchToggle
    @Binding var isOn: Bool

    init(title: String, help: String? = nil, style: Style = .switchToggle, isOn: Binding<Bool>) {
        self.title = title
        self.help = help
        self.style = style
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
        }
        .toggleStyle(IndexOptionSwitchToggleStyle(style: style))
        .help(help ?? title)
        .accessibilityValue(isOn ? "已开启" : "已关闭")
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct IndexOptionSwitchToggleStyle: ToggleStyle {
    var style: IndexOptionSwitch.Style = .switchToggle

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            switch style {
            case .switchToggle:
                HStack(spacing: 6) {
                    IndexSwitchTrack(
                        isOn: configuration.isOn,
                        offBackground: ToolTheme.panelBackground,
                        offBorder: ToolTheme.strongBorder,
                        offThumb: ToolTheme.textSecondary
                    )

                    configuration.label
                        .font(ToolTypography.bodyMedium)
                        .foregroundStyle(ToolTheme.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 4)
                .frame(height: 28)
                .background(
                    configuration.isOn ? ToolTheme.selectionFill : Color.clear,
                    in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))

            case .embeddedSwitch:
                IndexEmbeddedSwitchLabel(configuration: configuration)

            case .button:
                IndexOptionButtonLabel(configuration: configuration)
            }
        }
        .buttonStyle(IndexOptionPressableButtonStyle())
    }
}

/// Press feedback for option toggles: the same 0.98 settle the button and
/// icon families use, so every pressable control in the spine shares one
/// physical vocabulary (Reduce Motion collapses to identity).
private struct IndexOptionPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? ToolMotion.Scale.pressed : 1)
            .animation(
                ToolMotion.animation(ToolMotion.Preset.controlFeedback, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

private struct IndexEmbeddedSwitchLabel: View {
    let configuration: ToggleStyle.Configuration
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    private let thumbSize: CGFloat = 20
    private let trackPadding: CGFloat = 3
    private let textSpacing: CGFloat = 6
    private let textOuterPadding: CGFloat = 9

    private var isOn: Bool { configuration.isOn }
    private var hovering: Bool { isHovering && isEnabled }

    private var trackBackground: Color {
        if !isEnabled { return ToolTheme.editorBackground }
        if isOn {
            return hovering ? ToolTheme.accentHover : ToolTheme.accent
        }
        return hovering ? ToolTheme.hoverFill : ToolTheme.utilityBackground
    }

    private var trackBorder: Color {
        if !isEnabled { return ToolTheme.border }
        if isOn {
            return hovering ? ToolTheme.accentHover : ToolTheme.accent
        }
        return hovering ? ToolTheme.strongBorder : ToolTheme.strongBorder.opacity(0.85)
    }

    private var textForeground: Color {
        if !isEnabled { return ToolTheme.textTertiary }
        if isOn { return ToolTheme.onAccent }
        return hovering ? ToolTheme.textPrimary : ToolTheme.textSecondary
    }

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            configuration.label
                .font(ToolTypography.label)
                .foregroundStyle(textForeground)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, isOn ? textOuterPadding : (trackPadding + thumbSize + textSpacing))
                .padding(.trailing, isOn ? (trackPadding + thumbSize + textSpacing) : textOuterPadding)

            Circle()
                .fill(Color.white)
                .frame(width: thumbSize, height: thumbSize)
                .toolShadow(ToolTheme.Shadow.panel)
                .overlay {
                    Circle()
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                }
                .padding(.horizontal, trackPadding)
        }
        .frame(height: 26)
        .background(
            trackBackground,
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(trackBorder, lineWidth: 1)
        }
        .contentShape(Capsule(style: .continuous))
        .onHover { isHovering = $0 }
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: isOn)
        .toolAnimation(ToolMotion.Preset.controlFeedback, value: hovering)
    }
}

private struct IndexOptionButtonLabel: View {
    let configuration: ToggleStyle.Configuration
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    private var isOn: Bool { configuration.isOn }
    private var hovering: Bool { isHovering && isEnabled }

    private var background: Color {
        if isOn {
            return hovering ? ToolTheme.accentSoft.opacity(0.85) : ToolTheme.accentSoft
        }
        return hovering ? ToolTheme.hoverFill : ToolTheme.editorBackground
    }

    private var border: Color {
        if isOn {
            return ToolTheme.accentBorder
        }
        return hovering ? ToolTheme.strongBorder : ToolTheme.border
    }

    private var foreground: Color {
        if !isEnabled { return ToolTheme.textTertiary }
        if isOn { return ToolTheme.accent }
        return hovering ? ToolTheme.textPrimary : ToolTheme.textSecondary
    }

    var body: some View {
        configuration.label
            .font(ToolTypography.label)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                background,
                in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
            .onHover { isHovering = $0 }
            .toolAnimation(ToolMotion.Preset.controlFeedback, value: [hovering, isOn])
    }
}

struct IndexOptionPicker<Value: Hashable>: View {
    let items: [(Value, String)]
    @Binding var selection: Value
    var tone: ToolFeedbackTone? = nil
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                Button {
                    selection = item.0
                } label: {
                    let isSelected = selection == item.0

                    Text(item.1)
                        .font(ToolTypography.controlLabel(weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? ToolTheme.accentHover : ToolTheme.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 11)
                        .frame(height: 24)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                                    .fill(ToolTheme.selectionFill)
                                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
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
        .padding(2)
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(tone?.tint.opacity(0.7) ?? ToolTheme.border, lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .toolAnimation(ToolMotion.Preset.settle, value: selection)
    }
}

struct IndexOptionMenu: View {
    let items: [(String, String)]
    @Binding var selection: String
    var title = "选项"
    var tone: ToolFeedbackTone? = nil

    private var selectedLabel: String {
        items.first { $0.0 == selection }?.1 ?? title
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(items, id: \.0) { item in
                Text(item.1)
                    .tag(item.0)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(ToolTypography.controlLabel(weight: .semibold))
        .buttonStyle(.plain)
        .tint(tone?.tint ?? ToolTheme.accentHover)
        .padding(.leading, 7)
        .padding(.trailing, 24)
        .frame(minWidth: 116)
        .frame(height: 38)
        .background(ToolTheme.editorBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .strokeBorder(tone?.tint.opacity(0.7) ?? ToolTheme.border, lineWidth: 1)
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.down")
                .font(.system(size: ToolMetrics.IconSize.micro, weight: .semibold))
                .foregroundStyle(ToolTheme.textSecondary)
                .padding(.trailing, 9)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous))
        .help(title)
        .accessibilityLabel("\(title)：\(selectedLabel)")
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Legacy name kept for call-site compatibility — one implementation.
typealias IndexInlinePicker<Value: Hashable> = IndexOptionPicker<Value>




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
    var minimumDigits = 1
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
                text = displayText(normalized)
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
        text = displayText(normalized)
    }

    private func normalizedValue(_ newValue: Int) -> Int {
        min(max(newValue, range.lowerBound), range.upperBound)
    }

    private func displayText(_ value: Int) -> String {
        guard minimumDigits > 1 else { return "\(value)" }
        return String(format: "%0*d", minimumDigits, value)
    }
}
