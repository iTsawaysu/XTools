import Foundation

/// Best-effort classification of clipboard text so the shell can suggest the
/// tool that fits the copied value (DevToys-style smart detection).
///
/// Design rules:
/// - **Conservative.** A wrong suggestion is worse than no suggestion, so every
///   rule is a strict shape check rather than a keyword guess.
/// - **Bounded.** Inputs larger than `maxInspectedLength` are ignored instead of
///   classified; a suggestion on a huge blob is not actionable and the check
///   must stay cheap enough to run on app activation.
/// - **UI-free.** The detector returns a `Kind`, never a tool identity, so tool
///   routing and copywriting stay app-layer concerns.
/// - **Ordered.** Most specific kinds first; `base64` runs last because its
///   alphabet is the loosest and would otherwise swallow other kinds.
public enum SmartPasteDetector {
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        case json
        case jwt
        case html
        case xml
        case cssColor
        case unixTimestamp
        case urlEncoded
        case dataURL
        case base64
    }

    /// Maximum number of characters inspected. Longer input is ignored.
    public static let maxInspectedLength = 32 * 1024

    /// Classifies `raw`; returns `nil` when no rule matches confidently.
    public static func detect(_ raw: String) -> Kind? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= maxInspectedLength else { return nil }

        if let kind = detectTokenLike(text) {
            return kind
        }
        if let kind = detectStructuredText(text) {
            return kind
        }
        return detectEncodedText(text)
    }

    // MARK: - Single-token kinds (no line breaks, short)

    private static func detectTokenLike(_ text: String) -> Kind? {
        guard !text.contains(where: \.isNewline) else { return nil }

        if isCSSColor(text) {
            return .cssColor
        }
        if isUnixTimestamp(text) {
            return .unixTimestamp
        }
        if isJWT(text) {
            return .jwt
        }
        return nil
    }

    /// `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `rgb(...)`, `rgba(...)`,
    /// `hsl(...)`, `hsla(...)`. Deliberately excludes bare names like `red`.
    private static func isCSSColor(_ text: String) -> Bool {
        guard text.count <= 64 else { return false }

        let lowercased = text.lowercased()

        if lowercased.hasPrefix("#") {
            let digits = lowercased.dropFirst()
            let hexDigits = CharacterSet(charactersIn: "0123456789abcdef")
            guard [3, 4, 6, 8].contains(digits.count) else { return false }
            return digits.unicodeScalars.allSatisfy(hexDigits.contains)
        }

        let functions = ["rgb(", "rgba(", "hsl(", "hsla("]
        guard let function = functions.first(where: { lowercased.hasPrefix($0) }),
              lowercased.hasSuffix(")") else {
            return false
        }

        let body = lowercased.dropFirst(function.count).dropLast()
        guard !body.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.,% ")
        return body.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Nine/ten digits are seconds, twelve/thirteen are milliseconds; the value
    /// must land between 2001-01-01 and 2100-01-01. Eleven digits are rejected
    /// because both readings land outside that window.
    private static func isUnixTimestamp(_ text: String) -> Bool {
        var digits = Substring(text)
        var isNegative = false
        if digits.hasPrefix("-") {
            isNegative = true
            digits = digits.dropFirst()
        }
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return false }
        guard [9, 10, 12, 13].contains(digits.count) else { return false }

        let seconds: Int64?
        switch digits.count {
        case 9, 10:
            seconds = Int64(digits)
        default:
            seconds = Int64(digits).map { $0 / 1000 }
        }

        guard var value = seconds else { return false }
        if isNegative {
            value = -value
        }

        // 2001-01-01T00:00:00Z ... 2100-01-01T00:00:00Z
        return (978_307_200...4_102_444_800).contains(value)
    }

    private static func isJWT(_ text: String) -> Bool {
        guard text.count <= 8 * 1024 else { return false }
        guard text.filter({ $0 == "." }).count == 2 else { return false }
        let segments = text.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3, segments.allSatisfy({ !$0.isEmpty }) else { return false }
        return (try? JWTParser.parse(text)) != nil
    }

    // MARK: - Structured text

    private static func detectStructuredText(_ text: String) -> Kind? {
        guard let first = text.first else { return nil }

        if first == "{" || first == "[" {
            guard let last = text.last, last == "}" || last == "]" else { return nil }
            return (try? JSONFormatting.minify(text)) != nil ? .json : nil
        }

        if first == "<" {
            // HTML gets a conservative marker check; every other XML-looking
            // value still has to be well formed before suggesting a formatter.
            guard isWellFormedXML(text) else { return nil }
            return isHTMLDocument(text) ? .html : .xml
        }

        return nil
    }

    /// HTML needs a recognisable document/tag shape; a bare `<foo/>` stays XML.
    private static func isHTMLDocument(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        if lowercased.contains("<!doctype html") {
            return true
        }
        let htmlMarkers = ["<html", "<body", "<div", "<span", "<p>", "<a ", "<meta ", "<head"]
        guard htmlMarkers.contains(where: lowercased.contains) else { return false }
        return lowercased.contains("</")
    }

    private static func isWellFormedXML(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8) else { return false }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        return parser.parse()
    }

    // MARK: - Encoded text

    private static func detectEncodedText(_ text: String) -> Kind? {
        if isDataURL(text) {
            return .dataURL
        }

        if isPercentEncoded(text) {
            return .urlEncoded
        }

        if isBase64(text) {
            return .base64
        }

        return nil
    }

    private static func isDataURL(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        guard lowercased.hasPrefix("data:"),
              let comma = text.firstIndex(of: ",")
        else {
            return false
        }

        let metadata = text[text.index(text.startIndex, offsetBy: 5)..<comma]
        let metadataParts = metadata.split(separator: ";", omittingEmptySubsequences: false)
        guard metadataParts.last?.lowercased() == "base64" else { return false }

        let payloadStart = text.index(after: comma)
        let payload = text[payloadStart...]
        guard !payload.isEmpty,
              let data = Data(base64Encoded: String(payload))
        else {
            return false
        }
        return !data.isEmpty
    }

    private static func isPercentEncoded(_ text: String) -> Bool {
        guard !text.contains(where: \.isNewline), text.count <= 8 * 1024 else { return false }

        var escapeCount = 0
        var iterator = text.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            guard scalar == "%" else { continue }
            guard let first = iterator.next(), let second = iterator.next() else { return false }
            let digits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            guard digits.contains(first), digits.contains(second) else { return false }
            escapeCount += 1
        }

        // A single escape is too weak a signal (e.g. an encoded slash in prose).
        guard escapeCount >= 2 else { return false }
        guard let decoded = try? URLPercentCoding.decode(text), decoded != text else { return false }
        return true
    }

    /// Base64 with strict alphabet, length, and decode/re-encode round trip so
    /// ordinary words such as `abcdefghijklmnop` do not qualify.
    private static func isBase64(_ text: String) -> Bool {
        guard text.count >= 16 else { return false }

        let alphabet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        guard text.unicodeScalars.allSatisfy(alphabet.contains) else { return false }
        guard text.count % 4 == 0 else { return false }

        let paddingIndex = text.firstIndex(of: "=")
        if let paddingIndex {
            // Padding may only appear in the final one or two positions.
            let padding = text.distance(from: paddingIndex, to: text.endIndex)
            guard padding <= 2 else { return false }
        }

        guard let data = Data(base64Encoded: text), !data.isEmpty else { return false }
        guard let decoded = String(data: data, encoding: .utf8), !decoded.isEmpty else { return false }

        // Round trip keeps near-miss strings (URL-safe alphabet, stray text) out.
        return Base64Conversion.encode(decoded) == text
    }
}
