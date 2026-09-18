import Foundation
import Yams

public enum DockerComposeToRunError: Error, Equatable, Sendable {
    case invalidYAML
    case missingServicesSection
    case noServices
}

public struct DockerComposeToRunResult: Equatable, Sendable {
    /// One `docker run` command per service, in deterministic (sorted)
    /// service order.
    public let commands: [String]
    public let warnings: [String]

    public init(commands: [String], warnings: [String]) {
        self.commands = commands
        self.warnings = warnings
    }
}

public enum DockerComposeToRunDiagnostics {
    public static let invalidYAMLMessage = "无法解析 YAML：请检查缩进与语法。"
    public static let missingServicesMessage = "未找到 services 段：Compose 文件需要顶级 services 键。"
    public static let noServicesMessage = "services 段为空：至少需要一个服务定义。"

    public static func message(for error: DockerComposeToRunError) -> String {
        switch error {
        case .invalidYAML:
            return invalidYAMLMessage
        case .missingServicesSection:
            return missingServicesMessage
        case .noServices:
            return noServicesMessage
        }
    }

    public static func warningMessage(for warnings: [String]) -> String? {
        guard !warnings.isEmpty else { return nil }
        if warnings.count == 1 {
            return warnings[0]
        }
        return "转换提示（\(warnings.count) 项）：" + warnings.joined(separator: "；")
    }
}

/// Converts a docker-compose file into equivalent `docker run` command(s).
///
/// Mirrors the subset the forward `DockerRunToDockerComposeService` emits so
/// its YAML round-trips exactly; common hand-written variants (map-form
/// environment, long-form ports/volumes, deploy.resources limits) are also
/// accepted. Fields without a `docker run` equivalent (build, depends_on,
/// network details without a Docker CLI representation produce warnings instead of failing.
public enum DockerComposeToRunService {
    public static func convert(_ yamlText: String) throws -> DockerComposeToRunResult {
        let document: Any?
        do {
            document = try Yams.load(yaml: yamlText)
        } catch {
            throw DockerComposeToRunError.invalidYAML
        }

        guard let root = document as? [String: Any] else {
            throw DockerComposeToRunError.missingServicesSection
        }
        guard let services = root["services"] as? [String: Any] else {
            throw DockerComposeToRunError.missingServicesSection
        }
        guard !services.isEmpty else {
            throw DockerComposeToRunError.noServices
        }

        var warnings: [String] = []
        var commands: [String] = []

        // Top-level definitions (networks/volumes/configs/secrets) cannot be
        // inlined into a single run command — the service references to them
        // ARE mapped, so they get an informational note instead of being
        // reported as skipped fields.
        let definitionNotes = ["networks", "volumes", "configs", "secrets"].filter { root[$0] != nil }
        if !definitionNotes.isEmpty {
            warnings.append("顶层 \(definitionNotes.joined(separator: "、")) 定义不会写入命令（服务内引用已映射，需预先创建）")
        }
        let ignoredTopLevel = root.keys
            .filter { !["services", "version", "name"].contains($0) && !definitionNotes.contains($0) }
            .filter { !$0.hasPrefix("x-") }
            .sorted()
        if !ignoredTopLevel.isEmpty {
            warnings.append("忽略顶层字段：\(ignoredTopLevel.joined(separator: "、"))")
        }

        for (name, body) in services.sorted(by: { $0.key < $1.key }) {
            guard let service = body as? [String: Any] else {
                warnings.append("服务 \(name) 结构无效")
                continue
            }
            guard let image = scalarString(service["image"]), !image.isEmpty else {
                warnings.append("服务 \(name) 缺少 image")
                continue
            }
            commands.append(buildCommand(name: name, image: image, service: service, warnings: &warnings))
        }

        guard !commands.isEmpty else {
            throw DockerComposeToRunError.noServices
        }

        // Identical lines collapse (repeated identical notes across services);
        // per-service lines are intentionally distinct for attribution.
        var seen = Set<String>()
        warnings.removeAll { !seen.insert($0).inserted }
        return DockerComposeToRunResult(commands: commands, warnings: warnings)
    }

    // MARK: - Command assembly

    private static func buildCommand(
        name: String,
        image: String,
        service: [String: Any],
        warnings: inout [String]
    ) -> String {
        var skipped: [String] = []

        var args: [String] = []
        func flag(_ value: String, _ names: String...) {
            for flagName in names {
                args.append(flagName)
            }
            args.append(shellToken(value))
        }

        if let containerName = scalarString(service["container_name"]) {
            flag(containerName, "--name")
        }
        if service["platform"] != nil {
            if let platform = scalarString(service["platform"]) {
                flag(platform, "--platform")
            } else {
                skipped.append("platform(结构无法映射)")
            }
        }
        if let hostname = scalarString(service["hostname"]) {
            flag(hostname, "-h")
        }
        if let domainname = scalarString(service["domainname"]) {
            flag(domainname, "--domainname")
        }
        let entrypointSpecified = service["entrypoint"] != nil
        let entrypoint = strictStringList(service["entrypoint"], path: "entrypoint", skipped: &skipped) ?? []
        if entrypointSpecified, entrypoint.isEmpty {
            flag("", "--entrypoint")
        } else if let executable = entrypoint.first {
            flag(executable, "--entrypoint")
        }
        let command = strictStringList(service["command"], path: "command", skipped: &skipped) ?? []
        if let user = scalarString(service["user"]) {
            flag(user, "-u")
        }
        if let workingDir = scalarString(service["working_dir"]) {
            flag(workingDir, "-w")
        }
        if service["restart"] != nil {
            if let restart = scalarString(service["restart"]) {
                var value = restart
                if restart == "on-failure",
                   let attempts = deployRestartMaxAttempts(service) {
                    value = "on-failure:\(attempts)"
                }
                flag(value, "--restart")
            } else {
                skipped.append("restart(结构无法映射)")
            }
        }
        skipped.append(contentsOf: restartPolicyUnmappedPaths(service))
        if let networkMode = scalarString(service["network_mode"]) {
            flag(networkMode, "--network")
        } else {
            appendNetworkArguments(service["networks"], into: &args, skipped: &skipped)
        }
        if let macAddress = scalarString(service["mac_address"]) {
            flag(macAddress, "--mac-address")
        }

        for envFile in stringList(service["env_file"]) ?? [] {
            flag(envFile, "--env-file")
        }
        for pair in environmentPairs(service["environment"], skipped: &skipped) {
            flag(pair, "-e")
        }
        for port in portArguments(service["ports"], skipped: &skipped) {
            flag(port, "-p")
        }
        for exposed in stringList(service["expose"]) ?? [] {
            flag(exposed, "--expose")
        }
        appendVolumeArguments(service["volumes"], into: &args, skipped: &skipped)
        for tmpfs in stringList(service["tmpfs"]) ?? [] {
            flag(tmpfs, "--tmpfs")
        }
        for dns in stringList(service["dns"]) ?? [] {
            flag(dns, "--dns")
        }
        for dnsOpt in stringList(service["dns_opt"]) ?? [] {
            flag(dnsOpt, "--dns-opt")
        }
        for dnsSearch in stringList(service["dns_search"]) ?? [] {
            flag(dnsSearch, "--dns-search")
        }
        for extraHost in stringList(service["extra_hosts"]) ?? [] {
            flag(extraHost, "--add-host")
        }
        for link in stringList(service["links"]) ?? [] {
            flag(link, "--link")
        }
        for label in labelPairs(service["labels"]) {
            flag(label, "-l")
        }

        for cap in stringList(service["cap_add"]) ?? [] {
            flag(cap, "--cap-add")
        }
        for cap in stringList(service["cap_drop"]) ?? [] {
            flag(cap, "--cap-drop")
        }
        for securityOpt in stringList(service["security_opt"]) ?? [] {
            flag(securityOpt, "--security-opt")
        }
        if service["privileged"] as? Bool == true {
            args.append("--privileged")
        }
        if let userns = scalarString(service["userns_mode"]) {
            flag(userns, "--userns")
        }
        for group in stringList(service["group_add"]) ?? [] {
            flag(group, "--group-add")
        }
        for sysctl in keyValueList(service["sysctls"]) {
            flag(sysctl, "--sysctl")
        }
        for ulimit in ulimitArguments(service["ulimits"]) {
            flag(ulimit, "--ulimit")
        }
        for device in stringList(service["devices"]) ?? [] {
            flag(device, "--device")
        }

        // Resource limits: deploy.resources is the modern spelling; the flat
        // legacy keys are accepted as aliases.
        let resources = deployResources(service)
        if let resources {
            if let cpus = resources.limits.cpus {
                flag(cpus, "--cpus")
            }
            if let memory = resources.limits.memory {
                flag(memory, "-m")
            }
            if let pids = resources.limits.pids {
                flag(pids, "--pids-limit")
            }
            skipped.append(contentsOf: resources.unmappedPaths)
        }
        let deployMemoryReservation = resources?.reservationMemory
        var memoryReservation = deployMemoryReservation
        if service["mem_reservation"] != nil {
            if let flatMemoryReservation = scalarString(service["mem_reservation"]) {
                if let deployMemoryReservation,
                   !memoryValuesEquivalent(flatMemoryReservation, deployMemoryReservation) {
                    skipped.append("mem_reservation/deploy.resources.reservations.memory(值冲突)")
                    memoryReservation = nil
                } else {
                    memoryReservation = flatMemoryReservation
                }
            } else {
                skipped.append("mem_reservation(结构无法映射)")
            }
        }
        if let memoryReservation {
            flag(memoryReservation, "--memory-reservation")
        }
        if let cpus = scalarString(service["cpus"]) {
            flag(cpus, "--cpus")
        }
        if let memory = scalarString(service["mem_limit"]) ?? scalarString(service["memory"]) {
            flag(memory, "-m")
        }
        if let shares = scalarString(service["cpu_shares"]) {
            flag(shares, "--cpu-shares")
        }
        if let period = scalarString(service["cpu_period"]) {
            flag(period, "--cpu-period")
        }
        if let quota = scalarString(service["cpu_quota"]) {
            flag(quota, "--cpu-quota")
        }
        if let cpuset = scalarString(service["cpuset"]) ?? scalarString(service["cpuset_cpus"]) {
            flag(cpuset, "--cpuset-cpus")
        }
        if let swap = scalarString(service["memswap_limit"]) {
            flag(swap, "--memory-swap")
        }
        if let swappiness = scalarString(service["mem_swappiness"]) {
            flag(swappiness, "--memory-swappiness")
        }
        if let oomScore = scalarString(service["oom_score_adj"]) {
            flag(oomScore, "--oom-score-adj")
        }
        if let shmSize = scalarString(service["shm_size"]) {
            flag(shmSize, "--shm-size")
        }
        if let pidsLimit = scalarString(service["pids_limit"]) {
            flag(pidsLimit, "--pids-limit")
        }
        appendBlkioArguments(service["blkio_config"], into: &args)

        if let pid = scalarString(service["pid"]) {
            flag(pid, "--pid")
        }
        if let uts = scalarString(service["uts"]) {
            flag(uts, "--uts")
        }
        if let ipc = scalarString(service["ipc"]) {
            flag(ipc, "--ipc")
        }

        appendHealthcheckArguments(service["healthcheck"], into: &args, skipped: &skipped)
        appendLoggingArguments(service["logging"], into: &args)
        if let gpus = gpuReservationArgument(service) {
            flag(gpus, "--gpus")
        }
        if let stopSignal = scalarString(service["stop_signal"]) {
            flag(stopSignal, "--stop-signal")
        }
        if let stopGrace = scalarString(service["stop_grace_period"]) {
            flag(stopGrace, "--stop-timeout")
        }
        if service["init"] as? Bool == true {
            args.append("--init")
        }
        if service["read_only"] as? Bool == true {
            args.append("--read-only")
        }
        if service["stdin_open"] as? Bool == true {
            args.append("-i")
        }
        if service["tty"] as? Bool == true {
            args.append("-t")
        }
        if service["oom_kill_disable"] as? Bool == true {
            args.append("--oom-kill-disable")
        }

        if service["deploy"] != nil, !(service["deploy"] is [String: Any]) {
            skipped.append("deploy(结构无法映射)")
        }
        skipped.append(contentsOf: service.keys.filter { !handledKeys.contains($0) }.sorted())
        if let deploy = service["deploy"] as? [String: Any] {
            let deployHandled = deployHandledKeys(deploy)
            let unhandled = deploy.keys.filter { !deployHandled.contains($0) }
            if !unhandled.isEmpty {
                skipped.append("deploy.\(unhandled.sorted().joined(separator: "/"))")
            }
        }
        // One attributed sentence per service; repeated identical notes inside
        // a service (e.g. several networks with addresses) collapse first.
        if !skipped.isEmpty {
            var seenSkipped = Set<String>()
            skipped.removeAll { !seenSkipped.insert($0).inserted }
            warnings.append("服务 \(name) 未映射字段：\(skipped.sorted().joined(separator: "、"))")
        }

        var tokens = ["docker", "run", "-d"] + args + [shellToken(image)]
        if entrypoint.count > 1 {
            tokens += entrypoint.dropFirst().map(shellToken)
        }
        if !command.isEmpty {
            tokens += command.map(shellToken)
        }
        return tokens.joined(separator: " ")
    }

    // MARK: - Field normalizers

    private static let handledKeys: Set<String> = [
        "image", "platform", "container_name", "hostname", "domainname", "entrypoint", "command",
        "environment", "env_file", "ports", "expose", "volumes", "tmpfs",
        "network_mode", "networks", "mac_address", "dns", "dns_opt", "dns_search",
        "extra_hosts", "links", "labels", "cap_add", "cap_drop", "security_opt",
        "privileged", "userns_mode", "group_add", "cpus", "mem_limit", "memory", "mem_reservation",
        "cpu_shares", "cpu_period", "cpu_quota", "cpuset", "cpuset_cpus",
        "memswap_limit", "mem_swappiness", "oom_score_adj", "shm_size",
        "pids_limit", "blkio_config", "sysctls", "ulimits", "pid", "uts", "ipc",
        "healthcheck", "logging", "devices", "gpus", "stop_signal",
        "stop_grace_period", "init", "read_only", "stdin_open", "tty",
        "oom_kill_disable", "restart", "user", "working_dir", "deploy"
    ]

    private static func scalarString(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func memoryValuesEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        guard let leftBytes = memoryBytes(lhs), let rightBytes = memoryBytes(rhs) else {
            return false
        }
        return leftBytes == rightBytes
    }

    private static func memoryBytes(_ value: String) -> Decimal? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        let numberEnd = normalized.firstIndex { $0.isLetter } ?? normalized.endIndex
        let numberText = String(normalized[..<numberEnd])
        let unit = String(normalized[numberEnd...])
        guard !numberText.isEmpty,
              normalized[numberEnd...].allSatisfy(\.isLetter),
              let number = Decimal(string: numberText, locale: Locale(identifier: "en_US_POSIX")),
              number >= 0 else {
            return nil
        }
        let exponents: [String: Int] = [
            "": 0, "b": 0,
            "k": 1, "kb": 1,
            "m": 2, "mb": 2,
            "g": 3, "gb": 3,
            "t": 4, "tb": 4,
            "p": 5, "pb": 5
        ]
        guard let exponent = exponents[unit] else { return nil }
        let multiplier = (0..<exponent).reduce(Decimal(1)) { result, _ in result * 1024 }
        return number * multiplier
    }

    private static func stringList(_ value: Any?) -> [String]? {
        switch value {
        case let array as [Any]:
            let items = array.compactMap(scalarString)
            return items.isEmpty && !array.isEmpty ? nil : items
        case let string as String:
            return [string]
        default:
            return nil
        }
    }

    private static func strictStringList(
        _ value: Any?,
        path: String,
        skipped: inout [String]
    ) -> [String]? {
        guard value != nil else { return nil }
        if let string = value as? String { return [string] }
        guard let array = value as? [Any] else {
            skipped.append("\(path)(结构无法映射)")
            return nil
        }
        let items = array.compactMap(scalarString)
        guard items.count == array.count else {
            skipped.append("\(path)(结构无法映射)")
            return nil
        }
        return items
    }

    private static func environmentPairs(_ value: Any?, skipped: inout [String]) -> [String] {
        if let array = value as? [Any] {
            var pairs: [String] = []
            for (index, raw) in array.enumerated() {
                if let pair = scalarString(raw) {
                    pairs.append(pair)
                } else {
                    skipped.append("environment[\(index)](结构无法映射)")
                }
            }
            return pairs
        }
        if let map = value as? [String: Any] {
            return map.sorted { $0.key < $1.key }.compactMap { key, raw in
                if raw is NSNull {
                    return key
                }
                if let value = scalarString(raw) {
                    return "\(key)=\(value)"
                }
                skipped.append("environment.\(key)(结构无法映射)")
                return nil
            }
        }
        if value != nil {
            skipped.append("environment(结构无法映射)")
        }
        return []
    }

    private static func labelPairs(_ value: Any?) -> [String] {
        if let list = stringList(value) {
            return list
        }
        guard let map = value as? [String: Any] else { return [] }
        return map.sorted { $0.key < $1.key }.map { key, raw in
            scalarString(raw).map { "\(key)=\($0)" } ?? key
        }
    }

    private static func keyValueList(_ value: Any?) -> [String] {
        labelPairs(value)
    }

    private static func portArguments(_ value: Any?, skipped: inout [String]) -> [String] {
        guard let list = value as? [Any] else {
            if value != nil {
                skipped.append("ports(结构无法映射)")
            }
            return []
        }
        var result: [String] = []
        for item in list {
            if let short = scalarString(item) {
                result.append(short)
                continue
            }
            guard let long = item as? [String: Any] else {
                skipped.append("ports(结构无法映射)")
                continue
            }
            guard let target = scalarString(long["target"]) else {
                skipped.append("ports.target(结构无法映射)")
                continue
            }
            let published: String?
            if long["published"] == nil {
                published = nil
            } else if let value = scalarString(long["published"]) {
                published = value
            } else {
                skipped.append("ports.published(结构无法映射)")
                continue
            }
            let protocolName: String?
            if long["protocol"] == nil {
                protocolName = nil
            } else if let value = scalarString(long["protocol"]) {
                protocolName = value
            } else {
                skipped.append("ports.protocol(结构无法映射)")
                continue
            }
            if let mode = scalarString(long["mode"]), mode != "host" {
                skipped.append("ports.mode")
                continue
            } else if long["mode"] != nil, scalarString(long["mode"]) == nil {
                skipped.append("ports.mode(结构无法映射)")
                continue
            }
            let hostIP: String?
            if long["host_ip"] == nil {
                hostIP = nil
            } else if let value = scalarString(long["host_ip"]) {
                hostIP = value
            } else {
                skipped.append("ports.host_ip(结构无法映射)")
                continue
            }
            let unsupported = long.keys.filter {
                !["target", "published", "protocol", "host_ip", "mode"].contains($0)
            }
            skipped.append(contentsOf: unsupported.sorted().map { "ports.\($0)" })
            let suffix = protocolName.map { "/\($0)" } ?? ""
            if let published {
                result.append("\(hostIP.map { "\($0):" } ?? "")\(published):\(target)\(suffix)")
            } else if let hostIP {
                result.append("\(hostIP)::\(target)\(suffix)")
            } else {
                result.append("\(target)\(suffix)")
            }
        }
        return result
    }

    private static func appendNetworkArguments(_ value: Any?, into args: inout [String], skipped: inout [String]) {
        if let networks = value as? [String: Any] {
            for (name, rawConfig) in networks.sorted(by: { $0.key < $1.key }) {
                if rawConfig is NSNull {
                    args.append("--network")
                    args.append(shellToken(name))
                    continue
                }
                guard let config = rawConfig as? [String: Any] else {
                    skipped.append("networks.\(name)(结构无法映射)")
                    continue
                }
                var components = ["name=\(name)"]
                if let aliases = strictStringList(
                    config["aliases"],
                    path: "networks.\(name).aliases",
                    skipped: &skipped
                ) {
                    components += aliases.map { "alias=\($0)" }
                }
                if config["ipv4_address"] != nil {
                    if let ipv4 = scalarString(config["ipv4_address"]) {
                        components.append("ip=\(ipv4)")
                    } else {
                        skipped.append("networks.\(name).ipv4_address(结构无法映射)")
                    }
                }
                if config["ipv6_address"] != nil {
                    if let ipv6 = scalarString(config["ipv6_address"]) {
                        components.append("ip6=\(ipv6)")
                    } else {
                        skipped.append("networks.\(name).ipv6_address(结构无法映射)")
                    }
                }
                let unsupported = config.keys
                    .filter { !["aliases", "ipv4_address", "ipv6_address"].contains($0) }
                    .sorted()
                skipped.append(contentsOf: unsupported.map { "networks.\(name).\($0)" })
                args.append("--network")
                args.append(shellToken(components.joined(separator: ",")))
            }
            return
        }
        if let networks = value as? [Any] {
            for item in networks {
                guard let name = scalarString(item) else {
                    skipped.append("networks(结构无法映射)")
                    continue
                }
                args.append("--network")
                args.append(shellToken(name))
            }
        }
    }

    private static func appendVolumeArguments(_ value: Any?, into args: inout [String], skipped: inout [String]) {
        guard let list = value as? [Any] else { return }
        for item in list {
            if let short = scalarString(item) {
                args.append("-v")
                args.append(shellToken(short))
                continue
            }
            guard let long = item as? [String: Any] else {
                skipped.append("volumes(结构无法映射)")
                continue
            }
            let type: String
            if long["type"] == nil {
                type = "volume"
            } else if let declaredType = scalarString(long["type"]) {
                type = declaredType
            } else {
                skipped.append("volumes.type(结构无法映射)")
                continue
            }
            guard let target = scalarString(long["target"]) else {
                skipped.append("volumes.\(mountPathType(type)).target")
                continue
            }
            if type == "tmpfs" {
                var mount = "type=tmpfs,target=\(target)"
                var unsupportedPaths: [String] = []
                if let tmpfs = long["tmpfs"] as? [String: Any] {
                    if tmpfs["size"] != nil {
                        if let size = scalarString(tmpfs["size"]) {
                            mount += ",tmpfs-size=\(size)"
                        } else {
                            unsupportedPaths.append("volumes.tmpfs.tmpfs.size(结构无法映射)")
                        }
                    }
                    if tmpfs["mode"] != nil {
                        if let mode = scalarString(tmpfs["mode"]) {
                            mount += ",tmpfs-mode=\(mode)"
                        } else {
                            unsupportedPaths.append("volumes.tmpfs.tmpfs.mode(结构无法映射)")
                        }
                    }
                    let unsupported = tmpfs.keys.filter { !["size", "mode"].contains($0) }.sorted()
                    unsupportedPaths.append(contentsOf: unsupported.map { "volumes.tmpfs.tmpfs.\($0)" })
                } else if long["tmpfs"] != nil {
                    unsupportedPaths.append("volumes.tmpfs.tmpfs(结构无法映射)")
                }
                let unsupported = long.keys.filter { !["type", "target", "tmpfs"].contains($0) }.sorted()
                unsupportedPaths.append(contentsOf: unsupported.map { "volumes.tmpfs.\($0)" })
                guard unsupportedPaths.isEmpty else {
                    skipped.append(contentsOf: unsupportedPaths)
                    continue
                }
                args.append("--mount")
                args.append(shellToken(mount))
                continue
            }
            guard type == "bind" || type == "volume" else {
                skipped.append("volumes.\(mountPathType(type))")
                continue
            }
            let optionKey = type
            var unsupportedPaths: [String] = []
            if let options = long[optionKey] as? [String: Any] {
                let unsupported = options.keys.sorted()
                unsupportedPaths += unsupported.map { "volumes.\(type).\(optionKey).\($0)" }
            } else if long[optionKey] != nil {
                unsupportedPaths.append("volumes.\(type).\(optionKey)(结构无法映射)")
            }
            let allowed = Set(["type", "source", "target", "read_only", optionKey])
            let unsupported = long.keys.filter { !allowed.contains($0) }.sorted()
            unsupportedPaths += unsupported.map { "volumes.\(type).\($0)" }
            guard unsupportedPaths.isEmpty else {
                skipped.append(contentsOf: unsupportedPaths)
                continue
            }
            guard let source = scalarString(long["source"]) else {
                skipped.append("volumes.\(type).source")
                continue
            }
            guard long["read_only"] == nil || long["read_only"] is Bool else {
                skipped.append("volumes.\(type).read_only(结构无法映射)")
                continue
            }
            let readOnly = long["read_only"] as? Bool == true
            var mount = "type=\(type),source=\(source),target=\(target)"
            if readOnly {
                mount += ",readonly"
            }
            args.append("--mount")
            args.append(shellToken(mount))
        }
    }

    private static func mountPathType(_ type: String) -> String {
        ["bind", "volume", "tmpfs", "image", "cluster", "npipe"].contains(type) ? type : "type"
    }

    private static func ulimitArguments(_ value: Any?) -> [String] {
        if let list = stringList(value) {
            return list
        }
        guard let map = value as? [String: Any] else { return [] }
        return map.sorted { $0.key < $1.key }.map { name, raw in
            if let detail = raw as? [String: Any],
               let soft = scalarString(detail["soft"]),
               let hard = scalarString(detail["hard"]) {
                return "\(name)=\(soft):\(hard)"
            }
            if let single = scalarString(raw) {
                return "\(name)=\(single)"
            }
            return name
        }
    }

    private static func deployResources(_ service: [String: Any])
        -> (limits: (cpus: String?, memory: String?, pids: String?), reservationMemory: String?, unmappedPaths: [String])?
    {
        guard let deploy = service["deploy"] as? [String: Any] else {
            return nil
        }
        guard let resources = deploy["resources"] as? [String: Any] else {
            if deploy["resources"] != nil {
                return ((nil, nil, nil), nil, ["deploy.resources(结构无法映射)"])
            }
            return nil
        }
        let limits = resources["limits"] as? [String: Any] ?? [:]
        let reservations = resources["reservations"] as? [String: Any] ?? [:]
        var unmappedPaths = resources.keys
            .filter { !["limits", "reservations"].contains($0) }
            .map { "deploy.resources.\($0)" }
        if resources["limits"] != nil, !(resources["limits"] is [String: Any]) {
            unmappedPaths.append("deploy.resources.limits(结构无法映射)")
        }
        if resources["reservations"] != nil, !(resources["reservations"] is [String: Any]) {
            unmappedPaths.append("deploy.resources.reservations(结构无法映射)")
        }
        unmappedPaths += limits.keys
            .filter { !["cpus", "memory", "pids"].contains($0) }
            .map { "deploy.resources.limits.\($0)" }
        unmappedPaths += reservations.keys
            .filter { !["memory", "devices"].contains($0) }
            .map { "deploy.resources.reservations.\($0)" }
        for key in ["cpus", "memory", "pids"] where limits[key] != nil && scalarString(limits[key]) == nil {
            unmappedPaths.append("deploy.resources.limits.\(key)(结构无法映射)")
        }
        if reservations["memory"] != nil, scalarString(reservations["memory"]) == nil {
            unmappedPaths.append("deploy.resources.reservations.memory(结构无法映射)")
        }
        return (
            (
                scalarString(limits["cpus"]),
                scalarString(limits["memory"]),
                scalarString(limits["pids"])
            ),
            scalarString(reservations["memory"]),
            unmappedPaths.sorted()
        )
    }

    private static func deployHandledKeys(_ deploy: [String: Any]) -> Set<String> {
        var handled: Set<String> = []
        if deploy["restart_policy"] != nil {
            handled.insert("restart_policy")
        }
        if deploy["resources"] != nil {
            handled.insert("resources")
        }
        return handled
    }

    private static func deployRestartMaxAttempts(_ service: [String: Any]) -> String? {
        guard let deploy = service["deploy"] as? [String: Any],
              let policy = deploy["restart_policy"] as? [String: Any] else {
            return nil
        }
        return scalarString(policy["max_attempts"])
    }

    private static func restartPolicyUnmappedPaths(_ service: [String: Any]) -> [String] {
        guard let deploy = service["deploy"] as? [String: Any],
              let rawPolicy = deploy["restart_policy"] else {
            return []
        }
        guard let policy = rawPolicy as? [String: Any] else {
            return ["deploy.restart_policy(结构无法映射)"]
        }
        guard let restart = scalarString(service["restart"]) else {
            return ["deploy.restart_policy"]
        }

        var paths = policy.keys
            .filter { !["condition", "max_attempts"].contains($0) }
            .map { "deploy.restart_policy.\($0)" }
        if policy["condition"] != nil {
            if let condition = scalarString(policy["condition"]) {
                if condition != restart {
                    paths.append("deploy.restart_policy.condition")
                }
            } else {
                paths.append("deploy.restart_policy.condition(结构无法映射)")
            }
        }
        if policy["max_attempts"] != nil {
            if restart != "on-failure" {
                paths.append("deploy.restart_policy.max_attempts")
            } else if scalarString(policy["max_attempts"]) == nil {
                paths.append("deploy.restart_policy.max_attempts(结构无法映射)")
            }
        }
        return paths.sorted()
    }

    private static func gpuReservationArgument(_ service: [String: Any]) -> String? {
        if let direct = scalarString(service["gpus"]) {
            return direct
        }
        guard let deploy = service["deploy"] as? [String: Any],
              let resources = deploy["resources"] as? [String: Any],
              let reservations = resources["reservations"] as? [String: Any],
              let devices = reservations["devices"] as? [Any],
              let first = devices.first as? [String: Any] else {
            return nil
        }
        return scalarString(first["count"]) ?? "all"
    }

    private static func appendBlkioArguments(_ value: Any?, into args: inout [String]) {
        guard let config = value as? [String: Any] else { return }
        if let weight = scalarString(config["weight"]) {
            args.append("--blkio-weight")
            args.append(shellToken(weight))
        }
        let deviceOptions: [(String, String)] = [
            ("device_read_bps", "--device-read-bps"),
            ("device_write_bps", "--device-write-bps"),
            ("device_read_iops", "--device-read-iops"),
            ("device_write_iops", "--device-write-iops")
        ]
        for (key, flagName) in deviceOptions {
            guard let entries = config[key] as? [Any] else { continue }
            for entry in entries {
                guard let detail = entry as? [String: Any],
                      let path = scalarString(detail["path"]),
                      let rate = scalarString(detail["rate"]) else { continue }
                args.append(flagName)
                args.append(shellToken("\(path):\(rate)"))
            }
        }
    }

    private static func appendHealthcheckArguments(
        _ value: Any?,
        into args: inout [String],
        skipped: inout [String]
    ) {
        guard let healthcheck = value as? [String: Any] else {
            if value != nil { skipped.append("healthcheck(结构无法映射)") }
            return
        }
        if healthcheck["disable"] as? Bool == true || healthcheck["disabled"] as? Bool == true {
            args.append("--no-healthcheck")
            return
        }
        if let test = healthcheck["test"] {
            if let command = test as? String {
                args.append("--health-cmd")
                args.append(shellToken(command))
            } else if let list = test as? [Any], let kind = list.first as? String {
                switch kind {
                case "CMD-SHELL":
                    let parts = list.dropFirst().compactMap(scalarString)
                    if list.count == 2, parts.count == 1 {
                        args.append("--health-cmd")
                        args.append(shellToken(parts[0]))
                    } else {
                        skipped.append("healthcheck.test(结构无法映射)")
                        return
                    }
                case "NONE" where list.count == 1:
                    args.append("--no-healthcheck")
                    return
                case "CMD":
                    skipped.append("healthcheck.test(exec-form 无法等价映射)")
                    return
                default:
                    skipped.append("healthcheck.test(结构无法映射)")
                    return
                }
            } else {
                skipped.append("healthcheck.test(结构无法映射)")
            }
        }
        let scalarOptions = [
            ("interval", "--health-interval"),
            ("timeout", "--health-timeout"),
            ("retries", "--health-retries"),
            ("start_period", "--health-start-period"),
            ("start_interval", "--health-start-interval")
        ]
        for (key, option) in scalarOptions where healthcheck[key] != nil {
            if let scalar = scalarString(healthcheck[key]) {
                args.append(option)
                args.append(shellToken(scalar))
            } else {
                skipped.append("healthcheck.\(key)(结构无法映射)")
            }
        }
        let known = Set(["disable", "disabled", "test", "interval", "timeout", "retries", "start_period", "start_interval"])
        skipped.append(contentsOf: healthcheck.keys.filter { !known.contains($0) }.sorted().map { "healthcheck.\($0)" })
    }

    private static func appendLoggingArguments(_ value: Any?, into args: inout [String]) {
        guard let logging = value as? [String: Any] else { return }
        if let driver = scalarString(logging["driver"]) {
            args.append("--log-driver")
            args.append(shellToken(driver))
        }
        if let options = logging["options"] as? [String: Any] {
            for (key, raw) in options.sorted(by: { $0.key < $1.key }) {
                guard let value = scalarString(raw) else { continue }
                args.append("--log-opt")
                args.append(shellToken("\(key)=\(value)"))
            }
        }
    }

    // MARK: - Shell tokenization

    private static let shellUnsafeCharacters = CharacterSet(
        charactersIn: " \t\"'\\$`&|;<>(){}*?[]#~"
    )

    private static func shellToken(_ raw: String) -> String {
        guard raw.rangeOfCharacter(from: shellUnsafeCharacters) != nil || raw.isEmpty else {
            return raw
        }
        let escaped = raw.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
