import Foundation
import Testing
import Yams
@testable import XToolsCore

struct DockerConversionReliabilityTests {
    @Test func attachedPublishedPortStaysDynamic() throws {
        let result = try DockerRunToDockerComposeService.convert("docker run -p80 nginx")
        let service = try Self.service(in: result.yaml)
        #expect(service["ports"] as? [String] == ["80"])
    }

    @Test func omittedPublishedPortStaysOmitted() throws {
        for (input, expected) in [
            ("80", "80"), ("80/tcp", "80"), ("80/udp", "80/udp"),
            ("8000-8005", "8000-8005"), ("8080:80", "8080:80"),
            ("127.0.0.1::80", "127.0.0.1::80"), ("[::1]:8080:80", "[::1]:8080:80")
        ] {
            let result = try DockerRunToDockerComposeService.convert("docker run -p \(input) nginx")
            let service = try Self.service(in: result.yaml)
            #expect(service["ports"] as? [String] == [expected], Comment(rawValue: input))
            let reverse = try DockerComposeToRunService.convert(result.yaml)
            let tokens = try DockerRunToDockerComposeService.tokenize(#require(reverse.commands.first))
            let portIndex = try #require(tokens.firstIndex(of: "-p"))
            #expect(tokens[portIndex + 1] == expected)
        }
    }

    @Test func shellLiteralDollarsAreEscapedForComposeAndRoundTrip() throws {
        let sources = [
            #"docker run -e 'AUDIT=$literal' alpine"#,
            #"docker run -e "AUDIT=\$literal" alpine"#,
            #"docker run -e AUDIT=\$literal alpine"#,
            #"docker run -e AUDIT='$literal' alpine"#
        ]
        for source in sources {
            let result = try DockerRunToDockerComposeService.convert(source)
            let service = try Self.service(in: result.yaml)
            #expect(service["environment"] as? [String] == ["AUDIT=$$literal"])
            let reverse = try DockerComposeToRunService.convert(result.yaml)
            let tokens = try DockerRunToDockerComposeService.tokenize(#require(reverse.commands.first))
            #expect(tokens.contains("AUDIT=$literal"))
        }
    }

    @Test func quotedLiteralPWDIsNotRewrittenAsCurrentDirectory() throws {
        let result = try DockerRunToDockerComposeService.convert(#"docker run -v '$PWD/data:/data' alpine"#)
        let service = try Self.service(in: result.yaml)
        #expect(service["volumes"] as? [String] == ["$$PWD/data:/data"])
    }

    @Test func unresolvedShellEvaluationIsNotSilentlyConvertedToLiteral() {
        for source in [
            #"docker run -e AUDIT=$PRIVATE_SENTINEL alpine"#,
            #"docker run -e "AUDIT=${PRIVATE_SENTINEL:-secret}" alpine"#,
            #"docker run alpine echo $(whoami)"#
        ] {
            #expect(throws: (any Error).self) {
                _ = try DockerRunToDockerComposeService.convert(source)
            }
        }
    }

    @Test func composeEscapedDollarIsDecodedBeforeShellQuoting() throws {
        let result = try DockerComposeToRunService.convert("""
        services:
          app:
            image: alpine
            environment: ['AUDIT=$$literal', 'DOUBLE=$$$$value']
            command: [sh, -c, 'echo $$HOME']
        """)
        let tokens = try DockerRunToDockerComposeService.tokenize(#require(result.commands.first))
        #expect(tokens.contains("AUDIT=$literal"))
        #expect(tokens.contains("DOUBLE=$$value"))
        #expect(tokens.last == "echo $HOME")
    }

    @Test func composeUnresolvedInterpolationIsNotFrozenAsLiteral() {
        #expect(throws: (any Error).self) {
            _ = try DockerComposeToRunService.convert("""
            services:
              app:
                image: alpine
                environment: ['AUDIT=${PRIVATE_SENTINEL:-secret}']
            """)
        }
    }

    @Test func structuredRunWarningsDoNotKeepInlineSecretValues() throws {
        let result = try DockerRunToDockerComposeService.convert(
            "docker run --cidfile=PRIVATE_SENTINEL --unknown-token=PRIVATE_SENTINEL alpine"
        )
        #expect(result.warnings.contains(.init(kind: .notImplemented, option: "--cidfile")))
        #expect(result.warnings.allSatisfy { !$0.option.contains("PRIVATE_SENTINEL") })
        let details = DockerRunToDockerComposeDiagnostics.warningDetails(for: result.warnings)
        #expect(details.contains { $0.contains("--cidfile") && $0.contains("未写入结果") })
        #expect(details.allSatisfy { !$0.contains("PRIVATE_SENTINEL") })
    }

    @Test func composeSummaryCollapseDoesNotDiscardDetailedLosses() throws {
        let fields = (1...20).map { "unmapped_field_\($0)" }
        let source = "services:\n  app:\n    image: alpine\n" + fields.map {
            "    \($0): PRIVATE_SENTINEL"
        }.joined(separator: "\n")
        let result = try DockerComposeToRunService.convert(source)
        #expect(result.warnings.allSatisfy { $0.count <= 180 })
        for field in fields {
            #expect(result.warningDetails.contains { $0.contains("\(field) 未映射") })
        }
        #expect(result.warningDetails.allSatisfy { !$0.contains("PRIVATE_SENTINEL") })
    }

    @Test func composeLiteralKeysAndNonInterpolationDollarsStayLiteral() throws {
        let result = try DockerComposeToRunService.convert("""
        services:
          app:
            image: alpine
            environment:
              '$PRIVATE_SENTINEL': '$$(whoami)'
              PRICE: '$5'
            x-ignored: '$UNRESOLVED'
            deploy:
              placement: '$PRIVATE_SENTINEL'
              resources:
                limits: {cpus: '0.5', ignored: '$PRIVATE_SENTINEL'}
        """)
        let tokens = try DockerRunToDockerComposeService.tokenize(#require(result.commands.first))
        #expect(tokens.contains("$PRIVATE_SENTINEL=$(whoami)"))
        #expect(tokens.contains("PRICE=$5"))
        #expect(result.warningDetails.contains { $0.contains("deploy.placement") })
        #expect(result.warningDetails.allSatisfy { !$0.contains("PRIVATE_SENTINEL") })
    }

    @Test func commandAndHealthcheckLiteralsRoundTripWithoutHostEvaluation() throws {
        let source = #"docker run --health-cmd 'test "$READY" = yes' -e 'PAIR=$$HOME' alpine sh -c 'echo ${HOME:-fallback}'"#
        let result = try DockerRunToDockerComposeService.convert(source)
        let reverse = try DockerComposeToRunService.convert(result.yaml)
        let tokens = try DockerRunToDockerComposeService.tokenize(#require(reverse.commands.first))
        #expect(tokens.contains(#"test "$READY" = yes"#))
        #expect(tokens.contains("PAIR=$$HOME"))
        #expect(tokens.last == "echo ${HOME:-fallback}")
    }

    @Test func currentDirectoryShorthandOnlyAppliesToExpandableMountSources() throws {
        for spelling in ["$(pwd)", "${PWD}", "$PWD"] {
            let source = "docker run --mount type=bind,source=\(spelling)/data,target=/data alpine"
            let result = try DockerRunToDockerComposeService.convert(source)
            #expect(result.yaml.contains("source: ./data"))
        }
        let literal = try DockerRunToDockerComposeService.convert(#"docker run --mount 'type=bind,source=$PWD/data,target=/data' alpine"#)
        #expect(literal.yaml.contains("source: $$PWD/data"))
        #expect(throws: (any Error).self) {
            _ = try DockerRunToDockerComposeService.convert(#"docker run -v '$PWD'/suffix$SECRET:/data alpine"#)
        }
    }

    @Test func unresolvedExpressionDiagnosticsNameTheFieldWithoutTheValue() throws {
        do {
            _ = try DockerRunToDockerComposeService.convert(#"docker run --env=KEY=$PRIVATE_SENTINEL alpine"#)
            Issue.record("Expected unresolved Shell expression")
        } catch let error as DockerRunToDockerComposeError {
            #expect(error.errorDescription?.contains("--env") == true)
            #expect(error.errorDescription?.contains("PRIVATE_SENTINEL") == false)
        }
        do {
            _ = try DockerComposeToRunService.convert("services: {app: {image: '${PRIVATE_SENTINEL}'}}")
            Issue.record("Expected unresolved Compose interpolation")
        } catch let error as DockerComposeToRunError {
            let diagnostic = DockerComposeToRunDiagnostics.diagnostic(for: error)
            #expect(diagnostic.message.contains("image"))
            #expect(!diagnostic.message.contains("PRIVATE_SENTINEL"))
        }
    }

    @Test func warningDetailsHaveAnExplicitDisplayBudget() {
        let warnings = (0..<300).map {
            DockerRunToDockerComposeService.Warning(kind: .unknownFlag, option: "--field-\($0)")
        }
        let details = DockerRunToDockerComposeDiagnostics.warningDetails(for: warnings)
        #expect(details.count == 257)
        #expect(details.last?.contains("44") == true)
    }

    @Test func inactiveComposeAlternativesDoNotBlockMappedOutput() throws {
        let result = try DockerComposeToRunService.convert("""
        services:
          app:
            image: alpine
            network_mode: host
            networks: {ignored: {ipv4_address: '$PRIVATE_SENTINEL'}}
            healthcheck: {disable: true, test: '$PRIVATE_SENTINEL'}
            mem_limit: 128m
            memory: '$PRIVATE_SENTINEL'
            cpuset: '0-1'
            cpuset_cpus: '$PRIVATE_SENTINEL'
            gpus: all
            deploy:
              restart_policy: {max_attempts: '$PRIVATE_SENTINEL'}
              resources:
                reservations:
                  devices: [{count: '$PRIVATE_SENTINEL'}]
        """)
        let tokens = try DockerRunToDockerComposeService.tokenize(#require(result.commands.first))
        #expect(tokens.contains("--no-healthcheck"))
        #expect(tokens.contains("host"))
        #expect(tokens.contains("128m"))
        #expect(tokens.contains("0-1"))
        #expect(!tokens.contains { $0.contains("PRIVATE_SENTINEL") })
        #expect(result.warningDetails.contains { $0.contains("deploy.restart_policy") })
        #expect(!result.warningDetails.contains { $0.contains("PRIVATE_SENTINEL") })
    }

    @Test func unsupportedExecHealthcheckRemainsAWarnedPartialConversion() throws {
        let result = try DockerComposeToRunService.convert("""
        services:
          app:
            image: alpine
            healthcheck: {test: [CMD, echo, '$PRIVATE_SENTINEL']}
        """)
        #expect(result.commands.count == 1)
        #expect(result.warningDetails.contains { $0.contains("exec-form") })
        #expect(!result.warningDetails.contains { $0.contains("PRIVATE_SENTINEL") })
    }

    @Test func unusedGPUReservationsDoNotChangeTheExistingMappedCount() throws {
        let result = try DockerComposeToRunService.convert("""
        services:
          app:
            image: alpine
            deploy:
              resources:
                reservations:
                  devices: [{count: 2}, {count: '$PRIVATE_SENTINEL'}]
        """)
        let tokens = try DockerRunToDockerComposeService.tokenize(#require(result.commands.first))
        let index = try #require(tokens.firstIndex(of: "--gpus"))
        #expect(tokens[index + 1] == "2")
        #expect(!result.commands.joined().contains("PRIVATE_SENTINEL"))
    }

    @Test func shellSpecialQuotedExpressionsAreNotReinterpretedAsLiterals() {
        for source in [#"docker run -e KEY=$'line\nline' alpine"#,
                       #"docker run -e KEY=$"translated" alpine"#] {
            #expect(throws: (any Error).self) {
                _ = try DockerRunToDockerComposeService.convert(source)
            }
        }
    }

    private static func service(in yaml: String) throws -> [String: Any] {
        let root = try #require(Yams.load(yaml: yaml) as? [String: Any])
        let services = try #require(root["services"] as? [String: Any])
        return try #require(services.values.first as? [String: Any])
    }
}
