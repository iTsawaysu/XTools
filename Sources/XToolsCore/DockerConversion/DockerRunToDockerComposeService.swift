import Foundation

public enum DockerRunToDockerComposeService {
    public struct Warning: Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable {
            case notTranslatable
            case notImplemented
            case unknownFlag
        }

        public let kind: Kind
        public let option: String

        public init(kind: Kind, option: String) {
            self.kind = kind
            self.option = option
        }
    }

    public struct Result {
        public let yaml: String
        public let notTranslatable: [String]
        public let notImplemented: [String]
        public let unknownFlags: [String]
        public let warnings: [Warning]
    }

    public static func convert(_ command: String) throws -> Result {
        let sourceTokens = try tokenizeWithOrigins(command)
        let tokens = sourceTokens.map(\.value)
        try validateCommandHeader(tokens, command: command)

        var service = ComposeService()
        var pendingNetworkAttachment = NetworkAttachment(name: "")
        let notTranslatable: [String] = []
        var notImplemented: [String] = []
        var unknownFlags: [String] = []
        var index = 2
        var imageFound = false

        while index < tokens.count {
            let token = tokens[index]

            if imageFound {
                service.command.append(try sourceTokens[index].resolvedValue(for: "command"))
                index += 1
                continue
            }

            if token == "--" {
                try terminateOptionParsing(at: index, sourceTokens: sourceTokens, service: &service, imageFound: &imageFound)
                break
            }

            if !token.hasPrefix("-") {
                service.image = try sourceTokens[index].resolvedValue(for: "image")
                service.name = sanitizedServiceName(from: service.containerName ?? token)
                imageFound = true
                index += 1
                continue
            }

            let (rawFlag, inlineValue) = parseOptionToken(token)
            let flag = shortFlagAliases[rawFlag] ?? rawFlag
            var context = FlagParseContext(
                sourceTokens: sourceTokens,
                tokens: tokens,
                token: token,
                rawFlag: rawFlag,
                inlineValue: inlineValue,
                index: index
            )
            defer { index = context.index }

            if try applyShortFlagCluster(context: &context, service: &service) { continue }

            // 以下按 flag 族分派。具名族必须全部消费完毕，才轮到兜底的
            // 布尔/不支持/未知分支（where 语义依赖具名分支先行）。
            if try applyBasicFieldFlag(flag, context: &context, service: &service) { continue }
            if try applyNetworkAndMountFlag(
                flag,
                context: &context,
                service: &service,
                pendingNetworkAttachment: &pendingNetworkAttachment,
                notImplemented: &notImplemented
            ) { continue }
            if try applyRuntimeEnvironmentFlag(flag, context: &context, service: &service) { continue }
            if try applySecurityCapabilityFlag(flag, context: &context, service: &service) { continue }
            if try applyResourceLimitFlag(flag, context: &context, service: &service) { continue }
            if try applyNetworkAttachmentDetailFlag(
                flag,
                context: &context,
                service: &service,
                pendingNetworkAttachment: &pendingNetworkAttachment
            ) { continue }
            if try applyNamespaceHealthLoggingFlag(flag, context: &context, service: &service) { continue }
            if try applyLifecycleInteractiveFlag(flag, context: &context, service: &service) { continue }

            try applyUnmatchedFlagFallback(
                flag: flag,
                token: token,
                tokens: tokens,
                context: &context,
                notImplemented: &notImplemented,
                unknownFlags: &unknownFlags
            )
        }

        guard imageFound, !service.image.isEmpty else {
            throw DockerRunToDockerComposeError.missingImage
        }

        if service.healthcheckDisabled == true && Self.hasEffectiveHealthSettings(service) {
            throw DockerRunToDockerComposeError.conflictingHealthcheckOptions
        }

        appendOrphanNetworkAttachmentWarnings(pendingNetworkAttachment, into: &notImplemented)

        let yaml = renderYAML(service: service)
        return Result(
            yaml: yaml,
            notTranslatable: notTranslatable,
            notImplemented: notImplemented,
            unknownFlags: unknownFlags,
            warnings: warnings(
                notTranslatable: notTranslatable,
                notImplemented: notImplemented,
                unknownFlags: unknownFlags
            )
        )
    }

    /// convert 主循环里单个 flag 的解析游标：把取值/跳过/布尔判定集中到一处，
    /// 让各 flag 族 handler（apply*Flag）以同一套状态工作。
    private struct FlagParseContext {
        let sourceTokens: [ShellToken]
        let tokens: [String]
        let token: String
        let rawFlag: String
        let inlineValue: String?
        var index: Int

        /// 短别名归一后的 flag 名，与 convert 循环内的局部 `flag` 一致。
        var flag: String { shortFlagAliases[rawFlag] ?? rawFlag }

        mutating func takeValue() throws -> String {
            if let inlineValue {
                let value = try sourceTokens[index].resolvedValue(
                    for: flag,
                    droppingPrefix: token.unicodeScalars.count - inlineValue.unicodeScalars.count
                )
                index += 1
                return value
            }
            let valueIndex = index + 1
            _ = try requireValue(after: token, in: tokens, index: &index)
            return try sourceTokens[valueIndex].resolvedValue(for: flag)
        }

        mutating func skipFlag(_ hasValue: Bool) {
            if inlineValue != nil {
                index += 1
            } else if hasValue && index + 1 < tokens.count && !tokens[index + 1].hasPrefix("-") {
                index += 2
            } else {
                index += 1
            }
        }

        func booleanValue() throws -> Bool {
            try parseBooleanValue(inlineValue, flag: flag)
        }
    }

    private static func validateCommandHeader(_ tokens: [String], command: String) throws {
        guard tokens.count >= 2,
              tokens[0] == "docker",
              tokens[1] == "run" else {
            throw DockerRunToDockerComposeError.invalidCommand
        }
        // 「docker run」后面没有任何参数时是缺少镜像，不是命令无法识别——
        // 报 invalidCommand 会让用户误以为要拆成多条命令。
        guard tokens.count >= 3 else {
            throw DockerRunToDockerComposeError.missingImage
        }

        if dockerRunOccurrences(in: command) > 1 {
            throw DockerRunToDockerComposeError.multipleCommands
        }
    }

    /// `--` 终止选项解析。按 docker 语义，其后的第一个 token 是镜像，
    /// 其余才是命令；此前把整段都当成 command，导致 `docker run -- alpine echo hi`
    /// 报「缺少镜像名称」。
    private static func terminateOptionParsing(
        at index: Int,
        sourceTokens: [ShellToken],
        service: inout ComposeService,
        imageFound: inout Bool
    ) throws {
        let remaining = sourceTokens[(index + 1)...]
        if let imageToken = remaining.first {
            let image = try imageToken.resolvedValue(for: "image")
            service.image = image
            service.name = sanitizedServiceName(from: service.containerName ?? image)
            imageFound = true
            service.command.append(contentsOf: try remaining.dropFirst().map { try $0.resolvedValue(for: "command") })
        }
    }

    /// 聚合短布尔标志（如 `-dit`）逐字符展开；返回 true 表示已消费该 token。
    private static func applyShortFlagCluster(
        context: inout FlagParseContext,
        service: inout ComposeService
    ) throws -> Bool {
        guard context.rawFlag.hasPrefix("-"), !context.rawFlag.hasPrefix("--") else { return false }
        let shorthand = String(context.rawFlag.dropFirst())
        let booleanShorts: Set<Character> = ["d", "i", "t"]
        guard shorthand.count > 1, shorthand.allSatisfy({ booleanShorts.contains($0) }) else { return false }
        let lastOffset = shorthand.count - 1
        for (offset, char) in shorthand.enumerated() {
            let shortFlag = "-\(char)"
            let value = try parseBooleanValue(
                offset == lastOffset ? context.inlineValue : nil,
                flag: shortFlag
            )
            switch char {
            case "i": service.stdinOpen = value
            case "t": service.tty = value
            default: break // -d has no Compose field.
            }
        }
        context.index += 1
        return true
    }

    /// 基础字段族：名称、端口、环境、平台与重启策略。返回 true 表示 flag 已消费。
    private static func applyBasicFieldFlag(
        _ flag: String,
        context: inout FlagParseContext,
        service: inout ComposeService
    ) throws -> Bool {
        switch flag {
        case "--name":
            let value = try context.takeValue()
            service.containerName = value
            service.name = sanitizedServiceName(from: value)
        case "--publish":
            service.ports.append(normalizePort(try context.takeValue()))
        case "--expose":
            service.expose.append(try context.takeValue())
        case "--volume":
            service.volumes.append(try context.takeValue())
        case "--env":
            service.environment.append(try context.takeValue())
        case "--env-file":
            service.envFiles.append(try context.takeValue())
        case "--platform":
            service.platform = try context.takeValue()
        case "--restart":
            let value = try context.takeValue()
            if value.hasPrefix("on-failure:") {
                let parts = value.split(separator: ":")
                if parts.count == 2, let maxAttempts = Int(parts[1]) {
                    service.restart = "on-failure"
                    service.restartMaxAttempts = maxAttempts
                } else {
                    service.restart = "on-failure"
                }
            } else {
                service.restart = value
            }
        default:
            return false
        }
        return true
    }

    /// 网络与挂载族：--network 的模式/附件判定和 --mount 长式挂载。
    private static func applyNetworkAndMountFlag(
        _ flag: String,
        context: inout FlagParseContext,
        service: inout ComposeService,
        pendingNetworkAttachment: inout NetworkAttachment,
        notImplemented: inout [String]
    ) throws -> Bool {
        switch flag {
        case "--network":
            let value = try context.takeValue()
            // docker 的 --network 有几类取值不是「外部网络名」，必须映射到
            // compose 的 network_mode；否则会凭空生成一个同名外部网络
            // （`--network none` 曾生成 `networks: [none]` + `none: external: true`，
            // 语义与「禁用网络」完全相反）。
            if let mode = Self.networkModeValue(for: value) {
                service.networkMode = mode
            } else {
                let parsed = parseNetworkAttachment(value)
                notImplemented.append(contentsOf: parsed.unsupported.map { "--network.\($0)" })
                guard var attachment = parsed.attachment else { return true }
                if !pendingNetworkAttachment.aliases.isEmpty {
                    attachment.aliases = pendingNetworkAttachment.aliases + attachment.aliases
                }
                if attachment.ipv4Address == nil {
                    attachment.ipv4Address = pendingNetworkAttachment.ipv4Address
                }
                if attachment.ipv6Address == nil {
                    attachment.ipv6Address = pendingNetworkAttachment.ipv6Address
                }
                pendingNetworkAttachment = NetworkAttachment(name: "")
                service.networks.append(attachment.name)
                service.networkAttachments.append(attachment)
            }
        case "--mount":
            let mountValue = try context.takeValue()
            let parsed = parseMount(mountValue)
            notImplemented.append(contentsOf: parsed.unsupported.map { "--mount.\($0)" })
            if let mount = parsed.mount {
                service.mounts.append(mount)
            }
        default:
            return false
        }
        return true
    }

    /// 运行环境与元数据族：用户、目录、主机名、DNS、入口、tmpfs、hosts、标签与链接。
    private static func applyRuntimeEnvironmentFlag(
        _ flag: String,
        context: inout FlagParseContext,
        service: inout ComposeService
    ) throws -> Bool {
        switch flag {
        case "--user":
            service.user = try context.takeValue()
        case "--workdir":
            service.workingDir = try context.takeValue()
        case "--hostname":
            service.hostname = try context.takeValue()
        case "--dns":
            service.dns.append(try context.takeValue())
        case "--dns-opt":
            service.dnsOpt.append(try context.takeValue())
        case "--dns-search":
            service.dnsSearch.append(try context.takeValue())
        case "--entrypoint":
            let value = try context.takeValue()
            service.entrypoint = [value]
        case "--tmpfs":
            service.tmpfs.append(try context.takeValue())
        case "--add-host":
            service.extraHosts.append(try context.takeValue())
        case "--label":
            service.labels.append(try context.takeValue())
        case "--link":
            service.links.append(try context.takeValue())
        default:
            return false
        }
        return true
    }

    /// 安全与能力族：Linux capabilities、安全选项与特权/只读开关。
    private static func applySecurityCapabilityFlag(
        _ flag: String,
        context: inout FlagParseContext,
        service: inout ComposeService
    ) throws -> Bool {
        switch flag {
        case "--cap-add":
            service.capAdd.append(try context.takeValue())
        case "--cap-drop":
            service.capDrop.append(try context.takeValue())
        case "--security-opt":
            service.securityOpt.append(try context.takeValue())
        case "--privileged":
            service.privileged = try context.booleanValue()
            context.index += 1
        case "--read-only":
            service.readOnly = try context.booleanValue()
            context.index += 1
        case "--userns":
            service.userns = try context.takeValue()
        case "--group-add":
            service.groupAdd.append(try context.takeValue())
        default:
            return false
        }
        return true
    }

    /// 资源限制族：CPU/内存配额、设备 I/O 限速与 sysctl/ulimit。
    private static func applyResourceLimitFlag(
        _ flag: String,
        context: inout FlagParseContext,
        service: inout ComposeService
    ) throws -> Bool {
        switch flag {
        case "--cpus":
            service.cpus = try context.takeValue()
        case "--cpu-shares":
            service.cpuShares = try context.takeValue()
        case "--cpu-period":
            service.cpuPeriod = try context.takeValue()
        case "--cpu-quota":
            service.cpuQuota = try context.takeValue()
        case "--cpuset-cpus":
            service.cpusetCpus = try context.takeValue()
        case "--memory":
            service.memory = try context.takeValue()
        case "--memory-reservation":
            service.memoryReservation = try context.takeValue()
        case "--memory-swap":
            service.memorySwap = try context.takeValue()
        case "--memory-swappiness":
            service.memorySwappiness = try context.takeValue()
        case "--pids-limit":
            service.pidsLimit = try context.takeValue()
        case "--blkio-weight":
            service.blkioWeight = try context.takeValue()
        case "--shm-size":
            service.shmSize = try context.takeValue()
        case "--oom-score-adj":
            service.oomScoreAdj = try context.takeValue()

        case "--device-read-bps":
            service.deviceReadBps.append(try context.takeValue())
        case "--device-write-bps":
            service.deviceWriteBps.append(try context.takeValue())
        case "--device-read-iops":
            service.deviceReadIops.append(try context.takeValue())
        case "--device-write-iops":
            service.deviceWriteIops.append(try context.takeValue())

        case "--sysctl":
            service.sysctls.append(try context.takeValue())
        case "--ulimit":
            service.ulimits.append(try context.takeValue())
        default:
            return false
        }
        return true
    }

    /// 网络附件明细族：IP、MAC 与别名，归属到最近一次声明的网络附件。
    private static func applyNetworkAttachmentDetailFlag(
        _ flag: String,
        context: inout FlagParseContext,
        service: inout ComposeService,
        pendingNetworkAttachment: inout NetworkAttachment
    ) throws -> Bool {
        switch flag {
        case "--ip":
            let value = try context.takeValue()
            if !service.networkAttachments.isEmpty {
                service.networkAttachments[service.networkAttachments.count - 1].ipv4Address = value
            } else {
                pendingNetworkAttachment.ipv4Address = value
            }
        case "--ip6":
            let value = try context.takeValue()
            if !service.networkAttachments.isEmpty {
                service.networkAttachments[service.networkAttachments.count - 1].ipv6Address = value
            } else {
                pendingNetworkAttachment.ipv6Address = value
            }
        case "--mac-address":
            service.macAddress = try context.takeValue()
        case "--network-alias":
            let value = try context.takeValue()
            if !service.networkAttachments.isEmpty {
                service.networkAttachments[service.networkAttachments.count - 1].aliases.append(value)
            } else {
                pendingNetworkAttachment.aliases.append(value)
            }
        default:
            return false
        }
        return true
    }

    /// 命名空间、健康检查与日志族。
    private static func applyNamespaceHealthLoggingFlag(
        _ flag: String,
        context: inout FlagParseContext,
        service: inout ComposeService
    ) throws -> Bool {
        switch flag {
        case "--pid":
            service.pid = try context.takeValue()
        case "--uts":
            service.uts = try context.takeValue()
        case "--ipc":
            service.ipc = try context.takeValue()

        case "--health-cmd":
            service.healthCmd = try context.takeValue()
        case "--health-interval":
            service.healthInterval = try context.takeValue()
        case "--health-timeout":
            service.healthTimeout = try context.takeValue()
        case "--health-retries":
            service.healthRetries = try context.takeValue()
        case "--health-start-period":
            service.healthStartPeriod = try context.takeValue()
        case "--health-start-interval":
            service.healthStartInterval = try context.takeValue()
        case "--no-healthcheck":
            service.healthcheckDisabled = try context.booleanValue()
            context.index += 1

        case "--log-driver":
            service.logDriver = try context.takeValue()
        case "--log-opt":
            service.logOptions.append(try context.takeValue())
        default:
            return false
        }
        return true
    }

    /// 生命周期与交互族：设备、停止信号/宽限期、GPU 与前台/布尔开关。
    private static func applyLifecycleInteractiveFlag(
        _ flag: String,
        context: inout FlagParseContext,
        service: inout ComposeService
    ) throws -> Bool {
        switch flag {
        case "--device":
            service.devices.append(try context.takeValue())
        case "--stop-signal":
            service.stopSignal = try context.takeValue()
        case "--stop-timeout":
            service.stopGracePeriod = try context.takeValue()
        case "--gpus":
            service.gpus = try context.takeValue()

        case "-i", "--interactive":
            service.stdinOpen = try context.booleanValue()
            context.index += 1
        case "-t", "--tty":
            service.tty = try context.booleanValue()
            context.index += 1

        case "-d", "--detach", "--rm", "-a", "--attach", "--sig-proxy":
            if Self.booleanFlags.contains(flag) { _ = try context.booleanValue() }
            context.skipFlag(flagTakesValue(flag))

        case "--init":
            service.`init` = try context.booleanValue()
            context.index += 1

        case "--oom-kill-disable":
            service.oomKillDisable = try context.booleanValue()
            context.index += 1
        default:
            return false
        }
        return true
    }

    /// 兜底分支：已知布尔标志、已知不可翻译标志与未知标志。
    /// 必须在所有具名 flag 族之后调用，where 语义依赖具名分支先行。
    private static func applyUnmatchedFlagFallback(
        flag: String,
        token: String,
        tokens: [String],
        context: inout FlagParseContext,
        notImplemented: inout [String],
        unknownFlags: inout [String]
    ) throws {
        if Self.booleanFlags.contains(flag) {
            _ = try context.booleanValue()
            notImplemented.append(token)
            context.index += 1
        } else if unsupportedValueFlags.contains(flag) {
            notImplemented.append(token)
            context.skipFlag(true)
        } else {
            unknownFlags.append(token)
            // 未知标志是否带值不可知。若它后面只剩一个 token，吞掉就会让整条
            // 命令找不到镜像（`-P nginx` 报「缺少镜像名称」就是这么来的），
            // 因此这种情况下按布尔标志处理，把该 token 留给镜像判定。
            let hasTokenAfterNext = context.index + 2 < tokens.count
            let nextLooksLikeValue = context.index + 1 < tokens.count
                && !tokens[context.index + 1].hasPrefix("-")
            context.skipFlag(nextLooksLikeValue && hasTokenAfterNext)
        }
    }

    /// 尚未归属任何网络的 --ip/--ip6/--network-alias 只能降级为未实现提示。
    private static func appendOrphanNetworkAttachmentWarnings(
        _ pendingNetworkAttachment: NetworkAttachment,
        into notImplemented: inout [String]
    ) {
        if pendingNetworkAttachment.ipv4Address != nil {
            notImplemented.append("--ip")
        }
        if pendingNetworkAttachment.ipv6Address != nil {
            notImplemented.append("--ip6")
        }
        if !pendingNetworkAttachment.aliases.isEmpty {
            notImplemented.append("--network-alias")
        }
    }

    private static func hasEffectiveHealthSettings(_ service: ComposeService) -> Bool {
        if let command = service.healthCmd, !command.isEmpty { return true }
        if let retries = service.healthRetries, Int(retries) != 0 { return true }
        return [service.healthInterval, service.healthTimeout, service.healthStartPeriod, service.healthStartInterval]
            .compactMap { $0 }
            .contains { !isZeroDuration($0) }
    }

    private static func parseBooleanValue(_ inlineValue: String?, flag: String) throws -> Bool {
        guard let inlineValue else { return true }
        switch inlineValue {
        case "1", "t", "T", "TRUE", "true", "True": return true
        case "0", "f", "F", "FALSE", "false", "False": return false
        default: throw DockerRunToDockerComposeError.invalidBooleanValue(flag)
        }
    }

    private static func isZeroDuration(_ value: String) -> Bool {
        if value == "0" { return true }
        // Go durations may combine zero-valued units, for example 0h0m0s.
        let zeroDuration = #"^(?:[+-]?(?:0+(?:\.0*)?|\.0+)(?:ns|us|µs|μs|ms|s|m|h))+$"#
        return value.range(of: zeroDuration, options: .regularExpression) != nil
    }

    private static func warnings(
        notTranslatable: [String],
        notImplemented: [String],
        unknownFlags: [String]
    ) -> [Warning] {
        warnings(for: notTranslatable, kind: .notTranslatable)
            + warnings(for: notImplemented, kind: .notImplemented)
            + warnings(for: unknownFlags, kind: .unknownFlag)
    }

    private static func warnings(for options: [String], kind: Warning.Kind) -> [Warning] {
        var seen: Set<String> = []
        return options.compactMap { option in
            let name = DockerRunToDockerComposeDiagnostics.safeOptionName(option)
            guard seen.insert(name).inserted else { return nil }
            return Warning(kind: kind, option: name)
        }
    }
}
