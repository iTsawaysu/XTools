import Foundation

/// Pure workspace session for the JWT 双向结构化工具 page.
/// Owns generate/parse drafts, diagnostics, verification, transfer, and clear.
/// SwiftUI views bind to these fields and call mutating methods only.
public struct JWTWorkspaceSession: Equatable, Sendable {
    public enum Mode: String, Equatable, Sendable {
        case generate
        case parse
    }

    public static let defaultGeneratePayload = """
    {
      "sub": "1234567890",
      "name": "John Doe"
    }
    """

    public var mode: Mode

    public var generateAlgorithm: JWTAlgorithm
    public var generatePayload: String
    public var generateAdditionalHeaderJSON: String
    public var generateSecret: String
    public var generateSecretEncoding: JWTSecretEncoding
    public var generatedHeader: String
    public var generatedToken: String
    public var generationHeaderError: String?
    public var generationPayloadError: String?
    public var generationSecretError: String?

    public var parseInput: String
    public var parsedHeader: String
    public var parsedPayload: String
    public var registeredClaimInsights: [JWTRegisteredClaimInsight]
    public var parseError: String?
    public var parseSecret: String
    public var parseSecretEncoding: JWTSecretEncoding
    public var verificationResult: JWTVerifier.VerificationResult?
    public var transferError: String?

    public init(
        mode: Mode = .parse,
        generateAlgorithm: JWTAlgorithm = .hs256,
        generatePayload: String = JWTWorkspaceSession.defaultGeneratePayload,
        generateAdditionalHeaderJSON: String = "",
        generateSecret: String = "",
        generateSecretEncoding: JWTSecretEncoding = .utf8,
        generatedHeader: String = "",
        generatedToken: String = "",
        generationHeaderError: String? = nil,
        generationPayloadError: String? = nil,
        generationSecretError: String? = nil,
        parseInput: String = "",
        parsedHeader: String = "",
        parsedPayload: String = "",
        registeredClaimInsights: [JWTRegisteredClaimInsight] = [],
        parseError: String? = nil,
        parseSecret: String = "",
        parseSecretEncoding: JWTSecretEncoding = .utf8,
        verificationResult: JWTVerifier.VerificationResult? = nil,
        transferError: String? = nil
    ) {
        self.mode = mode
        self.generateAlgorithm = generateAlgorithm
        self.generatePayload = generatePayload
        self.generateAdditionalHeaderJSON = generateAdditionalHeaderJSON
        self.generateSecret = generateSecret
        self.generateSecretEncoding = generateSecretEncoding
        self.generatedHeader = generatedHeader
        self.generatedToken = generatedToken
        self.generationHeaderError = generationHeaderError
        self.generationPayloadError = generationPayloadError
        self.generationSecretError = generationSecretError
        self.parseInput = parseInput
        self.parsedHeader = parsedHeader
        self.parsedPayload = parsedPayload
        self.registeredClaimInsights = registeredClaimInsights
        self.parseError = parseError
        self.parseSecret = parseSecret
        self.parseSecretEncoding = parseSecretEncoding
        self.verificationResult = verificationResult
        self.transferError = transferError
    }

    public var hasGenerateContent: Bool {
        generateAlgorithm != .hs256
            || generateSecretEncoding != .utf8
            || !generatePayload.isEmpty
            || !generateAdditionalHeaderJSON.isEmpty
            || !generateSecret.isEmpty
            || !generatedToken.isEmpty
            || generationHeaderError != nil
            || generationPayloadError != nil
            || generationSecretError != nil
    }

    public var hasParseContent: Bool {
        parseSecretEncoding != .utf8
            || !parseInput.isEmpty
            || !parsedHeader.isEmpty
            || !parsedPayload.isEmpty
            || !registeredClaimInsights.isEmpty
            || !parseSecret.isEmpty
            || parseError != nil
            || verificationResult != nil
    }

    public var hasAnyContent: Bool {
        hasGenerateContent || hasParseContent
    }

    public mutating func refreshGeneration() {
        generationHeaderError = nil
        generationPayloadError = nil
        generationSecretError = nil
        generatedToken = ""

        do {
            generatedHeader = try JWTSigner.headerPreview(
                algorithm: generateAlgorithm,
                advancedHeaderJSON: generateAdditionalHeaderJSON
            )
        } catch let error as JWTSigner.SigningError {
            generatedHeader = ""
            generationHeaderError = generationErrorMessage(error)
            return
        } catch {
            generatedHeader = ""
            generationHeaderError = "JWT Header 生成失败。"
            return
        }

        do {
            let result = try JWTSigner.sign(config: .init(
                algorithm: generateAlgorithm,
                payloadJSON: generatePayload,
                advancedHeaderJSON: generateAdditionalHeaderJSON,
                secret: generateSecret,
                secretEncoding: generateSecretEncoding
            ))
            generatedHeader = result.header
            generatedToken = result.token
        } catch let error as JWTSigner.SigningError {
            applyGenerationError(error)
        } catch {
            generationPayloadError = "JWT 生成失败。"
        }
    }

    public mutating func parse() {
        parseError = nil
        transferError = nil
        let value = parseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            parsedHeader = ""
            parsedPayload = ""
            registeredClaimInsights = []
            verificationResult = nil
            return
        }

        do {
            let decoded = try JWTParser.parse(value)
            parsedHeader = decoded.header
            parsedPayload = decoded.payload
            registeredClaimInsights = (try? JWTRegisteredClaimInterpreter.interpret(
                payloadJSON: decoded.payload
            )) ?? []
            verify()
        } catch let error as JWTParser.ParseError {
            // ParseError 全 case 都有 errorDescription；文案以 core 为单一真相源，
            // 会话层不再复制——否则 core 更新文案时页面会静默停留旧版。
            clearParsedResult(error: error.errorDescription ?? "JWT 解析失败。")
        } catch {
            clearParsedResult(error: "JWT 解析失败。")
        }
    }

    public mutating func verify() {
        let value = parseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !parsedHeader.isEmpty, !parsedPayload.isEmpty else {
            verificationResult = nil
            return
        }

        do {
            verificationResult = try JWTVerifier.verify(
                token: value,
                config: .init(
                    secret: parseSecret.isEmpty ? nil : parseSecret,
                    secretEncoding: parseSecretEncoding
                )
            )
        } catch let error as JWTVerifier.VerificationError {
            verificationResult = verificationFailureResult(
                message: error.errorDescription ?? "JWT 本地检查失败。"
            )
        } catch {
            verificationResult = verificationFailureResult(message: "JWT 本地检查失败。")
        }
    }

    public mutating func clearGenerate() {
        generateAlgorithm = .hs256
        generatePayload = ""
        generateAdditionalHeaderJSON = ""
        generateSecret = ""
        generateSecretEncoding = .utf8
        generatedToken = ""
        generationHeaderError = nil
        generationPayloadError = nil
        generationSecretError = nil
        refreshGeneration()
    }

    public mutating func clearParse() {
        parseInput = ""
        parsedHeader = ""
        parsedPayload = ""
        registeredClaimInsights = []
        parseError = nil
        parseSecret = ""
        parseSecretEncoding = .utf8
        verificationResult = nil
        transferError = nil
    }

    public mutating func clearAll() {
        clearGenerate()
        clearParse()
    }

    public mutating func transferGeneratedToParse() {
        guard !generatedToken.isEmpty else { return }
        parseInput = generatedToken
        parseSecret = generateSecret
        parseSecretEncoding = generateSecretEncoding
        parse()
        mode = .parse
    }

    public mutating func transferParsedToGenerate() {
        guard !parsedHeader.isEmpty, !parsedPayload.isEmpty else { return }
        transferError = nil
        do {
            let draft = try JWTSigner.generationDraft(
                headerJSON: parsedHeader,
                payloadJSON: parsedPayload
            )
            generateAlgorithm = draft.algorithm
            generatePayload = draft.payloadJSON
            generateAdditionalHeaderJSON = draft.advancedHeaderJSON
            generateSecret = parseSecret
            generateSecretEncoding = parseSecret.isEmpty ? .utf8 : parseSecretEncoding
            refreshGeneration()
            mode = .generate
        } catch let error as JWTSigner.SigningError {
            transferError = generationErrorMessage(error)
        } catch {
            transferError = "当前 JWT 无法转换为生成参数。"
        }
    }

    public func verificationSummaryText(_ result: JWTVerifier.VerificationResult) -> String {
        Self.localCheckPresentation(for: result).summaryText
    }

    // MARK: - Internals

    private mutating func applyGenerationError(_ error: JWTSigner.SigningError) {
        switch error {
        case .emptyPayload:
            break
        case .invalidPayloadJSON:
            generationPayloadError = "Payload 不是有效的 JSON。"
        case .payloadMustBeObject:
            generationPayloadError = "Payload 必须是 JSON 对象。"
        case .duplicatePayloadKey:
            generationPayloadError = "Payload 不能包含重复 key。"
        case .invalidNumericDate(let claim):
            generationPayloadError = "\(claim) 必须是有效的 NumericDate 数字。"
        case .emptySecret:
            break
        case .invalidBase64Secret:
            generationSecretError = "Secret 不是有效的 Base64。"
        case .weakKey(let actualBytes, let requiredBytes):
            generationSecretError = "当前密钥为 \(actualBytes) 字节，\(generateAlgorithm.rawValue) 至少需要 \(requiredBytes) 字节。"
        default:
            generationHeaderError = generationErrorMessage(error)
        }
    }

    private func generationErrorMessage(_ error: JWTSigner.SigningError) -> String {
        switch error {
        case .invalidAdvancedHeaderJSON:
            return "Header 不是有效的 JSON。"
        case .advancedHeaderMustBeObject:
            return "Header 必须是 JSON 对象。"
        case .duplicateHeaderKey:
            return "Header 不能包含重复 key。"
        case .algorithmOverride:
            return "Header 不能覆盖算法选择器中的 alg。"
        case .unsupportedHeaderParameter:
            return "JWT Header 包含当前不支持的参数。"
        case .invalidHeaderValue:
            return "JWT Header 包含值无效的字段。"
        case .unsupportedAlgorithm:
            return "JWT 使用了当前不支持的签名算法。"
        case .invalidPayloadJSON:
            return "Payload 不是有效的 JSON。"
        case .payloadMustBeObject:
            return "Payload 必须是 JSON 对象。"
        case .duplicatePayloadKey:
            return "Payload 不能包含重复 key。"
        case .invalidNumericDate(let claim):
            return "\(claim) 必须是有效的 NumericDate 数字。"
        case .emptyPayload, .emptySecret:
            return ""
        case .invalidBase64Secret:
            return "Secret 不是有效的 Base64。"
        case .weakKey(let actualBytes, let requiredBytes):
            return "当前密钥为 \(actualBytes) 字节，至少需要 \(requiredBytes) 字节。"
        }
    }

    private mutating func clearParsedResult(error: String) {
        parsedHeader = ""
        parsedPayload = ""
        registeredClaimInsights = []
        verificationResult = nil
        parseError = error
    }

    private func verificationFailureResult(message: String) -> JWTVerifier.VerificationResult {
        JWTVerifier.VerificationResult(
            summary: .failed,
            signatureStatus: .failed,
            details: [
                .init(name: "本地检查", status: .failed, message: message, category: .signature)
            ]
        )
    }
}
