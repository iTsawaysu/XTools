import XToolsCore
import Testing

struct CSSColorReferenceVectorTests {
    private func expectClose(_ actual: Double, _ expected: Double, _ tolerance: Double = 1e-6) {
        #expect(abs(actual - expected) <= tolerance)
    }

    private func expectClose(_ actual: SIMD3<Double>, _ expected: SIMD3<Double>, _ tolerance: Double = 1e-6) {
        expectClose(actual.x, expected.x, tolerance)
        expectClose(actual.y, expected.y, tolerance)
        expectClose(actual.z, expected.z, tolerance)
    }

    @Test func sRGBReferenceRedUsesCSSColor4Matrix() throws {
        let red = try CSSColor(components: SIMD3(1, 0, 0), space: .sRGB, alpha: 1)
        expectClose(red.xyzD65, SIMD3(0.4123907992659595, 0.2126390058715104, 0.01933081871559185))
        expectClose(red.components(in: .sRGB), SIMD3(1, 0, 0))
    }

    @Test func displayP3ReferenceRedAndRoundTripStayWideGamut() throws {
        let red = try CSSColor(components: SIMD3(1, 0, 0), space: .displayP3, alpha: 0.8)
        expectClose(red.xyzD65, SIMD3(0.4865709486482162, 0.2289745640697488, 0), 2e-6)
        expectClose(red.components(in: .displayP3), SIMD3(1, 0, 0), 2e-6)
        #expect(red.alpha == 0.8)
        #expect(red.components(in: .sRGB).x > 1 || red.components(in: .sRGB).y < 0 || red.components(in: .sRGB).z < 0)
    }

    @Test func d50BradfordRoundTripIsStable() throws {
        let source = SIMD3(0.23, 0.41, 0.17)
        let color = try CSSColor(components: source, space: .xyzD50, alpha: 1)
        expectClose(color.components(in: .xyzD50), source, 2e-6)
        let d65 = color.components(in: .xyzD65)
        #expect(d65.x.isFinite && d65.y.isFinite && d65.z.isFinite)
    }

    @Test func everyPredefinedSpaceRoundTripsThroughCanonicalXYZ() throws {
        let source = SIMD3(0.23, 0.47, 0.61)
        let spaces: [CSSColorSpace] = [
            .sRGB, .sRGBLinear, .displayP3, .displayP3Linear, .a98RGB,
            .proPhotoRGB, .rec2020, .xyzD50, .xyzD65
        ]
        for space in spaces {
            let color = try CSSColor(components: source, space: space, alpha: 0.6)
            expectClose(color.components(in: space), source, 3e-6)
            #expect(color.alpha == 0.6)
        }
    }

    @Test func rec2020MidGrayUsesBT2020PiecewiseTransfer() throws {
        let gray = try CSSColor(components: SIMD3(repeating: 0.5), space: .rec2020, alpha: 1)
        expectClose(
            gray.xyzD65,
            SIMD3(0.246851878363338, 0.259719437101178, 0.282849465998030),
            1e-12
        )
        expectClose(gray.components(in: .rec2020), SIMD3(repeating: 0.5), 1e-12)
    }

    @Test func labAndOKLabReferenceValuesArePreserved() throws {
        let lab = try CSSColor(components: SIMD3(50, 0, 0), space: .lab, alpha: 1)
        let labBack = lab.components(in: .lab)
        expectClose(labBack, SIMD3(50, 0, 0), 2e-5)

        let red = try CSSColor(components: SIMD3(1, 0, 0), space: .sRGB, alpha: 1)
        let oklab = red.components(in: .oklab)
        expectClose(oklab, SIMD3(0.6279553606145516, 0.22486306106597398, 0.1258462985307351), 2e-5)
        expectClose(red.components(in: .oklab), oklab, 2e-5)
    }

    @Test func rayTraceMappingKeepsInGamutColorsAndAvoidsChannelClamp() throws {
        let p3Green = try CSSColor(components: SIMD3(0, 1, 0), space: .displayP3, alpha: 1)
        let mapped = CSSColorGamutMapping.sRGB(for: p3Green)
        #expect(mapped.wasMapped)
        #expect(mapped.components.x >= -1e-9 && mapped.components.x <= 1 + 1e-9)
        #expect(mapped.components.y >= -1e-9 && mapped.components.y <= 1 + 1e-9)
        #expect(mapped.components.z >= -1e-9 && mapped.components.z <= 1 + 1e-9)
        #expect(mapped.components != SIMD3(0, 1, 0))

        let sRGBBlue = try CSSColor(components: SIMD3(0, 0, 1), space: .sRGB, alpha: 1)
        let identity = CSSColorGamutMapping.sRGB(for: sRGBBlue)
        #expect(!identity.wasMapped)
        expectClose(identity.components, SIMD3(0, 0, 1), 1e-9)
    }
}
