import Foundation

public enum BasicAuthCodec {
    public struct Credentials: Equatable, Sendable {
        public let username: String
        public let password: String

        public init(username: String, password: String) {
            self.username = username
            self.password = password
        }
    }

    public enum ValidationIssue: Equatable {
        case usernameContainsColon
        case credentialsContainControlCharacter
    }

    public enum ParseError: Error, Equatable {
        case emptyInput
        case unsupportedHeader(String)
        case unsupportedScheme(String)
        case invalidHeader
        case invalidBase64
        case invalidUTF8
        case missingSeparator
        case credentialsContainControlCharacter
    }

    public static func authorizationHeader(username: String, password: String) -> String? {
        guard !username.isEmpty || !password.isEmpty else {
            return nil
        }
        return authorizationHeader(credentials: Credentials(username: username, password: password))
    }

    public static func authorizationHeader(credentials: Credentials) -> String? {
        guard validationIssue(username: credentials.username, password: credentials.password) == nil else {
            return nil
        }

        let value = "\(credentials.username):\(credentials.password)"
        return "Authorization: Basic \(Base64Conversion.encode(value))"
    }

    public static func validationIssue(username: String, password: String) -> ValidationIssue? {
        if username.contains(":") {
            return .usernameContainsColon
        }
        if containsControlCharacter(username) || containsControlCharacter(password) {
            return .credentialsContainControlCharacter
        }
        return nil
    }

    public static func parse(_ input: String) throws -> Credentials {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ParseError.emptyInput
        }

        let token = try credentialToken(from: trimmed)
        guard !token.contains(where: \.isWhitespace) else {
            throw ParseError.invalidBase64
        }

        let data: Data
        do {
            data = try Base64Conversion.decodeData(token)
        } catch {
            throw ParseError.invalidBase64
        }
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw ParseError.invalidUTF8
        }
        guard let separator = decoded.firstIndex(of: ":") else {
            throw ParseError.missingSeparator
        }

        let username = String(decoded[..<separator])
        let password = String(decoded[decoded.index(after: separator)...])
        guard !containsControlCharacter(username), !containsControlCharacter(password) else {
            throw ParseError.credentialsContainControlCharacter
        }

        return Credentials(username: username, password: password)
    }

    private static func credentialToken(from input: String) throws -> String {
        if let colon = input.firstIndex(of: ":") {
            let fieldName = String(input[..<colon])
            guard asciiCaseInsensitiveEqual(fieldName, "Authorization") else {
                throw ParseError.unsupportedHeader(fieldName)
            }

            let value = input[input.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                throw ParseError.invalidHeader
            }
            return try tokenFromHeaderValue(value)
        }

        if input.contains(where: \.isWhitespace) {
            return try tokenFromHeaderValue(input)
        }

        return input
    }

    private static func tokenFromHeaderValue(_ value: String) throws -> String {
        guard let separator = value.firstIndex(where: \.isWhitespace) else {
            throw ParseError.invalidHeader
        }

        let scheme = String(value[..<separator])
        guard asciiCaseInsensitiveEqual(scheme, "Basic") else {
            throw ParseError.unsupportedScheme(scheme)
        }

        var tokenStart = separator
        while tokenStart < value.endIndex, value[tokenStart] == " " {
            tokenStart = value.index(after: tokenStart)
        }
        guard tokenStart < value.endIndex else {
            throw ParseError.invalidHeader
        }

        let token = String(value[tokenStart...])
        guard !token.contains(where: \.isWhitespace) else {
            throw ParseError.invalidBase64
        }
        return token
    }

    private static func asciiCaseInsensitiveEqual(_ left: String, _ right: String) -> Bool {
        left.compare(right, options: [.caseInsensitive, .literal], locale: Locale(identifier: "en_US_POSIX")) == .orderedSame
    }

    private static func containsControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.value < 0x20 || scalar.value == 0x7F
        }
    }
}

public typealias BasicAuthGenerator = BasicAuthCodec
