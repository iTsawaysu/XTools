import Testing
@testable import XToolsCore

struct DockerRunToDockerComposeServiceTests {
    @Test func simpleContainerConversion() throws {
        let result = try DockerRunToDockerComposeService.convert("docker run -d nginx")

        #expect(result.yaml.contains("services:"))
        #expect(result.yaml.contains("image: nginx"))
        #expect(result.notTranslatable.isEmpty)
        #expect(result.notImplemented == [])
        #expect(result.warnings.isEmpty)
    }

    @Test func containerWithPortAndVolume() throws {
        let result = try DockerRunToDockerComposeService.convert(
            "docker run --name web -p 8080:80 -v $(pwd)/site:/usr/share/nginx/html:ro nginx"
        )

        #expect(result.yaml.contains("  web:"))
        #expect(result.yaml.contains("container_name: web"))
        #expect(result.yaml.contains("- \"8080:80\""))
        #expect(result.yaml.contains("- \"./site:/usr/share/nginx/html:ro\""))
    }

    @Test func containerWithEnvironmentAndCommand() throws {
        let result = try DockerRunToDockerComposeService.convert(
            "docker run --env APP_ENV=prod --entrypoint sh alpine -c \"echo hello\""
        )

        #expect(result.yaml.contains("- APP_ENV=prod"))
        #expect(result.yaml.contains("entrypoint:"))
        #expect(result.yaml.contains("- sh"))
        #expect(result.yaml.contains("command:"))
        #expect(result.yaml.contains("- -c"))
        #expect(result.yaml.contains("- \"echo hello\""))
    }

    @Test func combinedInteractiveFlags() throws {
        let result = try DockerRunToDockerComposeService.convert("docker run -it ubuntu bash")

        #expect(result.yaml.contains("stdin_open: true"))
        #expect(result.yaml.contains("tty: true"))
        #expect(result.yaml.contains("- bash"))
    }

    @Test func inlineLongOptions() throws {
        let result = try DockerRunToDockerComposeService.convert(
            "docker run --name=web --restart=unless-stopped --network=host nginx"
        )

        #expect(result.yaml.contains("  web:"))
        #expect(result.yaml.contains("container_name: web"))
        #expect(result.yaml.contains("restart: unless-stopped"))
        #expect(result.yaml.contains("network_mode: host"))
    }

    @Test func stickyShortOptions() throws {
        let result = try DockerRunToDockerComposeService.convert(
            "docker run -p8080:80 -eAPP_ENV=prod -v$(pwd)/data:/data:ro nginx"
        )

        #expect(result.yaml.contains("- \"8080:80\""))
        #expect(result.yaml.contains("APP_ENV=prod"))
        #expect(result.yaml.contains("- \"./data:/data:ro\""))
        #expect(result.yaml.contains("image: nginx"))
    }

    @Test func userShortOptionIsConverted() throws {
        let separated = try DockerRunToDockerComposeService.convert("docker run -u 1000:1000 alpine")
        let sticky = try DockerRunToDockerComposeService.convert("docker run -u1000:1000 alpine")

        #expect(separated.yaml.contains("user: \"1000:1000\""))
        #expect(sticky.yaml.contains("user: \"1000:1000\""))
        #expect(separated.unknownFlags.isEmpty)
        #expect(sticky.unknownFlags.isEmpty)
    }

    @Test func unsupportedValueFlagDoesNotConsumeImage() throws {
        let result = try DockerRunToDockerComposeService.convert("docker run --cidfile /tmp/nginx.cid nginx")

        #expect(result.yaml.contains("image: nginx"))
        #expect(result.notImplemented == ["--cidfile"])
        #expect(result.unknownFlags == [])
        #expect(result.warnings.contains(.init(kind: .notImplemented, option: "--cidfile")))
    }

    @Test func unsupportedBooleanFlagDoesNotConsumeImage() throws {
        let result = try DockerRunToDockerComposeService.convert("docker run --publish-all nginx")

        #expect(result.yaml.contains("image: nginx"))
        #expect(result.notImplemented == ["--publish-all"])
        #expect(result.unknownFlags == [])
        #expect(result.warnings.contains(.init(kind: .notImplemented, option: "--publish-all")))
    }

    @Test func supportedPlatformAndDisabledHealthcheckAreRendered() throws {
        let result = try DockerRunToDockerComposeService.convert("docker run --platform linux/amd64 --no-healthcheck nginx")

        #expect(result.yaml.contains("image: nginx"))
        #expect(result.yaml.contains("platform: linux/amd64"))
        #expect(result.yaml.contains("healthcheck:"))
        #expect(result.yaml.contains("disable: true"))
        #expect(result.notImplemented.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test func runLifecycleOptionsAreIgnoredWithoutWarnings() throws {
        let result = try DockerRunToDockerComposeService.convert(
            #"docker run --rm -d -a stdout --sig-proxy=false -it --name job-runner --entrypoint /bin/sh -w /workspace -u 1000:1000 -v "$PWD":/workspace node:22-alpine -lc "npm ci && npm test""#
        )

        #expect(result.yaml.contains("container_name: job-runner"))
        #expect(result.yaml.contains("stdin_open: true"))
        #expect(result.yaml.contains("tty: true"))
        #expect(result.yaml.contains("command:"))
        #expect(result.yaml.contains(#"- "npm ci && npm test""#))
        #expect(result.notTranslatable.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test func resourceRuntimeSampleIgnoresDetachWithoutWarning() throws {
        let result = try DockerRunToDockerComposeService.convert(
            #"docker run -d --name gpu-worker --gpus all --privileged --cap-add NET_ADMIN --device /dev/fuse:/dev/fuse --memory 2g --cpus 1.5 --health-cmd "curl -f http://localhost:9000/health || exit 1" --health-interval 30s --label com.example.role=worker example/gpu-worker:latest"#
        )

        #expect(result.yaml.contains("container_name: gpu-worker"))
        #expect(result.yaml.contains("privileged: true"))
        #expect(result.yaml.contains("cap_add:"))
        #expect(result.yaml.contains("- NET_ADMIN"))
        #expect(result.yaml.contains("devices:"))
        #expect(result.yaml.contains("- \"/dev/fuse:/dev/fuse\""))
        #expect(result.yaml.contains("healthcheck:"))
        #expect(result.yaml.contains("interval: 30s"))
        #expect(result.yaml.contains("deploy:"))
        #expect(result.notTranslatable.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test func unknownFlagIsReportedSeparatelyFromKnownUnsupportedFlags() throws {
        let result = try DockerRunToDockerComposeService.convert(
            "docker run --naem typo-nginx -p 8080:80 nginx"
        )

        #expect(result.yaml.contains("image: nginx"))
        #expect(result.yaml.contains("- \"8080:80\""))
        #expect(result.notImplemented == [])
        #expect(result.unknownFlags == ["--naem"])
        #expect(result.warnings.contains(.init(kind: .unknownFlag, option: "--naem")))
    }

    @Test func diagnosticsStayLocalizedAndGroupWarnings() {
        #expect(DockerRunToDockerComposeError.invalidCommand.errorDescription == "无法识别 docker run 命令：输入必须以 docker run 开头。")
        #expect(DockerRunToDockerComposeError.multipleCommands.errorDescription == "一次只能转换一条 docker run 命令。")
        #expect(DockerRunToDockerComposeError.missingImage.errorDescription == "docker run 命令缺少镜像名称。")
        #expect(DockerRunToDockerComposeError.missingOptionValue("--name").errorDescription == "选项 `--name` 缺少参数值。")
        #expect(DockerRunToDockerComposeError.unterminatedQuote.errorDescription == "命令包含未闭合的引号。")
        #expect(DockerRunToDockerComposeDiagnostics.inputTooLongMessage(maxCharacters: 200_000) == "输入内容过长，最多支持 200000 个字符。")
        #expect(DockerRunToDockerComposeDiagnostics.emptyOutputMessage == "命令未包含可转换的服务配置。")
        #expect(DockerRunToDockerComposeDiagnostics.fallbackErrorMessage == "docker run 命令格式无效。")
        #expect(!(DockerRunToDockerComposeError.missingOptionValue("--name").errorDescription ?? "").contains("处理方式："))
        #expect(!(DockerRunToDockerComposeError.invalidCommand.errorDescription ?? "").contains("Input must"))

        let message = DockerRunToDockerComposeDiagnostics.warningMessage(
            for: [
                .init(kind: .notTranslatable, option: "-d"),
                .init(kind: .notTranslatable, option: "--rm"),
                .init(kind: .notTranslatable, option: "--rm"),
                .init(kind: .notImplemented, option: "--cidfile"),
                .init(kind: .unknownFlag, option: "--naem"),
                .init(kind: .unknownFlag, option: "--mystery"),
                .init(kind: .unknownFlag, option: "--future")
            ],
            maxOptionsPerGroup: 2
        )

        #expect(message == "部分 Docker 选项无法转换。")
        ToolDiagnosticContract.expectFactual(message ?? "")

        let secretWarning = DockerRunToDockerComposeDiagnostics.warningMessage(for: [
            .init(kind: .unknownFlag, option: "--token=private-secret-value")
        ])
        #expect(secretWarning == "部分 Docker 选项无法转换。")
        ToolDiagnosticContract.expectFactual(
            secretWarning ?? "",
            sensitiveInputs: ["--token=private-secret-value"]
        )
    }

    @Test func invalidCommandThrows() throws {
        #expect {
            _ = try DockerRunToDockerComposeService.convert("docker compose up")
        } throws: { error in
            guard case DockerRunToDockerComposeError.invalidCommand = error else { return false }
            return true
        }
    }

    /// 裸「docker run」没有镜像参数，必须报缺镜像而不是「无法识别命令」——
    /// 它本来就是一条 docker run 命令。
    @Test func bareDockerRunReportsMissingImage() throws {
        #expect {
            _ = try DockerRunToDockerComposeService.convert("docker run")
        } throws: { error in
            guard case DockerRunToDockerComposeError.missingImage = error else { return false }
            return true
        }
    }

    @Test func unterminatedQuoteThrows() throws {
        #expect {
            _ = try DockerRunToDockerComposeService.convert(#"docker run -e MESSAGE="hello nginx"#)
        } throws: { error in
            guard case DockerRunToDockerComposeError.unterminatedQuote = error else { return false }
            return true
        }
    }

    @Test func missingOptionValueThrows() throws {
        #expect {
            _ = try DockerRunToDockerComposeService.convert("docker run --name")
        } throws: { error in
            guard case DockerRunToDockerComposeError.missingOptionValue("--name") = error else { return false }
            return true
        }
    }

    @Test func splicedCommandsThrow() throws {
        // Two complete commands pasted with a separating space.
        #expect {
            _ = try DockerRunToDockerComposeService.convert(
                "docker run --rm -it alpine sh docker run --rm -it alpine sh"
            )
        } throws: { error in
            guard case DockerRunToDockerComposeError.multipleCommands = error else { return false }
            return true
        }
    }

    @Test func concatenatedCommandsThrow() throws {
        // Two commands pasted with NO separator: `sh` and `docker` fuse into the
        // single token `shdocker`, so detection must scan the raw string rather
        // than rely on a standalone `docker` token.
        #expect {
            _ = try DockerRunToDockerComposeService.convert(
                "docker run --rm -it alpine shdocker run --rm -it alpine sh"
            )
        } throws: { error in
            guard case DockerRunToDockerComposeError.multipleCommands = error else { return false }
            return true
        }
    }

    @Test func dockerRunInQuotedArgumentIsAllowed() throws {
        // A literal `docker run` inside a quoted command argument must NOT be
        // counted as a second command.
        let result = try DockerRunToDockerComposeService.convert(
            "docker run alpine echo \"docker run inside a string\""
        )
        #expect(result.yaml.contains("image: alpine"))
    }

    @Test func deploySectionsAreMergedForResourcesRestartPolicyAndGpu() throws {
        let result = try DockerRunToDockerComposeService.convert(
            "docker run --cpus=0.5 --memory=256m --restart on-failure:3 --gpus all nginx"
        )

        #expect(result.yaml.components(separatedBy: "    deploy:").count - 1 == 1)
        #expect(result.yaml.contains("      resources:"))
        #expect(result.yaml.contains("        limits:"))
        #expect(result.yaml.contains("          cpus: \"0.5\""))
        #expect(result.yaml.contains("          memory: 256m"))
        #expect(result.yaml.contains("      restart_policy:"))
        #expect(result.yaml.contains("        condition: on-failure"))
        #expect(result.yaml.contains("        max_attempts: 3"))
        #expect(result.yaml.contains("        reservations:"))
        #expect(result.yaml.contains("          devices:"))
        #expect(result.yaml.contains("              count: all"))
    }

    @Test func gpuReservationMergesWithExistingResourceReservations() throws {
        let result = try DockerRunToDockerComposeService.convert(
            "docker run --memory-reservation=128m --gpus=2 nginx"
        )

        #expect(result.yaml.components(separatedBy: "        reservations:").count - 1 == 1)
        #expect(result.yaml.contains("          memory: 128m"))
        #expect(result.yaml.contains("          devices:"))
        #expect(result.yaml.contains("              count: \"2\""))
    }

    @Test func yamlScalarsEscapeBackslashesWhenQuoted() throws {
        let result = try DockerRunToDockerComposeService.convert(
            #"docker run --env WIN=C:\Temp\new nginx"#
        )

        #expect(result.yaml.contains(#"- "WIN=C:\\Temp\\new""#))
    }

    @Test func tokenizerPreservesShellSpecificBackslashSemantics() throws {
        let singleQuoted = try DockerRunToDockerComposeService.tokenize(
            #"docker run -e 'WIN=C:\temp' alpine"#
        )
        #expect(singleQuoted == ["docker", "run", "-e", #"WIN=C:\temp"#, "alpine"])

        let doubleQuoted = try DockerRunToDockerComposeService.tokenize(
            #"docker run -e "WIN=C:\q" alpine sh -c "echo C:\q \"quoted\" \\ done""#
        )
        #expect(doubleQuoted == [
            "docker", "run", "-e", #"WIN=C:\q"#, "alpine", "sh", "-c", #"echo C:\q "quoted" \ done"#
        ])

        let result = try DockerRunToDockerComposeService.convert(
            #"docker run -e 'WIN=C:\temp' alpine sh -c "echo C:\q \"quoted\" \\ done""#
        )
        #expect(result.yaml.contains(#"- "WIN=C:\\temp""#))
        #expect(result.yaml.contains(#"- "echo C:\\q \"quoted\" \\ done""#))
    }

    @Test func tokenizerPreservesEmptyQuotedArguments() throws {
        let tokens = try DockerRunToDockerComposeService.tokenize(
            #"docker run -e EMPTY="" alpine printf '%s' """#
        )
        #expect(tokens == ["docker", "run", "-e", "EMPTY=", "alpine", "printf", "%s", ""])

        let result = try DockerRunToDockerComposeService.convert(
            #"docker run -e EMPTY="" alpine printf '%s' """#
        )
        #expect(result.yaml.contains("- EMPTY="))
        #expect(result.yaml.contains("      - \"\""))
    }

    @Test func malformedExtendedNetworkAndMountOptionsWarnWithoutLeakingValues() throws {
        let network = try DockerRunToDockerComposeService.convert(
            "docker run --network alias=private-network-alias nginx"
        )
        #expect(!network.yaml.contains("private-network-alias"))
        #expect(network.notImplemented.contains("--network.name"))

        let mount = try DockerRunToDockerComposeService.convert(
            "docker run --mount type=bind,source=/host,target=/data,bind-propagation=private-mode nginx"
        )
        #expect(!mount.yaml.contains("/host:/data"))
        #expect(!mount.yaml.contains("private-mode"))
        #expect(mount.notImplemented.contains("--mount.bind-propagation"))
    }

    @Test func extendedNetworkAttachmentsRemainIndependentInCompose() throws {
        let result = try DockerRunToDockerComposeService.convert(
            "docker run --network name=front,alias=web,alias=api,ip=172.20.0.5,ip6=2001:db8::5 --network back nginx"
        )

        #expect(result.yaml.contains("      front:"))
        #expect(result.yaml.contains("        ipv4_address: 172.20.0.5"))
        #expect(result.yaml.contains("        ipv6_address: \"2001:db8::5\""))
        #expect(result.yaml.contains("          - web"))
        #expect(result.yaml.contains("          - api"))
        #expect(result.yaml.contains("      back:"))
    }

    @Test func networkModifiersBeforeOrAfterNetworkAttachToTheMatchingNetwork() throws {
        let before = try DockerRunToDockerComposeService.convert(
            "docker run --ip 172.20.0.5 --ip6 2001:db8::5 --network-alias web --network front --network back nginx"
        )
        #expect(before.yaml.contains("      front:"))
        #expect(before.yaml.contains("        ipv4_address: 172.20.0.5"))
        #expect(before.yaml.contains("        ipv6_address: \"2001:db8::5\""))
        #expect(before.yaml.contains("          - web"))
        #expect(!before.yaml.contains("      back:\n        ipv4_address"))

        let after = try DockerRunToDockerComposeService.convert(
            "docker run --network front --ip 172.20.0.5 --ip6 2001:db8::5 --network-alias web --network back nginx"
        )
        #expect(after.yaml == before.yaml)
    }

    @Test func yamlScalarsQuoteAndEscapeEmbeddedControlCharacters() throws {
        let tabbed = try DockerRunToDockerComposeService.convert(
            "docker run --env \"CTRL=line\tbreak\" nginx"
        )
        #expect(tabbed.yaml.contains(#"- "CTRL=line\tbreak""#))

        let controlled = try DockerRunToDockerComposeService.convert(
            "docker run --env \"CTRL=a\u{8}b\" nginx"
        )
        #expect(controlled.yaml.contains(#"- "CTRL=a\u0008b""#))
    }

    @Test func numericComposeSchemaFieldsRemainNumbers() throws {
        let result = try DockerRunToDockerComposeService.convert(
            "docker run --blkio-weight 300 alpine"
        )

        #expect(result.yaml.contains("weight: 300"))
        #expect(!result.yaml.contains("weight: \"300\""))
    }

    // MARK: - Unknown / boolean flags

    /// 布尔标志不接收值，不能把紧随其后的镜像名吞掉。
    /// 此前 `-P` / `--disable-content-trust` / `--no-healthcheck` 未列入布尔标志，
    /// 解析器按「未知标志可能有值」处理，把镜像名当成了它的参数。
    @Test func booleanFlagsDoNotSwallowTheImageName() throws {
        let commands = [
            "docker run -P nginx",
            "docker run --publish-all nginx",
            "docker run --disable-content-trust nginx",
            "docker run --no-healthcheck nginx",
            "docker run -d -P nginx",
            "docker run --privileged --no-healthcheck nginx"
        ]

        for command in commands {
            let result = try DockerRunToDockerComposeService.convert(command)
            #expect(
                result.yaml.contains("image: nginx"),
                Comment(rawValue: "「\(command)」丢失镜像：\(result.yaml)")
            )
        }
    }

    /// 未知标志后面只剩一个 token 时不能吞掉它，否则整条命令找不到镜像。
    /// 同时保留「未知标志确实带值」的常见形态（值后面还有 token）。
    @Test func unknownFlagsKeepTheImageRecoverable() throws {
        let trailingImage = try DockerRunToDockerComposeService.convert("docker run -Z alpine")
        #expect(trailingImage.yaml.contains("image: alpine"), Comment(rawValue: trailingImage.yaml))
        #expect(trailingImage.unknownFlags == ["-Z"])

        let flagWithValue = try DockerRunToDockerComposeService.convert("docker run --tlsverify value alpine")
        #expect(flagWithValue.yaml.contains("image: alpine"), Comment(rawValue: flagWithValue.yaml))
        #expect(flagWithValue.unknownFlags == ["--tlsverify"])
    }

    /// `--` 终止选项解析：其后第一个 token 是镜像，而不是命令的一部分。
    @Test func doubleDashTreatsTheNextTokenAsTheImage() throws {
        let result = try DockerRunToDockerComposeService.convert("docker run -- alpine echo hi")
        #expect(result.yaml.contains("image: alpine"), Comment(rawValue: result.yaml))
        #expect(result.yaml.contains("command:"), Comment(rawValue: result.yaml))
        #expect(!result.yaml.contains("image: echo"), Comment(rawValue: result.yaml))

        let withOptions = try DockerRunToDockerComposeService.convert("docker run -d --name x -- busybox sh -c 'echo hi'")
        #expect(withOptions.yaml.contains("image: busybox"), Comment(rawValue: withOptions.yaml))
        #expect(withOptions.yaml.contains("command:"), Comment(rawValue: withOptions.yaml))
    }

    // MARK: - Network mode

    /// `--network` 的 none / bridge / container: 不是外部网络名，必须走
    /// network_mode；否则会凭空生成同名外部网络，语义与 docker 完全相反。
    @Test func networkModesDoNotBecomeExternalNetworks() throws {
        let expectations = [
            ("docker run --network none alpine", "network_mode: none"),
            ("docker run --network bridge alpine", "network_mode: bridge"),
            ("docker run --network host alpine", "network_mode: host"),
            ("docker run --network container:abc alpine", "network_mode: \"container:abc\"")
        ]

        for (command, expected) in expectations {
            let result = try DockerRunToDockerComposeService.convert(command)
            #expect(result.yaml.contains(expected), Comment(rawValue: "「\(command)」→ \(result.yaml)"))
            #expect(!result.yaml.contains("external: true"), Comment(rawValue: result.yaml))
        }

        // 自定义网络名仍然走外部网络。
        let custom = try DockerRunToDockerComposeService.convert("docker run --network mynet alpine")
        #expect(custom.yaml.contains("      - mynet"), Comment(rawValue: custom.yaml))
        #expect(custom.yaml.contains("external: true"), Comment(rawValue: custom.yaml))
    }

    /// 宿主路径里的 Windows 盘符不能被凭空生成成具名卷。
    /// （本工具跑在 macOS，但输入是粘贴来的 docker 命令文本，可能来自 Windows 上写的命令。）
    @Test func windowsDriveVolumeStaysABindMount() throws {
        for command in ["docker run -v C:\\data:/data nginx", "docker run -v c:/data:/data nginx"] {
            let result = try DockerRunToDockerComposeService.convert(command)
            #expect(
                !result.yaml.contains("\nvolumes:"),
                Comment(rawValue: "「\(command)」凭空生成了具名卷：\(result.yaml)")
            )
            #expect(result.yaml.contains("image: nginx"), Comment(rawValue: result.yaml))
        }

        // 单字母具名卷必须仍然被声明，不能被盘符判定误伤。
        let singleLetter = try DockerRunToDockerComposeService.convert("docker run -v x:/data nginx")
        #expect(singleLetter.yaml.contains("\nvolumes:"), Comment(rawValue: singleLetter.yaml))
        #expect(singleLetter.yaml.contains("  x:"), Comment(rawValue: singleLetter.yaml))

        // 具名卷仍然要被声明。
        let named = try DockerRunToDockerComposeService.convert("docker run -v vol:/data nginx")
        #expect(named.yaml.contains("\nvolumes:"), Comment(rawValue: named.yaml))
        #expect(named.yaml.contains("  vol:"), Comment(rawValue: named.yaml))
    }

    // MARK: - YAML scalar quoting

    /// 以 YAML 节点指示符开头的参数值必须加引号：`*` 会被读成别名、`&` 锚点、
    /// `!` 标签、`|`/`>` 块标量、`%`/`@` 保留指示符。早先只检查「是否包含」常见
    /// 标点，于是 `echo '*'` 生成 `- *`（空别名），整份 Compose 直接解析失败。
    @Test func argumentsStartingWithYAMLIndicatorsStayParseable() throws {
        let commands = [
            "docker run alpine echo '*'",
            "docker run alpine echo '%pct'",
            "docker run alpine echo '@at'",
            "docker run alpine echo '|pipe'",
            "docker run alpine echo '>gt'",
            "docker run alpine echo '&anchor'",
            "docker run alpine echo '!tag'",
            "docker run alpine echo ',comma'",
            "docker run alpine echo '#hash'",
            "docker run alpine echo '`tick'",
            "docker run alpine echo '-'",
            "docker run alpine echo '?'",
            "docker run alpine echo ':'",
            "docker run alpine echo 'plain'",
            "docker run alpine echo '-dash'",
            "docker run alpine echo '?q'"
        ]

        for command in commands {
            let generated = try DockerRunToDockerComposeService.convert(command)
            // 生成物必须能被 Compose 解析器吃回去，否则用户拿到的是坏 YAML。
            let reparsed = try DockerComposeToRunService.convert(generated.yaml)
            let rerun = try #require(
                reparsed.commands.first,
                Comment(rawValue: "生成物无法回灌：\n\(generated.yaml)")
            )
            #expect(
                rerun.contains("--entrypoint") || rerun.contains(" echo ") || rerun.contains("-c "),
                Comment(rawValue: "「\(command)」的参数在回灌后丢失：\(rerun)")
            )
        }
    }

    /// `-m` / `-c` 是 `--memory` / `--cpu-shares` 的短写，此前被当成未知标志静默丢弃。
    @Test func shortResourceFlagsAreMappedInsteadOfDropped() throws {
        let memory = try DockerRunToDockerComposeService.convert("docker run -m 512m nginx")
        #expect(memory.yaml.contains("memory: 512m"), Comment(rawValue: memory.yaml))
        #expect(memory.unknownFlags.isEmpty, Comment(rawValue: "\(memory.unknownFlags)"))

        let shares = try DockerRunToDockerComposeService.convert("docker run -c 2 nginx")
        #expect(shares.yaml.contains("cpu_shares: \"2\""), Comment(rawValue: shares.yaml))
        #expect(shares.unknownFlags.isEmpty, Comment(rawValue: "\(shares.unknownFlags)"))

        // 同样支持短写紧贴取值：`-m512m` / `-c2`
        let tight = try DockerRunToDockerComposeService.convert("docker run -m512m -c2 nginx")
        #expect(tight.yaml.contains("memory: 512m"), Comment(rawValue: tight.yaml))
        #expect(tight.yaml.contains("cpu_shares: \"2\""), Comment(rawValue: tight.yaml))
    }

    /// Compose→Run 方向生成的正是 `-m`，两个方向必须对称，否则往返还原会丢字段。
    @Test func resourceLimitRoundTripReachesAFixedPoint() throws {
        let command = "docker run -d --cpus 1.5 -m 512m nginx"
        let first = try DockerRunToDockerComposeService.convert(command)
        // 第一轮就必须完整保留两项限制，否则「固定点」只是丢字段后的假稳定。
        #expect(first.yaml.contains("cpus: \"1.5\""), Comment(rawValue: first.yaml))
        #expect(first.yaml.contains("memory: 512m"), Comment(rawValue: first.yaml))

        let back = try DockerComposeToRunService.convert(first.yaml)
        let rerun = try #require(back.commands.first)
        #expect(rerun.contains("-m 512m"), Comment(rawValue: rerun))
        #expect(rerun.contains("--cpus 1.5"), Comment(rawValue: rerun))

        let second = try DockerRunToDockerComposeService.convert(rerun)
        #expect(second.yaml == first.yaml, Comment(rawValue: "第一轮:\(first.yaml)\n第二轮:\(second.yaml)"))
    }
}
