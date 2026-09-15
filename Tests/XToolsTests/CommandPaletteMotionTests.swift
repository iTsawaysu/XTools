import AppKit
import Foundation
import QuartzCore
import SwiftUI
@testable import XTools
import Testing

@Suite(.serialized)
struct CommandPaletteMotionTests {
    @Test
    func visibilityGeometryIsAContinuousFunctionOfProgress() {
        var previous = CommandPaletteVisibilityGeometry.resolve(
            progress: 0,
            reduceMotion: false
        )
        for progress in stride(from: CGFloat(0.05), through: 1, by: 0.05) {
            let current = CommandPaletteVisibilityGeometry.resolve(
                progress: progress,
                reduceMotion: false
            )

            #expect(abs(current.opacity - Double(progress)) < 0.000_001)
            #expect(abs(current.offsetY - previous.offsetY) <= ToolMotion.Distance.small * 0.05 + 0.000_001)
            previous = current
        }

        #expect(previous.offsetY == 0)
        #expect(previous.scale == 1)
    }

    @Test
    func reduceMotionKeepsScaleAndOffsetFixedAcrossAllProgress() {
        for progress in stride(from: CGFloat(0), through: 1, by: 0.05) {
            let geometry = CommandPaletteVisibilityGeometry.resolve(
                progress: progress,
                reduceMotion: true
            )

            #expect(geometry.scale == 1)
            #expect(geometry.offsetY == 0)
            #expect(geometry.opacity == Double(progress))
        }
    }

#if DEBUG
    /// This observes SwiftUI's `Animatable.animatableData` setter in a real
    /// RootView/NSWindow. It proves that rapid reversals keep one in-flight
    /// interpolation and do not reset progress at session boundaries. It does
    /// not measure display frames, frame rate, or animation completion on screen.
    @Test @MainActor
    func realRootWindowKeepsFirstAndWarmRapidReversalsContinuous() async throws {
        var samples: [TimedProgressSample] = []
        var shellMounted = false
        var fixtureForObserver: CommandPaletteWindowFixture?
        CommandPaletteTrace.observePresentationProgress { sample in
            samples.append(TimedProgressSample(
                timestamp: .now,
                sample: sample,
                observedShows: fixtureForObserver?.viewModel.showsCommandPalette,
                observedSession: fixtureForObserver?.viewModel.commandPalettePresentationSession
            ))
        }
        CommandPaletteTrace.observePresentationShell {
            shellMounted = true
        }
        defer {
            CommandPaletteTrace.observePresentationProgress(nil)
            CommandPaletteTrace.observePresentationShell(nil)
        }

        let fixture = try CommandPaletteWindowFixture()
        fixtureForObserver = fixture
        FileHandle.standardError.write(Data(
            "COMMAND_PALETTE_RAPID_CONFIG system_reduce_motion=\(ToolMotion.systemReduceMotionEnabled) fixture_reduce_motion=environment\n".utf8
        ))
        defer { fixture.dispose() }
        try await Self.waitForCondition(label: "initial hidden motion shell mount") {
            Self.flushMotion(in: fixture)
            return shellMounted && !fixture.viewModel.showsCommandPalette
        }
        // Let the hidden shell finish one run-loop/display boundary before the
        // first presentation mutates its target. This models an already shown
        // app window rather than racing fixture construction itself.
        try await Task.sleep(for: .milliseconds(1))
        Self.flushMotion(in: fixture)

        let firstMountStartIndex = samples.count
        let firstMountOpenedAt = ContinuousClock.now
        withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
            fixture.viewModel.openCommandPalette()
        }
        try await Self.waitForCondition(label: "first mount intermediate interpolation") {
            Self.flushMotion(in: fixture)
            return samples[firstMountStartIndex...].contains {
                $0.observedShows == true && Self.isIntermediate($0.sample.progress)
            }
        }
        let firstMountCloseIndex = samples.count
        let firstMountLastOpening = try #require(
            samples[firstMountStartIndex..<firstMountCloseIndex].last {
                $0.observedShows == true
            }
        )
        #expect(Self.isIntermediate(firstMountLastOpening.sample.progress))
        let firstMountCloseRequestedAt = ContinuousClock.now
        withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
            fixture.viewModel.closeCommandPalette()
        }
        try await Self.waitForCondition(label: "first mount close interpolation") {
            Self.flushMotion(in: fixture)
            return samples[firstMountCloseIndex...].contains { $0.observedShows == false }
        }
        let firstMountFirstClosing = try #require(
            samples[firstMountCloseIndex...].first { $0.observedShows == false }
        )
        #expect(Self.isIntermediate(firstMountFirstClosing.sample.progress))
        Self.expectContinuousBoundary(
            from: firstMountLastOpening,
            to: firstMountFirstClosing
        )

        let firstMountReopenIndex = samples.count
        let firstMountLastClosing = try #require(
            samples[firstMountCloseIndex..<firstMountReopenIndex].last {
                $0.observedShows == false
            }
        )
        #expect(Self.isIntermediate(firstMountLastClosing.sample.progress))
        let firstMountReopenRequestedAt = ContinuousClock.now
        withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
            fixture.viewModel.openCommandPalette()
        }
        try await Self.waitForCondition(label: "first mount reopen interpolation") {
            Self.flushMotion(in: fixture)
            return samples[firstMountReopenIndex...].contains { $0.observedShows == true }
        }
        let firstMountFirstReopening = try #require(
            samples[firstMountReopenIndex...].first { $0.observedShows == true }
        )
        #expect(Self.isIntermediate(firstMountFirstReopening.sample.progress))
        Self.expectContinuousBoundary(
            from: firstMountLastClosing,
            to: firstMountFirstReopening
        )
        let firstField = try await Self.waitForReadyField(in: fixture, excluding: nil)
        try await Self.waitForCondition(label: "first mount reopen terminal interpolation") {
            Self.flushMotion(in: fixture)
            return samples[firstMountReopenIndex...].contains {
                $0.observedShows == true && $0.sample.progress >= 0.999
            }
        }
        let firstMountElapsed = Self.milliseconds(from: firstMountOpenedAt, to: .now)
        let firstMountOpenToClose = Self.milliseconds(
            from: firstMountOpenedAt,
            to: firstMountCloseRequestedAt
        )
        let firstMountCloseToReopen = Self.milliseconds(
            from: firstMountCloseRequestedAt,
            to: firstMountReopenRequestedAt
        )
        FileHandle.standardError.write(Data(String(
            format: "COMMAND_PALETTE_FIRST_MOUNT_REVERSAL actual_open_to_close_ms=%.3f actual_close_to_reopen_ms=%.3f actual_open_through_reopen_terminal_ms=%.3f open_last_p=%.6f close_first_p=%.6f close_last_p=%.6f reopen_first_p=%.6f samples=%d\n",
            firstMountOpenToClose,
            firstMountCloseToReopen,
            firstMountElapsed,
            firstMountLastOpening.sample.progress,
            firstMountFirstClosing.sample.progress,
            firstMountLastClosing.sample.progress,
            firstMountFirstReopening.sample.progress,
            samples.count - firstMountStartIndex
        ).utf8))
        let firstTerminalCloseIndex = samples.count
        withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
            fixture.viewModel.closeCommandPalette()
        }
        try await Self.waitForCondition(label: "first terminal close interpolation") {
            Self.flushMotion(in: fixture)
            return samples[firstTerminalCloseIndex...].contains {
                $0.observedShows == false && $0.sample.progress <= 0.001
            }
        }

        var previousField: NSTextField? = firstField
        for requestedDelayMilliseconds in [20, 50, 100] {
            #expect(!fixture.viewModel.showsCommandPalette)
            let cycleStartIndex = samples.count
            let openRequestedAt = ContinuousClock.now
            withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
                fixture.viewModel.openCommandPalette()
            }
            let openingSession = fixture.viewModel.commandPalettePresentationSession

            try await Task.sleep(for: .milliseconds(requestedDelayMilliseconds))
            Self.flushMotion(in: fixture)
            let closeRequestedAt = ContinuousClock.now
            let closingStartIndex = samples.count
            let openingBeforeClose = Array(samples[cycleStartIndex..<closingStartIndex])
                .filter { $0.observedShows == true }
            Self.emitRawSamples(
                label: "before_close_\(requestedDelayMilliseconds)",
                samples: Array(samples[cycleStartIndex..<closingStartIndex]),
                relativeTo: openRequestedAt
            )
            let lastOpeningSample = try #require(openingBeforeClose.last)
            #expect(Self.isIntermediate(lastOpeningSample.sample.progress))

            withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
                fixture.viewModel.closeCommandPalette()
            }
            #expect(!fixture.viewModel.showsCommandPalette)

            try await Task.sleep(for: .milliseconds(requestedDelayMilliseconds))
            Self.flushMotion(in: fixture)
            let reopenRequestedAt = ContinuousClock.now
            let reopeningStartIndex = samples.count
            let closingBeforeReopen = Array(samples[closingStartIndex..<reopeningStartIndex])
                .filter { $0.observedShows == false }
            Self.emitRawSamples(
                label: "before_reopen_\(requestedDelayMilliseconds)",
                samples: Array(samples[closingStartIndex..<reopeningStartIndex]),
                relativeTo: closeRequestedAt
            )
            let lastClosingSample = try #require(closingBeforeReopen.last)
            #expect(Self.isIntermediate(lastClosingSample.sample.progress))
            let firstClosingSample = try #require(closingBeforeReopen.first)
            #expect(Self.isIntermediate(firstClosingSample.sample.progress))

            withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
                fixture.viewModel.openCommandPalette()
            }
            let reopeningSession = fixture.viewModel.commandPalettePresentationSession
            #expect(reopeningSession > openingSession)

            try await Self.waitForCondition(label: "intermediate reopen interpolation") {
                Self.flushMotion(in: fixture)
                return samples[reopeningStartIndex...].contains {
                    $0.observedShows == true && Self.isIntermediate($0.sample.progress)
                }
            }
            let reopeningSamples = Array(samples[reopeningStartIndex...])
                .filter { $0.observedShows == true }
            let firstReopeningSample = try #require(reopeningSamples.first)
            #expect(Self.isIntermediate(firstReopeningSample.sample.progress))
            Self.expectContinuousBoundary(
                from: lastClosingSample,
                to: firstReopeningSample
            )

            Self.expectContinuousBoundary(
                from: lastOpeningSample,
                to: firstClosingSample
            )

            // Inspect the first setter delivery after each direction change,
            // before filtering for intermediate values. An endpoint reset
            // followed by a fresh animation therefore fails this assertion.
            #expect(Self.isIntermediate(firstClosingSample.sample.progress))
            #expect(Self.isIntermediate(firstReopeningSample.sample.progress))

            let currentField = try await Self.waitForReadyField(
                in: fixture,
                excluding: previousField
            )
            if let previousField {
                #expect(currentField !== previousField)
                #expect(!previousField.isEnabled)
            }
            previousField = currentField

            try await Self.waitForCondition(label: "reopen interpolation terminal") {
                Self.flushMotion(in: fixture)
                return samples[reopeningStartIndex...].contains {
                    $0.observedShows == true && $0.sample.progress >= 0.999
                }
            }
            #expect(fixture.viewModel.showsCommandPalette)

            let openToClose = Self.milliseconds(from: openRequestedAt, to: closeRequestedAt)
            let closeToOpen = Self.milliseconds(from: closeRequestedAt, to: reopenRequestedAt)
            let openToCloseText = String(format: "%.3f", openToClose)
            let closeToOpenText = String(format: "%.3f", closeToOpen)
            let rawSamples = samples[cycleStartIndex...].map { sample in
                let elapsed = Self.milliseconds(from: openRequestedAt, to: sample.timestamp)
                return String(
                    format: "{t=%.3f,p=%.6f,label=%@,observed=%@,reduce=%@,labelSession=%d,observedSession=%@}",
                    elapsed,
                    sample.sample.progress,
                    String(sample.sample.isPresented),
                    sample.observedShows.map(String.init) ?? "nil",
                    String(sample.sample.reduceMotion),
                    sample.sample.session,
                    sample.observedSession.map(String.init) ?? "nil"
                )
            }.joined(separator: ",")
            FileHandle.standardError.write(Data(
                "COMMAND_PALETTE_RAPID_REVERSAL requested_delay_ms=\(requestedDelayMilliseconds) actual_open_to_close_ms=\(openToCloseText) actual_close_to_open_ms=\(closeToOpenText) first_mount=false opening_session=\(openingSession) reopening_session=\(reopeningSession) samples=[\(rawSamples)]\n".utf8
            ))

            let terminalCloseStartIndex = samples.count
            withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
                fixture.viewModel.closeCommandPalette()
            }
            try await Self.waitForCondition(label: "terminal close interpolation") {
                Self.flushMotion(in: fixture)
                return samples[terminalCloseStartIndex...].contains {
                    $0.observedShows == false && $0.sample.progress <= 0.001
                }
            }
        }

        // A close/open pair that coalesces before rendering still creates a
        // fresh input session, while the already-visible motion shell remains
        // at its current progress instead of restarting from an endpoint.
        withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
            fixture.viewModel.openCommandPalette()
        }
        let coalescedOldField = try await Self.waitForReadyField(
            in: fixture,
            excluding: previousField
        )
        try await Self.waitForCondition(label: "coalesced setup terminal interpolation") {
            Self.flushMotion(in: fixture)
            return samples.last.map {
                $0.observedShows == true && $0.sample.progress >= 0.999
            } ?? false
        }
        let sessionBeforeCoalescedReset = fixture.viewModel.commandPalettePresentationSession
        let coalescedStartIndex = samples.count
        withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
            fixture.viewModel.closeCommandPalette()
            fixture.viewModel.openCommandPalette()
        }
        #expect(fixture.viewModel.showsCommandPalette)
        #expect(
            fixture.viewModel.commandPalettePresentationSession
                > sessionBeforeCoalescedReset
        )
        let coalescedNewField = try await Self.waitForReadyField(
            in: fixture,
            excluding: coalescedOldField
        )
        #expect(coalescedNewField !== coalescedOldField)
        #expect(!coalescedOldField.isEnabled)
        #expect(
            !samples[coalescedStartIndex...].contains {
                $0.observedShows == true && $0.sample.progress <= 0.001
            }
        )

        let finalCloseStartIndex = samples.count
        withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
            fixture.viewModel.closeCommandPalette()
        }
        try await Self.waitForCondition(label: "final terminal close interpolation") {
            Self.flushMotion(in: fixture)
            return samples[finalCloseStartIndex...].contains {
                $0.observedShows == false && $0.sample.progress <= 0.001
            }
        }
    }

    /// Reduce Motion still exercises the real retained palette lifecycle and
    /// native focus handoff, while the presentation modifier moves directly
    /// between opacity endpoints without intermediate interpolation samples.
    @Test @MainActor
    func realRootWindowReduceMotionFocusesAndSuspendsWithoutInterpolation() async throws {
        var samples: [CommandPaletteTrace.PresentationProgressSample] = []
        CommandPaletteTrace.observePresentationProgress { samples.append($0) }
        defer { CommandPaletteTrace.observePresentationProgress(nil) }

        let fixture = try CommandPaletteWindowFixture(reduceMotion: true)
        defer { fixture.dispose() }

        let presentationStartIndex = samples.count
        withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
            fixture.viewModel.openCommandPalette()
        }
        let field = try await Self.waitForReadyField(in: fixture, excluding: nil)

        withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
            fixture.viewModel.closeCommandPalette()
        }
        try await Self.waitForCondition(label: "Reduce Motion field suspension") {
            Self.flushMotion(in: fixture)
            let ownsEditor = field.currentEditor().map {
                fixture.window.firstResponder === $0
            } ?? false
            return !field.isEnabled && !ownsEditor
        }

        // With animation disabled SwiftUI may apply the new value directly to
        // the view body without invoking the Animatable setter at all. If the
        // setter does run, every delivered value must still be a terminal one.
        let presentationSamples = samples[presentationStartIndex...]
        #expect(presentationSamples.allSatisfy { $0.reduceMotion })
        #expect(!presentationSamples.contains { Self.isIntermediate($0.progress) })
        #expect(!fixture.viewModel.showsCommandPalette)
    }

    /// Fixed-rate toggle bursts validate request parity and stale focus-callback
    /// isolation. A burst may legitimately coalesce before the first rendered
    /// interpolation, so this pressure test does not require midpoint samples.
    @Test @MainActor
    func realRootWindowTimedToggleBurstsHonorParityWithoutLateFocusRebound() async throws {
        for requestedDelayMilliseconds in [20, 50, 100] {
            let fixture = try CommandPaletteWindowFixture(reduceMotion: false)
            defer { fixture.dispose() }

            let oddSessionStart = fixture.viewModel.commandPalettePresentationSession
            let oddIntervals = try await Self.runTimedToggleBurst(
                count: 5,
                requestedDelayMilliseconds: requestedDelayMilliseconds,
                in: fixture
            )
            #expect(fixture.viewModel.showsCommandPalette)
            #expect(
                fixture.viewModel.commandPalettePresentationSession
                    == oddSessionStart + 5
            )
            let focusedField = try await Self.waitForReadyField(
                in: fixture,
                excluding: nil
            )
            try await Self.observePastFocusRetryDeadline(in: fixture)
            #expect(fixture.viewModel.showsCommandPalette)
            #expect(focusedField.isEnabled)
            #expect(focusedField.currentEditor().map {
                fixture.window.firstResponder === $0
            } ?? false)

            withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
                fixture.viewModel.closeCommandPalette()
            }
            try await Self.waitForCondition(label: "timed burst odd cleanup") {
                Self.flushMotion(in: fixture)
                return !focusedField.isEnabled
            }

            let evenSessionStart = fixture.viewModel.commandPalettePresentationSession
            let evenIntervals = try await Self.runTimedToggleBurst(
                count: 6,
                requestedDelayMilliseconds: requestedDelayMilliseconds,
                in: fixture
            )
            #expect(!fixture.viewModel.showsCommandPalette)
            #expect(
                fixture.viewModel.commandPalettePresentationSession
                    == evenSessionStart + 6
            )
            let settledSession = fixture.viewModel.commandPalettePresentationSession
            try await Self.observePastFocusRetryDeadline(in: fixture)
            let retainedFields = Self.fields(in: fixture.hostingView).filter {
                $0.accessibilityIdentifier() == "command-palette.search"
            }
            #expect(!retainedFields.isEmpty)
            #expect(!fixture.viewModel.showsCommandPalette)
            #expect(fixture.viewModel.commandPalettePresentationSession == settledSession)
            #expect(retainedFields.allSatisfy { !$0.isEnabled })
            #expect(retainedFields.allSatisfy { field in
                field.currentEditor().map {
                    fixture.window.firstResponder !== $0
                } ?? true
            })

            let oddIntervalText = oddIntervals
                .map { String(format: "%.3f", $0) }
                .joined(separator: ",")
            let evenIntervalText = evenIntervals
                .map { String(format: "%.3f", $0) }
                .joined(separator: ",")
            FileHandle.standardError.write(Data(
                "COMMAND_PALETTE_TIMED_TOGGLE_STRESS requested_delay_ms=\(requestedDelayMilliseconds) odd_count=5 odd_actual_intervals_ms=[\(oddIntervalText)] even_count=6 even_actual_intervals_ms=[\(evenIntervalText)] final_visible=\(fixture.viewModel.showsCommandPalette) final_session=\(settledSession)\n".utf8
            ))
        }
    }

    private static func isIntermediate(_ progress: CGFloat) -> Bool {
        progress > 0.001 && progress < 0.999
    }

    private static func expectContinuousBoundary(
        from lhs: TimedProgressSample,
        to rhs: TimedProgressSample
    ) {
        let progressDistance = abs(rhs.sample.progress - lhs.sample.progress)
        let offsetDistance = abs(rhs.sample.geometry.offsetY - lhs.sample.geometry.offsetY)
        let elapsedMilliseconds = milliseconds(from: lhs.timestamp, to: rhs.timestamp)
        #expect(lhs.timestamp <= rhs.timestamp)
        #expect(elapsedMilliseconds < 100)
        #expect(progressDistance < 0.25)
        #expect(
            offsetDistance
                <= ToolMotion.Distance.small * progressDistance + 0.000_001
        )
    }

    @MainActor
    private static func runTimedToggleBurst(
        count: Int,
        requestedDelayMilliseconds: Int,
        in fixture: CommandPaletteWindowFixture
    ) async throws -> [Double] {
        var intervals: [Double] = []
        var previousRequestAt: ContinuousClock.Instant?
        for index in 0..<count {
            let requestedAt = ContinuousClock.now
            if let previousRequestAt {
                intervals.append(milliseconds(from: previousRequestAt, to: requestedAt))
            }
            withToolAnimation(ToolMotion.Preset.modal, reduceMotion: false) {
                fixture.viewModel.toggleCommandPalette()
            }
            Self.flushMotion(in: fixture)
            previousRequestAt = requestedAt
            if index < count - 1 {
                try await Task.sleep(for: .milliseconds(requestedDelayMilliseconds))
            }
        }
        return intervals
    }

    @MainActor
    private static func observePastFocusRetryDeadline(
        in fixture: CommandPaletteWindowFixture
    ) async throws {
        // CommandPalette's longest scheduled native-focus retry is 150 ms.
        // Crossing 200 ms gives the main run loop time to deliver that callback
        // and makes a stale request visible to the assertions that follow.
        try await Task.sleep(for: .milliseconds(200))
        Self.flushMotion(in: fixture)
    }

    @MainActor
    private static func waitForCondition(
        label: String,
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) async throws {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() {
            guard Date() < deadline else {
                Issue.record("Timed out waiting for \(label)")
                throw CommandPaletteMotionTestError.timeout(label)
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @MainActor
    private static func waitForReadyField(
        in fixture: CommandPaletteWindowFixture,
        excluding excludedField: NSTextField?
    ) async throws -> NSTextField {
        var result: NSTextField?
        try await waitForCondition(label: "current palette field layout and focus") {
            fixture.flush()
            result = Self.fields(in: fixture.hostingView).first { field in
                guard field !== excludedField,
                      field.accessibilityIdentifier() == "command-palette.search",
                      field.window === fixture.window,
                      field.frame.width > 0,
                      field.frame.height > 0,
                      let editor = field.currentEditor()
                else {
                    return false
                }
                return fixture.window.firstResponder === editor
            }
            return result != nil
        }
        return try #require(result)
    }

    @MainActor
    private static func fields(in root: NSView) -> [NSTextField] {
        var result = root is NSTextField ? [root as! NSTextField] : []
        for subview in root.subviews {
            result.append(contentsOf: fields(in: subview))
        }
        return result
    }

    @MainActor
    private static func flushMotion(in fixture: CommandPaletteWindowFixture) {
        fixture.flush()
        fixture.hostingView.displayIfNeeded()
        fixture.window.displayIfNeeded()
        CATransaction.flush()
    }

    private static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Double {
        let value = (end - start).components
        return Double(value.seconds) * 1_000
            + Double(value.attoseconds) / 1_000_000_000_000_000
    }

    private static func emitRawSamples(
        label: String,
        samples: [TimedProgressSample],
        relativeTo start: ContinuousClock.Instant
    ) {
        let values = samples.map { sample in
            String(
                format: "{t=%.3f,p=%.6f,label=%@,observed=%@,reduce=%@,labelSession=%d,observedSession=%@}",
                milliseconds(from: start, to: sample.timestamp),
                sample.sample.progress,
                String(sample.sample.isPresented),
                sample.observedShows.map(String.init) ?? "nil",
                String(sample.sample.reduceMotion),
                sample.sample.session,
                sample.observedSession.map(String.init) ?? "nil"
            )
        }.joined(separator: ",")
        FileHandle.standardError.write(Data(
            "COMMAND_PALETTE_RAPID_RAW label=\(label) samples=[\(values)]\n".utf8
        ))
    }
#endif
}

#if DEBUG
private struct TimedProgressSample {
    let timestamp: ContinuousClock.Instant
    let sample: CommandPaletteTrace.PresentationProgressSample
    let observedShows: Bool?
    let observedSession: Int?
}
#endif

private enum CommandPaletteMotionTestError: Error {
    case timeout(String)
}
