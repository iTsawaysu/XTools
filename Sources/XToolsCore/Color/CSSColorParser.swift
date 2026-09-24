import Foundation

public enum CSSColorSyntaxFamily: String, Equatable, Sendable {
    case hex
    case rgb
    case hsl
    case hwb
    case lab
    case lch
    case oklab
    case oklch
    case color
    case named
}

public struct CSSParsedColor: Equatable, Sendable {
    public let color: CSSColor
    public let family: CSSColorSyntaxFamily
    public let predefinedSpace: CSSColorSpace?

    public init(color: CSSColor, family: CSSColorSyntaxFamily, predefinedSpace: CSSColorSpace? = nil) {
        self.color = color
        self.family = family
        self.predefinedSpace = predefinedSpace
    }
}

public enum CSSColorDraftStatus: Equatable, Sendable {
    case empty
    case incomplete
    case valid
    case invalid
}

public struct CSSColorDiagnostic: Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct CSSColorParseResult: Equatable, Sendable {
    public let status: CSSColorDraftStatus
    public let parsed: CSSParsedColor?
    public let diagnostic: CSSColorDiagnostic?

    public init(status: CSSColorDraftStatus, parsed: CSSParsedColor? = nil, diagnostic: CSSColorDiagnostic? = nil) {
        self.status = status
        self.parsed = parsed
        self.diagnostic = diagnostic
    }
}

public struct CSSColorParseError: Error, Equatable, Sendable {
    public let diagnostic: CSSColorDiagnostic
    public let isIncomplete: Bool

    public init(_ message: String, isIncomplete: Bool = false) {
        diagnostic = CSSColorDiagnostic(message: message)
        self.isIncomplete = isIncomplete
    }
}

public enum CSSColorParser {
    public static func classify(_ input: String) -> CSSColorParseResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return CSSColorParseResult(status: .empty) }
        do {
            return CSSColorParseResult(status: .valid, parsed: try parse(trimmed))
        } catch let error as CSSColorParseError {
            return CSSColorParseResult(
                status: error.isIncomplete ? .incomplete : .invalid,
                diagnostic: error.diagnostic
            )
        } catch {
            return CSSColorParseResult(
                status: .invalid,
                diagnostic: CSSColorDiagnostic(message: "无法解析此 CSS 颜色。")
            )
        }
    }

    public static func parse(_ input: String) throws -> CSSParsedColor {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw CSSColorParseError("请输入 CSS 颜色。", isIncomplete: true) }

        if value.hasPrefix("#") {
            return try parseHex(value)
        }

        let lowercased = value.lowercased()
        if lowercased == "transparent" {
            return CSSParsedColor(
                color: try CSSColor(components: .zero, space: .sRGB, alpha: 0),
                family: .named
            )
        }
        if let named = CSSNamedColors.color(named: lowercased) {
            return CSSParsedColor(color: named, family: .named)
        }

        if !value.contains("(") {
            if contextDependentKeywords.contains(lowercased) {
                throw CSSColorParseError("该颜色依赖外部 CSS 上下文，当前工具不解析。")
            }
            if isPotentialNamedColorPrefix(lowercased) {
                throw CSSColorParseError("命名颜色尚未输入完整。", isIncomplete: true)
            }
            throw CSSColorParseError("不是可识别的 CSS 命名颜色。")
        }

        guard let open = value.firstIndex(of: "(") else {
            throw CSSColorParseError("CSS 颜色函数缺少左括号。", isIncomplete: true)
        }
        guard value.contains(")") else {
            throw CSSColorParseError("CSS 颜色函数尚未输入完整。", isIncomplete: true)
        }
        guard value.last == ")" else {
            throw CSSColorParseError("CSS 颜色后不能包含其他内容。")
        }
        let rawName = String(value[..<open])
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawName == trimmedName else {
            throw CSSColorParseError("颜色函数名和左括号之间不能有空格。")
        }
        let name = trimmedName.lowercased()
        guard !name.isEmpty else { throw CSSColorParseError("CSS 颜色函数缺少名称。") }
        let bodyStart = value.index(after: open)
        let bodyEnd = value.index(before: value.endIndex)
        let body = String(value[bodyStart..<bodyEnd])

        let normalizedBody = body.lowercased().replacingOccurrences(of: " ", with: "")
        if ["calc(", "var(", "env(", "min(", "max(", "clamp("].contains(where: normalizedBody.contains) {
            throw CSSColorParseError("CSS 变量和数学表达式依赖外部求值，当前工具不解析。")
        }
        if body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("from ") {
            throw CSSColorParseError("相对颜色依赖源颜色上下文，当前工具不解析。")
        }

        if unsupportedFunctions.contains(name) {
            throw CSSColorParseError("该 CSS 颜色函数超出当前工具的独立颜色解析范围。")
        }
        let tokens = try tokenize(body)
        switch name {
        case "rgb", "rgba": return try parseRGB(tokens)
        case "hsl", "hsla": return try parseHSL(tokens)
        case "hwb": return try parseHWB(tokens)
        case "lab": return try parseLab(tokens)
        case "lch": return try parseLCH(tokens)
        case "oklab": return try parseOKLab(tokens)
        case "oklch": return try parseOKLCH(tokens)
        case "color": return try parseColorFunction(tokens)
        default: throw CSSColorParseError("不支持此 CSS 颜色函数。")
        }
    }

    private static let unsupportedFunctions: Set<String> = [
        "var", "env", "calc", "min", "max", "clamp", "color-mix", "light-dark",
        "device-cmyk", "contrast-color"
    ]

    private static let contextDependentKeywords: Set<String> = [
        "currentcolor", "inherit", "initial", "unset", "revert", "revert-layer",
        "accentcolor", "accentcolortext", "activetext", "buttonborder", "buttonface",
        "canvas", "canvastext", "linktext", "visitedtext", "buttontext",
        "field", "fieldtext", "graytext", "highlight", "highlighttext",
        "mark", "marktext", "selecteditem", "selecteditemtext", "system-color"
    ]

    private static func isPotentialNamedColorPrefix(_ input: String) -> Bool {
        guard input.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "-") }) else { return false }
        return CSSNamedColors.hasName(withPrefix: input)
    }

    private static func parseHex(_ value: String) throws -> CSSParsedColor {
        let payload = String(value.dropFirst())
        guard payload.allSatisfy(\.isASCIIHexDigit) else {
            throw CSSColorParseError("HEX 颜色只能包含 0–9 和 A–F。")
        }
        if ![3, 4, 6, 8].contains(payload.count) {
            let incomplete = payload.count < 8
            throw CSSColorParseError(
                incomplete ? "HEX 颜色尚未输入完整。" : "HEX 颜色必须使用 3、4、6 或 8 位。",
                isIncomplete: incomplete
            )
        }

        func byte(_ pair: Substring) -> Double { Double(Int(pair, radix: 16) ?? 0) / 255 }
        let characters = Array(payload)
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        if characters.count <= 4 {
            red = Double(Int(String(repeating: characters[0], count: 2), radix: 16) ?? 0) / 255
            green = Double(Int(String(repeating: characters[1], count: 2), radix: 16) ?? 0) / 255
            blue = Double(Int(String(repeating: characters[2], count: 2), radix: 16) ?? 0) / 255
            alpha = characters.count == 4
                ? Double(Int(String(repeating: characters[3], count: 2), radix: 16) ?? 0) / 255
                : 1
        } else {
            red = byte(payload.prefix(2))
            green = byte(payload.dropFirst(2).prefix(2))
            blue = byte(payload.dropFirst(4).prefix(2))
            alpha = payload.count == 8 ? byte(payload.suffix(2)) : 1
        }
        return CSSParsedColor(
            color: try CSSColor(components: SIMD3(red, green, blue), space: .sRGB, alpha: alpha),
            family: .hex
        )
    }

    private static func parseRGB(_ tokens: [Token]) throws -> CSSParsedColor {
        let (components, alpha): ([Token], Token?)
        if tokens.contains(where: { $0.kind == .comma }) {
            (components, alpha) = try legacyComponents(tokens)
            guard !components.contains(where: { $0.kind == .ident("none") }),
                  alpha?.kind != .ident("none") else {
                throw CSSColorParseError("旧式 RGB 语法不接受 none。")
            }
            let percentages = components.map { $0.kind.isPercentage }
            guard percentages.allSatisfy({ $0 }) || percentages.allSatisfy({ !$0 }) else {
                throw CSSColorParseError("旧式 RGB 语法不能混用数值和百分比通道。")
            }
        } else {
            (components, alpha) = try modernComponents(tokens, count: 3)
        }
        let rgb = try SIMD3(
            rgbChannel(components[0]),
            rgbChannel(components[1]),
            rgbChannel(components[2])
        )
        return CSSParsedColor(
            color: try CSSColor(components: rgb, space: .sRGB, alpha: try alphaValue(alpha)),
            family: .rgb
        )
    }

    private static func parseHSL(_ tokens: [Token]) throws -> CSSParsedColor {
        let (components, alpha): ([Token], Token?)
        if tokens.contains(where: { $0.kind == .comma }) {
            (components, alpha) = try legacyComponents(tokens)
            guard !components.contains(where: { $0.kind == .ident("none") }),
                  alpha?.kind != .ident("none") else {
                throw CSSColorParseError("旧式 HSL 语法不接受 none。")
            }
        } else {
            (components, alpha) = try modernComponents(tokens, count: 3)
        }
        let hsl = SIMD3(
            try angle(components[0]),
            try percentage(components[1], label: "饱和度"),
            try percentage(components[2], label: "亮度")
        )
        return CSSParsedColor(
            color: try CSSColor(components: hsl, space: .hsl, alpha: try alphaValue(alpha)),
            family: .hsl
        )
    }

    private static func parseHWB(_ tokens: [Token]) throws -> CSSParsedColor {
        guard !tokens.contains(where: { $0.kind == .comma }) else {
            throw CSSColorParseError("HWB 只支持空格分隔语法。")
        }
        let (components, alpha) = try modernComponents(tokens, count: 3)
        let hwb = SIMD3(
            try angle(components[0]),
            try percentage(components[1], label: "白度"),
            try percentage(components[2], label: "黑度")
        )
        return CSSParsedColor(
            color: try CSSColor(components: hwb, space: .hwb, alpha: try alphaValue(alpha)),
            family: .hwb
        )
    }

    private static func parseLab(_ tokens: [Token]) throws -> CSSParsedColor {
        let (components, alpha) = try modernComponents(tokens, count: 3)
        let lab = SIMD3(
            try lightness100(components[0]),
            try scaledNumber(components[1], percentageScale: 125),
            try scaledNumber(components[2], percentageScale: 125)
        )
        return CSSParsedColor(
            color: try CSSColor(components: lab, space: .lab, alpha: try alphaValue(alpha)),
            family: .lab
        )
    }

    private static func parseLCH(_ tokens: [Token]) throws -> CSSParsedColor {
        let (components, alpha) = try modernComponents(tokens, count: 3)
        let lch = SIMD3(
            try lightness100(components[0]),
            max(try scaledNumber(components[1], percentageScale: 150), 0),
            try angle(components[2])
        )
        return CSSParsedColor(
            color: try CSSColor(components: lch, space: .lch, alpha: try alphaValue(alpha)),
            family: .lch
        )
    }

    private static func parseOKLab(_ tokens: [Token]) throws -> CSSParsedColor {
        let (components, alpha) = try modernComponents(tokens, count: 3)
        let lab = SIMD3(
            try lightnessOne(components[0]),
            try scaledNumber(components[1], percentageScale: 0.4),
            try scaledNumber(components[2], percentageScale: 0.4)
        )
        return CSSParsedColor(
            color: try CSSColor(components: lab, space: .oklab, alpha: try alphaValue(alpha)),
            family: .oklab
        )
    }

    private static func parseOKLCH(_ tokens: [Token]) throws -> CSSParsedColor {
        let (components, alpha) = try modernComponents(tokens, count: 3)
        let lch = SIMD3(
            try lightnessOne(components[0]),
            max(try scaledNumber(components[1], percentageScale: 0.4), 0),
            try angle(components[2])
        )
        return CSSParsedColor(
            color: try CSSColor(components: lch, space: .oklch, alpha: try alphaValue(alpha)),
            family: .oklch
        )
    }

    private static func parseColorFunction(_ tokens: [Token]) throws -> CSSParsedColor {
        guard !tokens.contains(where: { $0.kind == .comma }), tokens.count >= 4 else {
            throw CSSColorParseError("color() 需要色彩空间和三个通道。", isIncomplete: tokens.count < 4)
        }
        guard case let .ident(profile) = tokens[0].kind else {
            throw CSSColorParseError("color() 缺少预定义色彩空间。")
        }
        guard tokens[1].leadingWhitespace else {
            throw CSSColorParseError("color() 色彩空间和通道之间需要空格。")
        }
        guard !profile.hasPrefix("--") else {
            throw CSSColorParseError("自定义色彩配置依赖外部 CSS 上下文，当前工具不解析。")
        }
        let space: CSSColorSpace
        switch profile {
        case "srgb": space = .sRGB
        case "srgb-linear": space = .sRGBLinear
        case "display-p3": space = .displayP3
        case "display-p3-linear": space = .displayP3Linear
        case "a98-rgb": space = .a98RGB
        case "prophoto-rgb": space = .proPhotoRGB
        case "rec2020": space = .rec2020
        case "xyz", "xyz-d65": space = .xyzD65
        case "xyz-d50": space = .xyzD50
        default: throw CSSColorParseError("color() 使用了不支持的预定义色彩空间。")
        }

        let (components, alpha) = try modernComponents(Array(tokens.dropFirst()), count: 3)
        let coordinates = try SIMD3(
            colorCoordinate(components[0]),
            colorCoordinate(components[1]),
            colorCoordinate(components[2])
        )
        return CSSParsedColor(
            color: try CSSColor(components: coordinates, space: space, alpha: try alphaValue(alpha)),
            family: .color,
            predefinedSpace: space
        )
    }

    private static func legacyComponents(_ tokens: [Token]) throws -> ([Token], Token?) {
        guard !tokens.contains(where: { $0.kind == .slash }) else {
            throw CSSColorParseError("旧式逗号语法不能使用斜杠 Alpha。")
        }
        let expectedCounts = [5, 7]
        guard expectedCounts.contains(tokens.count) else {
            throw CSSColorParseError("旧式颜色函数需要三个逗号分隔通道和可选 Alpha。", isIncomplete: tokens.count < 5)
        }
        for index in stride(from: 1, through: tokens.count - 2, by: 2) {
            guard tokens[index].kind == .comma else {
                throw CSSColorParseError("旧式颜色函数必须统一使用逗号分隔。")
            }
        }
        let values = stride(from: 0, to: min(tokens.count, 6), by: 2).map { tokens[$0] }
        guard values.count == 3 else { throw CSSColorParseError("颜色函数缺少通道。", isIncomplete: true) }
        return (values, tokens.count == 7 ? tokens[6] : nil)
    }

    private static func modernComponents(_ tokens: [Token], count: Int) throws -> ([Token], Token?) {
        guard !tokens.contains(where: { $0.kind == .comma }) else {
            throw CSSColorParseError("现代颜色函数必须统一使用空格分隔。")
        }
        let slashIndices = tokens.indices.filter { tokens[$0].kind == .slash }
        guard slashIndices.count <= 1 else { throw CSSColorParseError("颜色函数只能包含一个 Alpha 分隔斜杠。") }
        let componentTokens: [Token]
        let alpha: Token?
        if let slash = slashIndices.first {
            componentTokens = Array(tokens[..<slash])
            let tail = Array(tokens[tokens.index(after: slash)...])
            guard tail.count == 1 else {
                throw CSSColorParseError("Alpha 分隔斜杠后需要一个值。", isIncomplete: tail.isEmpty)
            }
            alpha = tail[0]
        } else {
            componentTokens = tokens
            alpha = nil
        }
        guard componentTokens.count == count else {
            throw CSSColorParseError("颜色函数需要 \(count) 个通道。", isIncomplete: componentTokens.count < count)
        }
        for index in 1..<componentTokens.count where !componentTokens[index].leadingWhitespace {
            throw CSSColorParseError("现代颜色函数的通道之间需要空格。")
        }
        return (componentTokens, alpha)
    }

    private static func rgbChannel(_ token: Token) throws -> Double {
        switch token.kind {
        case let .number(value): return min(max(value / 255, 0), 1)
        case let .percentage(value): return min(max(value / 100, 0), 1)
        case .ident("none"): return 0
        default: throw CSSColorParseError("RGB 通道必须是数值、百分比或 none。")
        }
    }

    private static func alphaValue(_ token: Token?) throws -> Double {
        guard let token else { return 1 }
        switch token.kind {
        case let .number(value): return min(max(value, 0), 1)
        case let .percentage(value): return min(max(value / 100, 0), 1)
        case .ident("none"): return 0
        default: throw CSSColorParseError("Alpha 必须是数值、百分比或 none。")
        }
    }

    private static func angle(_ token: Token) throws -> Double {
        let degrees: Double
        switch token.kind {
        case let .number(value): degrees = value
        case let .dimension(value, unit):
            switch unit {
            case "deg": degrees = value
            case "grad": degrees = value * 0.9
            case "rad": degrees = value * 180 / .pi
            case "turn": degrees = value * 360
            default: throw CSSColorParseError("色相角度单位必须是 deg、grad、rad 或 turn。")
            }
        case .ident("none"): degrees = 0
        default: throw CSSColorParseError("色相必须是角度或 none。")
        }
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    private static func percentage(_ token: Token, label: String) throws -> Double {
        switch token.kind {
        case let .percentage(value): return min(max(value, 0), 100)
        case .ident("none"): return 0
        default: throw CSSColorParseError("\(label)必须使用百分比或 none。")
        }
    }

    private static func lightness100(_ token: Token) throws -> Double {
        switch token.kind {
        case let .number(value), let .percentage(value): return min(max(value, 0), 100)
        case .ident("none"): return 0
        default: throw CSSColorParseError("亮度必须是数值、百分比或 none。")
        }
    }

    private static func lightnessOne(_ token: Token) throws -> Double {
        switch token.kind {
        case let .number(value): return min(max(value, 0), 1)
        case let .percentage(value): return min(max(value / 100, 0), 1)
        case .ident("none"): return 0
        default: throw CSSColorParseError("亮度必须是数值、百分比或 none。")
        }
    }

    private static func scaledNumber(_ token: Token, percentageScale: Double) throws -> Double {
        switch token.kind {
        case let .number(value): return value
        case let .percentage(value): return value / 100 * percentageScale
        case .ident("none"): return 0
        default: throw CSSColorParseError("颜色通道必须是数值、百分比或 none。")
        }
    }

    private static func colorCoordinate(_ token: Token) throws -> Double {
        switch token.kind {
        case let .number(value): return value
        case let .percentage(value): return value / 100
        case .ident("none"): return 0
        default: throw CSSColorParseError("color() 通道必须是数值、百分比或 none。")
        }
    }
}

private struct Token: Equatable {
    enum Kind: Equatable {
        case number(Double)
        case percentage(Double)
        case dimension(Double, String)
        case ident(String)
        case comma
        case slash

        var isPercentage: Bool {
            if case .percentage = self { return true }
            return false
        }
    }

    let kind: Kind
    let leadingWhitespace: Bool
}

private func tokenize(_ source: String) throws -> [Token] {
    let characters = Array(source)
    var tokens: [Token] = []
    var index = 0
    var hadWhitespace = false

    while index < characters.count {
        if characters[index].isWhitespace {
            hadWhitespace = true
            index += 1
            continue
        }
        if characters[index] == "/", index + 1 < characters.count, characters[index + 1] == "*" {
            guard let end = commentEnd(in: characters, after: index + 2) else {
                throw CSSColorParseError("CSS 注释尚未输入完整。", isIncomplete: true)
            }
            index = end
            hadWhitespace = true
            continue
        }

        let leadingWhitespace = hadWhitespace
        hadWhitespace = false
        if characters[index] == "," {
            tokens.append(Token(kind: .comma, leadingWhitespace: leadingWhitespace))
            index += 1
            continue
        }
        if characters[index] == "/" {
            tokens.append(Token(kind: .slash, leadingWhitespace: leadingWhitespace))
            index += 1
            continue
        }
        if isNumberStart(characters, at: index) {
            let start = index
            if characters[index] == "+" || characters[index] == "-" { index += 1 }
            while index < characters.count && characters[index].isASCIIDigit { index += 1 }
            if index + 1 < characters.count,
               characters[index] == ".",
               characters[index + 1].isASCIIDigit {
                index += 1
                while index < characters.count && characters[index].isASCIIDigit { index += 1 }
            }
            if index < characters.count && (characters[index] == "e" || characters[index] == "E") {
                let exponentStart = index
                index += 1
                if index < characters.count && (characters[index] == "+" || characters[index] == "-") { index += 1 }
                let digitStart = index
                while index < characters.count && characters[index].isASCIIDigit { index += 1 }
                if digitStart == index { index = exponentStart }
            }
            guard let number = Double(String(characters[start..<index])), number.isFinite else {
                throw CSSColorParseError("颜色通道包含无效数值。")
            }
            if index < characters.count && characters[index] == "%" {
                tokens.append(Token(kind: .percentage(number), leadingWhitespace: leadingWhitespace))
                index += 1
                continue
            }
            let unitStart = index
            while index < characters.count && characters[index].isASCIILetter { index += 1 }
            if unitStart < index {
                tokens.append(Token(
                    kind: .dimension(number, String(characters[unitStart..<index]).lowercased()),
                    leadingWhitespace: leadingWhitespace
                ))
            } else {
                tokens.append(Token(kind: .number(number), leadingWhitespace: leadingWhitespace))
            }
            continue
        }
        if characters[index].isASCIILetter || characters[index] == "-" {
            let start = index
            while index < characters.count && (characters[index].isASCIILetter || characters[index].isASCIIDigit || characters[index] == "-") {
                index += 1
            }
            tokens.append(Token(
                kind: .ident(String(characters[start..<index]).lowercased()),
                leadingWhitespace: leadingWhitespace
            ))
            continue
        }
        throw CSSColorParseError("颜色函数包含不支持的符号。")
    }
    return tokens
}

private func commentEnd(in characters: [Character], after start: Int) -> Int? {
    guard start <= characters.count else { return nil }
    var index = start
    while index + 1 < characters.count {
        if characters[index] == "*" && characters[index + 1] == "/" { return index + 2 }
        index += 1
    }
    return nil
}

private func isNumberStart(_ characters: [Character], at index: Int) -> Bool {
    let character = characters[index]
    if character.isASCIIDigit { return true }
    if character == "." { return index + 1 < characters.count && characters[index + 1].isASCIIDigit }
    if character == "+" || character == "-" {
        guard index + 1 < characters.count else { return false }
        return characters[index + 1].isASCIIDigit
            || (characters[index + 1] == "." && index + 2 < characters.count && characters[index + 2].isASCIIDigit)
    }
    return false
}

private extension Character {
    var isASCIIDigit: Bool { wholeNumberValue != nil && isASCII && ("0"..."9").contains(self) }
    var isASCIILetter: Bool {
        guard isASCII, let scalar = unicodeScalars.first?.value else { return false }
        return (65...90).contains(scalar) || (97...122).contains(scalar)
    }
}
