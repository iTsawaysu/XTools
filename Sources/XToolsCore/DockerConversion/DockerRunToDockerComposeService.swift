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
        guard tokens.count >= 3,
              tokens[0] == "docker",
              tokens[1] == "run" else {
            throw DockerRunToDockerComposeError.invalidCommand
        }

        if dockerRunOccurrences(in: command) > 1 {
            throw DockerRunToDockerComposeError.multipleCommands
        }

        var expandedTokens: [String] = []
        for token in tokens {
            if token.hasPrefix("-") && !token.hasPrefix("--") && token.count > 2 && !token.contains("=") {
                let flagPart = String(token.dropFirst())
                let knownBooleanShorts: Set<Character> = ["d", "i", "t"]
                if flagPart.allSatisfy({ knownBooleanShorts.contains($0) }) {
                    for char in flagPart {
                        expandedTokens.append("-\(char)")
                    }
                    continue
                }
            }
            expandedTokens.append(token)
        }

        var service = ComposeService()
        let notTranslatable: [String] = []
        var notImplemented: [String] = []
        var unknownFlags: [String] = []
        var index = 2
        var imageFound = false

        while index < expandedTokens.count {
            let token = expandedTokens[index]

            if token == "--" {
                service.command.append(contentsOf: expandedTokens[(index + 1)...])
                break
            }

            if imageFound {
                service.command.append(token)
                index += 1
                continue
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
                return try requireValue(after: token, in: expandedTokens, index: &index)
            }

            func skipFlag(_ hasValue: Bool) {
                if inlineValue != nil {
                    index += 1
                } else if hasValue && index + 1 < expandedTokens.count && !expandedTokens[index + 1].hasPrefix("-") {
                    index += 2
                } else {
                    index += 1
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
                if value == "host" {
                    service.networkMode = "host"
                } else {
                    service.networks.append(value)
                }
            case "--mount":
                let mountValue = try takeValue()
                let (volumeStr, tmpfsStr) = parseMountToVolume(mountValue)
                if let vol = volumeStr {
                    service.volumes.append(normalizeVolumePath(vol))
                }
                if let tmp = tmpfsStr {
                    service.tmpfs.append(tmp)
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
                let value = inlineValue ?? "true"
                service.privileged = (value != "false")
                index += 1
            case "--read-only":
                let value = inlineValue ?? "true"
                service.readOnly = (value != "false")
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
                service.ipv4Address = try takeValue()
            case "--ip6":
                service.ipv6Address = try takeValue()
            case "--mac-address":
                service.macAddress = try takeValue()
            case "--network-alias":
                service.networkAliases.append(try takeValue())

            case "--pid":
                service.pid = try takeValue()
            case "--uts":
                service.uts = try takeValue()
            case "--ipc":
                service.ipc = try takeValue()

            case "--health-cmd":
                service.healthcheckDisabled = false
                service.healthCmd = try takeValue()
            case "--health-interval":
                service.healthcheckDisabled = false
                service.healthInterval = try takeValue()
            case "--health-timeout":
                service.healthcheckDisabled = false
                service.healthTimeout = try takeValue()
            case "--health-retries":
                service.healthcheckDisabled = false
                service.healthRetries = try takeValue()
            case "--health-start-period":
                service.healthcheckDisabled = false
                service.healthStartPeriod = try takeValue()
            case "--no-healthcheck":
                let value = inlineValue ?? "true"
                let disabled = (value != "false")
                service.healthcheckDisabled = disabled
                if disabled {
                    service.healthCmd = nil
                    service.healthInterval = nil
                    service.healthTimeout = nil
                    service.healthRetries = nil
                    service.healthStartPeriod = nil
                }
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
                service.stdinOpen = true
                index += 1
            case "-t", "--tty":
                service.tty = true
                index += 1

            case "-d", "--detach", "--rm", "-a", "--attach", "--sig-proxy":
                skipFlag(flagTakesValue(flag))

            case "--init":
                let value = inlineValue ?? "true"
                service.`init` = (value != "false")
                index += 1

            case "--oom-kill-disable":
                let value = inlineValue ?? "true"
                service.oomKillDisable = (value != "false")
                index += 1

            case let flag where unsupportedValueFlags.contains(flag):
                notImplemented.append(token)
                skipFlag(true)
            case let flag where unsupportedBooleanFlags.contains(flag):
                notImplemented.append(token)
                index += 1

            default:
                unknownFlags.append(token)
                skipFlag(true)  // Assume it might have a value
            }
        }

        guard imageFound, !service.image.isEmpty else {
            throw DockerRunToDockerComposeError.missingImage
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
