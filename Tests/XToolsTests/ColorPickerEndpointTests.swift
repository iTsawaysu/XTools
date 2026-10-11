@testable import XTools
@testable import XToolsCore
import Testing

struct ColorPickerEndpointTests {
    @Test func sliderLabelsRoundToTheirWholeUnitStep() {
        #expect(colorSliderValueText(99.99999999999996, suffix: "%") == "100%")
        #expect(colorSliderValueText(232.6717557251908, suffix: "°") == "233°")
        #expect(colorSliderValueText(0, suffix: "%") == "0%")
        #expect(colorSliderValueText(35, suffix: "%") == "35%")
    }

    @Test func endpointAndAlphaEditsPreserveAxesBeforeReturningToBlue() throws {
        for endpoint in [0.0, 100.0] {
            var state = CSSColorWorkspaceState(defaultInput: "#0000FF")
            CSSColorWorkspaceReducer.reduce(state: &state, action: .hslChanged(hue: 240, saturation: 100, lightness: endpoint))
            #expect(state.hsl == SIMD3(240, 100, endpoint))
            #expect(state.draft == "hsl(240 100% \(Int(endpoint))%)")
            var withoutAlphaEdit = state
            CSSColorWorkspaceReducer.reduce(state: &withoutAlphaEdit, action: .hslChanged(
                hue: withoutAlphaEdit.hsl.x, saturation: withoutAlphaEdit.hsl.y, lightness: 50
            ))
            let directRGB = try #require(withoutAlphaEdit.lastValidColor).components(in: .sRGB)
            #expect(abs(directRGB.x) < 1e-12 && abs(directRGB.y) < 1e-12 && abs(directRGB.z - 1) < 1e-12)
            let xyz = try #require(state.lastValidColor).xyzD65
            CSSColorWorkspaceReducer.reduce(state: &state, action: .alphaChanged(0.35))
            #expect(state.lastValidColor?.xyzD65 == xyz)
            #expect(state.hsl == SIMD3(240, 100, endpoint))
            #expect(state.draft == "hsl(240 100% \(Int(endpoint))% / 0.35)")
            CSSColorWorkspaceReducer.reduce(state: &state, action: .hslChanged(hue: state.hsl.x, saturation: state.hsl.y, lightness: 50))
            let rgb = try #require(state.lastValidColor).components(in: .sRGB)
            #expect(abs(rgb.x) < 1e-12 && abs(rgb.y) < 1e-12 && abs(rgb.z - 1) < 1e-12)
            #expect(state.draft == "hsl(240 100% 50% / 0.35)")
        }
    }

    @Test func canonicalNeutralRoundTripsHaveNoFalseChroma() throws {
        for neutral in [0.0, 0.25, 0.5, 1.0] {
            let color = try CSSColor(components: SIMD3(repeating: neutral), space: .sRGB, alpha: 1)
            let mapped = CSSColorGamutMapping.sRGB(for: color)
            let hsl = CSSColorMath.hslFromSRGB(mapped.components)
            #expect(hsl.x == 0 && hsl.y == 0)
            #expect(abs(hsl.z - neutral * 100) < 1e-12)
        }
        // Real but very faint colors must survive the numerical-noise boundary.
        for delta in [1e-10, 1e-13] {
            let hsl = CSSColorMath.hslFromSRGB(SIMD3(0.5 + delta, 0.5, 0.5))
            #expect(hsl.x == 0 && hsl.y > 0)
        }
    }
}
