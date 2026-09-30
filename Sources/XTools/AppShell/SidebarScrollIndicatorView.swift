import AppKit

/// Self-drawn thin scroll indicator for the sidebar.
///
/// The native overlay scroller expands its knob into a wide grabber whenever
/// the pointer hovers the lane, and AppKit offers no opt-out — its overlay
/// rendering also bypasses `draw`/`drawKnob` overrides, so the sidebar owns
/// the indicator outright. One layer-backed capsule mirrors the native
/// overlay lifecycle: it fades in while scrolling or when the pointer reaches
/// the trailing lane, and fades out after a short idle, while staying the
/// same thin capsule in every state.
///
/// Pure chrome: `hitTest` returns nil, so row interaction, row hover and the
/// coordinator's pointer reconciliation are untouched.
@MainActor
final class SidebarScrollIndicatorView: NSView {
    /// Idle overlay knob geometry sampled from the sidebar surface (@2x):
    /// 7pt wide with the right edge 2pt in from the sidebar's trailing border.
    static let knobWidth: CGFloat = 7
    static let knobTrailingInset: CGFloat = 2
    static let laneVerticalInset: CGFloat = 2
    static let minKnobLength: CGFloat = 24
    /// Native overlay lane hit width; the hover-reveal strip matches it so
    /// reaching for the scroller still works with pure muscle memory.
    static let laneHoverWidth: CGFloat = 17

    private enum Motion {
        static let revealDuration = ToolMotion.Duration.quick
        static let hideDuration = ToolMotion.Duration.medium
        /// Native overlay scrollers stay visible for about a second after the
        /// last scroll; 0.6 keeps the sidebar snappier without flickering
        /// between steady-wheel scroll bursts.
        static let idleHideDelay: TimeInterval = 0.6
    }

    private let knobLayer = CALayer()
    private var laneTrackingArea: NSTrackingArea?
    private var hideWorkItem: DispatchWorkItem?
    private var isLiveScrolling = false
    private var isLaneHovered = false
    private var isRevealed = false
    private var isContentFits = false

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        knobLayer.cornerRadius = Self.knobWidth / 2
        knobLayer.opacity = 0
        layer?.addSublayer(knobLayer)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override var isFlipped: Bool { true }

    /// Pure chrome: never intercepts hits (rows keep every point they own).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Lifecycle inputs (owned by SidebarNavigationScrollView)

    func noteLiveScrollStarted() {
        isLiveScrolling = true
        cancelScheduledHide()
        reveal()
    }

    func noteLiveScrollEnded() {
        isLiveScrolling = false
        scheduleHide()
    }

    /// Test hook mirroring the idle hide work item, so fade-out state is
    /// observable without waiting on the run loop.
    func performScheduledHide() {
        guard !isLiveScrolling, !isLaneHovered else { return }
        isRevealed = false
        applyOpacity()
    }

    // MARK: - Geometry sync

    /// Recomputes the knob from the owning scroll view's state. Runs on every
    /// scroll tick and relayout: constant time, no allocations, and the layer
    /// frame write is skipped entirely when nothing moved.
    func refresh() {
        guard let scrollView = superview as? NSScrollView,
              let documentView = scrollView.documentView
        else { return }

        let viewportHeight = scrollView.contentView.bounds.height
        let documentHeight = documentView.frame.height
        let maxOffset = documentHeight - viewportHeight
        let contentFits = maxOffset <= 0.5
        if contentFits != isContentFits {
            isContentFits = contentFits
            applyOpacity()
        }
        guard !contentFits, viewportHeight > 0, documentHeight > 0 else { return }

        let offset = min(max(scrollView.contentView.bounds.origin.y, 0), maxOffset)
        let length = max(Self.minKnobLength, viewportHeight * viewportHeight / documentHeight)
        let travel = max(0, bounds.height - 2 * Self.laneVerticalInset - length)
        let frame = CGRect(
            x: bounds.width - Self.knobTrailingInset - Self.knobWidth,
            y: Self.laneVerticalInset + (offset / maxOffset) * travel,
            width: Self.knobWidth,
            height: length
        )
        if knobLayer.frame != frame {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            knobLayer.frame = frame
            CATransaction.commit()
        }
    }

    /// Refreshes the knob color for the current appearance (light/dark).
    func updateColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        knobLayer.backgroundColor = ToolTheme.ScrollbarNSColor.sidebarKnob.cgColor
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        refresh()
    }

    // MARK: - Lane hover reveal

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let laneTrackingArea {
            removeTrackingArea(laneTrackingArea)
            self.laneTrackingArea = nil
        }
        let strip = CGRect(
            x: max(0, bounds.width - Self.laneHoverWidth),
            y: 0,
            width: min(Self.laneHoverWidth, bounds.width),
            height: bounds.height
        )
        guard !strip.isEmpty else { return }
        let area = NSTrackingArea(
            rect: strip,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        laneTrackingArea = area
        // A relayout can move the strip under a stationary pointer, which
        // never produces an entered event on its own.
        setLaneHovered(strip.contains(convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)))
    }

    override func mouseEntered(with event: NSEvent) {
        setLaneHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setLaneHovered(false)
    }

    /// Test-support: resolved knob geometry and visibility, mirroring
    /// `debugTrackState` for the scroll indicator lane.
    var debugKnobFrame: CGRect { knobLayer.frame }
    var debugOpacity: Float { knobLayer.opacity }

    func setLaneHovered(_ hovered: Bool) {
        guard isLaneHovered != hovered else { return }
        isLaneHovered = hovered
        if hovered {
            cancelScheduledHide()
            reveal()
        } else {
            scheduleHide()
        }
    }

    // MARK: - Visibility

    private func reveal() {
        isRevealed = true
        applyOpacity()
    }

    private func scheduleHide() {
        guard !isLiveScrolling, !isLaneHovered else { return }
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performScheduledHide()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Motion.idleHideDelay, execute: work)
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func applyOpacity() {
        let target: Float = isRevealed && !isContentFits ? 1 : 0
        guard knobLayer.opacity != target else { return }
        let revealing = target > knobLayer.opacity
        if reduceMotion {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            knobLayer.opacity = target
            CATransaction.commit()
            return
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(
            revealing ? Motion.revealDuration : Motion.hideDuration
        )
        knobLayer.opacity = target
        CATransaction.commit()
    }
}
