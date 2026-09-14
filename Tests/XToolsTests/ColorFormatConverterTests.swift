import XToolsCore
import Testing

struct ColorFormatConverterTests {
    // MARK: - HEX → RGB

    @Test func parsesHexWithAndWithoutHash() {
        let withHash = ColorFormatConverter.rgb(fromHex: "#7C8CFF")
        #expect(withHash?.0 == 124)
        #expect(withHash?.1 == 140)
        #expect(withHash?.2 == 255)

        // same value without the leading '#'
        let withoutHash = ColorFormatConverter.rgb(fromHex: "7C8CFF")
        #expect(withoutHash?.0 == 124)
        #expect(withoutHash?.1 == 140)
        #expect(withoutHash?.2 == 255)
    }

    @Test func parsesHexCaseInsensitivelyAndTrimsWhitespace() {
        #expect(ColorFormatConverter.rgb(fromHex: "  #ffffff  ")! == (255, 255, 255))
        #expect(ColorFormatConverter.rgb(fromHex: "#000000")! == (0, 0, 0))
    }

    @Test func returnsNilForMalformedHex() {
        #expect(ColorFormatConverter.rgb(fromHex: "#FFF") == nil)      // 3 digits
        #expect(ColorFormatConverter.rgb(fromHex: "#FFFFFFFF") == nil) // 8 digits / alpha
        #expect(ColorFormatConverter.rgb(fromHex: "#GGGGGG") == nil)   // non-hex
        #expect(ColorFormatConverter.rgb(fromHex: "#1234567") == nil)  // 7 digits
        #expect(ColorFormatConverter.rgb(fromHex: "") == nil)
    }

    @Test func classifiesLiveHexInputForDiagnostics() {
        #expect(ColorFormatConverter.hexInputState("") == .empty)
        #expect(ColorFormatConverter.hexInputState("#") == .incomplete)
        #expect(ColorFormatConverter.hexInputState("#7C8") == .incomplete)
        #expect(ColorFormatConverter.hexInputState("#7C8CFF") == .valid)
        #expect(ColorFormatConverter.hexInputState("7c8cff") == .valid)
        #expect(ColorFormatConverter.hexInputState("#GGGGGG") == .invalidCharacter)
        #expect(ColorFormatConverter.hexInputState("##123456") == .invalidPrefix)
        #expect(ColorFormatConverter.hexInputState("#1234567") == .invalidLength)
        #expect(ColorFormatConverter.hexInputState("#12345678") == .unsupportedAlpha)
    }

    @Test func hexDiagnosticsIdentifyTheSpecificInputRule() {
        let cases: [(String, String)] = [
            ("#GGGGGG", "HEX 颜色只能包含 0–9 和 A–F。"),
            ("##123456", "# 只能出现在 HEX 颜色开头。"),
            ("#1234567", "HEX 颜色必须是 6 位 RGB。"),
            ("#12345678", "当前颜色转换仅支持 6 位 RGB，不支持 8 位 Alpha HEX。")
        ]

        for (input, expected) in cases {
            let message = ColorFormatConverter.hexInputState(input).diagnosticMessage
            #expect(message == expected)
            ToolDiagnosticContract.expectFactual(message ?? "", sensitiveInputs: [input])
        }

        for input in ["", "#", "#12345", "#123456"] {
            #expect(ColorFormatConverter.hexInputState(input).diagnosticMessage == nil)
        }
    }

    // MARK: - RGB → HSL

    @Test func convertsGrayscaleToZeroSaturation() {
        // pure white: L=100, S=0, H=0
        let white = ColorFormatConverter.hsl(r: 255, g: 255, b: 255)
        #expect(white == (0, 0, 100))
        // pure black: L=0
        let black = ColorFormatConverter.hsl(r: 0, g: 0, b: 0)
        #expect(black == (0, 0, 0))
        // mid gray: L≈50, S=0
        let gray = ColorFormatConverter.hsl(r: 128, g: 128, b: 128)
        #expect(gray.0 == 0)
        #expect(gray.1 == 0)
    }

    @Test func convertsPrimaryColorsToExpectedHue() {
        // pure red -> hue 0
        #expect(ColorFormatConverter.hsl(r: 255, g: 0, b: 0) == (0, 100, 50))
        // pure green -> hue 120
        #expect(ColorFormatConverter.hsl(r: 0, g: 255, b: 0) == (120, 100, 50))
        // pure blue -> hue 240
        #expect(ColorFormatConverter.hsl(r: 0, g: 0, b: 255) == (240, 100, 50))
    }

    @Test func clampsRGBComponentsBeforeConvertingToHSL() {
        #expect(ColorFormatConverter.hsl(r: 300, g: -20, b: 0) == (0, 100, 50))
        #expect(ColorFormatConverter.hsl(r: -10, g: 999, b: 0) == (120, 100, 50))
    }

    // MARK: - HSL → HEX

    @Test func convertsHSLBackToHex() {
        #expect(ColorFormatConverter.hexFromHSL(h: 0, s: 100, l: 50) == "#FF0000")   // red
        #expect(ColorFormatConverter.hexFromHSL(h: 120, s: 100, l: 50) == "#00FF00") // green
        #expect(ColorFormatConverter.hexFromHSL(h: 240, s: 100, l: 50) == "#0000FF") // blue
        #expect(ColorFormatConverter.hexFromHSL(h: 0, s: 0, l: 100) == "#FFFFFF")    // white
        #expect(ColorFormatConverter.hexFromHSL(h: 0, s: 0, l: 0) == "#000000")      // black
    }

    @Test func normalizesHueAndClampsSaturationAndLightness() {
        #expect(ColorFormatConverter.hexFromHSL(h: 480, s: 100, l: 50) == "#00FF00")
        #expect(ColorFormatConverter.hexFromHSL(h: -120, s: 100, l: 50) == "#0000FF")
        #expect(ColorFormatConverter.hexFromHSL(h: 0, s: 200, l: 50) == "#FF0000")
        #expect(ColorFormatConverter.hexFromHSL(h: 0, s: -20, l: 50) == "#808080")
        #expect(ColorFormatConverter.hexFromHSL(h: 0, s: 100, l: 150) == "#FFFFFF")
    }

    @Test func roundTripsPrimaryColors() {
        // hex -> hsl -> hex should be stable for saturated primaries
        for hex in ["#FF0000", "#00FF00", "#0000FF", "#FFFFFF", "#000000"] {
            let rgb = ColorFormatConverter.rgb(fromHex: hex)!
            let hsl = ColorFormatConverter.hsl(r: rgb.0, g: rgb.1, b: rgb.2)
            let back = ColorFormatConverter.hexFromHSL(h: hsl.0, s: hsl.1, l: hsl.2)
            #expect(back == hex)
        }
    }
}
