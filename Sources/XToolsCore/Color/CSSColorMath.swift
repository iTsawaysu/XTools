import Foundation

/// Color spaces understood by the CSS color converter. The canonical value is
/// always XYZ D65; the other cases describe a boundary representation only.
public enum CSSColorSpace: String, CaseIterable, Equatable, Sendable {
    case sRGB = "srgb"
    case sRGBLinear = "srgb-linear"
    case displayP3 = "display-p3"
    case displayP3Linear = "display-p3-linear"
    case a98RGB = "a98-rgb"
    case proPhotoRGB = "prophoto-rgb"
    case rec2020 = "rec2020"
    case xyzD50 = "xyz-d50"
    case xyzD65 = "xyz-d65"
    case lab
    case lch
    case oklab
    case oklch
    case hsl
    case hwb
}

public struct CSSColor: Equatable, Sendable {
    public let xyzD65: SIMD3<Double>
    public let alpha: Double

    public init(xyzD65: SIMD3<Double>, alpha: Double) throws {
        guard xyzD65.allSatisfy(\.isFinite), alpha.isFinite else {
            throw CSSColorMathError.nonFiniteComponent
        }
        self.xyzD65 = xyzD65
        self.alpha = min(max(alpha, 0), 1)
    }

    public init(components: SIMD3<Double>, space: CSSColorSpace, alpha: Double) throws {
        guard components.allSatisfy(\.isFinite), alpha.isFinite else {
            throw CSSColorMathError.nonFiniteComponent
        }
        let xyz: SIMD3<Double>
        switch space {
        case .sRGB:
            xyz = CSSColorMath.linearSRGBToXYZ(CSSColorMath.linearizeSRGB(components))
        case .sRGBLinear:
            xyz = CSSColorMath.linearSRGBToXYZ(components)
        case .displayP3:
            xyz = CSSColorMath.linearP3ToXYZ(CSSColorMath.linearizeSRGB(components))
        case .displayP3Linear:
            xyz = CSSColorMath.linearP3ToXYZ(components)
        case .a98RGB:
            xyz = CSSColorMath.linearA98ToXYZ(CSSColorMath.linearizeA98(components))
        case .proPhotoRGB:
            xyz = CSSColorMath.d50ToD65(CSSColorMath.linearProPhotoToXYZ(CSSColorMath.linearizeProPhoto(components)))
        case .rec2020:
            xyz = CSSColorMath.linear2020ToXYZ(CSSColorMath.linearize2020(components))
        case .xyzD50:
            xyz = CSSColorMath.d50ToD65(components)
        case .xyzD65:
            xyz = components
        case .lab:
            xyz = CSSColorMath.d50ToD65(CSSColorMath.labToXYZD50(components))
        case .lch:
            xyz = CSSColorMath.d50ToD65(CSSColorMath.labToXYZD50(CSSColorMath.lchToLab(components)))
        case .oklab:
            xyz = CSSColorMath.okLabToXYZ(components)
        case .oklch:
            xyz = CSSColorMath.okLabToXYZ(CSSColorMath.okLCHToOKLab(components))
        case .hsl:
            xyz = CSSColorMath.linearSRGBToXYZ(CSSColorMath.linearizeSRGB(CSSColorMath.sRGBFromHSL(components)))
        case .hwb:
            xyz = CSSColorMath.linearSRGBToXYZ(CSSColorMath.linearizeSRGB(CSSColorMath.sRGBFromHWB(components)))
        }
        try self.init(xyzD65: xyz, alpha: alpha)
    }

    public func components(in space: CSSColorSpace) -> SIMD3<Double> {
        switch space {
        case .sRGB:
            return CSSColorMath.encodeSRGB(CSSColorMath.xyzToLinearSRGB(xyzD65))
        case .sRGBLinear:
            return CSSColorMath.xyzToLinearSRGB(xyzD65)
        case .displayP3:
            return CSSColorMath.encodeSRGB(CSSColorMath.xyzToLinearP3(xyzD65))
        case .displayP3Linear:
            return CSSColorMath.xyzToLinearP3(xyzD65)
        case .a98RGB:
            return CSSColorMath.encodeA98(CSSColorMath.xyzToLinearA98(xyzD65))
        case .proPhotoRGB:
            return CSSColorMath.encodeProPhoto(CSSColorMath.xyzD50ToProPhoto(CSSColorMath.d65ToD50(xyzD65)))
        case .rec2020:
            return CSSColorMath.encode2020(CSSColorMath.xyzToLinear2020(xyzD65))
        case .xyzD50:
            return CSSColorMath.d65ToD50(xyzD65)
        case .xyzD65:
            return xyzD65
        case .lab:
            return CSSColorMath.xyzD50ToLab(CSSColorMath.d65ToD50(xyzD65))
        case .lch:
            return CSSColorMath.labToLCH(CSSColorMath.xyzD50ToLab(CSSColorMath.d65ToD50(xyzD65)))
        case .oklab:
            return CSSColorMath.xyzToOKLab(xyzD65)
        case .oklch:
            return CSSColorMath.okLabToOKLCH(CSSColorMath.xyzToOKLab(xyzD65))
        case .hsl:
            return CSSColorMath.hslFromSRGB(components(in: .sRGB))
        case .hwb:
            return CSSColorMath.hwbFromSRGB(components(in: .sRGB))
        }
    }
}

public enum CSSColorMathError: Error, Equatable, Sendable {
    case nonFiniteComponent
}

public struct CSSMappedSRGB: Equatable, Sendable {
    public let components: SIMD3<Double>
    public let alpha: Double
    public let wasMapped: Bool

    public init(components: SIMD3<Double>, alpha: Double, wasMapped: Bool) {
        self.components = components
        self.alpha = alpha
        self.wasMapped = wasMapped
    }
}

public enum CSSColorGamutMapping {
    public static func sRGB(for color: CSSColor) -> CSSMappedSRGB {
        let original = color.components(in: .sRGBLinear)
        guard original.allSatisfy({ $0 >= -1e-12 && $0 <= 1 + 1e-12 }) else {
            let mappedLinear = rayTrace(color)
            return CSSMappedSRGB(
                components: CSSColorMath.encodeSRGB(mappedLinear),
                alpha: color.alpha,
                wasMapped: true
            )
        }
        return CSSMappedSRGB(
            components: CSSColorMath.encodeSRGB(original.map { min(max($0, 0), 1) }),
            alpha: color.alpha,
            wasMapped: false
        )
    }

    private static func rayTrace(_ color: CSSColor) -> SIMD3<Double> {
        let originOKLCH = color.components(in: .oklch)
        let lightness = originOKLCH.x
        let hue = originOKLCH.z
        if lightness >= 1 {
            return SIMD3(repeating: 1)
        }
        if lightness <= 0 {
            return .zero
        }

        var anchor = linearSRGB(forOKLCH: SIMD3(lightness, 0, hue))
        var origin = color.components(in: .sRGBLinear)
        var last = origin
        let low = 1e-12
        let high = 1 - 1e-12

        for iteration in 0..<4 {
            if iteration > 0 {
                let current = CSSColorMath.xyzToOKLCH(CSSColorMath.linearSRGBToXYZ(origin))
                origin = linearSRGB(forOKLCH: SIMD3(lightness, current.y, hue))
            }
            guard let intersection = rayIntersection(start: anchor, end: origin) else {
                origin = last
                break
            }
            if iteration > 0 && origin.allSatisfy({ $0 > low && $0 < high }) {
                anchor = origin
            }
            origin = intersection
            last = intersection
        }
        return origin.map { min(max($0, 0), 1) }
    }

    private static func linearSRGB(forOKLCH value: SIMD3<Double>) -> SIMD3<Double> {
        let okLab = CSSColorMath.okLCHToOKLab(value)
        return CSSColorMath.xyzToLinearSRGB(CSSColorMath.okLabToXYZ(okLab))
    }

    private static func rayIntersection(start: SIMD3<Double>, end: SIMD3<Double>) -> SIMD3<Double>? {
        var tNear = -Double.infinity
        var tFar = Double.infinity
        var direction = SIMD3<Double>.zero
        for index in 0..<3 {
            let delta = end[index] - start[index]
            direction[index] = delta
            if abs(delta) > 1e-12 {
                let inverse = 1 / delta
                let t1 = -start[index] * inverse
                let t2 = (1 - start[index]) * inverse
                tNear = max(min(t1, t2), tNear)
                tFar = min(max(t1, t2), tFar)
            } else if start[index] < 0 || start[index] > 1 {
                return nil
            }
        }
        guard tNear <= tFar, tFar >= 0 else { return nil }
        if tNear < 0 { tNear = tFar }
        guard tNear.isFinite else { return nil }
        return start + direction * tNear
    }
}

public enum CSSColorMath {
    private static let d50 = SIMD3(0.3457 / 0.3585, 1.0, (1 - 0.3457 - 0.3585) / 0.3585)
    private static let d65 = SIMD3(0.3127 / 0.3290, 1.0, (1 - 0.3127 - 0.3290) / 0.3290)

    static func linearizeSRGB(_ value: SIMD3<Double>) -> SIMD3<Double> {
        value.map { transfer($0, threshold: 0.04045, slope: 12.92, exponent: 2.4, offset: 0.055, scale: 1.055) }
    }

    static func encodeSRGB(_ value: SIMD3<Double>) -> SIMD3<Double> {
        value.map { inverseTransfer($0, threshold: 0.0031308, slope: 12.92, exponent: 1 / 2.4, offset: 0.055, scale: 1.055) }
    }

    private static func transfer(_ value: Double, threshold: Double, slope: Double, exponent: Double, offset: Double, scale: Double) -> Double {
        let sign = value < 0 ? -1.0 : 1.0
        let magnitude = abs(value)
        if magnitude <= threshold { return value / slope }
        return sign * pow((magnitude + offset) / scale, exponent)
    }

    private static func inverseTransfer(_ value: Double, threshold: Double, slope: Double, exponent: Double, offset: Double, scale: Double) -> Double {
        let sign = value < 0 ? -1.0 : 1.0
        let magnitude = abs(value)
        if magnitude <= threshold { return slope * value }
        return sign * (scale * pow(magnitude, exponent) - offset)
    }

    static func linearizeA98(_ value: SIMD3<Double>) -> SIMD3<Double> { value.map { signedPow($0, 563 / 256) } }
    static func encodeA98(_ value: SIMD3<Double>) -> SIMD3<Double> { value.map { signedPow($0, 256 / 563) } }
    static func linearize2020(_ value: SIMD3<Double>) -> SIMD3<Double> {
        let alpha = 1.09929682680944
        let beta = 0.018053968510807
        return value.map {
            let sign = $0 < 0 ? -1.0 : 1.0
            let magnitude = abs($0)
            return magnitude < beta * 4.5
                ? $0 / 4.5
                : sign * pow((magnitude + alpha - 1) / alpha, 1 / 0.45)
        }
    }

    static func encode2020(_ value: SIMD3<Double>) -> SIMD3<Double> {
        let alpha = 1.09929682680944
        let beta = 0.018053968510807
        return value.map {
            let sign = $0 < 0 ? -1.0 : 1.0
            let magnitude = abs($0)
            return magnitude > beta
                ? sign * (alpha * pow(magnitude, 0.45) - (alpha - 1))
                : 4.5 * $0
        }
    }

    static func linearizeProPhoto(_ value: SIMD3<Double>) -> SIMD3<Double> {
        value.map { abs($0) <= 16 / 512 ? $0 / 16 : signedPow($0, 1.8) }
    }

    static func encodeProPhoto(_ value: SIMD3<Double>) -> SIMD3<Double> {
        value.map { abs($0) >= 1 / 512 ? signedPow($0, 1 / 1.8) : 16 * $0 }
    }

    private static func signedPow(_ value: Double, _ exponent: Double) -> Double {
        guard value != 0 else { return 0 }
        return (value < 0 ? -1 : 1) * pow(abs(value), exponent)
    }

    static func linearSRGBToXYZ(_ value: SIMD3<Double>) -> SIMD3<Double> {
        multiply([
            [506752.0 / 1228815, 87881.0 / 245763, 12673.0 / 70218],
            [87098.0 / 409605, 175762.0 / 245763, 12673.0 / 175545],
            [7918.0 / 409605, 87881.0 / 737289, 1001167.0 / 1053270]
        ], value)
    }

    static func xyzToLinearSRGB(_ value: SIMD3<Double>) -> SIMD3<Double> {
        multiply([
            [12831.0 / 3959, -329.0 / 214, -1974.0 / 3959],
            [-851781.0 / 878810, 1648619.0 / 878810, 36519.0 / 878810],
            [705.0 / 12673, -2585.0 / 12673, 705.0 / 667]
        ], value)
    }

    static func linearP3ToXYZ(_ value: SIMD3<Double>) -> SIMD3<Double> {
        multiply([
            [608311.0 / 1250200, 189793.0 / 714400, 198249.0 / 1000160],
            [35783.0 / 156275, 247089.0 / 357200, 198249.0 / 2500400],
            [0, 32229.0 / 714400, 5220557.0 / 5000800]
        ], value)
    }

    static func xyzToLinearP3(_ value: SIMD3<Double>) -> SIMD3<Double> {
        multiply([
            [446124.0 / 178915, -333277.0 / 357830, -72051.0 / 178915],
            [-14852.0 / 17905, 63121.0 / 35810, 423.0 / 17905],
            [11844.0 / 330415, -50337.0 / 660830, 316169.0 / 330415]
        ], value)
    }

    static func linearA98ToXYZ(_ value: SIMD3<Double>) -> SIMD3<Double> {
        multiply([
            [573536.0 / 994567, 263643.0 / 1420810, 187206.0 / 994567],
            [591459.0 / 1989134, 6239551.0 / 9945670, 374412.0 / 4972835],
            [53769.0 / 1989134, 351524.0 / 4972835, 4929758.0 / 4972835]
        ], value)
    }

    static func xyzToLinearA98(_ value: SIMD3<Double>) -> SIMD3<Double> {
        multiply([
            [1829569.0 / 896150, -506331.0 / 896150, -308931.0 / 896150],
            [-851781.0 / 878810, 1648619.0 / 878810, 36519.0 / 878810],
            [16779.0 / 1248040, -147721.0 / 1248040, 1266979.0 / 1248040]
        ], value)
    }

    static func linearProPhotoToXYZ(_ value: SIMD3<Double>) -> SIMD3<Double> {
        multiply([
            [0.7977666449006423, 0.13518129740053308, 0.0313477341283922],
            [0.2880748288194013, 0.711835234241873, 0.00008993693872564],
            [0, 0, 0.8251046025104602]
        ], value)
    }

    static func xyzD50ToProPhoto(_ value: SIMD3<Double>) -> SIMD3<Double> {
        multiply([
            [1.3457868816471583, -0.25557208737979464, -0.05110186497554526],
            [-0.5446307051249019, 1.5082477428451468, 0.02052744743642139],
            [0, 0, 1.2119675456389452]
        ], value)
    }

    static func linear2020ToXYZ(_ value: SIMD3<Double>) -> SIMD3<Double> {
        multiply([
            [63426534.0 / 99577255, 20160776.0 / 139408157, 47086771.0 / 278816314],
            [26158966.0 / 99577255, 472592308.0 / 697040785, 8267143.0 / 139408157],
            [0, 19567812.0 / 697040785, 295819943.0 / 278816314]
        ], value)
    }

    static func xyzToLinear2020(_ value: SIMD3<Double>) -> SIMD3<Double> {
        multiply([
            [30757411.0 / 17917100, -6372589.0 / 17917100, -4539589.0 / 17917100],
            [-19765991.0 / 29648200, 47925759.0 / 29648200, 467509.0 / 29648200],
            [792561.0 / 44930125, -1921689.0 / 44930125, 42328811.0 / 44930125]
        ], value)
    }

    static func d65ToD50(_ value: SIMD3<Double>) -> SIMD3<Double> {
        multiply([
            [1.0479297925449969, 0.022946870601609652, -0.05019226628920524],
            [0.02962780877005599, 0.9904344267538799, -0.017073799063418826],
            [-0.009243040646204504, 0.015055191490298152, 0.7518742814281371]
        ], value)
    }

    static func d50ToD65(_ value: SIMD3<Double>) -> SIMD3<Double> {
        multiply([
            [0.955473421488075, -0.02309845494876471, 0.06325924320057072],
            [-0.0283697093338637, 1.0099953980813041, 0.021041441191917323],
            [0.012314014864481998, -0.020507649298898964, 1.330365926242124]
        ], value)
    }

    static func xyzD50ToLab(_ value: SIMD3<Double>) -> SIMD3<Double> {
        let epsilon = 216.0 / 24389.0
        let kappa = 24389.0 / 27.0
        let scaled = SIMD3(value.x / d50.x, value.y / d50.y, value.z / d50.z)
        let f = scaled.map { $0 > epsilon ? cbrt($0) : (kappa * $0 + 16) / 116 }
        return SIMD3(116 * f.y - 16, 500 * (f.x - f.y), 200 * (f.y - f.z))
    }

    static func labToXYZD50(_ value: SIMD3<Double>) -> SIMD3<Double> {
        let epsilon = 216.0 / 24389.0
        let kappa = 24389.0 / 27.0
        let fy = (value.x + 16) / 116
        let fx = value.y / 500 + fy
        let fz = fy - value.z / 200
        func inverse(_ f: Double) -> Double {
            let cube = f * f * f
            return cube > epsilon ? cube : (116 * f - 16) / kappa
        }
        return SIMD3(inverse(fx) * d50.x, inverse(fy) * d50.y, inverse(fz) * d50.z)
    }

    static func labToLCH(_ value: SIMD3<Double>) -> SIMD3<Double> {
        let chroma = hypot(value.y, value.z)
        let hue = chroma <= 0.0015 ? 0 : normalizedHue(atan2(value.z, value.y) * 180 / .pi)
        return SIMD3(value.x, chroma, hue)
    }

    static func lchToLab(_ value: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(value.x, value.y * cos(value.z * .pi / 180), value.y * sin(value.z * .pi / 180))
    }

    static func xyzToOKLab(_ value: SIMD3<Double>) -> SIMD3<Double> {
        let lms = multiply([
            [0.819022437996703, 0.3619062600528904, -0.1288737815209879],
            [0.0329836539323885, 0.9292868615863434, 0.0361446663506424],
            [0.0481771893596242, 0.2642395317527308, 0.6335478284694309]
        ], value).map(cbrt)
        return multiply([
            [0.210454268309314, 0.7936177747023054, -0.0040720430116193],
            [1.9779985324311684, -2.4285922420485799, 0.450593709617411],
            [0.0259040424655478, 0.7827717124575296, -0.8086757549230774]
        ], lms)
    }

    static func okLabToXYZ(_ value: SIMD3<Double>) -> SIMD3<Double> {
        let lms = multiply([
            [1, 0.3963377773761749, 0.2158037573099136],
            [1, -0.1055613458156586, -0.0638541728258133],
            [1, -0.0894841775298119, -1.2914855480194092]
        ], value).map { $0 * $0 * $0 }
        return multiply([
            [1.2268798758459243, -0.5578149944602171, 0.2813910456659647],
            [-0.0405757452148008, 1.112286803280317, -0.0717110580655164],
            [-0.0763729366746601, -0.4214933324022432, 1.5869240198367816]
        ], lms)
    }

    static func xyzToOKLCH(_ value: SIMD3<Double>) -> SIMD3<Double> {
        okLabToOKLCH(xyzToOKLab(value))
    }

    static func okLabToOKLCH(_ value: SIMD3<Double>) -> SIMD3<Double> {
        let chroma = hypot(value.y, value.z)
        let hue = chroma <= 0.000004 ? 0 : normalizedHue(atan2(value.z, value.y) * 180 / .pi)
        return SIMD3(value.x, chroma, hue)
    }

    static func okLCHToOKLab(_ value: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(value.x, value.y * cos(value.z * .pi / 180), value.y * sin(value.z * .pi / 180))
    }

    static func hslFromSRGB(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let maxValue = max(rgb.x, max(rgb.y, rgb.z))
        let minValue = min(rgb.x, min(rgb.y, rgb.z))
        let lightness = (maxValue + minValue) / 2
        guard maxValue != minValue else { return SIMD3(0, 0, lightness * 100) }
        let delta = maxValue - minValue
        let saturation = lightness > 0.5 ? delta / (2 - maxValue - minValue) : delta / (maxValue + minValue)
        var hue: Double
        if maxValue == rgb.x { hue = (rgb.y - rgb.z) / delta + (rgb.y < rgb.z ? 6 : 0) }
        else if maxValue == rgb.y { hue = (rgb.z - rgb.x) / delta + 2 }
        else { hue = (rgb.x - rgb.y) / delta + 4 }
        return SIMD3(hue * 60, saturation * 100, lightness * 100)
    }

    static func sRGBFromHSL(_ value: SIMD3<Double>) -> SIMD3<Double> {
        let h = normalizedHue(value.x) / 360
        let s = min(max(value.y / 100, 0), 1)
        let l = min(max(value.z / 100, 0), 1)
        guard s > 0 else { return SIMD3(repeating: l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func hue(_ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return SIMD3(hue(h + 1 / 3), hue(h), hue(h - 1 / 3))
    }

    static func hwbFromSRGB(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        let hsl = hslFromSRGB(rgb)
        return SIMD3(hsl.x, min(rgb.x, min(rgb.y, rgb.z)) * 100, (1 - max(rgb.x, max(rgb.y, rgb.z))) * 100)
    }

    static func sRGBFromHWB(_ value: SIMD3<Double>) -> SIMD3<Double> {
        let white = min(max(value.y / 100, 0), 1)
        let black = min(max(value.z / 100, 0), 1)
        if white + black >= 1 { return SIMD3(repeating: white / (white + black)) }
        let pure = sRGBFromHSL(SIMD3(value.x, 100, 50))
        let scale = 1 - white - black
        return pure * scale + SIMD3(repeating: white)
    }

    private static func normalizedHue(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }

    private static func multiply(_ matrix: [[Double]], _ vector: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            matrix[0][0] * vector.x + matrix[0][1] * vector.y + matrix[0][2] * vector.z,
            matrix[1][0] * vector.x + matrix[1][1] * vector.y + matrix[1][2] * vector.z,
            matrix[2][0] * vector.x + matrix[2][1] * vector.y + matrix[2][2] * vector.z
        )
    }
}

extension SIMD3 where Scalar == Double {
    func allSatisfy(_ predicate: (Double) -> Bool) -> Bool {
        predicate(x) && predicate(y) && predicate(z)
    }

}

private extension SIMD3 where Scalar == Double {
    func map(_ transform: (Double) -> Double) -> SIMD3<Double> {
        SIMD3(transform(x), transform(y), transform(z))
    }
}
