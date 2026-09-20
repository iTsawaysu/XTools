import Foundation
import Testing
@testable import XToolsCore

struct DockerComposeToRunServiceTests {
    // MARK: - Basic conversion

    @Test func convertsCommonServiceFieldsIntoRunFlags() throws {
        let yaml = """
        services:
          web:
            image: nginx:latest
            container_name: web
            ports:
              - 8080:80
            environment:
              - ENV=prod
            volumes:
              - ./site:/usr/share/nginx/html:ro
            restart: always
        """
        let result = try DockerComposeToRunService.convert(yaml)
        #expect(result.commands.count == 1)
        #expect(result.warnings.isEmpty)

        let command = try #require(result.commands.first)
        #expect(command.hasPrefix("docker run -d"))
        #expect(command.contains("--name web"))
        #expect(command.contains("-p 8080:80"))
        #expect(command.contains("-e ENV=prod"))
        #expect(command.contains("-v ./site:/usr/share/nginx/html:ro"))
        #expect(command.contains("--restart always"))
        #expect(command.hasSuffix("nginx:latest"))
    }

    @Test func mapFormEnvironmentAndLabelsConvert() throws {
        let yaml = """
        services:
          api:
            image: api:1
            environment:
              DEBUG: false
              PORT: 8080
            labels:
              owner: team-a
        """
        let result = try DockerComposeToRunService.convert(yaml)
        let command = try #require(result.commands.first)
        #expect(command.contains("-e DEBUG=false"))
        #expect(command.contains("-e PORT=8080"))
        #expect(command.contains("-l owner=team-a"))
    }

    @Test func longFormPortsAndVolumesConvert() throws {
        let yaml = """
        services:
          web:
            image: nginx
            ports:
              - target: 80
                published: 8080
                protocol: udp
            volumes:
              - type: bind
                source: ./site
                target: /usr/share/nginx/html
                read_only: true
        """
        let result = try DockerComposeToRunService.convert(yaml)
        let command = try #require(result.commands.first)
        #expect(command.contains("-p 8080:80/udp"))
        #expect(command.contains("--mount type=bind,source=./site,target=/usr/share/nginx/html,readonly"))
    }

    @Test func multipleServicesProduceSortedCommands() throws {
        let yaml = """
        services:
          web:
            image: nginx
          db:
            image: postgres:16
        """
        let result = try DockerComposeToRunService.convert(yaml)
        #expect(result.commands.count == 2)
        #expect(result.commands[0].contains("postgres:16"))
        #expect(result.commands[1].contains("nginx"))
    }

    @Test func deployResourceLimitsMapToRunFlags() throws {
        let yaml = """
        services:
          app:
            image: app:2
            deploy:
              resources:
                limits:
                  cpus: "1.5"
                  memory: 512m
                  pids: 200
        """
        let result = try DockerComposeToRunService.convert(yaml)
        let command = try #require(result.commands.first)
        #expect(command.contains("--cpus 1.5"))
        #expect(command.contains("-m 512m"))
        #expect(command.contains("--pids-limit 200"))
    }

    @Test func reservationMemoryMapsWithoutHidingUnsupportedResourcePaths() throws {
        let yaml = """
        services:
          app:
            image: app:2
            deploy:
              resources:
                limits:
                  memory: 512m
                  custom_limit: private-secret-value
                reservations:
                  memory: 256m
                  cpus: "0.5"
        """
        let result = try DockerComposeToRunService.convert(yaml)
        let command = try #require(result.commands.first)
        #expect(command.contains("-m 512m"))
        #expect(command.contains("--memory-reservation 256m"))
        let warning = try #require(result.warnings.first { $0.contains("服务 app 未映射字段") })
        #expect(warning.contains("deploy.resources.limits.custom_limit"))
        #expect(warning.contains("deploy.resources.reservations.cpus"))
        #expect(!warning.contains("private-secret-value"))
    }

    @Test func flatMemoryReservationMapsAndMergesWithEquivalentDeployValue() throws {
        let flatOnly = try DockerComposeToRunService.convert("""
        services:
          app:
            image: alpine
            mem_reservation: 256m
        """)
        let flatSemantics = try DockerInvocationSemantics(try #require(flatOnly.commands.first))
        #expect(flatSemantics.resources.memoryReservation == "256m")
        #expect(flatOnly.warnings.isEmpty)

        let equivalentAliases = try DockerComposeToRunService.convert("""
        services:
          app:
            image: alpine
            mem_reservation: 256m
            deploy:
              resources:
                reservations:
                  memory: "268435456"
        """)
        let command = try #require(equivalentAliases.commands.first)
        let semantics = try DockerInvocationSemantics(command)
        #expect(semantics.resources.memoryReservation == "256m")
        #expect(command.components(separatedBy: "--memory-reservation").count == 2)
        #expect(equivalentAliases.warnings.isEmpty)
    }

    @Test func conflictingOrMalformedFlatMemoryReservationWarnsWithoutChoosingAValue() throws {
        let conflicting = try DockerComposeToRunService.convert("""
        services:
          app:
            image: alpine
            mem_reservation: 256m
            deploy:
              resources:
                reservations:
                  memory: 512m
        """)
        let conflictCommand = try #require(conflicting.commands.first)
        let conflictWarning = try #require(conflicting.warnings.first { $0.contains("服务 app 未映射字段") })
        #expect(!conflictCommand.contains("--memory-reservation"))
        #expect(conflictWarning.contains("mem_reservation/deploy.resources.reservations.memory(值冲突)"))
        #expect(!conflictWarning.contains("256m"))
        #expect(!conflictWarning.contains("512m"))

        let malformed = try DockerComposeToRunService.convert("""
        services:
          app:
            image: alpine
            mem_reservation: { private-memory: 256m }
        """)
        let malformedCommand = try #require(malformed.commands.first)
        let malformedWarning = try #require(malformed.warnings.first { $0.contains("服务 app 未映射字段") })
        #expect(!malformedCommand.contains("--memory-reservation"))
        #expect(malformedWarning.contains("mem_reservation(结构无法映射)"))
        #expect(!malformedWarning.contains("private-memory"))
    }

    @Test func longFormTmpfsUsesTmpfsMountInsteadOfAnonymousVolume() throws {
        let yaml = """
        services:
          app:
            image: nginx
            volumes:
              - type: tmpfs
                target: /cache
                tmpfs:
                  size: 65536
                  mode: 1770
        """
        let result = try DockerComposeToRunService.convert(yaml)
        let command = try #require(result.commands.first)
        #expect(command.contains("--mount type=tmpfs,target=/cache,tmpfs-size=65536,tmpfs-mode=1770"))
        #expect(!command.contains("-v /cache"))
        #expect(result.warnings.isEmpty)
    }

    @Test func tmpfsSizeAndModeSurviveComposeRunComposeSemanticRoundTrip() throws {
        let yaml = """
        services:
          app:
            image: nginx
            volumes:
              - type: tmpfs
                target: /cache
                tmpfs:
                  size: 65536
                  mode: 1770
        """
        let reverse = try DockerComposeToRunService.convert(yaml)
        let run = try #require(reverse.commands.first)
        let forward = try DockerRunToDockerComposeService.convert(run)
        let reconstructed = try DockerComposeToRunService.convert(forward.yaml)

        #expect(
            try DockerInvocationSemantics(try #require(reconstructed.commands.first))
                == DockerInvocationSemantics(run)
        )
        let semantics = try DockerInvocationSemantics(run)
        #expect(semantics.mounts == [
            .init(kind: .tmpfs, target: "/cache", tmpfsSize: "65536", tmpfsMode: "1770")
        ])
    }

    @Test func unsupportedLongFormMountFieldsWarnAndDoNotEmitWeakerVolume() throws {
        let yaml = """
        services:
          app:
            image: nginx
            volumes:
              - type: bind
                source: /host/data
                target: /data
                bind:
                  propagation: rshared
              - type: image
                source: private-image-reference
                target: /image
              - type: cluster
                source: private-cluster-reference
                target: /cluster
              - type: npipe
                source: private-pipe-reference
                target: /pipe
        """
        let result = try DockerComposeToRunService.convert(yaml)
        let command = try #require(result.commands.first)
        let warning = try #require(result.warnings.first { $0.contains("服务 app 未映射字段") })

        #expect(warning.contains("volumes.bind.bind.propagation"))
        #expect(warning.contains("volumes.image"))
        #expect(warning.contains("volumes.cluster"))
        #expect(warning.contains("volumes.npipe"))
        for secret in ["private-image-reference", "private-cluster-reference", "private-pipe-reference"] {
            #expect(!warning.contains(secret))
            #expect(!command.contains(secret))
        }
        #expect(!command.contains("/host/data:/data"))
    }

    @Test func unsupportedTmpfsAndNetworkFieldsWarnByPathWithoutValues() throws {
        let yaml = """
        services:
          app:
            image: nginx
            volumes:
              - type: tmpfs
                target: /cache
                tmpfs:
                  uid: private-secret-value
            networks:
              front:
                link_local_ips: [203.0.113.10]
        """
        let result = try DockerComposeToRunService.convert(yaml)
        let command = try #require(result.commands.first)
        let warning = try #require(result.warnings.first { $0.contains("服务 app 未映射字段") })
        #expect(warning.contains("volumes.tmpfs.tmpfs.uid"))
        #expect(warning.contains("networks.front.link_local_ips"))
        #expect(!warning.contains("private-secret-value"))
        #expect(!command.contains("--mount"))
        #expect(!warning.contains("203.0.113.10"))
    }

    @Test func malformedRecognizedNetworkAndResourceValuesWarnByPathWithoutValues() throws {
        let yaml = """
        services:
          app:
            image: nginx
            volumes:
              - type: tmpfs
                target: /cache
                tmpfs:
                  size: [private-secret-value]
            networks:
              front:
                ipv4_address: [private-secret-value]
            deploy:
              resources:
                limits:
                  memory: [private-secret-value]
                reservations:
                  memory: [private-secret-value]
        """
        let result = try DockerComposeToRunService.convert(yaml)
        let command = try #require(result.commands.first)
        let warning = try #require(result.warnings.first { $0.contains("服务 app 未映射字段") })
        #expect(warning.contains("volumes.tmpfs.tmpfs.size(结构无法映射)"))
        #expect(warning.contains("networks.front.ipv4_address(结构无法映射)"))
        #expect(warning.contains("deploy.resources.limits.memory(结构无法映射)"))
        #expect(warning.contains("deploy.resources.reservations.memory(结构无法映射)"))
        #expect(!warning.contains("private-secret-value"))
        #expect(!command.contains("--mount"))
    }

    @Test func malformedNetworkAttachmentWarnsWithoutEmittingTheAttachment() throws {
        let yaml = """
        services:
          app:
            image: nginx
            networks:
              front: [private-secret-value]
        """
        let result = try DockerComposeToRunService.convert(yaml)
        let command = try #require(result.commands.first)
        let warning = try #require(result.warnings.first { $0.contains("服务 app 未映射字段") })

        #expect(warning.contains("networks.front(结构无法映射)"))
        #expect(!warning.contains("private-secret-value"))
        #expect(!command.contains("--network"))
    }

    @Test func multipleNetworkAttachmentsRetainAliasesAndAddresses() throws {
        let yaml = """
        services:
          app:
            image: nginx
            networks:
              front:
                aliases: [web, api]
                ipv4_address: 172.20.0.5
                ipv6_address: 2001:db8::5
              back: {}
        """
        let result = try DockerComposeToRunService.convert(yaml)
        #expect(result.warnings.isEmpty)
        let semantics = try DockerInvocationSemantics(try #require(result.commands.first))
        #expect(semantics.networks == [
            .init(name: "back"),
            .init(name: "front", aliases: ["web", "api"], ipv4: "172.20.0.5", ipv6: "2001:db8::5")
        ])
    }

    @Test func entrypointAndCommandKeepExecutableAndFinalArgvBoundaries() throws {
        let yaml = """
        services:
          app:
            image: busybox
            entrypoint: ["/bin/sh", "-c"]
            command: ["echo hi"]
        """
        let result = try DockerComposeToRunService.convert(yaml)
        let semantics = try DockerInvocationSemantics(try #require(result.commands.first))
        #expect(semantics.image == "busybox")
        #expect(semantics.entrypoint == ["/bin/sh"])
        #expect(semantics.command == ["-c", "echo hi"])
        #expect(semantics.finalExecArgv == ["/bin/sh", "-c", "echo hi"])
    }

    @Test func unmappableFieldsCollectIntoWarnings() throws {
        let yaml = """
        services:
          web:
            image: nginx
            build: .
            depends_on:
              - db
          db:
            image: postgres:16
            healthcheck:
              test: ["CMD-SHELL", "pg_isready"]
              interval: 10s
        """
        let result = try DockerComposeToRunService.convert(yaml)
        #expect(result.commands.count == 2)
        #expect(result.warnings.contains(where: { $0.contains("服务 web 未映射字段：build、depends_on") }))

        let dbCommand = result.commands.first { $0.contains("postgres") }
        #expect(dbCommand?.contains("--health-cmd pg_isready") == true)
        #expect(dbCommand?.contains("--health-interval 10s") == true)
    }

    @Test func commandArgumentsAppendAfterImage() throws {
        let yaml = """
        services:
          app:
            image: busybox
            command:
              - echo
              - hello world
        """
        let result = try DockerComposeToRunService.convert(yaml)
        let command = try #require(result.commands.first)
        #expect(command.contains("busybox echo 'hello world'"))
    }

    // MARK: - Error paths

    @Test func invalidYAMLThrows() {
        #expect(throws: DockerComposeToRunError.invalidYAML) {
            _ = try DockerComposeToRunService.convert("services: [broken")
        }
    }

    @Test func missingServicesSectionThrows() {
        #expect(throws: DockerComposeToRunError.missingServicesSection) {
            _ = try DockerComposeToRunService.convert("networks:\n  default: {}")
        }
    }

    @Test func serviceWithoutImageWarnsAndSkips() throws {
        let yaml = """
        services:
          builder:
            build: .
        """
        #expect(throws: DockerComposeToRunError.noServices) {
            _ = try DockerComposeToRunService.convert(yaml)
        }
    }

    // MARK: - Round-trip against the forward converter

    @Test func forwardOutputRoundTripsBackToEquivalentRunCommand() throws {
        let runCommand = """
        docker run -d --name web -p 8080:80 -e ENV=prod -v ./site:/usr/share/nginx/html:ro --restart always -w /app -u root --memory 512m --cpus 1.5 nginx:latest
        """
        let forward = try DockerRunToDockerComposeService.convert(runCommand)
        #expect(forward.warnings.isEmpty)

        let reverse = try DockerComposeToRunService.convert(forward.yaml)
        #expect(reverse.warnings.isEmpty)

        let reconstructed = try #require(reverse.commands.first)
        #expect(
            Self.normalizedTokens(reconstructed) == Self.normalizedTokens(runCommand),
            "forward→reverse must reproduce the original run command, got: \(reconstructed)"
        )
    }

    @Test func forwardOutputWithCommandArgsRoundTrips() throws {
        let runCommand = "docker run -d --name echoer busybox echo hello"
        let forward = try DockerRunToDockerComposeService.convert(runCommand)
        let reverse = try DockerComposeToRunService.convert(forward.yaml)
        let reconstructed = try #require(reverse.commands.first)
        #expect(Self.normalizedTokens(reconstructed) == Self.normalizedTokens(runCommand))
    }

    @Test func forwardAndReverseCompareThroughTypedInvocationSemantics() throws {
        let runCommand = "docker run --memory-reservation 256m --network name=front,alias=web,ip=172.20.0.5 --network back --mount type=tmpfs,target=/cache alpine echo hello"
        let forward = try DockerRunToDockerComposeService.convert(runCommand)
        let reverse = try DockerComposeToRunService.convert(forward.yaml)
        #expect(reverse.warnings.allSatisfy { $0.contains("顶层 networks 定义不会写入命令") })
        #expect(
            try DockerInvocationSemantics(try #require(reverse.commands.first))
                == DockerInvocationSemantics(runCommand)
        )
    }

    @Test func networkModifierOrderRoundTripsThroughTypedInvocationSemantics() throws {
        let before = "docker run --ip 172.20.0.5 --ip6 2001:db8::5 --network-alias web --network front --network back nginx"
        let after = "docker run --network front --ip 172.20.0.5 --ip6 2001:db8::5 --network-alias web --network back nginx"
        let forward = try DockerRunToDockerComposeService.convert(before)
        let reverse = try DockerComposeToRunService.convert(forward.yaml)

        #expect(try DockerInvocationSemantics(before) == DockerInvocationSemantics(after))
        #expect(
            try DockerInvocationSemantics(try #require(reverse.commands.first))
                == DockerInvocationSemantics(before)
        )
    }

    @Test func typedInvocationOracleCoversResourceLimitsAndMountSemantics() throws {
        let yaml = """
        services:
          app:
            image: nginx
            deploy:
              resources:
                limits:
                  cpus: "1.5"
                  memory: 512m
                  pids: 200
                reservations:
                  memory: 256m
            volumes:
              - type: bind
                source: /host/data
                target: /data
                read_only: true
              - type: volume
                source: cache
                target: /cache
              - type: tmpfs
                target: /run
        """
        let result = try DockerComposeToRunService.convert(yaml)
        let semantics = try DockerInvocationSemantics(try #require(result.commands.first))

        #expect(semantics.resources == .init(cpus: "1.5", memoryLimit: "512m", pidsLimit: "200", memoryReservation: "256m"))
        #expect(semantics.mounts == [
            .init(kind: .bind, source: "/host/data", target: "/data", readOnly: true),
            .init(kind: .volume, source: "cache", target: "/cache"),
            .init(kind: .tmpfs, target: "/run")
        ])
    }

    @Test func commonRuntimeFieldsRoundTripThroughTypedInvocationSemantics() throws {
        let run = "docker run --platform linux/arm64 -e MODE=prod -e EMPTY= -l owner=team-a -p 127.0.0.1:8080:80/tcp --restart on-failure:3 --health-cmd 'curl -f http://localhost/health' --health-interval 30s --health-timeout 5s --health-retries 4 --health-start-period 10s --health-start-interval 2s --entrypoint /bin/sh app:1 -c 'echo ready'"
        let forward = try DockerRunToDockerComposeService.convert(run)
        let reverse = try DockerComposeToRunService.convert(forward.yaml)

        #expect(forward.warnings.isEmpty)
        #expect(reverse.warnings.isEmpty)
        let reconstructed = try DockerInvocationSemantics(try #require(reverse.commands.first))
        let original = try DockerInvocationSemantics(run)
        #expect(reconstructed == original)
    }

    @Test func explicitLongMountKindsSurviveBothRoundTripDirections() throws {
        let run = "docker run --mount type=bind,source=relative-host,target=/host-data,readonly --mount type=volume,source=cache,target=/cache alpine"
        let forward = try DockerRunToDockerComposeService.convert(run)
        let reverse = try DockerComposeToRunService.convert(forward.yaml)
        #expect(
            try DockerInvocationSemantics(try #require(reverse.commands.first)).mounts
                == DockerInvocationSemantics(run).mounts
        )

        let compose = """
        services:
          app:
            image: alpine
            volumes:
              - type: bind
                source: relative-host
                target: /host-data
                read_only: true
              - type: volume
                source: cache
                target: /cache
        """
        let fromCompose = try DockerComposeToRunService.convert(compose)
        #expect(try DockerInvocationSemantics(try #require(fromCompose.commands.first)).mounts == [
            .init(kind: .bind, source: "relative-host", target: "/host-data", readOnly: true),
            .init(kind: .volume, source: "cache", target: "/cache")
        ])
    }

    @Test func malformedKnownFieldsWarnByPathAndDoNotEmitPseudoEquivalentFlags() throws {
        let yaml = """
        services:
          app:
            image: nginx
            platform: [private-platform-value]
            restart: { private-policy: always }
            environment:
              SECRET_TOKEN: null
            ports:
              - target: 80
                published: 8080
                mode: private-port-mode
            healthcheck:
              test: ["CMD", "private-health-binary", "--check"]
              interval: private-health-interval
            deploy:
              resources: [private-resource-value]
        """
        let result = try DockerComposeToRunService.convert(yaml)
        let command = try #require(result.commands.first)
        let warning = try #require(result.warnings.first { $0.contains("服务 app 未映射字段") })

        for path in ["platform(结构无法映射)", "restart(结构无法映射)", "ports.mode", "healthcheck.test(exec-form 无法等价映射)", "deploy.resources(结构无法映射)"] {
            #expect(warning.contains(path))
        }
        for value in ["private-platform-value", "private-policy", "private-port-mode", "private-health-binary", "private-resource-value"] {
            #expect(!warning.contains(value))
            #expect(!command.contains(value))
        }
        #expect(command.contains("-e SECRET_TOKEN"))
        #expect(!command.contains("-p 8080:80"))
        #expect(!command.contains("--health-cmd"))
        #expect(!command.contains("--health-interval"))
    }

    @Test func nullEnvironmentValueMapsToHostResolvedBareKey() throws {
        let result = try DockerComposeToRunService.convert("""
        services:
          app:
            image: alpine
            environment:
              XTOOLS_NULL_ENV_PROBE:
        """)
        #expect(result.warnings.isEmpty)
        #expect(try #require(result.commands.first).contains("-e XTOOLS_NULL_ENV_PROBE"))
    }

    @Test func emptyAndMalformedEntrypointCommandKeepArgvHonest() throws {
        let empty = try DockerComposeToRunService.convert("""
        services:
          app:
            image: alpine
            entrypoint: []
            command: ["printf", "%s", ""]
        """)
        let emptySemantics = try DockerInvocationSemantics(try #require(empty.commands.first))
        #expect(emptySemantics.entrypoint == [""])
        #expect(emptySemantics.command == ["printf", "%s", ""])

        let malformed = try DockerComposeToRunService.convert("""
        services:
          app:
            image: alpine
            entrypoint: ["/bin/sh", { private-entrypoint: value }]
            command: ["echo", { private-command: value }]
        """)
        let command = try #require(malformed.commands.first)
        let warning = try #require(malformed.warnings.first { $0.contains("服务 app 未映射字段") })
        #expect(warning.contains("entrypoint(结构无法映射)"))
        #expect(warning.contains("command(结构无法映射)"))
        #expect(!command.contains("private-entrypoint"))
        #expect(!command.contains("private-command"))
    }

    @Test func deployOnlyRestartPolicyWarnsInsteadOfInventingContainerRestartSemantics() throws {
        let result = try DockerComposeToRunService.convert("""
        services:
          app:
            image: nginx
            deploy:
              restart_policy:
                condition: any
                delay: private-delay
        """)
        let command = try #require(result.commands.first)
        let warning = try #require(result.warnings.first { $0.contains("服务 app 未映射字段") })
        #expect(warning.contains("deploy.restart_policy"))
        #expect(!warning.contains("private-delay"))
        #expect(!command.contains("--restart"))
    }

    /// Flag order and quoting may differ; compare as a sorted multiset with
    /// the always-present `-d` normalized away.
    private static let flagAliases: [String: String] = [
        "--memory": "-m",
        "--hostname": "-h",
        "--label": "-l",
        "--workdir": "-w"
    ]

    private static func normalizedTokens(_ command: String) -> [String] {
        var tokens = command
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .map { flagAliases[$0] ?? $0 }
        if let runIndex = tokens.firstIndex(of: "run") {
            tokens.removeSubrange(...runIndex)
        }
        tokens.removeAll { $0 == "-d" }
        return tokens.sorted()
    }
}

private struct DockerInvocationSemantics: Equatable {
    struct Resources: Equatable {
        var cpus: String?
        var memoryLimit: String?
        var pidsLimit: String?
        var memoryReservation: String?
    }

    struct Mount: Equatable {
        enum Kind: Equatable {
            case bind
            case volume
            case tmpfs
        }

        let kind: Kind
        var source: String?
        let target: String
        var readOnly = false
        var tmpfsSize: String?
        var tmpfsMode: String?
    }

    struct Network: Equatable {
        let name: String
        var aliases: [String] = []
        var ipv4: String?
        var ipv6: String?
    }

    struct Healthcheck: Equatable {
        var command: String?
        var interval: String?
        var timeout: String?
        var retries: String?
        var startPeriod: String?
        var startInterval: String?
        var disabled = false
    }

    let image: String
    let entrypoint: [String]
    let command: [String]
    let resources: Resources
    let networks: [Network]
    let mounts: [Mount]
    let environment: [String]
    let labels: [String]
    let ports: [String]
    let platform: String?
    let restart: String?
    let healthcheck: Healthcheck

    var finalExecArgv: [String] { entrypoint + command }

    init(_ commandText: String) throws {
        let tokens = try DockerRunToDockerComposeService.tokenize(commandText)
        guard let runIndex = tokens.firstIndex(of: "run") else {
            throw DockerComposeToRunError.invalidYAML
        }

        var entrypoint: [String] = []
        var resources = Resources()
        var networks: [Network] = []
        var pendingNetwork = Network(name: "")
        var mounts: [Mount] = []
        var environment: [String] = []
        var labels: [String] = []
        var ports: [String] = []
        var platform: String?
        var restart: String?
        var healthcheck = Healthcheck()
        var index = runIndex + 1
        while index < tokens.count, tokens[index].hasPrefix("-") {
            let option = tokens[index]
            guard index + 1 < tokens.count else { break }
            let value = tokens[index + 1]
            switch option {
            case "--entrypoint":
                entrypoint = [value]
            case "--cpus":
                resources.cpus = value
            case "-m", "--memory":
                resources.memoryLimit = value
            case "--pids-limit":
                resources.pidsLimit = value
            case "--memory-reservation":
                resources.memoryReservation = value
            case "-e", "--env":
                environment.append(value)
            case "-l", "--label":
                labels.append(value)
            case "-p", "--publish":
                ports.append(value.hasSuffix("/tcp") ? String(value.dropLast(4)) : value)
            case "--platform":
                platform = value
            case "--restart":
                restart = value
            case "--health-cmd":
                healthcheck.command = value
            case "--health-interval":
                healthcheck.interval = value
            case "--health-timeout":
                healthcheck.timeout = value
            case "--health-retries":
                healthcheck.retries = value
            case "--health-start-period":
                healthcheck.startPeriod = value
            case "--health-start-interval":
                healthcheck.startInterval = value
            case "--network":
                var network = Self.network(from: value)
                if !pendingNetwork.aliases.isEmpty {
                    network.aliases = pendingNetwork.aliases + network.aliases
                }
                if network.ipv4 == nil {
                    network.ipv4 = pendingNetwork.ipv4
                }
                if network.ipv6 == nil {
                    network.ipv6 = pendingNetwork.ipv6
                }
                pendingNetwork = Network(name: "")
                networks.append(network)
            case "--ip":
                if networks.isEmpty {
                    pendingNetwork.ipv4 = value
                } else {
                    networks[networks.count - 1].ipv4 = value
                }
            case "--ip6":
                if networks.isEmpty {
                    pendingNetwork.ipv6 = value
                } else {
                    networks[networks.count - 1].ipv6 = value
                }
            case "--network-alias":
                if networks.isEmpty {
                    pendingNetwork.aliases.append(value)
                } else {
                    networks[networks.count - 1].aliases.append(value)
                }
            case "--mount":
                let pieces = value.split(separator: ",").map(String.init)
                let options = Dictionary(
                    uniqueKeysWithValues: pieces.compactMap { part -> (String, String)? in
                        let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
                        guard pair.count == 2 else { return nil }
                        return (pair[0], pair[1])
                    }
                )
                if let type = options["type"], let target = options["target"] ?? options["dst"] ?? options["destination"] {
                    let kind: Mount.Kind? = switch type {
                    case "bind": .bind
                    case "volume": .volume
                    case "tmpfs": .tmpfs
                    default: nil
                    }
                    if let kind {
                        mounts.append(.init(
                            kind: kind,
                            source: options["source"] ?? options["src"],
                            target: target,
                            readOnly: pieces.contains("readonly") || pieces.contains("ro"),
                            tmpfsSize: options["tmpfs-size"],
                            tmpfsMode: options["tmpfs-mode"]
                        ))
                    }
                }
            case "--tmpfs":
                mounts.append(.init(kind: .tmpfs, target: value.split(separator: ":", maxSplits: 1).map(String.init)[0]))
            case "-v", "--volume":
                let parts = value.split(separator: ":", maxSplits: 2).map(String.init)
                if parts.count >= 2 {
                    let source = parts[0]
                    let kind: Mount.Kind = source.hasPrefix("/") || source.hasPrefix(".") || source.hasPrefix("~") || source.hasPrefix("$") ? .bind : .volume
                    mounts.append(.init(kind: kind, source: source, target: parts[1], readOnly: parts.dropFirst(2).first == "ro"))
                }
            case "--no-healthcheck":
                healthcheck.disabled = true
                index += 1
                continue
            case "-d", "-i", "-t", "--privileged", "--read-only", "--init", "--oom-kill-disable":
                index += 1
                continue
            default:
                break
            }
            index += 2
        }

        let image = tokens[index]
        self.image = image
        self.entrypoint = entrypoint
        self.command = Array(tokens.dropFirst(index + 1))
        self.resources = resources
        self.networks = networks.sorted { $0.name < $1.name }
        self.mounts = mounts
        self.environment = environment.sorted()
        self.labels = labels.sorted()
        self.ports = ports.sorted()
        self.platform = platform
        self.restart = restart
        self.healthcheck = healthcheck
    }

    private static func network(from value: String) -> Network {
        guard value.contains("=") else { return .init(name: value) }
        var name = ""
        var aliases: [String] = []
        var ipv4: String?
        var ipv6: String?
        for item in value.split(separator: ",") {
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            switch pair[0] {
            case "name": name = pair[1]
            case "alias": aliases.append(pair[1])
            case "ip": ipv4 = pair[1]
            case "ip6": ipv6 = pair[1]
            default: continue
            }
        }
        return .init(name: name, aliases: aliases, ipv4: ipv4, ipv6: ipv6)
    }
}


// MARK: - Warning copy quality

struct DockerComposeToRunWarningTests {
    @Test func domainnameMapsToRunFlagInsteadOfWarning() throws {
        let yaml = """
        services:
          web:
            image: nginx
            domainname: example.com
        """
        let result = try DockerComposeToRunService.convert(yaml)
        #expect(result.warnings.isEmpty, "domainname has a docker run equivalent and must map, not warn")
        #expect(try #require(result.commands.first).contains("--domainname example.com"))
    }

    @Test func topLevelDefinitionsGetANoteInsteadOfSkippedFieldKeys() throws {
        let yaml = """
        networks:
          default: {}
        volumes:
          data: {}
        services:
          web:
            image: nginx
            networks:
              - default
            volumes:
              - data:/var/lib/data
        """
        let result = try DockerComposeToRunService.convert(yaml)
        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].contains("顶层 networks、volumes 定义不会写入命令"))
        #expect(!result.warnings[0].contains("未映射"), "definition notes must not read as skipped fields")

        let command = try #require(result.commands.first)
        #expect(command.contains("--network default"), "service-level network references stay mapped")
        #expect(command.contains("-v data:/var/lib/data"))
    }

    @Test func mappedNetworkAddressesDoNotProduceSkippedFieldWarnings() throws {
        let yaml = """
        services:
          web:
            image: nginx
            networks:
              front:
                ipv4_address: 172.20.0.5
              back:
                ipv4_address: 172.21.0.5
        """
        let result = try DockerComposeToRunService.convert(yaml)
        #expect(result.warnings.isEmpty)
        let semantics = try DockerInvocationSemantics(try #require(result.commands.first))
        #expect(semantics.networks == [
            .init(name: "back", ipv4: "172.21.0.5"),
            .init(name: "front", ipv4: "172.20.0.5")
        ])
    }

    @Test func multipleWarningsJoinWithSemicolonPrefix() throws {
        let result = DockerComposeToRunDiagnostics.warningMessage(for: ["顶层 networks 定义不会写入命令（服务内引用已映射，需预先创建）", "服务 web 未映射字段：build"])
        #expect(result?.hasPrefix("转换提示（2 项）") == true)
        #expect(DockerComposeToRunDiagnostics.warningMessage(for: ["单独一条"]) == "单独一条")
        #expect(DockerComposeToRunDiagnostics.warningMessage(for: []) == nil)
    }

    // MARK: - Shell quoting safety

    /// 生成命令里的每个值都必须能在 shell 引号语义下原样取回。
    /// 早先的转义用「不安全字符黑名单」，漏掉了换行，含换行的环境变量值既不加引号
    /// 也不做处理，粘贴执行时会被换行切成两条命令（`-e K=a` 之后又执行 `whoami`）。
    ///
    /// 未覆盖 `\r\n` 相邻出现：YAML 依赖会把双引号标量里转义出的 CRLF 当成换行
    /// 折成空格，属于依赖层行为，与本工具的引用逻辑无关（单独 CR / 单独 LF 均原样保留）。
    @Test func generatedCommandsTokenizeBackToTheirOriginalValues() throws {
        let values = [
            "K=plain",
            "K=a b",
            "K=a\nwhoami",
            "K=a\rwhoami",
            "K=a\tb",
            "K=$(whoami)",
            "K=`whoami`",
            "K=a;whoami",
            "K=a&&whoami",
            "K=a|whoami",
            "K=a>b",
            "K=a<b",
            "K=a(b)",
            "K=a{b}",
            "K=a[b]",
            "K=*",
            "K=?",
            "K=~root",
            "K=a#b",
            "K=a%b",
            "K=a&b",
            "K=a!b",
            "K=it's",
            "K=\"quoted\"",
            "K=a'b",
            "K=a\\b"
        ]

        for value in values {
            let yaml = """
            services:
              a:
                image: alpine
                environment:
                  - \(Self.yamlDoubleQuoted(value))
            """
            let result = try DockerComposeToRunService.convert(yaml)
            let command = try #require(result.commands.first, Comment(rawValue: "missing command for \(value.debugDescription)"))
            let semantics = try DockerInvocationSemantics(command)
            #expect(
                semantics.environment == [value],
                Comment(rawValue: "值 \(value.debugDescription) 未能从「\(command)」原样取回")
            )
        }
    }

    /// 双引号 YAML 标量：把控制字符写成转义，避免测试自身构造出无效 YAML。
    static func yamlDoubleQuoted(_ value: String) -> String {
        var out = ""
        for character in value {
            switch character {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(character)
            }
        }
        return "\"\(out)\""
    }
}
