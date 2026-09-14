import XToolsCore
import Testing

struct CSSColorParserTests {
    private func distance(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        let delta = lhs - rhs
        return (delta.x * delta.x + delta.y * delta.y + delta.z * delta.z).squareRoot()
    }

    private func expectParse(_ input: String, family: CSSColorSyntaxFamily? = nil) throws -> CSSParsedColor {
        let parsed = try CSSColorParser.parse(input)
        if let family {
            #expect(parsed.family == family)
        }
        #expect(parsed.color.alpha.isFinite)
        return parsed
    }

    @Test func parsesAllHexLengthsAndAlpha() throws {
        let rgb = try expectParse("#abc", family: .hex)
        #expect(distance(rgb.color.components(in: .sRGB), SIMD3(0.6666666667, 0.7333333333, 0.8)) < 1e-9)
        let rgba = try expectParse("#abcd", family: .hex)
        #expect(abs(rgba.color.alpha - 0.8666666667) < 1e-9)
        _ = try expectParse("#11223344", family: .hex)
    }

    @Test func parsesModernAndLegacyRGBWithoutMixingGrammars() throws {
        let modern = try expectParse("rgb(100% 0 0 / 50%)", family: .rgb)
        #expect(abs(modern.color.alpha - 0.5) < 1e-9)
        let legacy = try expectParse("rgba(255, 0, 0, .25)", family: .rgb)
        #expect(abs(legacy.color.alpha - 0.25) < 1e-9)
        #expect(throws: CSSColorParseError.self) { try CSSColorParser.parse("rgb(1, 0 0)") }
        #expect(throws: CSSColorParseError.self) { try CSSColorParser.parse("rgb(1 0, 0)") }
        #expect(throws: CSSColorParseError.self) { try CSSColorParser.parse("rgba(0, 0, 0, none)") }
        #expect(throws: CSSColorParseError.self) { try CSSColorParser.parse("rgb(1. 0 0)") }
    }

    @Test func parsesHSLHWBAnglesAndNone() throws {
        let hsl = try expectParse("hsl(-120deg 100% 50% / 25%)", family: .hsl)
        #expect(abs(hsl.color.components(in: .sRGB).z - 1) < 1e-9)
        #expect(abs(hsl.color.alpha - 0.25) < 1e-9)
        let hwb = try expectParse("hwb(0.5turn 20% 10% / none)", family: .hwb)
        #expect(hwb.color.alpha == 0)
        _ = try expectParse("hsl(none none none)", family: .hsl)
    }

    @Test func parsesLabLCHOKLabAndOKLCH() throws {
        _ = try expectParse("lab(60% 20 -30 / .7)", family: .lab)
        _ = try expectParse("lch(60 40 120deg)", family: .lch)
        _ = try expectParse("oklab(60% 0.1 -0.05)", family: .oklab)
        _ = try expectParse("oklch(60% 20% 120)", family: .oklch)
    }

    @Test func parsesEveryRequestedColorProfile() throws {
        for profile in ["srgb", "srgb-linear", "display-p3", "display-p3-linear", "a98-rgb", "prophoto-rgb", "rec2020", "xyz", "xyz-d50", "xyz-d65"] {
            _ = try expectParse("color(\(profile) 0.2 40% none / 80%)", family: .color)
        }
        #expect(throws: CSSColorParseError.self) { try CSSColorParser.parse("color(srgb+0 0 0)") }
        #expect(throws: CSSColorParseError.self) { try CSSColorParser.parse("rgb (0 0 0)") }
    }

    @Test func parsesNamedColorsAndTransparent() throws {
        #expect(CSSNamedColors.count == 148)
        let grey = try expectParse("GREY", family: .named)
        let gray = try expectParse("gray", family: .named)
        #expect(grey.color == gray.color)
        let transparent = try expectParse("transparent", family: .named)
        #expect(transparent.color.alpha == 0)
        #expect(transparent.color.xyzD65 == .zero)
    }

    @Test func rejectsContextDependentAndUnsupportedValues() {
        for input in ["currentColor", "CanvasText", "var(--color)", "calc(1 + 2)", "rgb(calc(20%) 0 0)", "rgb(from red r g b)", "color(--brand 1 0 0)", "color-mix(in srgb, red, blue)", "device-cmyk(0 0 0 0)", "system-color"] {
            let result = CSSColorParser.classify(input)
            #expect(result.status == .invalid)
            #expect(result.diagnostic?.message.isEmpty == false)
        }
    }

    @Test func clampsStandaloneComponentsAndRejectsLegacyNone() throws {
        let rgb = try expectParse("rgb(300 -20 10 / 140%)")
        let components = rgb.color.components(in: .sRGB)
        #expect(distance(components, SIMD3(1, 0, 10.0 / 255)) < 1e-8)
        #expect(rgb.color.alpha == 1)

        let hwb = try expectParse("hwb(0 80% 80%)")
        #expect(distance(hwb.color.components(in: .sRGB), SIMD3(repeating: 0.5)) < 1e-8)
        #expect(throws: CSSColorParseError.self) { try CSSColorParser.parse("rgb(none, 0, 0)") }
        #expect(throws: CSSColorParseError.self) { try CSSColorParser.parse("hsla(0, 0%, 0%, none)") }
        #expect(throws: CSSColorParseError.self) { try CSSColorParser.parse("rgb(0 0 0) trailing") }
    }

    @Test func distinguishesEmptyIncompleteValidAndInvalidDrafts() {
        #expect(CSSColorParser.classify("   ").status == .empty)
        #expect(CSSColorParser.classify("rgb(1 2").status == .incomplete)
        #expect(CSSColorParser.classify("#12").status == .incomplete)
        #expect(CSSColorParser.classify("#123456").status == .valid)
        #expect(CSSColorParser.classify("#gggggg").status == .invalid)
    }

    @Test func formatterRoundTripsPreciseAndAlphaValues() throws {
        let parsed = try expectParse("color(display-p3 1 0.2 0.1 / 0.42)")
        for value in CSSColorFormatter.values(for: parsed.color) where value.mappingStatus == .original {
            let reparsed = try CSSColorParser.parse(value.text)
            #expect(abs(reparsed.color.alpha - parsed.color.alpha) < 1e-5)
            #expect(distance(reparsed.color.xyzD65, parsed.color.xyzD65) < 1e-4)
        }
    }
}
