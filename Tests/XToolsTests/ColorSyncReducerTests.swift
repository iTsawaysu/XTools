import XToolsCore
import Testing

struct ColorSyncReducerTests {
    private func distance(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        let delta = lhs - rhs
        return (delta.x * delta.x + delta.y * delta.y + delta.z * delta.z).squareRoot()
    }

    @Test func validInvalidAndRecoveryPreserveLastValidColor() {
        var state = CSSColorWorkspaceState(defaultInput: "#FF0000")
        let red = state.lastValidColor

        CSSColorWorkspaceReducer.reduce(state: &state, action: .draftChanged("rgb(1 2"))
        #expect(state.draftStatus == .incomplete)
        #expect(state.isUsingLastValidResult)
        #expect(state.lastValidColor == red)
        #expect(!state.formattedValues.isEmpty)

        CSSColorWorkspaceReducer.reduce(state: &state, action: .draftChanged("not-a-color"))
        #expect(state.draftStatus == .invalid)
        #expect(state.lastValidColor == red)

        CSSColorWorkspaceReducer.reduce(state: &state, action: .draftChanged("oklch(0.7 0.2 40)"))
        #expect(state.draftStatus == .valid)
        #expect(!state.isUsingLastValidResult)
        #expect(state.sourceFamily == .oklch)
    }

    @Test func emptyDraftHidesResultsWithoutDestroyingRecoveryColor() {
        var state = CSSColorWorkspaceState(defaultInput: "#336699")
        let retained = state.lastValidColor
        CSSColorWorkspaceReducer.reduce(state: &state, action: .draftChanged(""))
        #expect(state.draftStatus == .empty)
        #expect(state.visibleColor == nil)
        #expect(state.formattedValues.isEmpty)
        #expect(state.lastValidColor == retained)
    }

    @Test func alphaEditPreservesWideGamutCanonicalColorAndFamily() {
        var state = CSSColorWorkspaceState(defaultInput: "color(display-p3 1 0 0)")
        let xyz = state.lastValidColor?.xyzD65
        CSSColorWorkspaceReducer.reduce(state: &state, action: .alphaChanged(0.35))
        #expect(state.lastValidColor?.xyzD65 == xyz)
        #expect(state.lastValidColor?.alpha == 0.35)
        #expect(state.sourceFamily == .color)
        #expect(state.draft.hasPrefix("color(display-p3 "))
        #expect(state.draft.hasSuffix(" / 0.35)"))
    }

    @Test func hslEditIntentionallyStartsFromSRGBAndWritesHSL() {
        var state = CSSColorWorkspaceState(defaultInput: "color(display-p3 0 1 0)")
        CSSColorWorkspaceReducer.reduce(
            state: &state,
            action: .hslChanged(hue: 240, saturation: 100, lightness: 50)
        )
        #expect(state.sourceFamily == .hsl)
        #expect(state.draft.hasPrefix("hsl(240 100% 50%"))
        #expect(state.lastValidColor.map { distance($0.components(in: .sRGB), SIMD3(0, 0, 1)) } ?? 1 < 1e-8)
    }

    @Test func systemPickerWritesSRGBAndKeepsOpacity() {
        var state = CSSColorWorkspaceState()
        CSSColorWorkspaceReducer.reduce(
            state: &state,
            action: .systemColorPicked(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        )
        #expect(state.sourceFamily == .rgb)
        #expect(state.lastValidColor?.alpha == 0.4)
        #expect(state.draft.hasPrefix("rgb("))
    }

    @Test func controlsRecoverFromInvalidDraft() {
        var state = CSSColorWorkspaceState(defaultInput: "#123456")
        CSSColorWorkspaceReducer.reduce(state: &state, action: .draftChanged("broken"))
        CSSColorWorkspaceReducer.reduce(state: &state, action: .alphaChanged(0.5))
        #expect(state.draftStatus == .valid)
        #expect(state.diagnostic == nil)
        #expect(state.draft == "#12345680")
    }
}
