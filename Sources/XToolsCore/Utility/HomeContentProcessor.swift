import Foundation

public enum HomeContentAction: String, CaseIterable, Hashable, Sendable {
    case jsonFormat
    case base64Decode
    case urlDecode
}

public struct HomeContentResult: Equatable, Sendable {
    public let text: String
    public let warning: String?

    public init(text: String, warning: String? = nil) {
        self.text = text
        self.warning = warning
    }
}

public enum HomeContentFailure: Error, LocalizedError, Equatable, Sendable {
    case emptyInput
    case inputTooLong(maximumCharacterCount: Int)
    case inputTooDeep(maximumNestingDepth: Int)
    case processingFailed(String)

    public var message: String {
        switch self {
        case .emptyInput:
            return "请输入要处理的内容。"
        case .inputTooLong(let maximumCharacterCount):
            return "快速处理最多支持 \(maximumCharacterCount) 个字符，请缩短内容后重试。"
        case .inputTooDeep(let maximumNestingDepth):
            return "JSON 最多支持 \(maximumNestingDepth) 层嵌套，请减少嵌套后重试。"
        case .processingFailed(let message):
            return message
        }
    }

    public var errorDescription: String? {
        message
    }
}

public enum HomeContentProcessor {
    public static let maximumCharacterCount = SmartPasteDetector.maxInspectedLength
    public static let maximumJSONNestingDepth = 64

    public static func detect(_ input: String) -> SmartPasteDetector.Kind? {
        guard input.count <= maximumCharacterCount else { return nil }
        guard hasSafeJSONNesting(input) else { return nil }
        if let detected = SmartPasteDetector.detect(input) {
            return detected
        }

        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if isShortUTF8Base64(text) {
            return .base64
        }
        if isPercentEncodedText(text) {
            return .urlEncoded
        }
        return nil
    }

    public static func preferredAction(for kind: SmartPasteDetector.Kind) -> HomeContentAction? {
        switch kind {
        case .json:
            return .jsonFormat
        case .base64:
            return .base64Decode
        case .urlEncoded:
            return .urlDecode
        case .jwt, .html, .xml, .cssColor, .unixTimestamp, .dataURL:
            return nil
        }
    }

    public static func run(
        _ action: HomeContentAction,
        input: String
    ) -> Result<HomeContentResult, HomeContentFailure> {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.emptyInput)
        }
        guard input.count <= maximumCharacterCount else {
            return .failure(.inputTooLong(maximumCharacterCount: maximumCharacterCount))
        }
        guard action != .jsonFormat || hasSafeJSONNesting(input) else {
            return .failure(.inputTooDeep(maximumNestingDepth: maximumJSONNestingDepth))
        }

        do {
            switch action {
            case .jsonFormat:
                let formatted = try JSONFormatting.formatResult(
                    input,
                    sortKeys: false,
                    indentWidth: 2
                )
                return .success(HomeContentResult(text: formatted.text, warning: formatted.warning))
            case .base64Decode:
                return .success(HomeContentResult(text: try Base64Conversion.decode(input)))
            case .urlDecode:
                return .success(HomeContentResult(text: try URLPercentCoding.decode(input)))
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? "处理失败，请检查输入内容。"
            return .failure(.processingFailed(message))
        }
    }

    private static func hasSafeJSONNesting(_ input: String) -> Bool {
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for character in input {
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            switch character {
            case "\"":
                isInsideString = true
            case "{", "[":
                depth += 1
                if depth > maximumJSONNestingDepth {
                    return false
                }
            case "}", "]":
                depth = max(0, depth - 1)
            default:
                continue
            }
        }

        return true
    }

    private static func isShortUTF8Base64(_ text: String) -> Bool {
        guard text.count >= 8, text.count.isMultiple(of: 4) else { return false }
        let alphabet = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
        )
        guard text.unicodeScalars.allSatisfy(alphabet.contains),
              let decoded = try? Base64Conversion.decode(text) else {
            return false
        }
        return Base64Conversion.encode(decoded) == text
    }

    private static func isPercentEncodedText(_ text: String) -> Bool {
        guard !text.contains(where: \Character.isNewline),
              containsPercentEscape(text),
              let decoded = try? URLPercentCoding.decode(text) else {
            return false
        }
        return decoded != text
    }

    private static func containsPercentEscape(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count >= 3 else { return false }

        for index in 0..<(bytes.count - 2) where bytes[index] == UInt8(ascii: "%") {
            if isHexDigit(bytes[index + 1]), isHexDigit(bytes[index + 2]) {
                return true
            }
        }
        return false
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "A")...UInt8(ascii: "F"),
             UInt8(ascii: "a")...UInt8(ascii: "f"):
            return true
        default:
            return false
        }
    }
}
