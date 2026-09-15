import AppKit
@testable import XTools
import Testing

@Suite(.serialized)
struct CommandPaletteNativeBridgeTests {
    @Test @MainActor
    func suspendKeepsTheEntryButStopsNativeCallbacksUntilTheNextSession() throws {
        let registry = CommandPaletteRevealRegistry()
        let firstScrollView = Self.scrollView()
        let secondScrollView = Self.scrollView()
        let view = CommandPaletteRevealView(frame: NSRect(x: 0, y: 40, width: 220, height: 36))
        let tracker = CommandPalettePointerMovementTracker()
        let firstDocument = try #require(firstScrollView.documentView)
        let secondDocument = try #require(secondScrollView.documentView)

        registry.resume(session: 1)
        firstDocument.addSubview(view)
        Self.configure(view, registry: registry, tracker: tracker, session: 1, interactionEnabled: true)
        let identity = try #require(registry.debugEntryIdentity(for: "tool.json"))
        #expect(registry.debugIsObserving(firstScrollView.contentView))
        #expect(Self.pointerTrackingAreaCount(in: view) == 1)

        Self.configure(view, registry: registry, tracker: tracker, session: 1, interactionEnabled: false)
        #expect(registry.debugEntryIdentity(for: "tool.json") == identity)
        #expect(registry.debugObservedClipViewCount == 0)
        #expect(Self.pointerTrackingAreaCount(in: view) == 0)

        Self.configure(view, registry: registry, tracker: tracker, session: 1, interactionEnabled: true)
        #expect(registry.debugIsObserving(firstScrollView.contentView))
        #expect(Self.pointerTrackingAreaCount(in: view) == 1)

        registry.suspend(session: 1)
        #expect(registry.debugEntryCount == 1)
        #expect(registry.debugEntryIdentity(for: "tool.json") == identity)
        #expect(registry.debugObservedClipViewCount == 0)
        #expect(!registry.debugIsObserving(firstScrollView.contentView))
        #expect(Self.pointerTrackingAreaCount(in: view) == 0)

        view.removeFromSuperview()
        secondDocument.addSubview(view)
        #expect(registry.debugEntryIdentity(for: "tool.json") == identity)
        #expect(registry.debugObservedClipViewCount == 0)
        #expect(!registry.debugIsObserving(secondScrollView.contentView))
        #expect(Self.pointerTrackingAreaCount(in: view) == 0)

        registry.resume(session: 2)
        Self.configure(view, registry: registry, tracker: tracker, session: 2, interactionEnabled: true)
        #expect(registry.debugEntryIdentity(for: "tool.json") == identity)
        #expect(registry.debugObservedClipViewCount == 1)
        #expect(!registry.debugIsObserving(firstScrollView.contentView))
        #expect(registry.debugIsObserving(secondScrollView.contentView))
        #expect(Self.pointerTrackingAreaCount(in: view) == 1)

        view.unregister()
        #expect(registry.debugEntryCount == 0)
        #expect(registry.debugObservedClipViewCount == 0)

        view.removeFromSuperview()
        firstDocument.addSubview(view)
        #expect(registry.debugEntryCount == 0)
        #expect(registry.debugObservedClipViewCount == 0)
    }

    @Test @MainActor
    func aNewResumeInvalidatesThePriorSessionBeforeItsRowsAreReconfigured() throws {
        let registry = CommandPaletteRevealRegistry()
        let scrollView = Self.scrollView()
        let document = try #require(scrollView.documentView)
        let view = CommandPaletteRevealView(frame: NSRect(x: 0, y: 40, width: 220, height: 36))
        let tracker = CommandPalettePointerMovementTracker()

        registry.resume(session: 31)
        document.addSubview(view)
        Self.configure(view, registry: registry, tracker: tracker, session: 31, interactionEnabled: true)
        #expect(registry.debugIsObserving(scrollView.contentView))
        #expect(Self.pointerTrackingAreaCount(in: view) == 1)

        registry.resume(session: 32)
        #expect(registry.debugEntryCount == 1)
        #expect(registry.debugObservedClipViewCount == 0)
        #expect(Self.pointerTrackingAreaCount(in: view) == 0)

        Self.configure(view, registry: registry, tracker: tracker, session: 32, interactionEnabled: true)
        #expect(registry.debugIsObserving(scrollView.contentView))
        #expect(Self.pointerTrackingAreaCount(in: view) == 1)
    }

    @Test @MainActor
    func suspendResetsRevealAndManualScrollStateForTheFollowingSession() throws {
        let registry = CommandPaletteRevealRegistry()
        let scrollView = Self.scrollView()
        let document = try #require(scrollView.documentView)
        let view = CommandPaletteRevealView(frame: NSRect(x: 0, y: 420, width: 220, height: 36))
        let tracker = CommandPalettePointerMovementTracker()

        registry.resume(session: 11)
        document.addSubview(view)
        Self.configure(view, registry: registry, tracker: tracker, session: 11, interactionEnabled: true)
        registry.markRevealRequest(token: 7, session: 11)
        registry.markKeyboardRevealPending(itemID: "tool.json", token: 7, session: 11)
        registry.recordManualScroll()
        #expect(registry.hasLatestPendingKeyboardReveal(itemID: "tool.json"))
        #expect(registry.hasManualScrollAfterLatestKeyboardReveal())

        registry.suspend(session: 11)
        registry.resume(session: 12)
        #expect(!registry.hasLatestPendingKeyboardReveal(itemID: "tool.json"))
        #expect(!registry.hasManualScrollAfterLatestKeyboardReveal())
        #expect(registry.debugObservedClipViewCount == 0)
        #expect(Self.pointerTrackingAreaCount(in: view) == 0)
    }

    @Test @MainActor
    func delayedRevealFromASuspendedSessionCannotScrollAfterAttachment() async throws {
        let registry = CommandPaletteRevealRegistry()
        let scrollView = Self.scrollView()
        let document = try #require(scrollView.documentView)
        let view = CommandPaletteRevealView(frame: NSRect(x: 0, y: 420, width: 220, height: 36))
        let tracker = CommandPalettePointerMovementTracker()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView

        registry.resume(session: 21)
        Self.configure(view, registry: registry, tracker: tracker, session: 21, interactionEnabled: true)
        let request = CommandPaletteRevealRequest(
            id: "tool.json",
            anchor: .keyboardEdge(delta: 1),
            token: 1,
            session: 21
        )
        registry.markRevealRequest(token: request.token, session: request.session)
        view.reveal(request: request)
        registry.suspend(session: 21)
        registry.resume(session: 22)
        registry.markRevealRequest(token: request.token, session: 22)

        document.addSubview(view)
        Self.configure(view, registry: registry, tracker: tracker, session: 22, interactionEnabled: true)
        #expect(registry.debugObservedClipViewCount == 1)
        #expect(Self.pointerTrackingAreaCount(in: view) == 1)

        await Self.drainMainQueue()
        #expect(scrollView.contentView.bounds.origin.y == 0)

        registry.suspend(session: 22)
        #expect(registry.debugObservedClipViewCount == 0)
        #expect(Self.pointerTrackingAreaCount(in: view) == 0)
    }

    @Test @MainActor
    func dismantlingOneRowDoesNotClearTheSharedPointerBaselineForVisibleRows() throws {
        let registry = CommandPaletteRevealRegistry()
        let scrollView = Self.scrollView()
        let document = try #require(scrollView.documentView)
        let firstView = CommandPaletteRevealView(frame: NSRect(x: 0, y: 40, width: 220, height: 36))
        let secondView = CommandPaletteRevealView(frame: NSRect(x: 0, y: 80, width: 220, height: 36))
        let tracker = CommandPalettePointerMovementTracker()
        var mouseMoveCount = 0

        registry.resume(session: 41)
        document.addSubview(firstView)
        document.addSubview(secondView)
        Self.configure(
            firstView,
            itemID: "first",
            registry: registry,
            tracker: tracker,
            session: 41,
            interactionEnabled: true
        )
        Self.configure(
            secondView,
            itemID: "second",
            registry: registry,
            tracker: tracker,
            session: 41,
            interactionEnabled: true,
            onMouseMove: { mouseMoveCount += 1 }
        )
        tracker.reset(to: NSPoint(x: 10, y: 10))

        firstView.unregister()
        secondView.mouseMoved(with: try #require(Self.mouseMovedEvent(at: NSPoint(x: 11, y: 10))))

        #expect(mouseMoveCount == 1)
    }

    @Test @MainActor
    func oneHundredSuspendResumeCyclesKeepNativeRowsBoundedAndDiscardOldRetries() async throws {
        let registry = CommandPaletteRevealRegistry()
        let scrollView = Self.scrollView(documentHeight: 2_400)
        let document = try #require(scrollView.documentView)
        let tracker = CommandPalettePointerMovementTracker()
        let rows = (0..<50).map { index in
            CommandPaletteRevealView(
                frame: NSRect(x: 0, y: CGFloat(index * 40), width: 220, height: 36)
            )
        }
        for row in rows {
            document.addSubview(row)
        }
        let itemIDs = rows.indices.map { "row.\($0)" }
        var identities: [String: ObjectIdentifier] = [:]

        for session in 1...100 {
            registry.resume(session: session)
            for (index, row) in rows.enumerated() {
                Self.configure(
                    row,
                    itemID: itemIDs[index],
                    registry: registry,
                    tracker: tracker,
                    session: session,
                    interactionEnabled: true
                )
            }

            var currentIdentities: [String: ObjectIdentifier] = [:]
            for itemID in itemIDs {
                currentIdentities[itemID] = try #require(registry.debugEntryIdentity(for: itemID))
            }
            if session == 1 {
                identities = currentIdentities
            } else {
                #expect(currentIdentities == identities)
            }
            #expect(registry.debugEntryCount == 50)
            #expect(registry.debugObservedClipViewCount == 1)
            #expect(Self.pointerTrackingAreaCount(in: rows) == 50)

            let request = CommandPaletteRevealRequest(
                id: itemIDs[49],
                anchor: .keyboardEdge(delta: 1),
                token: session,
                session: session
            )
            registry.markRevealRequest(token: request.token, session: session)
            rows[49].reveal(request: request)
            registry.suspend(session: session)

            #expect(registry.debugEntryCount == 50)
            #expect(registry.debugObservedClipViewCount == 0)
            #expect(Self.pointerTrackingAreaCount(in: rows) == 0)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        await Self.drainMainQueue()
        #expect(scrollView.contentView.bounds.origin.y == 0)
        #expect(registry.debugObservedClipViewCount == 0)
        #expect(Self.pointerTrackingAreaCount(in: rows) == 0)

        for row in rows {
            row.unregister()
            row.removeFromSuperview()
        }
        #expect(registry.debugEntryCount == 0)
        #expect(registry.debugObservedClipViewCount == 0)
        #expect(Self.pointerTrackingAreaCount(in: rows) == 0)
    }

    @Test @MainActor
    func repeatedRegistrationKeepsTheEntryAndReleasesTheOldScrollObserver() throws {
        let registry = CommandPaletteRevealRegistry()
        let firstScrollView = Self.scrollView()
        let secondScrollView = Self.scrollView()
        let view = CommandPaletteRevealView(frame: NSRect(x: 0, y: 40, width: 220, height: 36))
        let tracker = CommandPalettePointerMovementTracker()

        registry.resume(session: 1)
        let firstDocument = try #require(firstScrollView.documentView)
        firstDocument.addSubview(view)
        Self.configure(view, registry: registry, tracker: tracker, session: 1, interactionEnabled: true)
        let firstEntryIdentity = try #require(registry.debugEntryIdentity(for: "tool.json"))

        Self.configure(view, registry: registry, tracker: tracker, session: 1, interactionEnabled: true)
        #expect(registry.debugEntryIdentity(for: "tool.json") == firstEntryIdentity)
        #expect(registry.debugEntryCount == 1)
        #expect(registry.debugObservedClipViewCount == 1)
        #expect(registry.debugIsObserving(firstScrollView.contentView))
        view.updateTrackingAreas()
        view.updateTrackingAreas()
        #expect(Self.pointerTrackingAreaCount(in: view) == 1)
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil)

        let secondDocument = try #require(secondScrollView.documentView)
        view.removeFromSuperview()
        secondDocument.addSubview(view)
        Self.configure(view, registry: registry, tracker: tracker, session: 1, interactionEnabled: true)

        #expect(registry.debugEntryIdentity(for: "tool.json") == firstEntryIdentity)
        #expect(registry.debugObservedClipViewCount == 1)
        #expect(!registry.debugIsObserving(firstScrollView.contentView))
        #expect(registry.debugIsObserving(secondScrollView.contentView))

        view.unregister()
        #expect(registry.debugEntryCount == 0)
        #expect(registry.debugObservedClipViewCount == 0)

        view.removeFromSuperview()
        firstDocument.addSubview(view)
        #expect(registry.debugEntryCount == 0)
        #expect(registry.debugObservedClipViewCount == 0)
    }

    @MainActor
    private static func configure(
        _ view: CommandPaletteRevealView,
        itemID: String = "tool.json",
        registry: CommandPaletteRevealRegistry,
        tracker: CommandPalettePointerMovementTracker,
        session: Int,
        interactionEnabled: Bool,
        onMouseMove: @escaping () -> Void = {}
    ) {
        view.configure(
            itemID: itemID,
            selectableIndex: 0,
            registry: registry,
            session: session,
            interactionEnabled: interactionEnabled,
            pointerMovementTracker: tracker,
            onMouseMove: onMouseMove
        )
    }

    @MainActor
    private static func mouseMovedEvent(at location: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(
            with: .mouseMoved,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )
    }

    private static func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    @MainActor
    private static func scrollView(documentHeight: CGFloat = 600) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: 120))
        let documentView = FlippedDocumentView(
            frame: NSRect(x: 0, y: 0, width: 220, height: documentHeight)
        )
        scrollView.documentView = documentView
        return scrollView
    }

    private final class FlippedDocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    @MainActor
    private static func pointerTrackingAreaCount(in view: NSView) -> Int {
        view.trackingAreas.filter { area in
            area.options.contains(.mouseMoved)
                && area.options.contains(.activeInKeyWindow)
                && area.options.contains(.inVisibleRect)
        }.count
    }

    @MainActor
    private static func pointerTrackingAreaCount(in views: [CommandPaletteRevealView]) -> Int {
        views.reduce(0) { partialResult, view in
            partialResult + pointerTrackingAreaCount(in: view)
        }
    }
}
