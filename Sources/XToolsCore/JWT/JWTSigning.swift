import CryptoSwift
import Foundation

public enum JWTAlgorithm: String, CaseIterable, Equatable, Sendable {
    case hs256 = "HS256"
    case hs384 = "HS384"
    case hs512 = "HS512"

    public var minimumKeyByteCount: Int {
        switch self {
        case .hs256: return 32
        case .hs384: return 48
        case .hs512: return 64
        }
    }

    init?(headerValue: String) {
        self.init(rawValue: headerValue)
    }

    fileprivate var hmacVariant: HMAC.Variant {
        switch self {
        case .hs256: return .sha2(.sha256)
        case .hs384: return .sha2(.sha384)
        case .hs512: return .sha2(.sha512)
        }
    }
}

public enum JWTSecretEncoding: String, CaseIterable, Equatable, Sendable {
    case utf8
    case base64
}

public enum JWTSecretMaterial {
    public struct Resolved: Equatable, Sendable {
        public let bytes: [UInt8]

        public var byteCount: Int {
            bytes.count
        }
    }

    public enum ResolutionError: Error, Equatable {
        case emptySecret
        case invalidBase64
    }

    public static func resolve(_ secret: String, encoding: JWTSecretEncoding) throws -> Resolved {
        let bytes: [UInt8]

        switch encoding {
        case .utf8:
            bytes = Array(secret.utf8)
        case .base64:
            guard !secret.contains(where: \.isWhitespace) else {
                throw ResolutionError.invalidBase64
            }
            let data: Data
            do {
                data = try Base64Conversion.decodeData(secret)
            } catch {
                throw ResolutionError.invalidBase64
            }
            bytes = Array(data)
        }

        guard !bytes.isEmpty else {
            throw ResolutionError.emptySecret
        }
        return Resolved(bytes: bytes)
    }
}

enum JWTHMAC {
    static func digest(message: String, key: [UInt8], algorithm: JWTAlgorithm) throws -> [UInt8] {
        try HMAC(key: key, variant: algorithm.hmacVariant).authenticate(Array(message.utf8))
    }
}

public enum JWTSigner {
    public struct SigningConfig: Equatable, Sendable {
        public let algorithm: JWTAlgorithm
        public let payloadJSON: String
        public let advancedHeaderJSON: String
        public let secret: String
        public let secretEncoding: JWTSecretEncoding

        public init(
            algorithm: JWTAlgorithm,
            payloadJSON: String,
            advancedHeaderJSON: String,
            secret: String,
            secretEncoding: JWTSecretEncoding
        ) {
            self.algorithm = algorithm
            self.payloadJSON = payloadJSON
            self.advancedHeaderJSON = advancedHeaderJSON
            self.secret = secret
            self.secretEncoding = secretEncoding
        }
    }

    public struct SignedToken: Equatable, Sendable {
        public let token: String
        public let header: String
        public let payload: String

        public init(token: String, header: String, payload: String) {
            self.token = token
            self.header = header
            self.payload = payload
        }
    }

    public struct GenerationDraft: Equatable, Sendable {
        public let algorithm: JWTAlgorithm
        public let payloadJSON: String
        public let advancedHeaderJSON: String

        public init(algorithm: JWTAlgorithm, payloadJSON: String, advancedHeaderJSON: String) {
            self.algorithm = algorithm
            self.payloadJSON = payloadJSON
            self.advancedHeaderJSON = advancedHeaderJSON
        }
    }

    public enum SigningError: Error, Equatable {
        case emptyPayload
        case invalidPayloadJSON
        case payloadMustBeObject
        case duplicatePayloadKey
        case invalidAdvancedHeaderJSON
        case advancedHeaderMustBeObject
        case duplicateHeaderKey
        case algorithmOverride
        case unsupportedHeaderParameter(String)
        case invalidHeaderValue(String)
        case unsupportedAlgorithm(String)
        case invalidNumericDate(String)
        case emptySecret
        case invalidBase64Secret
        case weakKey(actualBytes: Int, requiredBytes: Int)
    }

    public static func headerPreview(
        algorithm: JWTAlgorithm,
        advancedHeaderJSON: String
    ) throws -> String {
        let header = try buildHeader(algorithm: algorithm, advancedHeaderJSON: advancedHeaderJSON)
        do {
            let data = try JSONSerialization.data(withJSONObject: header, options: [.prettyPrinted, .sortedKeys])
            guard let text = String(data: data, encoding: .utf8) else {
                throw SigningError.invalidAdvancedHeaderJSON
            }
            return text
        } catch let error as SigningError {
            throw error
        } catch {
            throw SigningError.invalidAdvancedHeaderJSON
        }
    }

    public static func generationDraft(
        headerJSON: String,
        payloadJSON: String
    ) throws -> GenerationDraft {
        let parsedHeader: ParsedJSONObject
        do {
            parsedHeader = try parseJSONObject(headerJSON)
        } catch {
            throw SigningError.invalidAdvancedHeaderJSON
        }
        guard let algorithmName = parsedHeader.object["alg"] as? String else {
            throw SigningError.invalidHeaderValue("alg")
        }
        guard let algorithm = JWTAlgorithm(headerValue: algorithmName) else {
            throw SigningError.unsupportedAlgorithm(algorithmName)
        }
        for parameter in ["crit", "b64"] where parsedHeader.object[parameter] != nil {
            throw SigningError.unsupportedHeaderParameter(parameter)
        }

        var advanced = parsedHeader.object
        advanced.removeValue(forKey: "alg")
        if advanced["typ"] as? String == "JWT" {
            advanced.removeValue(forKey: "typ")
        }

        let advancedHeaderJSON: String
        if advanced.isEmpty {
            advancedHeaderJSON = ""
        } else {
            do {
                let data = try JSONSerialization.data(withJSONObject: advanced, options: [.prettyPrinted, .sortedKeys])
                guard let text = String(data: data, encoding: .utf8) else {
                    throw SigningError.invalidAdvancedHeaderJSON
                }
                advancedHeaderJSON = text
            } catch let error as SigningError {
                throw error
            } catch {
                throw SigningError.invalidAdvancedHeaderJSON
            }
        }

        return GenerationDraft(
            algorithm: algorithm,
            payloadJSON: payloadJSON,
            advancedHeaderJSON: advancedHeaderJSON
        )
    }

    public static func sign(config: SigningConfig) throws -> SignedToken {
        let payload = try parsePayload(config.payloadJSON)
        let header = try buildHeader(
            algorithm: config.algorithm,
            advancedHeaderJSON: config.advancedHeaderJSON
        )
        let secret = try resolveSecret(config.secret, encoding: config.secretEncoding)

        guard secret.byteCount >= config.algorithm.minimumKeyByteCount else {
            throw SigningError.weakKey(
                actualBytes: secret.byteCount,
                requiredBytes: config.algorithm.minimumKeyByteCount
            )
        }

        let headerData: Data
        let prettyHeaderData: Data
        do {
            headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
            prettyHeaderData = try JSONSerialization.data(withJSONObject: header, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw SigningError.invalidAdvancedHeaderJSON
        }

        guard let prettyHeader = String(data: prettyHeaderData, encoding: .utf8) else {
            throw SigningError.invalidAdvancedHeaderJSON
        }

        let encodedHeader = Base64Conversion.encodeBase64URL(headerData)
        let encodedPayload = Base64Conversion.encodeBase64URL(Data(payload.minified.utf8))
        let signingInput = "\(encodedHeader).\(encodedPayload)"
        let digest = try JWTHMAC.digest(
            message: signingInput,
            key: secret.bytes,
            algorithm: config.algorithm
        )
        let signature = Base64Conversion.encodeBase64URL(Data(digest))

        return SignedToken(
            token: "\(signingInput).\(signature)",
            header: prettyHeader,
            payload: payload.pretty
        )
    }

    private static func resolveSecret(
        _ secret: String,
        encoding: JWTSecretEncoding
    ) throws -> JWTSecretMaterial.Resolved {
        do {
            return try JWTSecretMaterial.resolve(secret, encoding: encoding)
        } catch JWTSecretMaterial.ResolutionError.emptySecret {
            throw SigningError.emptySecret
        } catch JWTSecretMaterial.ResolutionError.invalidBase64 {
            throw SigningError.invalidBase64Secret
        } catch {
            throw SigningError.invalidBase64Secret
        }
    }

    private static func parsePayload(_ source: String) throws -> ParsedJSONObject {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SigningError.emptyPayload
        }

        let parsed: ParsedJSONObject
        do {
            parsed = try parseJSONObject(trimmed)
        } catch JSONObjectError.invalidJSON {
            throw SigningError.invalidPayloadJSON
        } catch JSONObjectError.notObject {
            throw SigningError.payloadMustBeObject
        } catch JSONObjectError.duplicateKey {
            throw SigningError.duplicatePayloadKey
        }

        for name in ["exp", "nbf", "iat"] {
            guard let value = parsed.object[name] else { continue }
            guard !(value is Bool),
                  let number = value as? NSNumber,
                  number.doubleValue.isFinite else {
                throw SigningError.invalidNumericDate(name)
            }
        }

        return parsed
    }

    private static func buildHeader(
        algorithm: JWTAlgorithm,
        advancedHeaderJSON: String
    ) throws -> [String: Any] {
        var header: [String: Any] = [
            "alg": algorithm.rawValue,
            "typ": "JWT"
        ]
        let trimmed = advancedHeaderJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return header
        }

        let parsed: ParsedJSONObject
        do {
            parsed = try parseJSONObject(trimmed)
        } catch JSONObjectError.invalidJSON {
            throw SigningError.invalidAdvancedHeaderJSON
        } catch JSONObjectError.notObject {
            throw SigningError.advancedHeaderMustBeObject
        } catch JSONObjectError.duplicateKey {
            throw SigningError.duplicateHeaderKey
        }

        if parsed.object["alg"] != nil {
            throw SigningError.algorithmOverride
        }
        for parameter in ["crit", "b64"] where parsed.object[parameter] != nil {
            throw SigningError.unsupportedHeaderParameter(parameter)
        }
        for name in ["typ", "cty", "kid"] {
            if let value = parsed.object[name], !(value is String) {
                throw SigningError.invalidHeaderValue(name)
            }
        }

        for (key, value) in parsed.object {
            header[key] = value
        }
        return header
    }

    private struct ParsedJSONObject {
        let minified: String
        let pretty: String
        let object: [String: Any]
    }

    private enum JSONObjectError: Error {
        case invalidJSON
        case notObject
        case duplicateKey
    }

    private static func parseJSONObject(_ source: String) throws -> ParsedJSONObject {
        let minifiedResult: JSONFormatting.FormattingResult
        let pretty: String
        do {
            minifiedResult = try JSONFormatting.minifyResult(source)
            pretty = try JSONFormatting.format(source, sortKeys: true, indentWidth: 2)
        } catch {
            throw JSONObjectError.invalidJSON
        }

        if minifiedResult.warning != nil {
            throw JSONObjectError.duplicateKey
        }

        guard let data = minifiedResult.text.data(using: .utf8) else {
            throw JSONObjectError.invalidJSON
        }
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw JSONObjectError.invalidJSON
        }
        guard let object = value as? [String: Any] else {
            throw JSONObjectError.notObject
        }

        return ParsedJSONObject(minified: minifiedResult.text, pretty: pretty, object: object)
    }
}
