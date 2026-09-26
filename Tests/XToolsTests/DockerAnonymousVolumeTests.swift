import Testing
import Yams
@testable import XToolsCore

struct DockerAnonymousVolumeTests {
    @Test func runAnonymousVolumeKeepsOmittedSourceAndRoundTrips() throws {
        let run = "docker run --mount type=volume,target=/data,readonly --mount type=volume,source=cache,target=/cache alpine"
        let forward = try DockerRunToDockerComposeService.convert(run)
        #expect(forward.notImplemented.isEmpty)

        let (mounts, shorts, root) = try parsedMounts(in: forward.yaml)
        #expect(mounts.count == 2)
        #expect(shorts.isEmpty)
        #expect(mounts[0]["type"] as? String == "volume")
        #expect(mounts[0]["source"] == nil)
        #expect(mounts[0]["target"] as? String == "/data")
        #expect(mounts[0]["read_only"] as? Bool == true)
        #expect(mounts[1]["source"] as? String == "cache")
        let declarations = try #require(root["volumes"] as? [String: Any])
        #expect(Set(declarations.keys) == ["cache"])

        let reverse = try DockerComposeToRunService.convert(forward.yaml)
        let arguments = try DockerRunToDockerComposeService.tokenize(try #require(reverse.commands.first))
        #expect(mountArguments(in: arguments) == [
            "type=volume,target=/data,readonly",
            "type=volume,source=cache,target=/cache"
        ])
    }

    @Test func composeAnonymousVolumeKeepsReadOnlyAndOtherMountKinds() throws {
        let yaml = """
        services:
          app:
            image: alpine
            volumes:
              - type: volume
                target: /data
                read_only: true
              - type: volume
                source: cache
                target: /cache
              - type: bind
                source: ./site
                target: /site
              - /scratch
              - type: tmpfs
                target: /run
        """
        let reverse = try DockerComposeToRunService.convert(yaml)
        #expect(reverse.warnings.isEmpty)
        let arguments = try DockerRunToDockerComposeService.tokenize(try #require(reverse.commands.first))
        #expect(mountArguments(in: arguments) == [
            "type=volume,target=/data,readonly",
            "type=volume,source=cache,target=/cache",
            "type=bind,source=./site,target=/site",
            "type=tmpfs,target=/run"
        ])
        #expect(zip(arguments, arguments.dropFirst()).contains { $0.0 == "-v" && $0.1 == "/scratch" })

        let forward = try DockerRunToDockerComposeService.convert(try #require(reverse.commands.first))
        #expect(forward.notImplemented.isEmpty)
        let (mounts, shorts, root) = try parsedMounts(in: forward.yaml)
        #expect(mounts.count == 4)
        #expect(mounts[0]["source"] == nil)
        #expect(mounts[0]["target"] as? String == "/data")
        #expect(mounts[0]["read_only"] as? Bool == true)
        #expect(mounts[1]["source"] as? String == "cache")
        #expect(mounts[2]["source"] as? String == "./site")
        #expect(mounts[3]["target"] as? String == "/run")
        #expect(shorts == ["/scratch"])
        let declarations = try #require(root["volumes"] as? [String: Any])
        #expect(Set(declarations.keys) == ["cache"])
    }

    @Test func missingBindSourceAndUnsupportedOptionsStillWarn() throws {
        let run = "docker run --mount type=bind,target=/lost --mount type=volume,source=,target=/empty --mount type=volume,target=/ok alpine"
        let forward = try DockerRunToDockerComposeService.convert(run)
        // The existing option splitter classifies an explicit `source=` as an
        // empty option; it still rejects that mount rather than treating it as
        // an omitted source for an anonymous volume.
        #expect(Set(forward.notImplemented) == ["--mount.source", "--mount.option"])
        let (mounts, shorts, _) = try parsedMounts(in: forward.yaml)
        #expect(mounts.count == 1)
        #expect(shorts.isEmpty)
        #expect(mounts[0]["target"] as? String == "/ok")

        let yaml = """
        services:
          app:
            image: alpine
            volumes:
              - type: bind
                target: /lost
              - type: volume
                target: /unsupported
                volume:
                  nocopy: true
              - type: volume
                target: /ok
        """
        let reverse = try DockerComposeToRunService.convert(yaml)
        let arguments = try DockerRunToDockerComposeService.tokenize(try #require(reverse.commands.first))
        #expect(mountArguments(in: arguments) == ["type=volume,target=/ok"])
        let warning = try #require(reverse.warnings.first { $0.contains("服务 app 未映射字段") })
        #expect(warning.contains("volumes.bind.source"))
        #expect(warning.contains("volumes.volume.volume.nocopy"))
    }

    private func parsedMounts(in yaml: String) throws -> ([[String: Any]], [String], [String: Any]) {
        let root = try #require(try Yams.load(yaml: yaml) as? [String: Any])
        let services = try #require(root["services"] as? [String: Any])
        let service = try #require(services["alpine"] as? [String: Any] ?? services["app"] as? [String: Any])
        let items = try #require(service["volumes"] as? [Any])
        return (items.compactMap { $0 as? [String: Any] }, items.compactMap { $0 as? String }, root)
    }

    private func mountArguments(in tokens: [String]) -> [String] {
        zip(tokens, tokens.dropFirst()).compactMap { pair in
            pair.0 == "--mount" ? pair.1 : nil
        }
    }
}
