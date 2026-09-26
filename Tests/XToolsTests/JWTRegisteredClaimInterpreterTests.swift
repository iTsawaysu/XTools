import XToolsCore
import Foundation
import Testing

struct JWTRegisteredClaimInterpreterTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let utc = TimeZone(secondsFromGMT: 0)!

    @Test func interpretsRegisteredClaimsInStableOrder() throws {
        let insights = try JWTRegisteredClaimInterpreter.interpret(
            payloadJSON: #"{"iss":"https://issuer.example","sub":"user-42","aud":["api://one","api://two"],"exp":1700003600,"nbf":1699999940,"iat":1699999940,"jti":"token-7","custom":true}"#,
            now: now,
            timeZone: utc
        )

        #expect(insights.map(\.kind) == [
            .issuer, .subject, .audience, .expiration, .notBefore, .issuedAt, .jwtID
        ])

        let expiration = try #require(insights.first { $0.kind == .expiration })
        #expect(expiration.status == .passed)
        #expect(expiration.displayValue == "2023-11-14 23:13:20（本机时区）")
        #expect(expiration.explanation == "未过期")

        let notBefore = try #require(insights.first { $0.kind == .notBefore })
        #expect(notBefore.status == .passed)
        #expect(notBefore.explanation == "已生效")

        let issuedAt = try #require(insights.first { $0.kind == .issuedAt })
        #expect(issuedAt.status == .informational)
        #expect(issuedAt.explanation.contains("仅解释"))

        let audience = try #require(insights.first { $0.kind == .audience })
        #expect(audience.displayValue == "api://one · api://two")
        #expect(audience.explanation == "2 个受众；未按应用上下文检查。")
    }

    @Test func numericDateBoundariesMatchRFCComparisonRules() throws {
        let insights = try JWTRegisteredClaimInterpreter.interpret(
            payloadJSON: #"{"exp":1700000000,"nbf":1700000000,"iat":1700000000.5}"#,
            now: now,
            timeZone: utc
        )

        #expect(insights.first { $0.kind == .expiration }?.status == .failed)
        #expect(insights.first { $0.kind == .expiration }?.explanation == "已过期")
        #expect(insights.first { $0.kind == .notBefore }?.status == .passed)
        #expect(insights.first { $0.kind == .notBefore }?.explanation == "已生效")
        #expect(insights.first { $0.kind == .issuedAt }?.status == .informational)
    }

    @Test func zeroAndOneAreNumericDatesForEveryClaim() throws {
        for numeric in [0, 1] {
            let insights = try JWTRegisteredClaimInterpreter.interpret(
                payloadJSON: "{\"exp\":\(numeric),\"nbf\":\(numeric),\"iat\":\(numeric)}",
                now: now,
                timeZone: utc
            )

            let exp = try #require(insights.first { $0.kind == .expiration })
            let nbf = try #require(insights.first { $0.kind == .notBefore })
            let iat = try #require(insights.first { $0.kind == .issuedAt })
            let display = "1970-01-01 00:00:0\(numeric)（本机时区）"

            #expect(exp.status == .failed)
            #expect(exp.explanation == "已过期")
            #expect(exp.displayValue == display)
            #expect(nbf.status == .passed)
            #expect(nbf.explanation == "已生效")
            #expect(nbf.displayValue == display)
            #expect(iat.status == .informational)
            #expect(iat.displayValue == display)
        }
    }

    @Test func booleansAreNotNumericDatesForEveryClaim() throws {
        for literal in ["true", "false"] {
            let insights = try JWTRegisteredClaimInterpreter.interpret(
                payloadJSON: "{\"exp\":\(literal),\"nbf\":\(literal),\"iat\":\(literal)}",
                now: now,
                timeZone: utc
            )

            for kind in [
                JWTRegisteredClaimInsight.Kind.expiration,
                .notBefore,
                .issuedAt
            ] {
                let insight = try #require(insights.first { $0.kind == kind })
                #expect(insight.status == .failed)
                #expect(insight.explanation.contains("NumericDate"))
            }
        }
    }

    @Test func acceptsAudienceStringAndStringArray() throws {
        let scalar = try JWTRegisteredClaimInterpreter.interpret(
            payloadJSON: #"{"aud":"api://single"}"#,
            now: now,
            timeZone: utc
        )
        #expect(scalar.first?.displayValue == "api://single")
        #expect(scalar.first?.explanation == "单个受众；未按应用上下文检查。")

        let array = try JWTRegisteredClaimInterpreter.interpret(
            payloadJSON: #"{"aud":["api://one","api://two"]}"#,
            now: now,
            timeZone: utc
        )
        #expect(array.first?.displayValue == "api://one · api://two")
        #expect(array.first?.explanation == "2 个受众；未按应用上下文检查。")
    }

    @Test func reportsInvalidRegisteredClaimTypesWithoutInventingValidation() throws {
        let insights = try JWTRegisteredClaimInterpreter.interpret(
            payloadJSON: #"{"iss":42,"sub":{},"aud":["api://one",7],"exp":"tomorrow","nbf":true,"iat":[],"jti":null}"#,
            now: now,
            timeZone: utc
        )

        for kind in [
            JWTRegisteredClaimInsight.Kind.issuer,
            .subject,
            .audience,
            .jwtID
        ] {
            let insight = try #require(insights.first { $0.kind == kind })
            #expect(insight.status == .warning)
            #expect(insight.displayValue == "类型不符合注册声明定义")
        }

        for kind in [
            JWTRegisteredClaimInsight.Kind.expiration,
            .notBefore,
            .issuedAt
        ] {
            let insight = try #require(insights.first { $0.kind == kind })
            #expect(insight.status == .failed)
            #expect(insight.explanation.contains("NumericDate"))
        }
    }

    @Test func noRegisteredClaimsProducesEmptyProjection() throws {
        let insights = try JWTRegisteredClaimInterpreter.interpret(
            payloadJSON: #"{"name":"Ada","roles":["admin"]}"#,
            now: now,
            timeZone: utc
        )

        #expect(insights.isEmpty)
    }

    @Test func rejectsPayloadThatIsNotAJSONObject() {
        #expect(throws: JWTRegisteredClaimInterpreter.InterpretationError.invalidPayloadJSON) {
            _ = try JWTRegisteredClaimInterpreter.interpret(
                payloadJSON: #"["not","an","object"]"#,
                now: now,
                timeZone: utc
            )
        }
    }
}
