import Foundation

public enum ColorFormatConverter {
    public enum HexInputState: Equatable {
        case empty
        case incomplete
        case valid
        case invalidLength
        case invalidCharacter
        case invalidPrefix
        case unsupportedAlpha

        public var diagnosticMessage: String? {
            switch self {
            case .invalidCharacter:
                return "HEX 颜色只能包含 0–9 和 A–F。"
            case .invalidPrefix:
                return "# 只能出现在 HEX 颜色开头。"
            case .unsupportedAlpha:
                return "当前颜色转换仅支持 6 位 RGB，不支持 8 位 Alpha HEX。"
            case .invalidLength:
                return "HEX 颜色必须是 6 位 RGB。"
            case .empty, .incomplete, .valid:
                return nil
            }
        }
    }

    public static func rgb(fromHex hex: String) -> (Int, Int, Int)? {
        guard let value = normalizedHexPayload(hex),
              let int = Int(value, radix: 16) else {
            return nil
        }
        return ((int >> 16) & 255, (int >> 8) & 255, int & 255)
    }

    public static func hexInputState(_ hex: String) -> HexInputState {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let payload: Substring
        if trimmed.hasPrefix("#") {
            let start = trimmed.index(after: trimmed.startIndex)
            payload = trimmed[start...]
        } else {
            payload = trimmed[trimmed.startIndex...]
        }

        guard !payload.contains("#") else {
            return .invalidPrefix
        }
        guard payload.allSatisfy(isASCIIHexDigit) else {
            return .invalidCharacter
        }

        if payload.count == 6 {
            return .valid
        }

        if payload.count < 6 {
            return .incomplete
        }
        if payload.count == 8 {
            return .unsupportedAlpha
        }
        return .invalidLength
    }

    public static func hsl(r: Int, g: Int, b: Int) -> (Double, Double, Double) {
        let rd = Double(clampedByte(r)) / 255
        let gd = Double(clampedByte(g)) / 255
        let bd = Double(clampedByte(b)) / 255
        let maxv = max(rd, gd, bd), minv = min(rd, gd, bd)
        var h = 0.0, s = 0.0
        let l = (maxv + minv) / 2
        if maxv != minv {
            let d = maxv - minv
            s = l > 0.5 ? d / (2 - maxv - minv) : d / (maxv + minv)
            if maxv == rd { h = (gd - bd) / d + (gd < bd ? 6 : 0) }
            else if maxv == gd { h = (bd - rd) / d + 2 }
            else { h = (rd - gd) / d + 4 }
            h /= 6
        }
        return ((h * 360).rounded(), (s * 100).rounded(), (l * 100).rounded())
    }

    public static func hexFromHSL(h: Double, s: Double, l: Double) -> String {
        let h = normalizedHue(h)
        let s = clampedPercent(s) / 100
        let l = clampedPercent(l) / 100
        let a = s * min(l, 1 - l)
        func f(_ n: Double) -> Int {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            return clampedChannel(255 * (l - a * max(min(k - 3, 9 - k, 1), -1)))
        }
        return String(format: "#%02X%02X%02X", f(0), f(8), f(4))
    }

    private static func clampedByte(_ value: Int) -> Int {
        min(max(value, 0), 255)
    }

    private static func clampedPercent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 100)
    }

    private static func normalizedHue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    private static func clampedChannel(_ value: Double) -> Int {
        min(max(Int(value.rounded()), 0), 255)
    }

    private static func normalizedHexPayload(_ hex: String) -> String? {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: Substring
        if trimmed.hasPrefix("#") {
            let start = trimmed.index(after: trimmed.startIndex)
            payload = trimmed[start...]
        } else {
            payload = trimmed[trimmed.startIndex...]
        }

        guard payload.count == 6,
              payload.allSatisfy(isASCIIHexDigit) else {
            return nil
        }

        return String(payload)
    }

    private static func isASCIIHexDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return false
        }

        return (48...57).contains(scalar.value)
            || (65...70).contains(scalar.value)
            || (97...102).contains(scalar.value)
    }
}
