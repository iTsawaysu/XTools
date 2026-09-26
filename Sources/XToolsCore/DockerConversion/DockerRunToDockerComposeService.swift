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
        let tokens = try tokenize(command)
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
                service.command.append(token)
                index += 1
                continue
            }

            if token == "--" {
                // `--` 终止选项解析。按 docker 语义，其后的第一个 token 是镜像，
                // 其余才是命令；此前把整段都当成 command，导致 `docker run -- alpine echo hi`
                // 报「缺少镜像名称」。
                let remaining = tokens[(index + 1)...]
                if let image = remaining.first {
                    service.image = image
                    service.name = sanitizedServiceName(from: service.containerName ?? image)
                    imageFound = true
                    service.command.append(contentsOf: remaining.dropFirst())
                }
                break
            }

            if !token.hasPrefix("-") {
                service.image = token
                service.name = sanitizedServiceName(from: service.containerName ?? token)
                imageFound = true
                index += 1
                continue
            }

            let (rawFlag, inlineValue) = parseOptionToken(token)
            let flag = shortFlagAliases[rawFlag] ?? rawFlag

            func takeValue() throws -> String {
                if let inlineValue {
                    index += 1
                    return inlineValue
                }
                return try requireValue(after: token, in: tokens, index: &index)
            }

            func skipFlag(_ hasValue: Bool) {
                if inlineValue != nil {
                    index += 1
                } else if hasValue && index + 1 < tokens.count && !tokens[index + 1].hasPrefix("-") {
                    index += 2
                } else {
                    index += 1
                }
            }

            func booleanValue() throws -> Bool {
                try Self.parseBooleanValue(inlineValue, flag: flag)
            }

            if rawFlag.hasPrefix("-"), !rawFlag.hasPrefix("--") {
                let shorthand = String(rawFlag.dropFirst())
                let booleanShorts: Set<Character> = ["d", "i", "t"]
                if shorthand.count > 1 && shorthand.allSatisfy({ booleanShorts.contains($0) }) {
                    let lastOffset = shorthand.count - 1
                    for (offset, char) in shorthand.enumerated() {
                        let shortFlag = "-\(char)"
                        let value = try Self.parseBooleanValue(
                            offset == lastOffset ? inlineValue : nil,
                            flag: shortFlag
                        )
                        switch char {
                        case "i": service.stdinOpen = value
                        case "t": service.tty = value
                        default: break // -d has no Compose field.
                        }
                    }
                    index += 1
                    continue
                }
            }

            switch flag {
            case "--name":
                let value = try takeValue()
                service.containerName = value
                service.name = sanitizedServiceName(from: value)
            case "--publish":
                service.ports.append(normalizePort(try takeValue()))
            case "--expose":
                service.expose.append(try takeValue())
            case "--volume":
                service.volumes.append(normalizeVolumePath(try takeValue()))
            case "--env":
                service.environment.append(try takeValue())
            case "--env-file":
                service.envFiles.append(try takeValue())
            case "--platform":
                service.platform = try takeValue()
            case "--restart":
                let value = try takeValue()
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
            case "--network":
                let value = try takeValue()
                // docker 的 --network 有几类取值不是「外部网络名」，必须映射到
                // compose 的 network_mode；否则会凭空生成一个同名外部网络
                // （`--network none` 曾生成 `networks: [none]` + `none: external: true`，
                // 语义与「禁用网络」完全相反）。
                if let mode = Self.networkModeValue(for: value) {
                    service.networkMode = mode
                } else {
                    let parsed = parseNetworkAttachment(value)
                    notImplemented.append(contentsOf: parsed.unsupported.map { "--network.\($0)" })
                    guard var attachment = parsed.attachment else { continue }
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
                let mountValue = try takeValue()
                let parsed = parseMount(mountValue)
                notImplemented.append(contentsOf: parsed.unsupported.map { "--mount.\($0)" })
                if let mount = parsed.mount {
                    service.mounts.append(mount)
                }
            case "--user":
                service.user = try takeValue()
            case "--workdir":
                service.workingDir = try takeValue()
            case "--hostname":
                service.hostname = try takeValue()
            case "--dns":
                service.dns.append(try takeValue())
            case "--dns-opt":
                service.dnsOpt.append(try takeValue())
            case "--dns-search":
                service.dnsSearch.append(try takeValue())
            case "--entrypoint":
                let value = try takeValue()
                service.entrypoint = [value]
            case "--tmpfs":
                service.tmpfs.append(try takeValue())
            case "--add-host":
                service.extraHosts.append(try takeValue())
            case "--label":
                service.labels.append(try takeValue())
            case "--link":
                service.links.append(try takeValue())

            case "--cap-add":
                service.capAdd.append(try takeValue())
            case "--cap-drop":
                service.capDrop.append(try takeValue())
            case "--security-opt":
                service.securityOpt.append(try takeValue())
            case "--privileged":
                service.privileged = try booleanValue()
                index += 1
            case "--read-only":
                service.readOnly = try booleanValue()
                index += 1
            case "--userns":
                service.userns = try takeValue()
            case "--group-add":
                service.groupAdd.append(try takeValue())

            case "--cpus":
                service.cpus = try takeValue()
            case "--cpu-shares":
                service.cpuShares = try takeValue()
            case "--cpu-period":
                service.cpuPeriod = try takeValue()
            case "--cpu-quota":
                service.cpuQuota = try takeValue()
            case "--cpuset-cpus":
                service.cpusetCpus = try takeValue()
            case "--memory":
                service.memory = try takeValue()
            case "--memory-reservation":
                service.memoryReservation = try takeValue()
            case "--memory-swap":
                service.memorySwap = try takeValue()
            case "--memory-swappiness":
                service.memorySwappiness = try takeValue()
            case "--pids-limit":
                service.pidsLimit = try takeValue()
            case "--blkio-weight":
                service.blkioWeight = try takeValue()
            case "--shm-size":
                service.shmSize = try takeValue()
            case "--oom-score-adj":
                service.oomScoreAdj = try takeValue()

            case "--device-read-bps":
                service.deviceReadBps.append(try takeValue())
            case "--device-write-bps":
                service.deviceWriteBps.append(try takeValue())
            case "--device-read-iops":
                service.deviceReadIops.append(try takeValue())
            case "--device-write-iops":
                service.deviceWriteIops.append(try takeValue())

            case "--sysctl":
                service.sysctls.append(try takeValue())
            case "--ulimit":
                service.ulimits.append(try takeValue())

            case "--ip":
                let value = try takeValue()
                if !service.networkAttachments.isEmpty {
                    service.networkAttachments[service.networkAttachments.count - 1].ipv4Address = value
                } else {
                    pendingNetworkAttachment.ipv4Address = value
                }
            case "--ip6":
                let value = try takeValue()
                if !service.networkAttachments.isEmpty {
                    service.networkAttachments[service.networkAttachments.count - 1].ipv6Address = value
                } else {
                    pendingNetworkAttachment.ipv6Address = value
                }
            case "--mac-address":
                service.macAddress = try takeValue()
            case "--network-alias":
                let value = try takeValue()
                if !service.networkAttachments.isEmpty {
                    service.networkAttachments[service.networkAttachments.count - 1].aliases.append(value)
                } else {
                    pendingNetworkAttachment.aliases.append(value)
                }

            case "--pid":
                service.pid = try takeValue()
            case "--uts":
                service.uts = try takeValue()
            case "--ipc":
                service.ipc = try takeValue()

            case "--health-cmd":
                service.healthCmd = try takeValue()
            case "--health-interval":
                service.healthInterval = try takeValue()
            case "--health-timeout":
                service.healthTimeout = try takeValue()
            case "--health-retries":
                service.healthRetries = try takeValue()
            case "--health-start-period":
                service.healthStartPeriod = try takeValue()
            case "--health-start-interval":
                service.healthStartInterval = try takeValue()
            case "--no-healthcheck":
                service.healthcheckDisabled = try booleanValue()
                index += 1

            case "--log-driver":
                service.logDriver = try takeValue()
            case "--log-opt":
                service.logOptions.append(try takeValue())

            case "--device":
                service.devices.append(try takeValue())

            case "--stop-signal":
                service.stopSignal = try takeValue()
            case "--stop-timeout":
                service.stopGracePeriod = try takeValue()

            case "--gpus":
                service.gpus = try takeValue()

            case "-i", "--interactive":
                service.stdinOpen = try booleanValue()
                index += 1
            case "-t", "--tty":
                service.tty = try booleanValue()
                index += 1

            case "-d", "--detach", "--rm", "-a", "--attach", "--sig-proxy":
                if Self.booleanFlags.contains(flag) { _ = try booleanValue() }
                skipFlag(flagTakesValue(flag))

            case "--init":
                service.`init` = try booleanValue()
                index += 1

            case "--oom-kill-disable":
                service.oomKillDisable = try booleanValue()
                index += 1

            case let flag where Self.booleanFlags.contains(flag):
                _ = try booleanValue()
                notImplemented.append(token)
                index += 1
            case let flag where unsupportedValueFlags.contains(flag):
                notImplemented.append(token)
                skipFlag(true)

            default:
                unknownFlags.append(token)
                // 未知标志是否带值不可知。若它后面只剩一个 token，吞掉就会让整条
                // 命令找不到镜像（`-P nginx` 报「缺少镜像名称」就是这么来的），
                // 因此这种情况下按布尔标志处理，把该 token 留给镜像判定。
                let hasTokenAfterNext = index + 2 < tokens.count
                let nextLooksLikeValue = index + 1 < tokens.count
                    && !tokens[index + 1].hasPrefix("-")
                skipFlag(nextLooksLikeValue && hasTokenAfterNext)
            }
        }

        guard imageFound, !service.image.isEmpty else {
            throw DockerRunToDockerComposeError.missingImage
        }

        if service.healthcheckDisabled == true && Self.hasEffectiveHealthSettings(service) {
            throw DockerRunToDockerComposeError.conflictingHealthcheckOptions
        }

        if pendingNetworkAttachment.ipv4Address != nil {
            notImplemented.append("--ip")
        }
        if pendingNetworkAttachment.ipv6Address != nil {
            notImplemented.append("--ip6")
        }
        if !pendingNetworkAttachment.aliases.isEmpty {
            notImplemented.append("--network-alias")
        }

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
            guard seen.insert(option).inserted else { return nil }
            return Warning(kind: kind, option: option)
        }
    }
}
