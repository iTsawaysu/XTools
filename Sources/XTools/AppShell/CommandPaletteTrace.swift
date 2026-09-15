import AppKit
import Foundation

/// Opt-in DEBUG diagnostics for command-palette presentation work. Frequent
/// events are aggregated instead of printing on every SwiftUI/AppKit callback.
@MainActor
enum CommandPaletteTrace {
    enum Counter: String, CaseIterable {
        case rootBody, sidebarProjection, commandProjection
        case paletteBody, rowSnapshot
        case revealMake, revealUpdate, revealDismantle
        case hoverMake, hoverUpdate, hoverDismantle
        case iconAnchorResolution
        case visibleAnimatedTransaction, visibleDisabledTransaction, hiddenTransaction
        case visibilityIntermediateSample, visibilityTerminalSample
        case visibilityClosingIntermediateSample, visibilityClosingTerminalSample
    }

    struct Snapshot {
        let requestedMilliseconds: [String: Double]
        let openedMilliseconds: [String: Double]
        let counters: [Counter: Int]
    }

#if DEBUG
    struct PresentationProgressSample {
        let session: Int
        let isPresented: Bool
        let progress: CGFloat
        let reduceMotion: Bool
        let geometry: CommandPaletteVisibilityGeometry
    }
#endif

#if DEBUG
    private final class SessionState {
        let requestedAt: ContinuousClock.Instant
        var openedAt: ContinuousClock.Instant?
        var requestedMilliseconds: [String: Double] = [:]
        var openedMilliseconds: [String: Double] = [:]
        var counters: [Counter: Int] = [:]

        init(requestedAt: ContinuousClock.Instant) {
            self.requestedAt = requestedAt
        }
    }

    private static let isPresentationTraceEnabled =
        ProcessInfo.processInfo.environment["TOOLS_COMMAND_PALETTE_BENCHMARK"] == "1"
    private static let isFocusTraceEnabled =
        ProcessInfo.processInfo.environment["TOOLS_COMMAND_PALETTE_FOCUS_TRACE"] == "1"
    private static let isNativeReadyTraceEnabled =
        ProcessInfo.processInfo.environment["TOOLS_COMMAND_PALETTE_READY_TRACE"] == "1"
    private static let isEnabled = isPresentationTraceEnabled
        || isFocusTraceEnabled
        || isNativeReadyTraceEnabled
    private static var sessions: [Int: SessionState] = [:]
    private static var nativeReadyProbeSessions: Set<Int> = []
    private static var presentationProgressObserver: ((PresentationProgressSample) -> Void)?
    private static var presentationShellObserver: (() -> Void)?
    private(set) static var currentSession: Int?
#else
    static let currentSession: Int? = nil
#endif

    static func requestStarted(session: Int) {
#if DEBUG
        guard isEnabled else { return }
        if isPresentationTraceEnabled, let currentSession {
            emitCounts(session: currentSession, reason: "next_request")
        }
        currentSession = session
        sessions[session] = SessionState(requestedAt: .now)
        if sessions.count > 4 {
            let retained = Set(sessions.keys.sorted().suffix(4))
            sessions = sessions.filter { retained.contains($0.key) }
            nativeReadyProbeSessions.formIntersection(retained)
        }
        if isPresentationTraceEnabled {
            recordPhase("request_started", session: session, now: .now)
        }
#endif
    }

    static func opened(session: Int) {
#if DEBUG
        guard isEnabled, let state = sessions[session] else { return }
        state.openedAt = .now
        if isPresentationTraceEnabled {
            recordPhase("opened", session: session, now: .now)
        }
#endif
    }

    static func appeared(session: Int) {
#if DEBUG
        guard isPresentationTraceEnabled else { return }
        recordPhase("appeared", session: session, now: .now)
#endif
    }

    static func count(_ counter: Counter, session: Int? = currentSession) {
#if DEBUG
        guard isPresentationTraceEnabled, let session, let state = sessions[session] else { return }
        state.counters[counter, default: 0] += 1
#endif
    }

    static func presentationTransaction(
        session: Int,
        isPresented: Bool,
        isVisible: Bool,
        hasAnimation: Bool,
        disablesAnimations: Bool
    ) {
#if DEBUG
        guard isPresentationTraceEnabled, currentSession == session else {
            return
        }
        if !isPresented && !isVisible {
            count(.hiddenTransaction, session: session)
            return
        }
        guard isPresented, isVisible else { return }
        if disablesAnimations {
            count(.visibleDisabledTransaction, session: session)
        } else if hasAnimation {
            count(.visibleAnimatedTransaction, session: session)
        }
#endif
    }

    static func presentationProgress(
        session: Int,
        isPresented: Bool,
        progress: CGFloat,
        reduceMotion: Bool,
        geometry: CommandPaletteVisibilityGeometry
    ) {
#if DEBUG
        presentationProgressObserver?(PresentationProgressSample(
            session: session,
            isPresented: isPresented,
            progress: progress,
            reduceMotion: reduceMotion,
            geometry: geometry
        ))
        guard isPresentationTraceEnabled, currentSession == session else { return }
        if progress > 0.001, progress < 0.999 {
            count(
                isPresented
                    ? .visibilityIntermediateSample
                    : .visibilityClosingIntermediateSample,
                session: session
            )
        } else if isPresented, progress >= 0.999 {
            count(.visibilityTerminalSample, session: session)
        } else if !isPresented, progress <= 0.001 {
            count(.visibilityClosingTerminalSample, session: session)
        }
#endif
    }

#if DEBUG
    static func observePresentationProgress(
        _ observer: ((PresentationProgressSample) -> Void)?
    ) {
        presentationProgressObserver = observer
    }

    static func observePresentationShell(_ observer: (() -> Void)?) {
        presentationShellObserver = observer
    }
#endif

    static func presentationShellMounted() {
#if DEBUG
        presentationShellObserver?()
#endif
    }

    static func snapshot(session: Int) -> Snapshot? {
#if DEBUG
        guard isPresentationTraceEnabled, let state = sessions[session] else { return nil }
        return Snapshot(
            requestedMilliseconds: state.requestedMilliseconds,
            openedMilliseconds: state.openedMilliseconds,
            counters: state.counters
        )
#else
        return nil
#endif
    }

    static func dismissed(session: Int) {}

    static func finish(session: Int) {
#if DEBUG
        guard isPresentationTraceEnabled else { return }
        emitCounts(session: session, reason: "finished")
#endif
    }

    static func focusAttemptObserver(
        session: Int
    ) -> AppKitSearchFieldLifecycle.FocusAttemptObserver? {
#if DEBUG
        guard isFocusTraceEnabled else { return nil }
        return { attempt in
            recordFocusAttempt(attempt, session: session)
        }
#else
        return nil
#endif
    }

    static func observeNativeReady(
        _ field: NSTextField,
        session: Int,
        isValid: @escaping AppKitSearchFieldCoordinator.FocusRequestValidity
    ) {
#if DEBUG
        guard isNativeReadyTraceEnabled,
              sessions[session] != nil,
              isValid(),
              nativeReadyProbeSessions.insert(session).inserted
        else {
            return
        }
        DispatchQueue.main.async { [weak field] in
            pollNativeReady(
                field,
                session: session,
                isValid: isValid,
                attempt: 0,
                layoutFlushes: 0,
                deadline: .now + .seconds(2)
            )
        }
#endif
    }

#if DEBUG
    private static func recordPhase(
        _ phase: String,
        session: Int,
        now: ContinuousClock.Instant
    ) {
        guard isEnabled, let state = sessions[session] else { return }
        guard state.requestedMilliseconds[phase] == nil else { return }
        state.requestedMilliseconds[phase] = milliseconds(from: state.requestedAt, to: now)
        if let openedAt = state.openedAt {
            state.openedMilliseconds[phase] = milliseconds(from: openedAt, to: now)
        }
        let requested = state.requestedMilliseconds[phase] ?? 0
        let openedField = state.openedMilliseconds[phase]
            .map { String(format: "%.3f", $0) } ?? "na"
        write(String(
            format: "COMMAND_PALETTE_PRESENTATION_PHASE_RESULT session=%d phase=%@ requested_ms=%.3f opened_ms=%@ milliseconds=%@\n",
            session, phase, requested, openedField, openedField
        ))
    }

    private static func emitCounts(session: Int, reason: String) {
        guard let state = sessions[session] else { return }
        let fields = Counter.allCases
            .map { "\($0.rawValue)=\(state.counters[$0, default: 0])" }
            .joined(separator: " ")
        write("COMMAND_PALETTE_PRESENTATION_COUNTS session=\(session) reason=\(reason) \(fields)\n")
    }

    private static func recordFocusAttempt(
        _ attempt: AppKitSearchFieldFocusAttempt,
        session: Int
    ) {
        let state = sessions[session]
        let requestEndMilliseconds = state.map {
            String(format: "%.3f", milliseconds(from: $0.requestedAt, to: .now))
        } ?? "na"
        let openPreparationMilliseconds = state.flatMap { state in
            state.openedAt.map {
                String(format: "%.3f", milliseconds(from: state.requestedAt, to: $0))
            }
        } ?? "na"
        let source: String
        let delayMilliseconds: Double
        switch attempt.source {
        case .immediate:
            source = "immediate"
            delayMilliseconds = 0
        case .delayed(let delay):
            source = "delayed"
            delayMilliseconds = delay * 1_000
        }
        let makeFirstResponderResult = attempt.makeFirstResponderResult
            .map(String.init) ?? "na"
        let makeFirstResponderMilliseconds = attempt.makeFirstResponderMilliseconds
            .map { String(format: "%.3f", $0) } ?? "na"
        let currentSession = currentSession.map(String.init) ?? "none"
        write(String(
            format: "COMMAND_PALETTE_FOCUS_ATTEMPT session=%d current_session=%@ session_known=%@ source=%@ delay_ms=%.3f request_end_ms=%@ open_preparation_ms=%@ valid=%@ has_window=%@ key_window=%@ nonzero_frame=%@ make_first_responder=%@ make_first_responder_ms=%@ editor_owned=%@\n",
            session,
            currentSession,
            String(state != nil),
            source,
            delayMilliseconds,
            requestEndMilliseconds,
            openPreparationMilliseconds,
            String(attempt.isRequestValid),
            String(attempt.hasWindow),
            String(attempt.isKeyWindow),
            String(attempt.hasNonzeroFrame),
            makeFirstResponderResult,
            makeFirstResponderMilliseconds,
            String(attempt.firstResponderIsFieldEditor)
        ))
    }

    private static func pollNativeReady(
        _ field: NSTextField?,
        session: Int,
        isValid: @escaping AppKitSearchFieldCoordinator.FocusRequestValidity,
        attempt: Int,
        layoutFlushes: Int,
        deadline: ContinuousClock.Instant
    ) {
        guard currentSession == session else { return }
        guard isValid(), let field else {
            nativeReadyProbeSessions.remove(session)
            return
        }

        let window = field.window
        window?.contentView?.layoutSubtreeIfNeeded()
        let nextLayoutFlushes = layoutFlushes + (window?.contentView == nil ? 0 : 1)
        guard currentSession == session,
              isValid(),
              field.window === window
        else {
            return
        }
        let hasNonzeroFieldFrame = field.frame.width > 0 && field.frame.height > 0
        let editorOwned = field.currentEditor().map { window?.firstResponder === $0 } ?? false
        let isReady = window != nil
            && window?.isKeyWindow == true
            && hasNonzeroFieldFrame
            && editorOwned

        if isReady {
            recordPhase("native_ready", session: session, now: .now)
            guard let state = sessions[session] else { return }
            let elapsed = state.requestedMilliseconds["native_ready"] ?? 0
            let contentSize = window?.contentView?.frame.size ?? .zero
            write(String(
                format: "COMMAND_PALETTE_NATIVE_READY session=%d requested_ms=%.3f session_valid=true window_content_width=%.3f window_content_height=%.3f field_width=%.3f field_height=%.3f key_window=true editor_owned=true layout_flushes=%d\n",
                session,
                elapsed,
                contentSize.width,
                contentSize.height,
                field.frame.width,
                field.frame.height,
                nextLayoutFlushes
            ))
            return
        }

        guard attempt < 2_000, ContinuousClock.now < deadline else {
            let contentSize = window?.contentView?.frame.size ?? .zero
            write(String(
                format: "COMMAND_PALETTE_NATIVE_READY_TIMEOUT session=%d session_valid=true has_window=%@ window_content_width=%.3f window_content_height=%.3f field_width=%.3f field_height=%.3f key_window=%@ editor_owned=%@ layout_flushes=%d\n",
                session,
                String(window != nil),
                contentSize.width,
                contentSize.height,
                field.frame.width,
                field.frame.height,
                String(window?.isKeyWindow == true),
                String(editorOwned),
                nextLayoutFlushes
            ))
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1)) { [weak field] in
            pollNativeReady(
                field,
                session: session,
                isValid: isValid,
                attempt: attempt + 1,
                layoutFlushes: nextLayoutFlushes,
                deadline: deadline
            )
        }
    }

    private static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Double {
        let value = (end - start).components
        return Double(value.seconds) * 1_000
            + Double(value.attoseconds) / 1_000_000_000_000_000
    }

    private static func write(_ line: String) {
        FileHandle.standardError.write(Data(line.utf8))
    }
#endif
}
