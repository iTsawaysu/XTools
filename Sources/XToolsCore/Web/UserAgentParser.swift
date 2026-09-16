import Foundation

public enum UserAgentParser {
    public enum ValidationIssue: LocalizedError, Equatable, Sendable {
        case containsControlCharacter
        case missingProductToken

        public var errorDescription: String? {
            switch self {
            case .containsControlCharacter:
                return "User-Agent 不能包含控制字符。"
            case .missingProductToken:
                return "User-Agent 缺少 product/version 结构。"
            }
        }
    }

    public struct Result: Equatable {
        public let browser: String
        public let browserVersion: String
        public let os: String
        public let osVersion: String
        public let device: String

        public init(browser: String, browserVersion: String, os: String, osVersion: String, device: String) {
            self.browser = browser
            self.browserVersion = browserVersion
            self.os = os
            self.osVersion = osVersion
            self.device = device
        }
    }

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        // Safe: static regex patterns are compile-time constants.
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            fatalError("Invalid regex pattern: \(pattern)")
        }
        return regex
    }

    private static let edgeRegexes = [
        makeRegex("Edg/([0-9.]+)"),
        makeRegex("EdgiOS/([0-9.]+)"),
        makeRegex("EdgA/([0-9.]+)")
    ]
    private static let operaRegexes = [
        makeRegex("OPR/([0-9.]+)"),
        makeRegex("OPiOS/([0-9.]+)"),
        makeRegex("Version/([0-9.]+)"),
        makeRegex("Opera/([0-9.]+)")
    ]
    private static let firefoxRegexes = [
        makeRegex("Firefox/([0-9.]+)"),
        makeRegex("FxiOS/([0-9.]+)")
    ]
    private static let chromeRegexes = [
        makeRegex("Chrome/([0-9.]+)"),
        makeRegex("CriOS/([0-9.]+)"),
        makeRegex("Chromium/([0-9.]+)")
    ]
    private static let safariRegex = makeRegex("Version/([0-9.]+)")
    private static let windowsRegex = makeRegex("Windows NT ([0-9.]+)")
    private static let iosRegexes = [
        makeRegex("(?:CPU(?: iPhone)? OS|CPU OS) ([0-9_]+)"),
        makeRegex("OS ([0-9_]+) like Mac OS X")
    ]
    private static let androidRegex = makeRegex("Android ([0-9.]+)")
    private static let macOSRegex = makeRegex("Mac OS X ([0-9_]+)")

    public static func parse(_ userAgent: String) -> Result? {
        let trimmed = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard validationIssue(trimmed) == nil else { return nil }

        let ua = trimmed.lowercased()

        let browser: String
        let browserVersion: String
        if ua.contains("edg/") || ua.contains("edgios/") || ua.contains("edga/") {
            browser = "Microsoft Edge"
            browserVersion = firstVersion(in: trimmed, regexes: edgeRegexes)
        } else if ua.contains("opr/") || ua.contains("opera/") || ua.contains("opios/") {
            browser = "Opera"
            browserVersion = firstVersion(in: trimmed, regexes: operaRegexes)
        } else if ua.contains("firefox/") || ua.contains("fxios/") {
            browser = "Mozilla Firefox"
            browserVersion = firstVersion(in: trimmed, regexes: firefoxRegexes)
        } else if ua.contains("chrome/") || ua.contains("crios/") || ua.contains("chromium/") {
            browser = "Google Chrome"
            browserVersion = firstVersion(in: trimmed, regexes: chromeRegexes)
        } else if ua.contains("safari/") && !ua.contains("chrome") {
            browser = "Apple Safari"
            browserVersion = extractVersion(from: trimmed, regex: safariRegex)
        } else {
            browser = "(未知)"
            browserVersion = "(未知)"
        }

        let os: String
        let osVersion: String
        if ua.contains("windows nt") {
            os = "Windows"
            if ua.contains("windows nt 10.0") {
                osVersion = "10"
            } else if ua.contains("windows nt 6.3") {
                osVersion = "8.1"
            } else if ua.contains("windows nt 6.2") {
                osVersion = "8"
            } else if ua.contains("windows nt 6.1") {
                osVersion = "7"
            } else {
                osVersion = extractVersion(from: trimmed, regex: windowsRegex)
            }
        } else if ua.contains("iphone") || ua.contains("ipad") {
            os = "iOS"
            osVersion = firstVersion(in: trimmed, regexes: iosRegexes)
                .replacingOccurrences(of: "_", with: ".")
        } else if ua.contains("android") {
            os = "Android"
            osVersion = extractVersion(from: trimmed, regex: androidRegex)
        } else if ua.contains("mac os x") {
            os = "macOS"
            osVersion = extractVersion(from: trimmed, regex: macOSRegex).replacingOccurrences(of: "_", with: ".")
        } else if ua.contains("linux") {
            os = "Linux"
            osVersion = "(未知)"
        } else {
            os = "(未知)"
            osVersion = "(未知)"
        }

        let device: String
        if ua.contains("ipad") || ua.contains("tablet") || (ua.contains("android") && !ua.contains("mobile")) {
            device = "Tablet"
        } else if ua.contains("mobile") || ua.contains("iphone") || ua.contains("ipod") || ua.contains("android") {
            device = "Mobile"
        } else if browser != "(未知)", os == "Windows" || os == "macOS" || os == "Linux" {
            device = "Desktop"
        } else {
            device = "(未知)"
        }

        return Result(browser: browser, browserVersion: browserVersion, os: os, osVersion: osVersion, device: device)
    }

    public static func validationIssue(_ userAgent: String) -> ValidationIssue? {
        let trimmed = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.unicodeScalars.contains(where: isControlCharacter) {
            return .containsControlCharacter
        }

        if !containsProductToken(in: trimmed) {
            return .missingProductToken
        }

        return nil
    }

    private static func firstVersion(in text: String, regexes: [NSRegularExpression]) -> String {
        for regex in regexes {
            let version = extractVersion(from: text, regex: regex)
            if version != "(未知)" {
                return version
            }
        }
        return "(未知)"
    }

    private static func extractVersion(from text: String, regex: NSRegularExpression) -> String {
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, range: range),
           let versionRange = Range(match.range(at: 1), in: text) {
            return String(text[versionRange])
        }

        return "(未知)"
    }

    private static func containsProductToken(in text: String) -> Bool {
        var productHasCharacter = false
        var isReadingVersion = false
        var versionStartsWithDigit = false
        var versionHasCharacter = false

        for scalar in text.unicodeScalars {
            if isHTTPTokenScalar(scalar) {
                if isReadingVersion {
                    if !versionHasCharacter {
                        versionStartsWithDigit = ("0"..."9").contains(scalar)
                    }
                    versionHasCharacter = true
                } else {
                    productHasCharacter = true
                }
                continue
            }

            if scalar == "/", productHasCharacter, !isReadingVersion {
                isReadingVersion = true
                continue
            }

            if productHasCharacter && isReadingVersion && versionStartsWithDigit && versionHasCharacter {
                return true
            }

            productHasCharacter = false
            isReadingVersion = false
            versionStartsWithDigit = false
            versionHasCharacter = false
        }

        return productHasCharacter && isReadingVersion && versionStartsWithDigit && versionHasCharacter
    }

    private static func isHTTPTokenScalar(_ scalar: Unicode.Scalar) -> Bool {
        if isASCIIAlphaNumeric(scalar) {
            return true
        }

        switch scalar {
        case "!", "#", "$", "%", "&", "'", "*", "+", "-", ".", "^", "_", "`", "|", "~":
            return true
        default:
            return false
        }
    }

    private static func isControlCharacter(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || scalar.value == 0x7F
    }

    private static func isASCIIAlphaNumeric(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
            || (0x41...0x5A).contains(scalar.value)
            || (0x61...0x7A).contains(scalar.value)
    }
}
