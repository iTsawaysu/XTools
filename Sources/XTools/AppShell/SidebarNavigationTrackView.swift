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

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

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
        publishPointerLocation(from: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        publishPointerLocation(from: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointerLocationChange?(nil)
    }

    var currentPointerLocation: CGPoint? {
        guard let window, window.isKeyWindow else { return nil }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
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
final class SidebarNavigationScrollView: NSScrollView {
    var onViewportSizeChange: ((CGSize) -> Void)?
    var onViewportBoundsChange: (() -> Void)?
    private var lastViewportSize = CGSize.zero

    override func layout() {
        super.layout()
        let nextSize = contentSize
        guard nextSize != lastViewportSize else { return }
        lastViewportSize = nextSize
        onViewportSizeChange?(nextSize)
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        onViewportBoundsChange?()
    }
}
