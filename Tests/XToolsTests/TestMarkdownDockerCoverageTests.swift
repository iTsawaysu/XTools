import XToolsCore
import Testing

struct TestMarkdownDockerCoverageTests {
    @Test(arguments: [
        "DOCKER-01", "DOCKER-02", "DOCKER-03", "DOCKER-04", "DOCKER-05",
        "DOCKER-06", "DOCKER-07", "DOCKER-08", "DOCKER-09", "DOCKER-10",
        "DOCKER-11", "DOCKER-12", "DOCKER-13", "DOCKER-14", "DOCKER-15",
        "DOCKER-16", "DOCKER-17", "DOCKER-18", "DOCKER-19", "DOCKER-20"
    ])
    func dockerCase(_ id: String) throws {
        let testCase = try TestMarkdownCaseSupport.testCase(id)

        switch id {
        case "DOCKER-01":
            let result = try convert(testCase)
            #expect(result.yaml.contains("image: nginx"))
            #expect(result.yaml.contains("services:"))
        case "DOCKER-02":
            let result = try convert(testCase)
            for fragment in ["container_name: dev-api", "8080:80", "NODE_ENV=production", "LOG_LEVEL=info", "/Users/sun/data:/app/data", "restart: unless-stopped"] {
                #expect(result.yaml.contains(fragment))
            }
            #expect(result.warnings.isEmpty)
        case "DOCKER-03":
            let result = try convert(testCase)
            for fragment in ["stdin_open: true", "tty: true", "entrypoint:", "/bin/sh", "working_dir: /workspace", "user: \"1000:1000\"", "command:", "npm ci && npm test"] {
                #expect(result.yaml.contains(fragment))
            }
            #expect(result.warnings.isEmpty)
        case "DOCKER-04":
            let result = try convert(testCase)
            for fragment in ["dev-net", "db-client", "extra_hosts:", "host.docker.internal:host-gateway", "dns:", "1.1.1.1", "command:", "psql", "-h", "db", "-U", "app"] {
                #expect(result.yaml.contains(fragment))
            }
        case "DOCKER-05":
            let result = try convert(testCase)
            for fragment in ["privileged: true", "cap_add:", "NET_ADMIN", "devices:", "/dev/fuse:/dev/fuse", "memory: 2g", "cpus: \"1.5\"", "healthcheck:", "interval: 30s", "com.example.role=worker", "capabilities: [gpu]"] {
                #expect(result.yaml.contains(fragment))
            }
        case "DOCKER-06":
            let result = try convert(testCase)
            #expect(result.yaml.contains("EMPTY="))
            #expect(result.yaml.contains("TOKEN=abc=123==xyz"))
            #expect(result.yaml.contains(#"JSON={\"enabled\":true,\"count\":3}"#))
            #expect(result.yaml.contains("- env"))
        case "DOCKER-07":
            #expect {
                _ = try DockerRunToDockerComposeService.convert(try block(testCase, 0))
            } throws: { error in
                guard case DockerRunToDockerComposeError.missingImage = error else { return false }
                return true
            }
        case "DOCKER-08":
            let result = try convert(testCase)
            #expect(result.yaml.contains("image: nginx"))
            #expect(result.unknownFlags == ["--naem"])
            #expect(DockerRunToDockerComposeDiagnostics.warningMessage(for: result.warnings) == "部分 Docker 选项无法转换。")
        case "DOCKER-09":
            #expect {
                _ = try DockerRunToDockerComposeService.convert(try block(testCase, 0))
            } throws: { error in
                guard case DockerRunToDockerComposeError.unterminatedQuote = error else { return false }
                return true
            }
        case "DOCKER-10":
            let result = try convert(testCase)
            for fragment in ["hostname: web-1", "env_file:", ".env", "./secrets.env", "expose:", "9000", "read_only: true", "init: true"] {
                #expect(result.yaml.contains(fragment))
            }
        case "DOCKER-11":
            let result = try convert(testCase)
            for fragment in ["127.0.0.1:8080:80", "53:53/udp", "type: bind", "source: ./site", "target: /usr/share/nginx/html", "read_only: true", "type: volume", "source: cache-data", "target: /cache", "tmpfs:", "/run:size=64m", "volumes:", "cache-data:"] {
                #expect(result.yaml.contains(fragment))
            }
        case "DOCKER-12":
            let result = try convert(testCase)
            for fragment in ["container_name: inline", "stdin_open: true", "tty: true", "8080:80", "APP_ENV=prod", "./data:/data:ro", "restart_policy:", "max_attempts: 3", "- sh"] {
                #expect(result.yaml.contains(fragment))
            }
            #expect(result.yaml.components(separatedBy: "    deploy:").count - 1 == 1)
            #expect(result.warnings.isEmpty)
        case "DOCKER-13":
            let result = try convert(testCase)
            #expect(result.yaml.contains("image: nginx"))
            #expect(Set(result.notImplemented) == Set(["--cidfile", "--publish-all"]))
            let warning = DockerRunToDockerComposeDiagnostics.warningMessage(for: result.warnings)
            #expect(warning == "部分 Docker 选项无法转换。")
        case "DOCKER-14":
            #expect {
                _ = try DockerRunToDockerComposeService.convert(try block(testCase, 0))
            } throws: { error in
                guard case DockerRunToDockerComposeError.multipleCommands = error else { return false }
                return true
            }
        case "DOCKER-15":
            let result = try convert(testCase)
            try YAMLPrettifier.validate(result.yaml)
            #expect(result.yaml.contains(#"WIN=C:\\Temp\\new"#))
            #expect(result.yaml.contains(#"CTRL=line\tbreak"#))
            #expect(result.yaml.contains(#"note=A # B: C"#))
        case "DOCKER-16":
            #expect(DockerRunToDockerComposeError.invalidCommand.errorDescription == "无法识别 docker run 命令：输入必须以 docker run 开头。")
            #expect(DockerRunToDockerComposeError.multipleCommands.errorDescription == "一次只能转换一条 docker run 命令。")
            #expect(DockerRunToDockerComposeError.missingImage.errorDescription == "docker run 命令缺少镜像名称。")
            #expect(DockerRunToDockerComposeError.missingOptionValue("--name").errorDescription == "选项 `--name` 缺少参数值。")
            #expect(DockerRunToDockerComposeError.unterminatedQuote.errorDescription == "命令包含未闭合的引号。")
            let ignoredRuntimeOption = try DockerRunToDockerComposeService.convert("docker run -d nginx")
            #expect(DockerRunToDockerComposeDiagnostics.warningMessage(for: ignoredRuntimeOption.warnings) == nil)

            let warningCases = [
                try DockerRunToDockerComposeService.convert("docker run --cidfile /tmp/id nginx"),
                try DockerRunToDockerComposeService.convert("docker run --naem typo nginx")
            ]
            for result in warningCases {
                #expect(DockerRunToDockerComposeDiagnostics.warningMessage(for: result.warnings) != nil)
            }
        case "DOCKER-17":
            let source = try pageSource()
            #expect(source.contains("maxInputCharacters = 200_000"))
            #expect(source.contains("guard trimmed.count <= maxInputCharacters"))
            #expect(source.contains("DockerRunToDockerComposeDiagnostics.inputTooLongMessage"))
        case "DOCKER-18":
            let source = try pageSource()
            #expect(source.contains("guard !trimmed.isEmpty else"))
            #expect(source.contains("return FormatBinding()"))
            #expect(source.contains("execution.schedule"))
        case "DOCKER-19":
            let result = try convert(testCase)
            #expect(result.yaml.contains("platform: linux/amd64"))
            #expect(result.yaml.contains("healthcheck:"))
            #expect(result.yaml.contains("disable: true"))
            #expect(result.warnings.isEmpty)
        case "DOCKER-20":
            let matrix = try DockerRunToDockerComposeService.convert(try block(testCase, 0))
            let host = try DockerRunToDockerComposeService.convert(try block(testCase, 1))
            let requiredFragments = [
                "networks:", "aliases:", "ipv4_address: 172.20.0.10", "ipv6_address:", "mac_address:",
                "dns_opt:", "dns_search:", "pid: host", "uts: host", "ipc: host", "cap_add:", "cap_drop:",
                "security_opt:", "userns_mode: host", "group_add:", "sysctls:", "ulimits:", "devices:",
                "device_read_bps:", "device_write_bps:", "device_read_iops:", "device_write_iops:",
                "cpu_shares: \"512\"", "cpu_period: \"100000\"", "cpu_quota: \"50000\"", "cpuset: 0-3",
                "memory: 512m", "memory: 256m", "memswap_limit: 1g", "mem_swappiness: \"10\"",
                "pids: \"128\"", "weight: 300", "shm_size: 64m", "oom_score_adj: \"-500\"",
                "logging:", "max-size: 10m", "stop_signal: SIGTERM", "stop_grace_period: 15s",
                "capabilities: [gpu]", "init: true", "oom_kill_disable: true"
            ]
            for fragment in requiredFragments {
                #expect(matrix.yaml.contains(fragment), "Missing \(fragment)")
            }
            #expect(matrix.warnings.isEmpty)
            #expect(host.yaml.contains("network_mode: host"))
            try YAMLPrettifier.validate(matrix.yaml)
            try YAMLPrettifier.validate(host.yaml)
        default:
            Issue.record("Unhandled case \(id)")
        }
    }

    private func convert(_ testCase: MarkdownDevelopmentCase) throws -> DockerRunToDockerComposeService.Result {
        try DockerRunToDockerComposeService.convert(try block(testCase, 0))
    }

    private func block(_ testCase: MarkdownDevelopmentCase, _ index: Int) throws -> String {
        try TestMarkdownCaseSupport.block(testCase, index)
    }

    private func pageSource() throws -> String {
        try TestMarkdownCaseSupport.readSource("Sources/XTools/ToolPages/Development/DockerRunToComposePage.swift")
    }
}
