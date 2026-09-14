import Foundation

extension JWTWorkspaceSession {
    public struct LocalCheckPresentation: Equatable, Sendable {
        public struct Axis: Equatable, Sendable {
            public enum Status: Equatable, Sendable {
                case informational
                case passed
                case warning
                case failed
            }

            public let title: String
            public let message: String
            public let status: Status

            public init(title: String, message: String, status: Status) {
                self.title = title
                self.message = message
                self.status = status
            }
        }

        public let signature: Axis
        public let timeClaims: Axis
        public let scopeStatement: String
        public let details: [JWTVerifier.VerificationItem]

        public var summaryText: String {
            "\(signature.title) · \(timeClaims.title)"
        }

        public init(
            signature: Axis,
            timeClaims: Axis,
            scopeStatement: String,
            details: [JWTVerifier.VerificationItem]
        ) {
            self.signature = signature
            self.timeClaims = timeClaims
            self.scopeStatement = scopeStatement
            self.details = details
        }
    }

    public static let localCheckScopeStatement =
        "未检查 issuer、audience、subject、token type 和业务授权规则；结果不代表具体应用会接受此 Token。"

    public var localCheckPresentation: LocalCheckPresentation? {
        verificationResult.map(Self.localCheckPresentation(for:))
    }

    public static func localCheckPresentation(
        for result: JWTVerifier.VerificationResult
    ) -> LocalCheckPresentation {
        LocalCheckPresentation(
            signature: signaturePresentation(for: result),
            timeClaims: timeClaimsPresentation(for: result),
            scopeStatement: localCheckScopeStatement,
            details: result.details.filter { $0.category != .signature }
        )
    }

    private static func signaturePresentation(
        for result: JWTVerifier.VerificationResult
    ) -> LocalCheckPresentation.Axis {
        let detail = result.details.first { $0.category == .signature }
        let message = detail?.message ?? "没有可显示的签名检查明细。"

        switch result.signatureStatus {
        case .notVerified:
            return .init(
                title: "签名未检查",
                message: message,
                status: .informational
            )
        case .verified:
            let hasWarning = result.hasSecurityWarning
            return .init(
                title: hasWarning ? "签名匹配 · 密钥有警告" : "签名匹配",
                message: message,
                status: hasWarning ? .warning : .passed
            )
        case .failed:
            return .init(
                title: failedSignatureTitle(message: message),
                message: message,
                status: .failed
            )
        }
    }

    private static func failedSignatureTitle(message: String) -> String {
        switch message {
        case "不匹配":
            return "签名不匹配"
        case "JWT 使用了当前不支持的签名算法。":
            return "签名算法不支持"
        case "Secret 不是有效的 Base64。":
            return "Secret 格式错误"
        default:
            return "签名检查失败"
        }
    }

    private static func timeClaimsPresentation(
        for result: JWTVerifier.VerificationResult
    ) -> LocalCheckPresentation.Axis {
        let timeDetails = result.details.filter {
            $0.category == .expiration || $0.category == .claims
        }
        guard !timeDetails.isEmpty else {
            return .init(
                title: "没有时间声明",
                message: "未发现 exp、nbf 或 iat。",
                status: .informational
            )
        }

        if let failure = timeDetails.first(where: { $0.status == .failed }) {
            return .init(
                title: "时间声明有问题",
                message: failure.message,
                status: .failed
            )
        }

        return .init(
            title: "时间声明通过",
            message: "已检查 \(timeDetails.count) 项时间声明。",
            status: .passed
        )
    }
}
