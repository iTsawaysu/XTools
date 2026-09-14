import Foundation

public enum CSSColorFormatGroup: String, Equatable, Sendable {
    case common
    case perceptual
    case extended
}

public enum CSSColorMappingStatus: Equatable, Sendable {
    case original
    case mappedToSRGB
}

public struct CSSColorFormattedValue: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let text: String
    public let group: CSSColorFormatGroup
    public let mappingStatus: CSSColorMappingStatus

    public init(id: String, label: String, text: String, group: CSSColorFormatGroup, mappingStatus: CSSColorMappingStatus) {
        self.id = id
        self.label = label
        self.text = text
        self.group = group
        self.mappingStatus = mappingStatus
    }
}

public enum CSSColorFormatter {
    public static func values(for color: CSSColor) -> [CSSColorFormattedValue] {
        let mapped = CSSColorGamutMapping.sRGB(for: color)
        let mapping: CSSColorMappingStatus = mapped.wasMapped ? .mappedToSRGB : .original
        var result = [
            value("hex", "HEX", hex(mapped), .common, mapping),
            value("rgb", "RGB", rgb(mapped), .common, mapping),
            value("hsl", "HSL", hsl(mapped), .common, mapping),
            value("hwb", "HWB", hwb(mapped), .common, mapping),
            value("lab", "Lab", lab(color), .perceptual, .original),
            value("lch", "LCH", lch(color), .perceptual, .original),
            value("oklab", "OKLab", oklab(color), .perceptual, .original),
            value("oklch", "OKLCH", oklch(color), .perceptual, .original)
        ]
        for space in extendedSpaces {
            result.append(value(
                "color-\(space.rawValue)",
                extendedLabel(for: space),
                colorFunction(color, space: space),
                .extended,
                .original
            ))
        }
        return result
    }

    public static func inputText(
        for color: CSSColor,
        family: CSSColorSyntaxFamily,
        predefinedSpace: CSSColorSpace? = nil
    ) -> String {
        let mapped = CSSColorGamutMapping.sRGB(for: color)
        switch family {
        case .hex: return hex(mapped)
        case .rgb, .named: return rgb(mapped)
        case .hsl: return hsl(mapped)
        case .hwb: return hwb(mapped)
        case .lab: return lab(color)
        case .lch: return lch(color)
        case .oklab: return oklab(color)
        case .oklch: return oklch(color)
        case .color: return colorFunction(color, space: predefinedSpace ?? .displayP3)
        }
    }

    private static let extendedSpaces: [CSSColorSpace] = [
        .sRGB, .sRGBLinear, .displayP3, .displayP3Linear, .a98RGB,
        .proPhotoRGB, .rec2020, .xyzD50, .xyzD65
    ]

    private static func value(
        _ id: String,
        _ label: String,
        _ text: String,
        _ group: CSSColorFormatGroup,
        _ mapping: CSSColorMappingStatus
    ) -> CSSColorFormattedValue {
        CSSColorFormattedValue(id: id, label: label, text: text, group: group, mappingStatus: mapping)
    }

    private static func hex(_ mapped: CSSMappedSRGB) -> String {
        let bytes = mapped.components.map { Int((min(max($0, 0), 1) * 255).rounded()) }
        var output = String(format: "#%02X%02X%02X", bytes.x, bytes.y, bytes.z)
        if mapped.alpha < 1 - 1e-12 {
            output += String(format: "%02X", Int((mapped.alpha * 255).rounded()))
        }
        return output
    }

    private static func rgb(_ mapped: CSSMappedSRGB) -> String {
        let channels = mapped.components.map { decimal(min(max($0, 0), 1) * 255, digits: 4) }
        return "rgb(\(channels.x) \(channels.y) \(channels.z)\(alphaSuffix(mapped.alpha)))"
    }

    private static func hsl(_ mapped: CSSMappedSRGB) -> String {
        let components = CSSColorMath.hslFromSRGB(mapped.components)
        return "hsl(\(decimal(components.x, digits: 4)) \(decimal(components.y, digits: 4))% \(decimal(components.z, digits: 4))%\(alphaSuffix(mapped.alpha)))"
    }

    private static func hwb(_ mapped: CSSMappedSRGB) -> String {
        let components = CSSColorMath.hwbFromSRGB(mapped.components)
        return "hwb(\(decimal(components.x, digits: 4)) \(decimal(components.y, digits: 4))% \(decimal(components.z, digits: 4))%\(alphaSuffix(mapped.alpha)))"
    }

    private static func lab(_ color: CSSColor) -> String {
        let components = color.components(in: .lab)
        return "lab(\(decimal(components.x)) \(decimal(components.y)) \(decimal(components.z))\(alphaSuffix(color.alpha)))"
    }

    private static func lch(_ color: CSSColor) -> String {
        let components = color.components(in: .lch)
        return "lch(\(decimal(components.x)) \(decimal(components.y)) \(decimal(components.z))\(alphaSuffix(color.alpha)))"
    }

    private static func oklab(_ color: CSSColor) -> String {
        let components = color.components(in: .oklab)
        return "oklab(\(decimal(components.x)) \(decimal(components.y)) \(decimal(components.z))\(alphaSuffix(color.alpha)))"
    }

    private static func oklch(_ color: CSSColor) -> String {
        let components = color.components(in: .oklch)
        return "oklch(\(decimal(components.x)) \(decimal(components.y)) \(decimal(components.z))\(alphaSuffix(color.alpha)))"
    }

    private static func colorFunction(_ color: CSSColor, space: CSSColorSpace) -> String {
        let components = color.components(in: space)
        return "color(\(space.rawValue) \(decimal(components.x)) \(decimal(components.y)) \(decimal(components.z))\(alphaSuffix(color.alpha)))"
    }

    private static func extendedLabel(for space: CSSColorSpace) -> String {
        switch space {
        case .sRGB: return "sRGB"
        case .sRGBLinear: return "sRGB Linear"
        case .displayP3: return "Display P3"
        case .displayP3Linear: return "Display P3 Linear"
        case .a98RGB: return "A98 RGB"
        case .proPhotoRGB: return "ProPhoto RGB"
        case .rec2020: return "Rec. 2020"
        case .xyzD50: return "XYZ D50"
        case .xyzD65: return "XYZ D65"
        default: return space.rawValue
        }
    }

    private static func alphaSuffix(_ alpha: Double) -> String {
        alpha < 1 - 1e-12 ? " / \(decimal(alpha, digits: 6))" : ""
    }

    private static func decimal(_ value: Double, digits: Int = 7) -> String {
        guard value.isFinite else { return "0" }
        let threshold = 0.5 * pow(10, -Double(digits))
        let normalized = abs(value) < threshold ? 0 : value
        var output = String(
            format: "%.*f",
            locale: Locale(identifier: "en_US_POSIX"),
            digits,
            normalized
        )
        while output.contains(".") && output.last == "0" { output.removeLast() }
        if output.last == "." { output.removeLast() }
        return output == "-0" ? "0" : output
    }
}

private extension SIMD3 where Scalar == Double {
    func map<T>(_ transform: (Double) -> T) -> (x: T, y: T, z: T) {
        (transform(x), transform(y), transform(z))
    }
}
