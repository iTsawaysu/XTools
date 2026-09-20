import Foundation

extension DockerRunToDockerComposeService {
    static func renderYAML(service: ComposeService) -> String {
        var lines: [String] = [
            "services:",
            "  \(service.name):",
            "    image: \(yamlScalar(service.image))"
        ]

        if let platform = service.platform {
            lines.append("    platform: \(yamlScalar(platform))")
        }

        if let containerName = service.containerName {
            lines.append("    container_name: \(yamlScalar(containerName))")
        }

        if let hostname = service.hostname {
            lines.append("    hostname: \(yamlScalar(hostname))")
        }

        if !service.entrypoint.isEmpty {
            lines.append("    entrypoint:")
            lines.append(contentsOf: service.entrypoint.map { "      - \(yamlScalar($0))" })
        }

        if !service.command.isEmpty {
            lines.append("    command:")
            lines.append(contentsOf: service.command.map { "      - \(yamlScalar($0))" })
        }

        if !service.environment.isEmpty {
            lines.append("    environment:")
            lines.append(contentsOf: service.environment.map { "      - \(yamlScalar($0))" })
        }

        if !service.envFiles.isEmpty {
            lines.append("    env_file:")
            lines.append(contentsOf: service.envFiles.map { "      - \(yamlScalar($0))" })
        }

        if !service.ports.isEmpty {
            lines.append("    ports:")
            lines.append(contentsOf: service.ports.map { "      - \(yamlScalar($0))" })
        }

        if !service.expose.isEmpty {
            lines.append("    expose:")
            lines.append(contentsOf: service.expose.map { "      - \(yamlScalar($0))" })
        }

        if !service.volumes.isEmpty || !service.mounts.isEmpty {
            lines.append("    volumes:")
            lines.append(contentsOf: service.volumes.map { "      - \(yamlScalar($0))" })
            for mount in service.mounts {
                lines.append("      - type: \(mount.kind.rawValue)")
                if let source = mount.source {
                    lines.append("        source: \(yamlScalar(normalizeVolumePath(source)))")
                }
                lines.append("        target: \(yamlScalar(mount.target))")
                if mount.readOnly {
                    lines.append("        read_only: true")
                }
                if mount.kind == .tmpfs, mount.size != nil || mount.mode != nil {
                    lines.append("        tmpfs:")
                    if let size = mount.size {
                        lines.append("          size: \(yamlScalar(size))")
                    }
                    if let mode = mount.mode {
                        lines.append("          mode: \(yamlScalar(mode))")
                    }
                }
            }
        }

        if !service.tmpfs.isEmpty {
            lines.append("    tmpfs:")
            lines.append(contentsOf: service.tmpfs.map { "      - \(yamlScalar($0))" })
        }

        if let networkMode = service.networkMode {
            lines.append("    network_mode: \(yamlScalar(networkMode))")
        } else if !service.networks.isEmpty {
            let attachments = service.networkAttachments
            if attachments.contains(where: { $0.ipv4Address != nil || $0.ipv6Address != nil || !$0.aliases.isEmpty }) {
                lines.append("    networks:")
                for network in attachments {
                    lines.append("      \(network.name):")
                    if let ipv4 = network.ipv4Address {
                        lines.append("        ipv4_address: \(yamlScalar(ipv4))")
                    }
                    if let ipv6 = network.ipv6Address {
                        lines.append("        ipv6_address: \(yamlScalar(ipv6))")
                    }
                    if !network.aliases.isEmpty {
                        lines.append("        aliases:")
                        lines.append(contentsOf: network.aliases.map { "          - \(yamlScalar($0))" })
                    }
                }
            } else {
                lines.append("    networks:")
                lines.append(contentsOf: service.networks.map { "      - \(yamlScalar($0))" })
            }
        }

        if let macAddress = service.macAddress {
            lines.append("    mac_address: \(yamlScalar(macAddress))")
        }

        if !service.dns.isEmpty {
            lines.append("    dns:")
            lines.append(contentsOf: service.dns.map { "      - \(yamlScalar($0))" })
        }

        if !service.dnsOpt.isEmpty {
            lines.append("    dns_opt:")
            lines.append(contentsOf: service.dnsOpt.map { "      - \(yamlScalar($0))" })
        }

        if !service.dnsSearch.isEmpty {
            lines.append("    dns_search:")
            lines.append(contentsOf: service.dnsSearch.map { "      - \(yamlScalar($0))" })
        }

        if !service.extraHosts.isEmpty {
            lines.append("    extra_hosts:")
            lines.append(contentsOf: service.extraHosts.map { "      - \(yamlScalar($0))" })
        }

        if !service.links.isEmpty {
            lines.append("    links:")
            lines.append(contentsOf: service.links.map { "      - \(yamlScalar($0))" })
        }

        if !service.labels.isEmpty {
            lines.append("    labels:")
            lines.append(contentsOf: service.labels.map { "      - \(yamlScalar($0))" })
        }

        if let initFlag = service.`init`, initFlag {
            lines.append("    init: true")
        }

        // Security & Capabilities
        if let privileged = service.privileged {
            lines.append("    privileged: \(privileged)")
        }

        if !service.capAdd.isEmpty {
            lines.append("    cap_add:")
            lines.append(contentsOf: service.capAdd.map { "      - \(yamlScalar($0))" })
        }

        if !service.capDrop.isEmpty {
            lines.append("    cap_drop:")
            lines.append(contentsOf: service.capDrop.map { "      - \(yamlScalar($0))" })
        }

        if !service.securityOpt.isEmpty {
            lines.append("    security_opt:")
            lines.append(contentsOf: service.securityOpt.map { "      - \(yamlScalar($0))" })
        }

        if let userns = service.userns {
            lines.append("    userns_mode: \(yamlScalar(userns))")
        }

        if !service.groupAdd.isEmpty {
            lines.append("    group_add:")
            lines.append(contentsOf: service.groupAdd.map { "      - \(yamlScalar($0))" })
        }

        if let oomScore = service.oomScoreAdj {
            lines.append("    oom_score_adj: \(yamlScalar(oomScore))")
        }

        // Devices
        if !service.devices.isEmpty {
            lines.append("    devices:")
            lines.append(contentsOf: service.devices.map { "      - \(yamlScalar($0))" })
        }

        // Resource limits (deploy section for Compose v3+)
        let hasResources = service.cpus != nil || service.memory != nil || service.memoryReservation != nil ||
                          service.pidsLimit != nil
        if hasResources {
            lines.append("    deploy:")
            lines.append("      resources:")
            if service.cpus != nil || service.memory != nil || service.pidsLimit != nil {
                lines.append("        limits:")
                if let cpus = service.cpus {
                    lines.append("          cpus: \(yamlScalar(cpus))")
                }
                if let memory = service.memory {
                    lines.append("          memory: \(yamlScalar(memory))")
                }
                if let pidsLimit = service.pidsLimit {
                    lines.append("          pids: \(yamlScalar(pidsLimit))")
                }
            }
            if service.memoryReservation != nil {
                lines.append("        reservations:")
                if let memReserv = service.memoryReservation {
                    lines.append("          memory: \(yamlScalar(memReserv))")
                }
            }
        }

        // Extended resource configs
        if let cpuShares = service.cpuShares {
            lines.append("    cpu_shares: \(yamlScalar(cpuShares))")
        }
        if let cpuPeriod = service.cpuPeriod {
            lines.append("    cpu_period: \(yamlScalar(cpuPeriod))")
        }
        if let cpuQuota = service.cpuQuota {
            lines.append("    cpu_quota: \(yamlScalar(cpuQuota))")
        }
        if let cpusetCpus = service.cpusetCpus {
            lines.append("    cpuset: \(yamlScalar(cpusetCpus))")
        }
        if let memSwap = service.memorySwap {
            lines.append("    memswap_limit: \(yamlScalar(memSwap))")
        }
        if let memSwappiness = service.memorySwappiness {
            lines.append("    mem_swappiness: \(yamlScalar(memSwappiness))")
        }
        if let blkioWeight = service.blkioWeight {
            lines.append("    blkio_config:")
            lines.append("      weight: \(yamlIntegerScalar(blkioWeight))")
        }

        // Device I/O limits
        if !service.deviceReadBps.isEmpty || !service.deviceWriteBps.isEmpty ||
           !service.deviceReadIops.isEmpty || !service.deviceWriteIops.isEmpty {
            if service.blkioWeight == nil {
                lines.append("    blkio_config:")
            }
            if !service.deviceReadBps.isEmpty {
                lines.append("      device_read_bps:")
                for device in service.deviceReadBps {
                    let parts = device.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        lines.append("        - path: \(yamlScalar(String(parts[0])))")
                        lines.append("          rate: \(yamlScalar(String(parts[1])))")
                    }
                }
            }
            if !service.deviceWriteBps.isEmpty {
                lines.append("      device_write_bps:")
                for device in service.deviceWriteBps {
                    let parts = device.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        lines.append("        - path: \(yamlScalar(String(parts[0])))")
                        lines.append("          rate: \(yamlScalar(String(parts[1])))")
                    }
                }
            }
            if !service.deviceReadIops.isEmpty {
                lines.append("      device_read_iops:")
                for device in service.deviceReadIops {
                    let parts = device.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        lines.append("        - path: \(yamlScalar(String(parts[0])))")
                        lines.append("          rate: \(yamlScalar(String(parts[1])))")
                    }
                }
            }
            if !service.deviceWriteIops.isEmpty {
                lines.append("      device_write_iops:")
                for device in service.deviceWriteIops {
                    let parts = device.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 {
                        lines.append("        - path: \(yamlScalar(String(parts[0])))")
                        lines.append("          rate: \(yamlScalar(String(parts[1])))")
                    }
                }
            }
        }

        appendRuntimeSections(for: service, to: &lines)

        var namedVolumes = extractNamedVolumes(from: service.volumes)
        for mount in service.mounts where mount.kind == .volume {
            if let source = mount.source, !source.isEmpty {
                namedVolumes.insert(source)
            }
        }
        if !namedVolumes.isEmpty {
            lines.append("")
            lines.append("volumes:")
            for volumeName in namedVolumes.sorted() {
                lines.append("  \(volumeName):")
            }
        }

        if !service.networks.isEmpty {
            lines.append("")
            lines.append("networks:")
            for network in service.networks.sorted() {
                lines.append("  \(network):")
                lines.append("    external: true")
            }
        }

        return lines.joined(separator: "\n")
    }

    static func extractNamedVolumes(from volumes: [String]) -> Set<String> {
        var namedVolumes = Set<String>()

        for volume in volumes {
            // Windows 盘符宿主路径（`C:\data:/data`）直接按 “:” 切分会把盘符误判成
            // 具名卷，从而在顶层凭空生成 `volumes: C:`。输入文本可能来自 Windows
            // 上写的命令，因此需要识别这种形态；单字母具名卷（`x:/data`）不受影响。
            if isWindowsDrivePath(volume) { continue }

            let parts = volume.split(separator: ":")
            guard parts.count >= 2 else { continue }

            let source = String(parts[0])

            // Named volumes don't start with / or . or ~ or $ (those are bind mounts or shell variables)
            // Also check for common shell variables
            if !source.hasPrefix("/") &&
               !source.hasPrefix(".") &&
               !source.hasPrefix("~") &&
               !source.hasPrefix("$") &&
               !source.contains("$(") &&
               !source.contains("${") {
                namedVolumes.insert(source)
            }
        }

        return namedVolumes
    }

    static func yamlScalar(_ value: String) -> String {
        if value.isEmpty {
            return "\"\""
        }

        let normalizedLowercased = value.lowercased()
        if [
            "null", "~", "true", "false", "yes", "no",
            "on", "off"
        ].contains(normalizedLowercased) {
            let escaped = escapeDoubleQuotedYAML(value)
            return "\"\(escaped)\""
        }

        if value.first?.isWhitespace == true || value.last?.isWhitespace == true {
            let escaped = escapeDoubleQuotedYAML(value)
            return "\"\(escaped)\""
        }

        if Double(value) != nil {
            let escaped = escapeDoubleQuotedYAML(value)
            return "\"\(escaped)\""
        }

        // YAML 的节点指示符出现在标量开头时会被解析成结构，而不是文本：
        // `*` 变成别名引用、`&` 变成锚点、`!` 变成标签、`|`/`>` 变成块标量、
        // `%`/`@`/`` ` `` 是保留指示符。此前只检查了「是否包含」常见标点，
        // 于是 `echo '*'` 会生成 `- *`（空别名），整份 Compose 直接解析失败。
        // 另：`-`/`?`/`:` 只有后跟空白或独占整个标量时才算指示符，单独判断以免无谓加引号。
        if let first = value.first {
            if yamlNodeIndicators.contains(first) || (value.count == 1 && "-?:".contains(first)) {
                let escaped = escapeDoubleQuotedYAML(value)
                return "\"\(escaped)\""
            }
        }

        let needsQuotes = value.contains(":")
            || value.contains("#")
            || value.contains("{")
            || value.contains("}")
            || value.contains("[")
            || value.contains("]")
            || value.contains(",")
            || value.contains(" ")
            || value.contains("\"")
            || value.contains("'")
            || value.unicodeScalars.contains { $0.value < 0x20 }

        if !needsQuotes {
            return value
        }

        let escaped = escapeDoubleQuotedYAML(value)
        return "\"\(escaped)\""
    }

    /// 出现在标量开头即成为 YAML 节点指示符、必须加引号的字符。
    private static let yamlNodeIndicators: Set<Character> = [
        ",", "[", "]", "{", "}", "#", "&", "*", "!", "|", ">", "%", "@", "`"
    ]

    /// Compose schema fields that are numerically typed must remain YAML
    /// numbers. The general scalar helper intentionally quotes numeric-looking
    /// strings because environment variables, labels, and command arguments
    /// are string values; those semantics do not apply to `blkio_config.weight`.
    static func yamlIntegerScalar(_ value: String) -> String {
        guard Int(value) != nil else {
            return yamlScalar(value)
        }
        return value
    }

    private static func escapeDoubleQuotedYAML(_ value: String) -> String {
        var escaped = ""

        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\":
                escaped += "\\\\"
            case "\"":
                escaped += "\\\""
            case "\n":
                escaped += "\\n"
            case "\r":
                escaped += "\\r"
            case "\t":
                escaped += "\\t"
            default:
                if scalar.value < 0x20 {
                    escaped += String(format: "\\u%04X", scalar.value)
                } else {
                    escaped += String(scalar)
                }
            }
        }

        return escaped
    }
}
