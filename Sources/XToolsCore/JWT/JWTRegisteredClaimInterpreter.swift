import Foundation

public struct JWTRegisteredClaimInsight: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        case issuer = "iss"
        case subject = "sub"
        case audience = "aud"
        case expiration = "exp"
        case notBefore = "nbf"
        case issuedAt = "iat"
        case jwtID = "jti"

        public var title: String {
            switch self {
            case .issuer: return "签发方"
            case .subject: return "主题"
            case .audience: return "受众"
            case .expiration: return "过期时间"
            case .notBefore: return "生效时间"
            case .issuedAt: return "签发时间"
            case .jwtID: return "JWT ID"
            }
        }
    }

    public enum Status: Equatable, Sendable {
        case informational
        case passed
        case warning
        case failed
    }

    public let kind: Kind
    public let displayValue: String
    public let explanation: String
    public let status: Status

    public var id: Kind { kind }

    public init(
        kind: Kind,
        displayValue: String,
        explanation: String,
        status: Status
    ) {
        self.kind = kind
        self.displayValue = displayValue
        self.explanation = explanation
        self.status = status
    }
}

/// Interprets the registered claims that can be explained without application
/// trust context. It never performs issuer, audience, subject, or authorization
/// validation.
public enum JWTRegisteredClaimInterpreter {
    public enum InterpretationError: Error, Equatable {
        case invalidPayloadJSON
    }

    public static func interpret(
        payloadJSON: String,
        now: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) throws -> [JWTRegisteredClaimInsight] {
        guard let data = payloadJSON.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InterpretationError.invalidPayloadJSON
        }

        var dateFormatter: DateFormatter?
        return JWTRegisteredClaimInsight.Kind.allCases.compactMap { kind in
            guard let value = payload[kind.rawValue] else { return nil }
            switch kind {
            case .issuer, .subject, .jwtID:
                return stringInsight(kind: kind, value: value)
            case .audience:
                return audienceInsight(value: value)
            case .expiration, .notBefore, .issuedAt:
                let formatter = dateFormatter ?? makeDateFormatter(timeZone: timeZone)
                dateFormatter = formatter
                return numericDateInsight(
                    kind: kind,
                    value: value,
                    now: now,
                    dateFormatter: formatter
                )
            }
        }
    }

    private static func stringInsight(
        kind: JWTRegisteredClaimInsight.Kind,
        value: Any
    ) -> JWTRegisteredClaimInsight {
        guard let string = value as? String else {
            return invalidTypeInsight(
                kind: kind,
                expectedType: "字符串"
            )
        }

        return JWTRegisteredClaimInsight(
            kind: kind,
            displayValue: string.isEmpty ? "空字符串" : string,
            explanation: "仅展示原始值；未按应用上下文检查。",
            status: .informational
        )
    }

    private static func audienceInsight(value: Any) -> JWTRegisteredClaimInsight {
        if let audience = value as? String {
            return JWTRegisteredClaimInsight(
                kind: .audience,
                displayValue: audience.isEmpty ? "空字符串" : audience,
                explanation: "单个受众；未按应用上下文检查。",
                status: .informational
            )
        }

        if let values = value as? [Any],
           values.allSatisfy({ $0 is String }) {
            let audiences = values.compactMap { $0 as? String }
            return JWTRegisteredClaimInsight(
                kind: .audience,
                displayValue: audiences.isEmpty ? "空数组" : audiences.joined(separator: " · "),
                explanation: "\(audiences.count) 个受众；未按应用上下文检查。",
                status: .informational
            )
        }

        return invalidTypeInsight(
            kind: .audience,
            expectedType: "字符串或字符串数组"
        )
    }

    private static func numericDateInsight(
        kind: JWTRegisteredClaimInsight.Kind,
        value: Any,
        now: Date,
        dateFormatter: DateFormatter
    ) -> JWTRegisteredClaimInsight {
        guard let timestamp = numericDate(value) else {
            return JWTRegisteredClaimInsight(
                kind: kind,
                displayValue: "类型不符合注册声明定义",
                explanation: "\(kind.rawValue) 必须是 NumericDate 数字。",
                status: .failed
            )
        }

        let explanation: String
        let status: JWTRegisteredClaimInsight.Status
        switch kind {
        case .expiration:
            let isCurrent = now.timeIntervalSince1970 < timestamp
            explanation = isCurrent ? "未过期" : "已过期"
            status = isCurrent ? .passed : .failed
        case .notBefore:
            let isCurrent = now.timeIntervalSince1970 >= timestamp
            explanation = isCurrent ? "已生效" : "尚未生效"
            status = isCurrent ? .passed : .failed
        case .issuedAt:
            explanation = "仅解释签发时间，不判断发行策略。"
            status = .informational
        case .issuer, .subject, .audience, .jwtID:
            preconditionFailure("Only NumericDate claims can reach this branch")
        }

        return JWTRegisteredClaimInsight(
            kind: kind,
            displayValue: "\(dateFormatter.string(from: Date(timeIntervalSince1970: timestamp)))（本机时区）",
            explanation: explanation,
            status: status
        )
    }

    private static func invalidTypeInsight(
        kind: JWTRegisteredClaimInsight.Kind,
        expectedType: String
    ) -> JWTRegisteredClaimInsight {
        JWTRegisteredClaimInsight(
            kind: kind,
            displayValue: "类型不符合注册声明定义",
            explanation: "\(kind.rawValue) 应为\(expectedType)；未按应用上下文检查。",
            status: .warning
        )
    }

    private static func numericDate(_ value: Any) -> TimeInterval? {
        guard !(value is Bool), let number = value as? NSNumber else {
            return nil
        }
        let timestamp = number.doubleValue
        return timestamp.isFinite ? timestamp : nil
    }

    private static func makeDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}
