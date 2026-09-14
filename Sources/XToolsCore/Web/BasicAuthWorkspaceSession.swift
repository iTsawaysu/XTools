import Foundation

public struct BasicAuthWorkspaceSession: Equatable, Sendable {
    public enum Mode: String, Equatable, Sendable {
        case generate
        case parse
    }

    public var mode: Mode

    public var username: String
    public var password: String
    public var generateHasImportedCredentials: Bool

    public var parseInput: String
    public var parsedCredentials: BasicAuthCodec.Credentials?
    public var parseError: String?

    public init(
        mode: Mode = .generate,
        username: String = "",
        password: String = "",
        generateHasImportedCredentials: Bool = false,
        parseInput: String = "",
        parsedCredentials: BasicAuthCodec.Credentials? = nil,
        parseError: String? = nil
    ) {
        self.mode = mode
        self.username = username
        self.password = password
        self.generateHasImportedCredentials = generateHasImportedCredentials
        self.parseInput = parseInput
        self.parsedCredentials = parsedCredentials
        self.parseError = parseError
    }

    // MARK: - Derived

    public var output: String {
        if username.isEmpty, password.isEmpty, generateHasImportedCredentials {
            return BasicAuthCodec.authorizationHeader(
                credentials: .init(username: username, password: password)
            ) ?? ""
        }
        return BasicAuthCodec.authorizationHeader(username: username, password: password) ?? ""
    }

    public var outputDiagnostic: String? {
        switch BasicAuthCodec.validationIssue(username: username, password: password) {
        case .usernameContainsColon:
            return "用户名不能包含冒号。"
        case .credentialsContainControlCharacter:
            return "凭据不能包含控制字符。"
        case nil:
            return nil
        }
    }

    public var outputPlaceholder: String {
        outputDiagnostic ?? "填写凭据后自动生成"
    }

    public var hasGenerateContent: Bool {
        generateHasImportedCredentials || !username.isEmpty || !password.isEmpty || outputDiagnostic != nil
    }

    public var hasParseContent: Bool {
        !parseInput.isEmpty || parsedCredentials != nil || parseError != nil
    }

    public var hasAnyContent: Bool {
        hasGenerateContent || hasParseContent
    }

    // MARK: - Orchestration

    public mutating func parse() {
        parseError = nil
        let trimmed = parseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parsedCredentials = nil
            return
        }

        do {
            parsedCredentials = try BasicAuthCodec.parse(trimmed)
        } catch let error as BasicAuthCodec.ParseError {
            parsedCredentials = nil
            parseError = parseErrorMessage(error)
        } catch {
            parsedCredentials = nil
            parseError = "Basic Auth 解析失败。"
        }
    }

    public mutating func clearGenerate() {
        username = ""
        password = ""
        generateHasImportedCredentials = false
    }

    public mutating func clearParse() {
        parseInput = ""
        parsedCredentials = nil
        parseError = nil
    }

    public mutating func clearAll() {
        clearGenerate()
        clearParse()
    }

    public mutating func transferGeneratedToParse() {
        guard !output.isEmpty else { return }
        parseInput = output
        parse()
        mode = .parse
    }

    public mutating func transferParsedToGenerate() {
        guard let parsedCredentials else { return }
        username = parsedCredentials.username
        password = parsedCredentials.password
        generateHasImportedCredentials = true
        mode = .generate
    }

    // MARK: - Internals

    private func parseErrorMessage(_ error: BasicAuthCodec.ParseError) -> String {
        switch error {
        case .emptyInput:
            return ""
        case .unsupportedHeader:
            return "只支持 Authorization 请求头。"
        case .unsupportedScheme:
            return "认证方式不是 Basic。"
        case .invalidHeader:
            return "Basic Auth 请求头格式无效。"
        case .invalidBase64:
            return "凭据不是有效的 Base64。"
        case .invalidUTF8:
            return "凭据不是有效的 UTF-8 文本。"
        case .missingSeparator:
            return "解码后的凭据缺少用户名与密码之间的冒号。"
        case .credentialsContainControlCharacter:
            return "凭据不能包含控制字符。"
        }
    }
}
