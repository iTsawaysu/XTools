import CoreGraphics
import Combine
import Foundation
@testable import XTools
import Testing

/// Real behavior tests for the Command-K palette keyboard logic.
struct CommandPaletteSearchTests {
    @Test func commandPaletteRowSnapshotBenchmark() {
        guard ProcessInfo.processInfo.environment["TOOLS_COMMAND_PALETTE_BENCHMARK"] == "1" else {
            return
        }

        let projection = ToolNavigationCommandProjection(registry: .default, query: "")
        let snapshot = CommandPaletteNavigationState.snapshot(for: projection.entries)
        let rows = snapshot.rows
        let state = CommandPaletteNavigationState()
        let iterations = 1_000
        var checksum = 0
        let startedAt = ContinuousClock.now

        for _ in 0..<iterations {
            for row in rows {
                if row.id == state.activeRowID(in: snapshot) {
                    checksum &+= 1
                }
                if row.id == state.activeRowID(in: snapshot) {
                    checksum &+= 1
                }
                checksum &+= state.selectableIndex(of: row, in: snapshot) ?? 0
            }
        }

        let elapsed = ContinuousClock.now - startedAt
        let components = elapsed.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        FileHandle.standardError.write(Data(String(
            format: "COMMAND_PALETTE_ROW_SNAPSHOT_BENCHMARK rows=%d iterations=%d milliseconds=%.3f checksum=%d\n",
            rows.count,
            iterations,
            milliseconds,
            checksum
        ).utf8))
    }

    // MARK: - RootViewModel focus requests

    @MainActor
    @Test func commandPaletteToggleAlternatesVisibilityAcrossRepeatedCommandKPresses() {
        let viewModel = RootViewModel()

        viewModel.toggleCommandPalette()
        #expect(viewModel.showsCommandPalette)
        #expect(viewModel.commandPalettePresentationSession == 1)
        #expect(viewModel.commandPaletteFocusToken == 1)

        viewModel.toggleCommandPalette()
        #expect(!viewModel.showsCommandPalette)
        #expect(viewModel.commandPalettePresentationSession == 2)

        viewModel.toggleCommandPalette()
        #expect(viewModel.showsCommandPalette)
        #expect(viewModel.commandPalettePresentationSession == 3)
        #expect(viewModel.commandPaletteFocusToken == 2)
    }

    @MainActor
    @Test func commandPaletteOpenRefocusesWithoutStartingAnotherSession() {
        let viewModel = RootViewModel()

        viewModel.openCommandPalette()

        #expect(viewModel.showsCommandPalette)
        #expect(viewModel.commandPaletteFocusToken == 1)
        #expect(viewModel.commandPalettePresentationSession == 1)

        viewModel.openCommandPalette()

        #expect(viewModel.showsCommandPalette)
        #expect(viewModel.commandPaletteFocusToken == 2)
        #expect(viewModel.commandPalettePresentationSession == 1)

        viewModel.closeCommandPalette()
        #expect(!viewModel.showsCommandPalette)
        #expect(viewModel.commandPalettePresentationSession == 2)

        viewModel.openCommandPalette()
        #expect(viewModel.showsCommandPalette)
        #expect(viewModel.commandPalettePresentationSession == 3)
    }

    @MainActor
    @Test func palettePresentationPublishesAtomicallyWithoutForwardingThroughRoot() {
        let viewModel = RootViewModel()
        var rootPublications = 0
        var presentationPublications = 0
        let rootCancellable = viewModel.objectWillChange.sink { rootPublications += 1 }
        let presentationCancellable = viewModel.commandPalettePresentation.objectWillChange.sink {
            presentationPublications += 1
        }

        viewModel.openCommandPalette()
        let preview = viewModel.commandPalettePreviewValue
        #expect(rootPublications == 0)
        #expect(presentationPublications == 1)

        viewModel.openCommandPalette()
        #expect(rootPublications == 0)
        #expect(presentationPublications == 2)
        #expect(viewModel.commandPalettePreviewValue == preview)

        viewModel.closeCommandPalette()
        #expect(rootPublications == 0)
        #expect(presentationPublications == 3)
        #expect(viewModel.commandPalettePreviewValue == preview)

        viewModel.closeCommandPalette()
        #expect(presentationPublications == 3)

        viewModel.consumeCommandPalettePreviewValue()
        #expect(rootPublications == 0)
        #expect(presentationPublications == 4)
        #expect(viewModel.commandPalettePreviewValue == nil)

        withExtendedLifetime((rootCancellable, presentationCancellable)) {}
    }

    @MainActor
    @Test func paletteSessionQuerySynchronouslyRebuildsSnapshotAndResetsActiveRow() throws {
        let registry = ToolRegistry.default
        let model = CommandPaletteSessionModel(registry: registry, actions: [])
        model.navigationState.moveActive(by: 8, in: model.snapshot.rows)
        #expect(model.navigationState.activeSelectableIndex(in: model.snapshot) == 8)

        let changed = model.setQuery("jwt")
        let expectedToolID = try #require(registry.matchingTools(query: "jwt").first?.id)

        #expect(changed)
        #expect(model.query == "jwt")
        #expect(model.navigationState.activeSelectableIndex(in: model.snapshot) == 0)
        #expect(model.navigationState.activeRow(in: model.snapshot)?.toolID == expectedToolID)
        #expect(!model.setQuery("jwt"))
    }

    @MainActor
    @Test func paletteSessionBeginsWithOneAtomicResetPublication() throws {
        let model = CommandPaletteSessionModel(registry: .default, actions: [], session: 1)
        #expect(model.setQuery("jwt"))
        model.navigationState.moveActive(by: 1, in: model.snapshot.rows)
        var publications = 0
        let cancellable = model.objectWillChange.sink { publications += 1 }

        model.beginSession(3, actions: [])

        #expect(publications == 1)
        #expect(model.session == 3)
        #expect(model.query.isEmpty)
        #expect(model.navigationState.activeSelectableIndex(in: model.snapshot) == 0)
        #expect(model.snapshot.rows.count > 1)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    @Test func paletteCloseSynchronouslyNotifiesItsInstalledLifecycle() {
        let presentation = CommandPalettePresentationModel()
        let lifecycle = RecordingPalettePresentationLifecycle()
        presentation.installLifecycle(lifecycle)
        presentation.open()

        #expect(lifecycle.openedSessions == [1])

        presentation.close()

        #expect(lifecycle.closedSessions == [1])
        #expect(!presentation.shows)
        #expect(presentation.session == 2)
    }

    // MARK: - clampedHighlight (keyboard navigation)

    @Test func highlightMovesWithinBounds() {
        #expect(CommandPaletteSearch.clampedHighlight(0, movingBy: 1, count: 5) == 1)
        #expect(CommandPaletteSearch.clampedHighlight(3, movingBy: -1, count: 5) == 2)
    }

    @Test func highlightClampsAtLowerBound() {
        #expect(CommandPaletteSearch.clampedHighlight(0, movingBy: -1, count: 5) == 0)
        #expect(CommandPaletteSearch.clampedHighlight(0, movingBy: -10, count: 5) == 0)
    }

    @Test func highlightClampsAtUpperBound() {
        #expect(CommandPaletteSearch.clampedHighlight(4, movingBy: 1, count: 5) == 4)
        #expect(CommandPaletteSearch.clampedHighlight(4, movingBy: 10, count: 5) == 4)
    }

    @Test func activeMovementReportsWhetherAKeyCanLeaveTheCurrentBoundary() {
        let rows = CommandPaletteNavigationState.rows(for: [
            Self.entry(.json, title: "JSON Formatter"),
            Self.entry(.jwt, title: "Token Inspector"),
            Self.entry(.regex, title: "Regex Tester")
        ])
        var state = CommandPaletteNavigationState()

        #expect(!state.canMoveActive(by: -1, in: rows))
        #expect(state.canMoveActive(by: 1, in: rows))

        state.moveActive(by: 2, in: rows)
        #expect(state.canMoveActive(by: -1, in: rows))
        #expect(!state.canMoveActive(by: 1, in: rows))

        #expect(!state.canMoveActive(by: 1, in: [.empty]))
        #expect(!state.canMoveActive(by: -1, in: [.empty]))
    }

    @Test func keyboardMovePolicyLongDownStopsAtLastSelectableRow() {
        let rows = Self.threeToolRows()
        var state = CommandPaletteNavigationState()

        for _ in 0..<5 {
            let decision = state.keyboardMoveDecision(
                by: 1,
                in: rows,
                visibleHandoffIndex: nil,
                isCurrentActiveVisible: true,
                hasPendingKeyboardRevealForCurrentActive: false,
                allowsVisibleHandoff: false
            )
            Self.apply(decision, to: &state, in: rows)
        }

        #expect(state.activeRowID(in: rows) == "tool.regex")
        #expect(state.keyboardMoveDecision(
            by: 1,
            in: rows,
            visibleHandoffIndex: nil,
            isCurrentActiveVisible: true,
            hasPendingKeyboardRevealForCurrentActive: false,
            allowsVisibleHandoff: false
        ) == .none)
    }

    @Test func keyboardMovePolicyLongUpStopsAtFirstSelectableRow() {
        let rows = Self.threeToolRows()
        var state = CommandPaletteNavigationState()
        state.setActiveSelectableIndex(2, in: rows)

        for _ in 0..<5 {
            let decision = state.keyboardMoveDecision(
                by: -1,
                in: rows,
                visibleHandoffIndex: nil,
                isCurrentActiveVisible: true,
                hasPendingKeyboardRevealForCurrentActive: false,
                allowsVisibleHandoff: false
            )
            Self.apply(decision, to: &state, in: rows)
        }

        #expect(state.activeRowID(in: rows) == "tool.json")
        #expect(state.keyboardMoveDecision(
            by: -1,
            in: rows,
            visibleHandoffIndex: nil,
            isCurrentActiveVisible: true,
            hasPendingKeyboardRevealForCurrentActive: false,
            allowsVisibleHandoff: false
        ) == .none)
    }

    @Test func blockedBoundaryKeyRevealsCurrentRowAndIgnoresOppositeVisibleHandoff() {
        let rows = Self.threeToolRows()
        var state = CommandPaletteNavigationState()
        state.setActiveSelectableIndex(2, in: rows)

        let downAtLast = state.keyboardMoveDecision(
            by: 1,
            in: rows,
            visibleHandoffIndex: 0,
            isCurrentActiveVisible: false,
            hasPendingKeyboardRevealForCurrentActive: false,
            allowsVisibleHandoff: true
        )

        state.setActiveSelectableIndex(0, in: rows)
        let upAtFirst = state.keyboardMoveDecision(
            by: -1,
            in: rows,
            visibleHandoffIndex: 2,
            isCurrentActiveVisible: false,
            hasPendingKeyboardRevealForCurrentActive: false,
            allowsVisibleHandoff: true
        )

        #expect(downAtLast == .revealCurrent)
        #expect(upAtFirst == .revealCurrent)
    }

    @Test func movableOffscreenActiveRowCanAlignToVisibleEdge() {
        let rows = Self.threeToolRows()
        var state = CommandPaletteNavigationState()

        let decision = state.keyboardMoveDecision(
            by: 1,
            in: rows,
            visibleHandoffIndex: 2,
            isCurrentActiveVisible: false,
            hasPendingKeyboardRevealForCurrentActive: false,
            allowsVisibleHandoff: true
        )
        Self.apply(decision, to: &state, in: rows)

        #expect(decision == .alignToVisibleSelectableIndex(2))
        #expect(state.activeRowID(in: rows) == "tool.regex")
    }

    @Test func visibleActiveRowMovesByDeltaInsteadOfUsingVisibleHandoff() {
        let rows = Self.threeToolRows()
        var state = CommandPaletteNavigationState()

        let decision = state.keyboardMoveDecision(
            by: 1,
            in: rows,
            visibleHandoffIndex: 2,
            isCurrentActiveVisible: true,
            hasPendingKeyboardRevealForCurrentActive: false,
            allowsVisibleHandoff: true
        )
        Self.apply(decision, to: &state, in: rows)

        #expect(decision == .move(toSelectableIndex: 1))
        #expect(state.activeRowID(in: rows) == "tool.jwt")
    }

    @Test func pendingKeyboardRevealSuppressesVisibleEdgeHandoffForSameActiveRow() {
        let rows = Self.threeToolRows()
        var state = CommandPaletteNavigationState()

        let decision = state.keyboardMoveDecision(
            by: 1,
            in: rows,
            visibleHandoffIndex: 2,
            isCurrentActiveVisible: false,
            hasPendingKeyboardRevealForCurrentActive: true,
            allowsVisibleHandoff: true
        )
        Self.apply(decision, to: &state, in: rows)

        #expect(decision == .move(toSelectableIndex: 1))
        #expect(state.activeRowID(in: rows) == "tool.jwt")
    }

    @Test func keyboardMovePolicyIsNoOpWhenOnlyDisplayRowsExist() {
        let decision = CommandPaletteNavigationState().keyboardMoveDecision(
            by: 1,
            in: [.empty],
            visibleHandoffIndex: 0,
            isCurrentActiveVisible: false,
            hasPendingKeyboardRevealForCurrentActive: false,
            allowsVisibleHandoff: true
        )

        #expect(decision == .none)
    }

    @Test func keyboardRepeatDoesNotTreatRevealLagAsManualVisibleHandoff() {
        let entries = ToolNavigationCommandProjection(registry: .default, query: "").entries
        let rows = CommandPaletteNavigationState.rows(for: entries)
        var state = CommandPaletteNavigationState()
        let hashIndex = entries.firstIndex { $0.title == "Hash 文本" }
        let encryptionIndex = entries.firstIndex { $0.title == "文本加密" }

        #expect(hashIndex != nil)
        #expect(encryptionIndex == hashIndex.map { $0 + 1 })

        state.setActiveSelectableIndex(hashIndex ?? 0, in: rows)
        let decision = state.keyboardMoveDecision(
            by: 1,
            in: rows,
            visibleHandoffIndex: 0,
            isCurrentActiveVisible: false,
            hasPendingKeyboardRevealForCurrentActive: false,
            allowsVisibleHandoff: false
        )
        Self.apply(decision, to: &state, in: rows)

        #expect(decision == .move(toSelectableIndex: encryptionIndex ?? -1))
        #expect(state.activeRowID(in: rows) == "tool.text-encryption")
    }

    @Test func manualScrollEvidenceStillAllowsVisibleEdgeHandoff() {
        let rows = Self.threeToolRows()
        var state = CommandPaletteNavigationState()

        let decision = state.keyboardMoveDecision(
            by: 1,
            in: rows,
            visibleHandoffIndex: 2,
            isCurrentActiveVisible: false,
            hasPendingKeyboardRevealForCurrentActive: false,
            allowsVisibleHandoff: true
        )
        Self.apply(decision, to: &state, in: rows)

        #expect(decision == .alignToVisibleSelectableIndex(2))
        #expect(state.activeRowID(in: rows) == "tool.regex")
    }

    @Test func highlightIsNoOpWhenNothingSelectable() {
        // With no selectable rows the index is returned unchanged, so the
        // caller's assignment can't push it to a bogus value.
        #expect(CommandPaletteSearch.clampedHighlight(0, movingBy: 1, count: 0) == 0)
        #expect(CommandPaletteSearch.clampedHighlight(7, movingBy: -3, count: 0) == 7)
    }

    // MARK: - Submit / activation

    @Test func activationClampsHighlightIntoBounds() {
        #expect(CommandPaletteSearch.activationIndex(highlight: 3, count: 5) == 3)
        // A highlight left past the end of a shrunken result set activates the
        // last row, never an out-of-range index.
        #expect(CommandPaletteSearch.activationIndex(highlight: 9, count: 5) == 4)
        #expect(CommandPaletteSearch.activationIndex(highlight: -2, count: 5) == 0)
    }

    @Test func activationIsNoOpWhenNothingSelectable() {
        // No selectable rows -> nil so the caller treats submit as a no-op
        // (the palette must not activate a tool when the list is empty).
        #expect(CommandPaletteSearch.activationIndex(highlight: 0, count: 0) == nil)
        #expect(CommandPaletteSearch.activationIndex(highlight: 4, count: 0) == nil)
    }

    // MARK: - row projection and active-row state

    @Test func rowProjectionKeepsSectionTitlesAndEmptyRowsOutOfSelection() {
        let rows = CommandPaletteNavigationState.rows(for: [
            Self.entry(.json, title: "JSON Formatter"),
            Self.entry(.jwt, title: "Token Inspector")
        ])
        let emptyRows = CommandPaletteNavigationState.rows(for: [])
        let state = CommandPaletteNavigationState()

        #expect(rows.map(\.id) == ["title.工具", "tool.json", "tool.jwt"])
        #expect(rows.map(\.isSelectable) == [false, true, true])
        #expect(state.activeSelectableIndex(in: rows) == 0)
        #expect(state.activeRowID(in: rows) == "tool.json")

        #expect(emptyRows == [.empty])
        #expect(state.activeSelectableIndex(in: emptyRows) == nil)
        #expect(state.activeRowID(in: emptyRows) == nil)
        #expect(state.activeToolID(in: emptyRows) == nil)
    }

    @Test func rowSnapshotPrecomputesSelectionWithoutChangingDisplayOrder() {
        let action = CommandActionEntry(
            id: .openPreferences,
            title: "打开设置",
            subtitle: nil,
            systemImage: "gearshape"
        )
        let snapshot = CommandPaletteNavigationState.snapshot(
            for: [
                Self.entry(.json, title: "JSON Formatter"),
                Self.entry(.jwt, title: "Token Inspector")
            ],
            actions: [action]
        )

        #expect(snapshot.rows.map(\.id) == [
            "title.动作",
            "command.\(CommandActionID.openPreferences.rawValue)",
            "title.工具",
            "tool.json",
            "tool.jwt"
        ])
        #expect(snapshot.selectableCount == 3)
        #expect(snapshot.selectableIndex(of: snapshot.rows[0]) == nil)
        #expect(snapshot.selectableIndex(of: snapshot.rows[1]) == 0)
        #expect(snapshot.selectableIndex(of: snapshot.rows[3]) == 1)
        #expect(snapshot.selectableIndex(of: snapshot.rows[4]) == 2)
    }

    @Test func activeRowMovementResetAndPointerMoveUseTheSameSelectableRows() {
        let rows = CommandPaletteNavigationState.rows(for: [
            Self.entry(.json, title: "JSON Formatter"),
            Self.entry(.jwt, title: "Token Inspector"),
            Self.entry(.regex, title: "Regex Tester")
        ])
        var state = CommandPaletteNavigationState()

        state.moveActive(by: 2, in: rows)
        #expect(state.activeRowID(in: rows) == "tool.regex")

        state.resetActiveRow()
        #expect(state.activeRowID(in: rows) == "tool.json")

        state.setActiveRow(rows[2], in: rows)
        #expect(state.activeRowID(in: rows) == "tool.jwt")

        state.setActiveRow(rows[0], in: rows)
        #expect(state.activeRowID(in: rows) == "tool.jwt")
    }

    @Test func activeRowCanAlignToVisibleSelectableIndexAfterManualScroll() {
        let rows = CommandPaletteNavigationState.rows(for: [
            Self.entry(.json, title: "JSON Formatter"),
            Self.entry(.jwt, title: "Token Inspector"),
            Self.entry(.regex, title: "Regex Tester")
        ])
        var state = CommandPaletteNavigationState()

        #expect(state.selectableIndex(of: rows[1], in: rows) == 0)
        #expect(state.selectableIndex(of: rows[2], in: rows) == 1)
        #expect(state.selectableIndex(of: rows[0], in: rows) == nil)

        state.setActiveSelectableIndex(2, in: rows)
        #expect(state.activeRowID(in: rows) == "tool.regex")

        state.setActiveSelectableIndex(100, in: rows)
        #expect(state.activeRowID(in: rows) == "tool.regex")

        state.setActiveSelectableIndex(-10, in: rows)
        #expect(state.activeRowID(in: rows) == "tool.json")

        state.setActiveSelectableIndex(2, in: [.empty])
        #expect(state.activeRowID(in: rows) == "tool.json")
    }

    @Test func activeToolActivationAndClickLookupShareToolOnlyRules() {
        let rows = CommandPaletteNavigationState.rows(for: [
            Self.entry(.json, title: "JSON Formatter"),
            Self.entry(.jwt, title: "Token Inspector")
        ])
        var state = CommandPaletteNavigationState()

        #expect(state.activeToolID(in: rows) == .json)

        state.setActiveRow(rows[2], in: rows)
        #expect(state.activeToolID(in: rows) == .jwt)
        #expect(state.toolID(for: rows[2]) == .jwt)
        #expect(state.toolID(for: rows[0]) == nil)
        #expect(state.toolID(for: .empty) == nil)
    }

    @Test func activeChangeRevealPolicyIsEventDrivenAndPointerSafe() {
        #expect(CommandPaletteActiveChangeSource.keyboard(delta: 1).revealAnchor == .keyboardEdge(delta: 1))
        #expect(CommandPaletteActiveChangeSource.keyboard(delta: -1).revealAnchor == .keyboardEdge(delta: -1))
        #expect(CommandPaletteActiveChangeSource.queryReset.revealAnchor == .top)
        #expect(CommandPaletteActiveChangeSource.openReset.revealAnchor == .top)
        #expect(CommandPaletteActiveChangeSource.pointerMove.revealAnchor == nil)
        #expect(CommandPaletteActiveChangeSource.directActivation.revealAnchor == nil)
    }

    @Test func pointerMovementRequiresRealWindowCoordinateChange() {
        var movement = CommandPalettePointerMovementState()

        movement.reset(to: CGPoint(x: 120, y: 220))

        let stationaryAtBaseline = movement.acceptsMouseMoved(at: CGPoint(x: 120, y: 220))
        let movedRight = movement.acceptsMouseMoved(at: CGPoint(x: 121, y: 220))
        let stationaryAfterMove = movement.acceptsMouseMoved(at: CGPoint(x: 121, y: 220))
        let movedUp = movement.acceptsMouseMoved(at: CGPoint(x: 121, y: 219))

        #expect(!stationaryAtBaseline)
        #expect(movedRight)
        #expect(!stationaryAfterMove)
        #expect(movedUp)
    }

    @Test func pointerMovementTreatsUnseededFirstEventAsBaselineOnly() {
        var movement = CommandPalettePointerMovementState()

        let firstEvent = movement.acceptsMouseMoved(at: CGPoint(x: 10, y: 10))
        let repeatedEvent = movement.acceptsMouseMoved(at: CGPoint(x: 10, y: 10))
        let movedEvent = movement.acceptsMouseMoved(at: CGPoint(x: 10, y: 11))

        #expect(!firstEvent)
        #expect(!repeatedEvent)
        #expect(movedEvent)
    }

    @MainActor
    @Test func pointerMovementTrackerSharesWindowCoordinatesAcrossRows() {
        let tracker = CommandPalettePointerMovementTracker()

        tracker.reset(to: CGPoint(x: 120, y: 220))

        #expect(tracker.acceptsMouseMoved(at: CGPoint(x: 121, y: 220)))
        #expect(!tracker.acceptsMouseMoved(at: CGPoint(x: 121, y: 220)))

        tracker.reset(to: CGPoint(x: 130, y: 220))

        #expect(!tracker.acceptsMouseMoved(at: CGPoint(x: 130, y: 220)))
        #expect(tracker.acceptsMouseMoved(at: CGPoint(x: 131, y: 220)))
    }

    private static func threeToolRows() -> [CommandPaletteRowProjection] {
        CommandPaletteNavigationState.rows(for: [
            entry(.json, title: "JSON Formatter"),
            entry(.jwt, title: "Token Inspector"),
            entry(.regex, title: "Regex Tester")
        ])
    }

    private static func apply(
        _ decision: CommandPaletteKeyboardMoveDecision,
        to state: inout CommandPaletteNavigationState,
        in rows: [CommandPaletteRowProjection]
    ) {
        switch decision {
        case .move(let index), .alignToVisibleSelectableIndex(let index):
            state.setActiveSelectableIndex(index, in: rows)
        case .revealCurrent, .none:
            break
        }
    }


    // MARK: - Command system rows (v3)

    @Test func rowsInterleaveCommandActionsBeforeTools() {
        let toolEntry = Self.entry(.json, title: "JSON 格式化")
        let action = CommandActionEntry(
            id: .openPreferences,
            title: "打开设置",
            subtitle: "外观与启动行为",
            systemImage: "gearshape"
        )

        let both = CommandPaletteNavigationState.rows(for: [toolEntry], actions: [action])
        #expect(both.count == 4)
        #expect(both[0] == .sectionTitle("动作"))
        #expect(both[1] == .command(action))
        #expect(both[2] == .sectionTitle("工具"))
        #expect(both[3] == .tool(toolEntry))
        #expect(both[1].commandID == .openPreferences)
        #expect(both[1].isSelectable)

        let toolOnly = CommandPaletteNavigationState.rows(for: [toolEntry])
        #expect(toolOnly == [.sectionTitle("工具"), .tool(toolEntry)])

        let empty = CommandPaletteNavigationState.rows(for: [])
        #expect(empty == [.empty])
    }

    @Test func commandActionMatchingUsesTitleAndKeywords() {
        let action = CommandActionEntry(
            id: .copyGeneratedUUID,
            title: "生成并复制 UUID",
            subtitle: nil,
            systemImage: "barcode",
            keywords: ["uuid", "复制", "生成"]
        )

        #expect(action.matches(query: ""))
        #expect(action.matches(query: "uuid"))
        #expect(action.matches(query: "复制"))
        #expect(!action.matches(query: "jwt"))
    }

    @Test func sessionCommandActionsRecreateConsumedUUIDPreview() throws {
        let baseAction = CommandActionEntry(
            id: .openPreferences,
            title: "打开设置",
            subtitle: nil,
            systemImage: "gearshape"
        )
        let stalePreview = CommandActionEntry.paletteActions(
            baseActions: [baseAction],
            previewValue: "first"
        )
        let consumed = CommandActionEntry.paletteActions(
            baseActions: stalePreview,
            previewValue: nil
        )
        let reopened = CommandActionEntry.paletteActions(
            baseActions: consumed,
            previewValue: "second"
        )

        #expect(consumed == [baseAction])
        #expect(reopened.filter { $0.id == .copyGeneratedUUID }.count == 1)
        #expect(
            try #require(reopened.first { $0.id == .copyGeneratedUUID }).subtitle
                == "second"
        )
    }

    @MainActor
    @Test func commandPalettePresentationRefreshesPreviewPayloadOncePerSession() {
        let viewModel = RootViewModel()

        viewModel.openCommandPalette()
        let first = viewModel.commandPalettePreviewValue
        #expect(first != nil)

        viewModel.focusCommandPalette()
        #expect(viewModel.commandPalettePreviewValue == first)

        viewModel.closeCommandPalette()
        viewModel.openCommandPalette()
        #expect(viewModel.commandPalettePreviewValue != nil)
        #expect(viewModel.commandPalettePreviewValue != first)
    }

    private static func entry(_ id: ToolID, title: String) -> ToolNavigationCommandEntry {
        ToolNavigationCommandEntry(
            toolID: id,
            title: title,
            categoryTitle: "Development",
            systemImage: "gear"
        )
    }
}

@MainActor
private final class RecordingPalettePresentationLifecycle: CommandPalettePresentationLifecycle {
    private(set) var openedSessions: [Int] = []
    private(set) var closedSessions: [Int] = []

    func commandPaletteDidOpen(session: Int, previewValue: String?) {
        openedSessions.append(session)
    }

    func commandPaletteDidClose(session: Int) {
        closedSessions.append(session)
    }
}

private extension ToolID {
    static let json = ToolID(rawValue: "json")
    static let jwt = ToolID(rawValue: "jwt")
    static let regex = ToolID(rawValue: "regex")
}
