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
        #expect(command.contains("-v ./site:/usr/share/nginx/html:ro"))
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

    @Test func repeatedIdenticalNotesCollapseInsideOneService() throws {
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
        let unmappedLines = result.warnings.filter { $0.contains("networks.ipv4/ipv6_address") }
        #expect(unmappedLines.count == 1, "two networks with addresses must produce one note, not two")
        #expect(unmappedLines[0].contains("服务 web 未映射字段"))
    }

    @Test func multipleWarningsJoinWithSemicolonPrefix() throws {
        let result = DockerComposeToRunDiagnostics.warningMessage(for: ["顶层 networks 定义不会写入命令（服务内引用已映射，需预先创建）", "服务 web 未映射字段：build"])
        #expect(result?.hasPrefix("转换提示（2 项）") == true)
        #expect(DockerComposeToRunDiagnostics.warningMessage(for: ["单独一条"]) == "单独一条")
        #expect(DockerComposeToRunDiagnostics.warningMessage(for: []) == nil)
    }
}
