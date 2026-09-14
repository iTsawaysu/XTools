import XToolsCore
import Testing

struct CSSColorFormatterTests {
    private func distance(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        let delta = lhs - rhs
        return (delta.x * delta.x + delta.y * delta.y + delta.z * delta.z).squareRoot()
    }

    @Test func exposesStableCommonPerceptualAndExtendedGroups() throws {
        let color = try CSSColor(components: SIMD3(0.2, 0.4, 0.6), space: .displayP3, alpha: 0.75)
        let values = CSSColorFormatter.values(for: color)
        #expect(values.filter { $0.group == .common }.count == 4)
        #expect(values.filter { $0.group == .perceptual }.count == 4)
        #expect(values.filter { $0.group == .extended }.count == 9)
        #expect(Set(values.map(\.id)).count == values.count)
        #expect(values.first?.id == "hex")
        #expect(values.last?.id == "color-xyz-d65")
    }

    @Test func hexUsesEightBitAlphaWhilePreciseFormatsRetainAlpha() throws {
        let color = try CSSColor(components: SIMD3(1, 0, 0), space: .sRGB, alpha: 0.5)
        let values = CSSColorFormatter.values(for: color)
        #expect(values.first { $0.id == "hex" }?.text == "#FF000080")
        #expect(values.first { $0.id == "rgb" }?.text == "rgb(255 0 0 / 0.5)")
        #expect(values.first { $0.id == "oklab" }?.text.hasSuffix(" / 0.5)") == true)
    }

    @Test func formatterNeverEmitsNonFiniteOrNegativeZeroText() throws {
        let color = try CSSColor(xyzD65: SIMD3(-0.4, 0.2, 1.8), alpha: 0.333333)
        for value in CSSColorFormatter.values(for: color) {
            #expect(!value.text.lowercased().contains("nan"))
            #expect(!value.text.lowercased().contains("inf"))
            #expect(!value.text.contains("-0 "))
            #expect(!value.text.contains("-0)"))
        }
    }

    @Test func preciseFormatsRoundTripWithinColorTolerance() throws {
        let samples = [
            try CSSColor(components: SIMD3(0.12, 0.78, 0.33), space: .displayP3, alpha: 0.42),
            try CSSColor(components: SIMD3(58, 32, 244), space: .lch, alpha: 1),
            try CSSColor(components: SIMD3(0.63, 0.18, 315), space: .oklch, alpha: 0.125)
        ]
        for sample in samples {
            for value in CSSColorFormatter.values(for: sample) where value.group != .common {
                let parsed = try CSSColorParser.parse(value.text).color
                #expect(distance(parsed.xyzD65, sample.xyzD65) <= 1e-5)
                #expect(abs(parsed.alpha - sample.alpha) <= 1e-5)
            }
        }
    }

    @Test func outOfSRGBMarksOnlyLegacyDisplayFormatsAsMapped() throws {
        let color = try CSSColor(components: SIMD3(0, 1, 0), space: .displayP3, alpha: 1)
        let values = CSSColorFormatter.values(for: color)
        #expect(values.filter { $0.group == .common }.allSatisfy { $0.mappingStatus == .mappedToSRGB })
        #expect(values.filter { $0.group != .common }.allSatisfy { $0.mappingStatus == .original })
    }
}
