import AppKit
import SwiftUI

struct CommandPaletteRevealRequest: Equatable {
    let id: String
    let anchor: CommandPaletteRevealAnchor
    let token: Int
    let session: Int
}

struct CommandPaletteRowAttachment: NSViewRepresentable {
    let itemID: String
    let selectableIndex: Int?
    let registry: CommandPaletteRevealRegistry
    let session: Int
    let interactionEnabled: Bool
    let revealRequest: CommandPaletteRevealRequest?
    let pointerMovementTracker: CommandPalettePointerMovementTracker
    let onMouseMove: () -> Void

    func makeNSView(context: Context) -> CommandPaletteRevealView {
        CommandPaletteTrace.count(.revealMake)
        let view = CommandPaletteRevealView()
        view.traceSession = CommandPaletteTrace.currentSession
        return view
    }

    func updateNSView(_ view: CommandPaletteRevealView, context: Context) {
        view.traceSession = session
        CommandPaletteTrace.count(.revealUpdate, session: view.traceSession)
        view.configure(
            itemID: itemID,
            selectableIndex: selectableIndex,
            registry: registry,
            session: session,
            interactionEnabled: interactionEnabled,
            pointerMovementTracker: pointerMovementTracker,
            onMouseMove: onMouseMove
        )

        guard let revealRequest, revealRequest.id == itemID else { return }
        view.reveal(request: revealRequest)
    }

    static func dismantleNSView(_ view: CommandPaletteRevealView, coordinator: ()) {
        CommandPaletteTrace.count(.revealDismantle, session: view.traceSession)
        view.unregister()
    }
}

@MainActor
final class CommandPaletteRevealRegistry: NSObject {
    private final class Entry {
        weak var view: CommandPaletteRevealView?
        weak var clipView: NSClipView?
        var selectableIndex: Int
        var session: Int

        init(
            view: CommandPaletteRevealView,
            clipView: NSClipView?,
            selectableIndex: Int,
            session: Int
        ) {
            self.view = view
            self.clipView = clipView
            self.selectableIndex = selectableIndex
            self.session = session
        }
    }

    private var entries: [String: Entry] = [:]
    private var pendingKeyboardReveal: PendingKeyboardReveal?
    private var latestRevealRequestToken = 0
    private var manualScrollGeneration = 0
    private var manualScrollGenerationAtLatestKeyboardReveal = 0
    private var observedClipViews: [ObjectIdentifier: NSClipView] = [:]
    private var liveSession: Int?

    var debugEntryCount: Int {
        entries.count
    }

    var debugObservedClipViewCount: Int {
        observedClipViews.count
    }

    func debugEntryIdentity(for itemID: String) -> ObjectIdentifier? {
        entries[itemID].map(ObjectIdentifier.init)
    }

    func debugIsObserving(_ clipView: NSClipView) -> Bool {
        observedClipViews[ObjectIdentifier(clipView)] != nil
    }

    private struct PendingKeyboardReveal {
        let itemID: String
        let token: Int
        let session: Int
    }

    func resume(session: Int) {
        guard liveSession != session else { return }

        if let previousSession = liveSession {
            for entry in entries.values {
                entry.view?.suspendInteraction(
                    session: previousSession,
                    clearsPointerBaseline: true
                )
            }
        }
        removeAllObservers()
        liveSession = session
        resetRevealState()

        for entry in entries.values {
            rebind(entry: entry, for: session)
        }
    }

    func suspend(session: Int) {
        guard liveSession == session else { return }

        liveSession = nil
        resetRevealState()
        removeAllObservers()

        for entry in entries.values {
            entry.view?.suspendInteraction(session: session, clearsPointerBaseline: true)
        }
    }

    func isLive(session: Int) -> Bool {
        liveSession == session
    }

    func register(
        itemID: String,
        selectableIndex: Int?,
        session: Int,
        view: CommandPaletteRevealView
    ) {
        guard let selectableIndex else {
            unregister(itemID: itemID, view: view)
            return
        }
        let clipView = view.enclosingScrollView?.contentView

        if let entry = entries[itemID], entry.view === view {
            let previousClipView = entry.clipView
            entry.selectableIndex = selectableIndex
            entry.session = session
            entry.clipView = clipView
            if let previousClipView {
                // Rows under one palette share the same clip view. Skip the
                // O(rows) still-used sweep only when this very entry still
                // keeps that clip view observed; a handed-over or suspended
                // session must run the sweep so the observer comes off.
                let entryStillDrivesClipView = previousClipView === clipView
                    && isLive(session: session)
                    && view.isInteractionActive(session: session)
                if !entryStillDrivesClipView {
                    removeObserverIfUnused(for: previousClipView)
                }
            }
            observeIfLive(entry: entry)
            return
        }

        if let replacedEntry = entries.removeValue(forKey: itemID),
           let replacedClipView = replacedEntry.clipView {
            removeObserverIfUnused(for: replacedClipView)
        }

        let entry = Entry(
            view: view,
            clipView: clipView,
            selectableIndex: selectableIndex,
            session: session
        )
        entries[itemID] = entry
        observeIfLive(entry: entry)
    }

    func unregister(itemID: String?, view: CommandPaletteRevealView) {
        guard let itemID,
              let entry = entries[itemID],
              entry.view === view
        else {
            return
        }
        entries.removeValue(forKey: itemID)

        if let clipView = entry.clipView {
            removeObserverIfUnused(for: clipView)
        }
    }

    func visibleEdgeSelectableIndex(direction: Int) -> Int? {
        guard liveSession != nil else { return nil }
        pruneDeadEntries()

        var edgeIndex: Int?
        for entry in entries.values where isVisible(entry) {
            guard let currentEdge = edgeIndex else {
                edgeIndex = entry.selectableIndex
                continue
            }

            if direction < 0 {
                edgeIndex = max(currentEdge, entry.selectableIndex)
            } else {
                edgeIndex = min(currentEdge, entry.selectableIndex)
            }
        }
        return edgeIndex
    }

    func isVisible(itemID: String) -> Bool {
        guard liveSession != nil else { return false }
        pruneDeadEntries()
        guard let entry = entries[itemID] else { return false }
        return isVisible(entry)
    }

    func hasLatestPendingKeyboardReveal(itemID: String) -> Bool {
        guard let liveSession else { return false }
        return pendingKeyboardReveal?.itemID == itemID
            && pendingKeyboardReveal?.token == latestRevealRequestToken
            && pendingKeyboardReveal?.session == liveSession
    }

    func hasManualScrollAfterLatestKeyboardReveal() -> Bool {
        guard liveSession != nil else { return false }
        return manualScrollGeneration > manualScrollGenerationAtLatestKeyboardReveal
    }

    func markKeyboardRevealPending(itemID: String, token: Int, session: Int) {
        guard isLive(session: session) else { return }
        pendingKeyboardReveal = PendingKeyboardReveal(
            itemID: itemID,
            token: token,
            session: session
        )
        manualScrollGenerationAtLatestKeyboardReveal = manualScrollGeneration
    }

    fileprivate func finishKeyboardReveal(request: CommandPaletteRevealRequest) {
        guard isLive(session: request.session),
              pendingKeyboardReveal?.itemID == request.id,
              pendingKeyboardReveal?.token == request.token,
              pendingKeyboardReveal?.session == request.session
        else {
            return
        }
        pendingKeyboardReveal = nil
    }

    func markRevealRequest(token: Int, session: Int) {
        guard isLive(session: session) else { return }
        latestRevealRequestToken = token
        if pendingKeyboardReveal?.token != token || pendingKeyboardReveal?.session != session {
            pendingKeyboardReveal = nil
        }
    }

    fileprivate func isLatestRevealRequest(_ request: CommandPaletteRevealRequest) -> Bool {
        isLive(session: request.session) && request.token == latestRevealRequestToken
    }

    func revealImmediately(request: CommandPaletteRevealRequest) {
        guard isLatestRevealRequest(request),
              let entry = entries[request.id],
              entry.session == request.session,
              let view = entry.view
        else {
            return
        }

        view.reveal(request: request)
    }

    private func rebind(entry: Entry, for session: Int) {
        guard entry.session == session,
              let view = entry.view,
              view.resumeInteraction(session: session)
        else {
            return
        }
        entry.clipView = view.enclosingScrollView?.contentView
        observeIfLive(entry: entry)
    }

    private func observeIfLive(entry: Entry) {
        guard isLive(session: entry.session),
              entry.view?.isInteractionActive(session: entry.session) == true
        else {
            return
        }
        observeScrollView(entry.clipView)
    }

    private func observeScrollView(_ clipView: NSClipView?) {
        guard let clipView else { return }
        let id = ObjectIdentifier(clipView)
        guard observedClipViews[id] == nil else { return }

        clipView.postsBoundsChangedNotifications = true
        observedClipViews[id] = clipView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
    }

    private func removeObserverIfUnused(for clipView: NSClipView) {
        let isStillUsed = entries.values.contains { entry in
            entry.clipView === clipView
                && isLive(session: entry.session)
                && entry.view?.isInteractionActive(session: entry.session) == true
        }
        guard !isStillUsed else { return }

        NotificationCenter.default.removeObserver(
            self,
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
        observedClipViews.removeValue(forKey: ObjectIdentifier(clipView))
    }

    private func removeAllObservers() {
        for clipView in observedClipViews.values {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
        }
        observedClipViews.removeAll()
    }

    private func resetRevealState() {
        pendingKeyboardReveal = nil
        manualScrollGeneration = 0
        manualScrollGenerationAtLatestKeyboardReveal = 0
    }

    @objc private func scrollViewBoundsDidChange(_ notification: Notification) {
        guard NSApp.currentEvent?.type == .scrollWheel else { return }
        recordManualScroll()
    }

    func recordManualScroll() {
        guard liveSession != nil else { return }
        manualScrollGeneration += 1
    }

    private func isVisible(_ entry: Entry) -> Bool {
        guard entry.session == liveSession,
              let view = entry.view,
              view.isInteractionActive(session: entry.session),
              let scrollView = view.enclosingScrollView,
              let documentView = scrollView.documentView
        else {
            return false
        }

        let visibleRect = scrollView.contentView.bounds
        let rowRect = view.convert(view.bounds, to: documentView)
        return visibleRect.intersects(rowRect)
    }

    private func pruneDeadEntries() {
        entries = entries.filter { _, entry in
            entry.view != nil
        }

        let activeClipViewIDs = Set(
            entries.values.compactMap { entry -> ObjectIdentifier? in
                guard isLive(session: entry.session),
                      entry.view?.isInteractionActive(session: entry.session) == true
                else {
                    return nil
                }
                return entry.clipView.map(ObjectIdentifier.init)
            }
        )
        for (id, clipView) in observedClipViews where !activeClipViewIDs.contains(id) {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: clipView
            )
            observedClipViews.removeValue(forKey: id)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

final class CommandPaletteRevealView: NSView {
    private var lastRevealRequest: CommandPaletteRevealRequest?
    private var scheduledRevealRetryRequest: CommandPaletteRevealRequest?
    private weak var registry: CommandPaletteRevealRegistry?
    private var itemID: String?
    private var selectableIndex: Int?
    private var session: Int?
    private var wantsInteraction = false
    private var interactionEnabled = false
    var traceSession: Int?
    var pointerMovementTracker: CommandPalettePointerMovementTracker?
    var onMouseMove: (() -> Void)?
    private var mouseTrackingArea: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    func configure(
        itemID: String,
        selectableIndex: Int?,
        registry: CommandPaletteRevealRegistry,
        session: Int,
        interactionEnabled: Bool,
        pointerMovementTracker: CommandPalettePointerMovementTracker,
        onMouseMove: @escaping () -> Void
    ) {
        if self.itemID != itemID || self.registry !== registry {
            unregister()
        }

        self.itemID = itemID
        self.selectableIndex = selectableIndex
        self.registry = registry
        self.session = session
        self.pointerMovementTracker = pointerMovementTracker
        self.onMouseMove = onMouseMove
        wantsInteraction = interactionEnabled
        self.interactionEnabled = interactionEnabled && registry.isLive(session: session)
        registry.register(
            itemID: itemID,
            selectableIndex: selectableIndex,
            session: session,
            view: self
        )
        refreshTrackingArea()
    }

    func unregister() {
        suspendInteraction(session: session, clearsPointerBaseline: false)
        registry?.unregister(itemID: itemID, view: self)
        registry = nil
        itemID = nil
        selectableIndex = nil
        session = nil
        pointerMovementTracker = nil
        onMouseMove = nil
        lastRevealRequest = nil
        scheduledRevealRetryRequest = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        refreshRegistration()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshRegistration()
        resetPointerBaselineToCurrentWindowLocation()
    }

    override func mouseMoved(with event: NSEvent) {
        guard let session,
              interactionEnabled,
              registry?.isLive(session: session) == true,
              pointerMovementTracker?.acceptsMouseMoved(at: event.locationInWindow) == true
        else {
            return
        }
        onMouseMove?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    fileprivate func isInteractionActive(session: Int) -> Bool {
        self.session == session && interactionEnabled
    }

    @discardableResult
    fileprivate func resumeInteraction(session: Int) -> Bool {
        guard self.session == session, wantsInteraction else { return false }
        interactionEnabled = true
        refreshTrackingArea()
        return true
    }

    fileprivate func suspendInteraction(
        session: Int?,
        clearsPointerBaseline: Bool
    ) {
        guard session == nil || self.session == session else { return }
        wantsInteraction = false
        interactionEnabled = false
        scheduledRevealRetryRequest = nil
        if clearsPointerBaseline {
            pointerMovementTracker?.clear()
        }
        removeMouseTrackingArea()
    }

    func reveal(request: CommandPaletteRevealRequest) {
        guard request != lastRevealRequest,
              session == request.session,
              interactionEnabled,
              registry?.isLatestRevealRequest(request) == true
        else {
            return
        }
        guard window != nil else {
            guard scheduledRevealRetryRequest != request else { return }
            scheduledRevealRetryRequest = request
            DispatchQueue.main.async { [weak self, request] in
                guard let self,
                      self.window != nil,
                      self.session == request.session,
                      self.interactionEnabled,
                      self.registry?.isLatestRevealRequest(request) == true
                else {
                    return
                }
                self.reveal(request: request)
            }
            return
        }

        lastRevealRequest = request
        switch request.anchor {
        case .keyboardEdge(let delta):
            scrollToKeyboardEdge(delta: delta)
        case .top:
            scrollToTop()
        }
        registry?.finishKeyboardReveal(request: request)
    }

    private func scrollToKeyboardEdge(delta: Int) {
        guard let scrollView = enclosingScrollView,
              let documentView = scrollView.documentView
        else {
            scrollToVisible(bounds)
            return
        }

        let clipView = scrollView.contentView
        let visibleRect = clipView.bounds
        let rowRect = viewRectInDocumentView(documentView)
        let targetY: CGFloat?

        if delta > 0 {
            targetY = rowRect.maxY > visibleRect.maxY
                ? rowRect.maxY - visibleRect.height
                : nil
        } else if delta < 0 {
            targetY = rowRect.minY < visibleRect.minY
                ? rowRect.minY
                : nil
        } else {
            targetY = nil
        }

        guard let targetY else { return }

        let documentBounds = documentView.bounds
        let maxY = max(documentBounds.minY, documentBounds.maxY - visibleRect.height)
        let clampedY = min(max(targetY, documentBounds.minY), maxY)
        clipView.scroll(to: NSPoint(x: visibleRect.origin.x, y: clampedY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func viewRectInDocumentView(_ documentView: NSView) -> NSRect {
        if bounds.width > 0, bounds.height > 0 {
            return convert(bounds, to: documentView)
        }

        if let superview, superview.bounds.width > 0, superview.bounds.height > 0 {
            return superview.convert(superview.bounds, to: documentView)
        }

        return convert(bounds, to: documentView)
    }

    private func scrollToTop() {
        guard let scrollView = enclosingScrollView,
              let documentView = scrollView.documentView
        else {
            scrollToVisible(bounds)
            return
        }

        let clipView = scrollView.contentView
        let topY: CGFloat
        if documentView.isFlipped {
            topY = documentView.bounds.minY
        } else {
            topY = max(documentView.bounds.minY, documentView.bounds.maxY - clipView.bounds.height)
        }

        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: topY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func refreshRegistration() {
        guard let itemID, let registry, let session else { return }
        registry.register(
            itemID: itemID,
            selectableIndex: selectableIndex,
            session: session,
            view: self
        )
    }

    private func refreshTrackingArea() {
        guard let session,
              interactionEnabled,
              registry?.isLive(session: session) == true
        else {
            removeMouseTrackingArea()
            return
        }

        if mouseTrackingArea == nil {
            let trackingArea = NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            mouseTrackingArea = trackingArea
        }
        resetPointerBaselineToCurrentWindowLocation()
    }

    private func removeMouseTrackingArea() {
        if let mouseTrackingArea {
            removeTrackingArea(mouseTrackingArea)
        }
        mouseTrackingArea = nil
    }

    private func resetPointerBaselineToCurrentWindowLocation() {
        guard interactionEnabled,
              let window,
              pointerMovementTracker?.isSeeded != true
        else {
            return
        }
        pointerMovementTracker?.reset(to: window.mouseLocationOutsideOfEventStream)
    }
}
