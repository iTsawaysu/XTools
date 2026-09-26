import AppKit

struct SidebarNavigationTrackDebugState: Equatable {
    let frameHeight: CGFloat
    let contentHeight: CGFloat
    let isHidden: Bool
    let isInteractionEnabled: Bool
    let acceptsPresentationSelection: Bool
    let isAccessibilityHidden: Bool
    let isHostedContentAccessibilityHidden: Bool
    let areHostedControlsEnabled: Bool
    let isHovered: Bool
}

@MainActor
final class SidebarNavigationTrackView: NSView {
    let trackID: String
    var groupID: String
    let kind: SidebarNavigationTrackKind
    private(set) var naturalContentHeight: CGFloat
    private(set) var interaction: SidebarNavigationTrackInteraction
    let hostedContentView: NSView
    let hoverState: SidebarNavigationTrackHoverState
    /// v3 full-row hit target: fires when any point of the row activates it.
    /// The trailing favorite slot stays a SwiftUI pass-through.
    var onActivateRow: (() -> Void)?
    var onActivateHeader: ((NSEvent) -> Void)?

    override var isFlipped: Bool { true }

    init(
        trackID: String,
        groupID: String,
        kind: SidebarNavigationTrackKind,
        naturalContentHeight: CGFloat,
        hostedContentView: NSView,
        hoverState: SidebarNavigationTrackHoverState = SidebarNavigationTrackHoverState()
    ) {
        self.trackID = trackID
        self.groupID = groupID
        self.kind = kind
        self.naturalContentHeight = naturalContentHeight
        self.hostedContentView = hostedContentView
        self.hoverState = hoverState
        interaction = .finalized(targetExpanded: true)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        autoresizesSubviews = true
        setAccessibilityElement(false)
        addSubview(hostedContentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func layout() {
        super.layout()
        hostedContentView.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: naturalContentHeight
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interaction.isInteractionEnabled else { return nil }
        return super.hitTest(point)
    }

    @discardableResult
    func update(groupID: String, naturalContentHeight: CGFloat) -> Bool {
        self.groupID = groupID
        guard self.naturalContentHeight != naturalContentHeight else {
            return false
        }
        self.naturalContentHeight = naturalContentHeight
        needsLayout = true
        return true
    }

    /// v3: activates this row for any point outside the trailing favorite
    /// slot (24pt control + 9pt padding stays a star pass-through). Header
    /// rows activate across their full width.
    func activateRowIfOutsideFavoriteSlot(at point: NSPoint, event: NSEvent? = nil) -> Bool {
        guard onActivateRow != nil || onActivateHeader != nil, interaction.isInteractionEnabled else {
            return false
        }
        switch kind {
        case .tool:
            let favoriteSlotWidth: CGFloat = 24 + SidebarMetrics.toolRowHorizontalPadding
            guard point.x <= bounds.width - favoriteSlotWidth else {
                return false
            }
            onActivateRow?()
            return true
        case .header:
            if let event, let onActivateHeader {
                onActivateHeader(event)
            } else {
                onActivateRow?()
            }
            return true
        case .spacing:
            return false
        }
    }

    func applyInteraction(_ next: SidebarNavigationTrackInteraction) {
        // reconcileTracks applies the interaction twice around each content
        // update; on a tool switch (contentOnly mode) the interaction is
        // usually unchanged, and the AX/control walks below visit every
        // hosted subview — skip them when nothing actually changed.
        guard next != interaction else { return }
        interaction = next
        setAccessibilityHidden(next.isAccessibilityHidden)
        // Hide the hosting container as one AX subtree. Recursively writing
        // `false` here would erase child SwiftUI semantics such as a favorite
        // button's conditional accessibilityHidden state.
        applyAccessibilityHidden(next.isAccessibilityHidden, to: hostedContentView)
        applyControlsEnabled(next.areControlsEnabled, to: hostedContentView)
        isHidden = next.isHidden
    }

    var presentationFrame: CGRect? {
        guard let frame = layer?.presentation()?.frame,
              !frame.isEmpty
        else {
            return nil
        }
        return frame
    }

    var debugState: SidebarNavigationTrackDebugState {
        SidebarNavigationTrackDebugState(
            frameHeight: frame.height,
            contentHeight: hostedContentView.frame.height,
            isHidden: isHidden,
            isInteractionEnabled: interaction.isInteractionEnabled,
            acceptsPresentationSelection: interaction.acceptsPresentationSelection,
            isAccessibilityHidden: interaction.isAccessibilityHidden,
            isHostedContentAccessibilityHidden: hostedContentView.isAccessibilityHidden(),
            areHostedControlsEnabled: controlsAreEnabled(in: hostedContentView),
            isHovered: hoverState.isHovered
        )
    }

    private func applyAccessibilityHidden(_ isHidden: Bool, to view: NSView) {
        // NSAccessibilityHidden on a hosting container hides its complete
        // subtree. Do not mutate descendants: SwiftUI owns their individual
        // semantics and may intentionally hide controls (for example the
        // hover-only favorite action).
        view.setAccessibilityHidden(isHidden)
    }

    private func applyControlsEnabled(_ isEnabled: Bool, to view: NSView) {
        (view as? NSControl)?.isEnabled = isEnabled
        for subview in view.subviews {
            applyControlsEnabled(isEnabled, to: subview)
        }
    }

    private func controlsAreEnabled(in view: NSView) -> Bool {
        if let control = view as? NSControl, !control.isEnabled {
            return false
        }
        return view.subviews.allSatisfy(controlsAreEnabled(in:))
    }
}

@MainActor
final class SidebarNavigationDocumentView: NSView {
    var onFrameSizeChange: (() -> Void)?
    var onMoveSelection: ((Int) -> Void)?
    var onActivateSelection: (() -> Void)?
    var onActivatePresentationSelection: ((NSPoint) -> Bool)?
    var onPointerLocationChange: ((CGPoint?) -> Void)?

    private var pointerTrackingArea: NSTrackingArea?
    private var lastKnownPointerLocationInWindow: CGPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onFrameSizeChange?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onPointerLocationChange?(currentPointerLocation)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        lastKnownPointerLocationInWindow = event.locationInWindow
        publishPointerLocation(from: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        lastKnownPointerLocationInWindow = event.locationInWindow
        publishPointerLocation(from: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        lastKnownPointerLocationInWindow = nil
        onPointerLocationChange?(nil)
    }

    var currentPointerLocation: CGPoint? {
        guard let window, window.isKeyWindow else { return nil }
        let rawPoint = lastKnownPointerLocationInWindow ?? window.mouseLocationOutsideOfEventStream
        let point = convert(rawPoint, from: nil)
        return visibleRect.contains(point) ? point : nil
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125:
            onMoveSelection?(1)
        case 126:
            onMoveSelection?(-1)
        case 36, 49, 76:
            onActivateSelection?()
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if onActivatePresentationSelection?(point) == true {
            return
        }
        // v3 full-row hit target: clicks that fall through the hosted label
        // (e.g. the blank trailing area) still activate the row, matching
        // native sidebar rows where the whole row is the target.
        if activateRowTrack(at: point, event: event) {
            return
        }
        super.mouseDown(with: event)
    }

    private func activateRowTrack(at point: NSPoint, event: NSEvent) -> Bool {
        guard let track = subviews.lazy
            .compactMap({ $0 as? SidebarNavigationTrackView })
            .first(where: { $0.frame.contains(point) })
        else {
            return false
        }
        return track.activateRowIfOutsideFavoriteSlot(at: convert(point, to: track), event: event)
    }

    private func publishPointerLocation(from event: NSEvent) {
        onPointerLocationChange?(convert(event.locationInWindow, from: nil))
    }
}

@MainActor
final class SidebarNavigationScrollView: NSScrollView {    var onViewportSizeChange: ((CGSize) -> Void)?
    var onViewportBoundsChange: (() -> Void)?
    private var lastViewportSize = CGSize.zero
    private(set) var isLiveScrolling = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installLiveScrollObservers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installLiveScrollObservers()
    }

    private func installLiveScrollObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillStartLiveScroll),
            name: NSScrollView.willStartLiveScrollNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEndLiveScroll),
            name: NSScrollView.didEndLiveScrollNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleWillStartLiveScroll() {
        isLiveScrolling = true
    }

    @objc private func handleDidEndLiveScroll() {
        isLiveScrolling = false
        onViewportBoundsChange?()
    }

    override func layout() {
        super.layout()
        let nextSize = contentSize
        guard nextSize != lastViewportSize else { return }
        lastViewportSize = nextSize
        onViewportSizeChange?(nextSize)
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        guard !isLiveScrolling else { return }
        onViewportBoundsChange?()
    }
}

/// Sliding selection chrome for the flat sidebar document.
///
/// Owns the selection syntax the tool row used to paint itself — the
/// `selectionFill` pill and the 3×17pt accent rail — as one layer-backed view
/// living *below* every track. A tool switch springs it from the outgoing row
/// to the incoming row (`ToolMotion.AppKitPreset.selectionSlide`) while the
/// hosted row text colors flip instantly; disclosure accordion and structural
/// relayouts (expand/collapse, search, favorite reorder, resize) reposition it
/// without its own spring. Reduce Motion always lands frames directly.
@MainActor
final class SidebarSelectionIndicatorView: NSView {
    override var isFlipped: Bool { true }

    private enum Layout {
        static let pillCornerRadius: CGFloat = SidebarMetrics.rowCornerRadius
        static let railWidth: CGFloat = 3
        static let railHeight: CGFloat = 17
        static let railCornerRadius: CGFloat = ToolMetrics.CornerRadius.nestedControl
        /// The rail sits at the row pill's left edge minus the row's horizontal
        /// padding, i.e. at the sidebar gutter (document x = 1) — same place
        /// the row-level overlay painted it before the indicator took over.
        static let railLeadingOffset: CGFloat = -SidebarMetrics.toolRowHorizontalPadding
    }

    private static let slideAnimationKey = "sidebar.selection.slide"

    private let pillLayer = CALayer()
    private let railLayer = CALayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        pillLayer.cornerRadius = Layout.pillCornerRadius
        railLayer.cornerRadius = Layout.railCornerRadius
        layer?.addSublayer(pillLayer)
        layer?.addSublayer(railLayer)
        alphaValue = 0
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pillLayer.frame = CGRect(origin: .zero, size: bounds.size)
        railLayer.frame = CGRect(
            x: Layout.railLeadingOffset,
            y: (bounds.height - Layout.railHeight) / 2,
            width: Layout.railWidth,
            height: Layout.railHeight
        )
        CATransaction.commit()
    }

    /// The indicator is presentation-only chrome; it never intercepts hits.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Refreshes layer colors for the current appearance (light/dark).
    func updateColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pillLayer.backgroundColor = ToolTheme.SelectionNSColor.fill.cgColor
        railLayer.backgroundColor = ToolTheme.SelectionNSColor.rail.cgColor
        CATransaction.commit()
    }

    /// Positions the indicator over the selected row's track frame.
    ///
    /// - `slide`: spring the move (pure tool switch); the model frame still
    ///   lands immediately, the layer presentation springs and can retarget
    ///   mid-flight from its presentation value.
    /// - Size changes (resize) and Reduce Motion always land directly.
    func setSelectionFrame(_ frame: CGRect, slide: Bool, reduceMotion: Bool) {
        let wasHidden = alphaValue < 0.01
        let sizeChanged = bounds.size != frame.size
        self.frame = frame
        layoutSubtreeIfNeeded()

        if wasHidden {
            removeSlideAnimation()
            alphaValue = 1
            return
        }
        guard slide, !reduceMotion, !sizeChanged else {
            removeSlideAnimation()
            return
        }
        springSlide()
    }

    func setHidden(_ hidden: Bool) {
        removeSlideAnimation()
        alphaValue = hidden ? 0 : 1
    }

    /// Drops any in-flight selection spring so structural motion (accordion,
    /// animator-driven frames) becomes the sole geometry owner.
    func prepareForStructuralMotion() {
        removeSlideAnimation()
    }

    private func springSlide() {
        guard let layer else { return }
        let fromY = layer.presentation()?.position.y ?? layer.position.y
        removeSlideAnimation()
        let toY = layer.position.y
        guard abs(fromY - toY) > 0.5 else { return }
        let spring = ToolMotion.AppKitPreset.selectionSlide()
        spring.fromValue = fromY
        spring.toValue = toY
        layer.add(spring, forKey: Self.slideAnimationKey)
    }

    private func removeSlideAnimation() {
        layer?.removeAnimation(forKey: Self.slideAnimationKey)
    }
}
