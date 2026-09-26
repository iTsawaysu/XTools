import Foundation

public enum JWTVerifier {
    public struct VerificationConfig: Equatable, Sendable {
        public let secret: String?
        public let secretEncoding: JWTSecretEncoding

        public init(secret: String?, secretEncoding: JWTSecretEncoding = .utf8) {
            self.secret = secret
            self.secretEncoding = secretEncoding
        }
    }

    public enum SignatureStatus: Equatable, Sendable {
        case notVerified
        case verified
        case failed
    }

    public enum Summary: Equatable, Sendable {
        case notVerified
        case verified
        case failed
    }

    public struct VerificationResult: Equatable, Sendable {
        public let summary: Summary
        public let signatureStatus: SignatureStatus
        public let details: [VerificationItem]

        public var isValid: Bool {
            summary == .verified
        }

        public var hasSecurityWarning: Bool {
            details.contains { $0.status == .warning }
        }

        public init(
            summary: Summary,
            signatureStatus: SignatureStatus,
            details: [VerificationItem]
        ) {
            self.summary = summary
            self.signatureStatus = signatureStatus
            self.details = details
        }

        /// Compatibility initializer for page-local error fallbacks while callers
        /// migrate to the explicit summary/signature model.
        public init(isValid: Bool, details: [VerificationItem]) {
            self.summary = isValid ? .verified : .failed
            self.signatureStatus = isValid ? .verified : .failed
            self.details = details
        }
    }

    public struct VerificationItem: Equatable, Sendable {
        public let name: String
        public let status: Status
        public let message: String
        public let category: Category
        /// 签名检查的结构化归因。展示层按它派生标题，而不是反查 message
        /// 字符串——那样文案一改标题映射就会静默失效。
        public let reason: Reason?

        public var passed: Bool {
            status == .passed || status == .informational
        }

        public enum Status: Equatable, Sendable {
            case passed
            case failed
            case warning
            case informational
        }

        public enum Category: Equatable, Sendable {
            case signature
            case expiration
            case claims
            case security
        }

        public enum Reason: Equatable, Sendable {
            case signatureMismatch
            case unsupportedAlgorithm
            case invalidSecretBase64
        }

        public init(
            name: String,
            status: Status,
            message: String,
            category: Category,
            reason: Reason? = nil
        ) {
            self.name = name
            self.status = status
            self.message = message
            self.category = category
            self.reason = reason
        }

        public init(name: String, passed: Bool, message: String, category: Category) {
            self.init(
                name: name,
                status: passed ? .passed : .failed,
                message: message,
                category: category
            )
        }
    }

    public enum VerificationError: Error, Equatable, LocalizedError {
        case missingAlgorithm
        case unsupportedAlgorithm(String)
        case missingSecret
        case invalidSignature
        case parseError

        /// 验证失败的文案以 core 为单一真相源；会话层直接透传，
        /// 避免 core 更新文案时页面停留旧版。
        public var errorDescription: String? {
            switch self {
            case .missingAlgorithm:
                return "JWT Header 缺少 alg。"
            case .unsupportedAlgorithm:
                return "JWT 使用了当前不支持的签名算法。"
            case .missingSecret:
                return "Secret 不能为空。"
            case .invalidSignature:
                return "JWT 签名无效。"
            case .parseError:
                return "JWT 格式无效，无法执行本地检查。"
            }
        }
    }

    public static func verify(token: String, config: VerificationConfig) throws -> VerificationResult {
        var details: [VerificationItem] = []

        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else {
            throw VerificationError.parseError
        }

        let headerData: Data
        do {
            headerData = try JWTBase64URL.decode(parts[0])
        } catch {
            throw VerificationError.parseError
        }
        guard let headerJSON = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let algorithmName = headerJSON["alg"] as? String else {
            throw VerificationError.missingAlgorithm
        }

        let signatureStatus = verifySignature(
            token: value,
            algorithmName: algorithmName,
            config: config,
            details: &details
        )

        let payloadData: Data
        do {
            payloadData = try JWTBase64URL.decode(parts[1])
        } catch {
            throw VerificationError.parseError
        }
        guard let payloadJSON = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw VerificationError.parseError
        }

        let claimsResult = verifyClaims(payload: payloadJSON)
        details.append(contentsOf: claimsResult.details)

        let summary: Summary
        if signatureStatus == .failed || !claimsResult.isValid {
            summary = .failed
        } else if signatureStatus == .notVerified {
            summary = .notVerified
        } else {
            summary = .verified
        }

        return VerificationResult(
            summary: summary,
            signatureStatus: signatureStatus,
            details: details
        )
    }

    private static func verifySignature(
        token: String,
        algorithmName: String,
        config: VerificationConfig,
        details: inout [VerificationItem]
    ) -> SignatureStatus {
        guard let secretText = config.secret, !secretText.isEmpty else {
            details.append(VerificationItem(
                name: "签名",
                status: .warning,
                message: "未提供 Secret，签名未验证。",
                category: .signature
            ))
            return .notVerified
        }

        let secret: JWTSecretMaterial.Resolved
        do {
            secret = try JWTSecretMaterial.resolve(secretText, encoding: config.secretEncoding)
        } catch JWTSecretMaterial.ResolutionError.invalidBase64 {
            details.append(VerificationItem(
                name: "签名",
                status: .failed,
                message: "Secret 不是有效的 Base64。",
                category: .signature,
                reason: .invalidSecretBase64
            ))
            return .failed
        } catch {
            details.append(VerificationItem(
                name: "签名",
                status: .failed,
                message: "Secret 不能为空。",
                category: .signature
            ))
            return .failed
        }

        guard let algorithm = JWTAlgorithm(headerValue: algorithmName) else {
            details.append(VerificationItem(
                name: "签名",
                status: .failed,
                message: "JWT 使用了当前不支持的签名算法。",
                category: .signature,
                reason: .unsupportedAlgorithm
            ))
            return .failed
        }

        let signaturePassed = verifyHMACSignature(
            token: token,
            key: secret.bytes,
            algorithm: algorithm
        )
        details.append(VerificationItem(
            name: "签名",
            status: signaturePassed ? .passed : .failed,
            message: signaturePassed ? "匹配 (\(algorithm.rawValue))" : "不匹配",
            category: .signature,
            reason: signaturePassed ? nil : .signatureMismatch
        ))

        if secret.byteCount < algorithm.minimumKeyByteCount {
            details.append(VerificationItem(
                name: "密钥强度",
                status: .warning,
                message: "当前密钥为 \(secret.byteCount) 字节，低于 \(algorithm.rawValue) 的 \(algorithm.minimumKeyByteCount) 字节安全基线。",
                category: .security
            ))
        }

        return signaturePassed ? .verified : .failed
    }

    private static func verifyHMACSignature(
        token: String,
        key: [UInt8],
        algorithm: JWTAlgorithm
    ) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else {
            return false
        }

        let message = "\(parts[0]).\(parts[1])"
        let signature = parts[2]
        guard let computedDigest = try? JWTHMAC.digest(message: message, key: key, algorithm: algorithm),
              let providedSignature = try? JWTBase64URL.decode(signature) else {
            return false
        }

        return constantTimeEquals(Array(providedSignature), computedDigest)
    }

    private static func verifyClaims(payload: [String: Any]) -> (isValid: Bool, details: [VerificationItem]) {
        var details: [VerificationItem] = []
        var isValid = true
        let now = Date().timeIntervalSince1970

        if let expValue = payload["exp"] {
            guard let exp = JWTNumericDate.timestamp(expValue) else {
                details.append(invalidNumericDateItem(name: "过期时间 (exp)", category: .expiration))
                return (false, details)
            }
            let passed = now < exp
            let message = passed
                ? "未过期（\(formatDate(exp))）"
                : "已过期（\(formatDate(exp))）"
            details.append(VerificationItem(
                name: "过期时间 (exp)",
                status: passed ? .passed : .failed,
                message: message,
                category: .expiration
            ))
            if !passed {
                isValid = false
            }
        }

        if let nbfValue = payload["nbf"] {
            guard let nbf = JWTNumericDate.timestamp(nbfValue) else {
                details.append(invalidNumericDateItem(name: "生效时间 (nbf)", category: .expiration))
                return (false, details)
            }
            let passed = now >= nbf
            let message = passed
                ? "已生效"
                : "尚未生效（生效时间：\(formatDate(nbf))）"
            details.append(VerificationItem(
                name: "生效时间 (nbf)",
                status: passed ? .passed : .failed,
                message: message,
                category: .expiration
            ))
            if !passed {
                isValid = false
            }
        }

        if let iatValue = payload["iat"] {
            guard let iat = JWTNumericDate.timestamp(iatValue) else {
                details.append(invalidNumericDateItem(name: "签发时间 (iat)", category: .claims))
                return (false, details)
            }
            details.append(VerificationItem(
                name: "签发时间 (iat)",
                status: .informational,
                message: formatDate(iat),
                category: .claims
            ))
        }

        return (isValid, details)
    }

    private static func invalidNumericDateItem(
        name: String,
        category: VerificationItem.Category
    ) -> VerificationItem {
        VerificationItem(
            name: name,
            status: .failed,
            message: "不是有效的 NumericDate 数字时间戳",
            category: category
        )
    }

    private static func constantTimeEquals(_ left: [UInt8], _ right: [UInt8]) -> Bool {
        let count = max(left.count, right.count)
        var difference = left.count ^ right.count

        for index in 0..<count {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= Int(leftByte ^ rightByte)
        }

        return difference == 0
    }

    private static func formatDate(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}
