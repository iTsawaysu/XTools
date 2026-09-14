import XToolsCore
import SwiftUI

struct IndexASCIIBinaryPage: View {
    nonisolated static func isEmptyInput(_ input: String, mode: String) -> Bool {
        switch mode {
        case "bin", "ascii":
            return input.isEmpty
        default:
            return input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        IndexConverterPage(
            toolID: "text-to-ascii-binary",
            title: "ASCII / 二进制",
            subtitle: "文本与 ASCII 码、二进制串之间互转。",
            modes: [
                IndexConverterMode(id: "bin", label: "文本→二进制"),
                IndexConverterMode(id: "debin", label: "二进制→文本"),
                IndexConverterMode(id: "ascii", label: "文本→ASCII"),
                IndexConverterMode(id: "deascii", label: "ASCII→文本")
            ],
            placeholder: "输入文本或二进制串…",
            outputPresentation: .nativeReadOnlyText,
            backfillModeTransition: { currentMode, newMode in
                switch (currentMode, newMode) {
                case ("bin", "debin"),
                     ("debin", "bin"),
                     ("ascii", "deascii"),
                     ("deascii", "ascii"):
                    return true
                default:
                    return false
                }
            },
            isEmptyInputForMode: Self.isEmptyInput,
            errorMessage: { error in
                (error as? ASCIIBinaryConversion.ConversionError)?.errorDescription
                    ?? "ASCII 或二进制转换失败。"
            }
        ) { input, mode in
            switch mode {
            case "ascii":
                return try ASCIIBinaryConversion.validatedTextToASCII(input)
            case "deascii":
                return try ASCIIBinaryConversion.validatedASCIIToText(input)
            case "debin":
                return try ASCIIBinaryConversion.validatedBinaryToText(input)
            default:
                return ASCIIBinaryConversion.textToBinary(input)
            }
        }
    }
}
