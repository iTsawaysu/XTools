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
/// network addresses/aliases, …) produce warnings instead of failing.
public enum DockerComposeToRunService {
    public static func convert(_ yamlText: String) throws -> DockerComposeToRunResult {
        let document: Any
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
        if let platform = scalarString(service["platform"]) {
            flag(platform, "--platform")
        }
        if let hostname = scalarString(service["hostname"]) {
            flag(hostname, "-h")
        }
        if let domainname = scalarString(service["domainname"]) {
            flag(domainname, "--domainname")
        }
        if let entrypoint = stringList(service["entrypoint"]), !entrypoint.isEmpty {
            flag(entrypoint.joined(separator: " "), "--entrypoint")
        }
        if let user = scalarString(service["user"]) {
            flag(user, "-u")
        }
        if let workingDir = scalarString(service["working_dir"]) {
            flag(workingDir, "-w")
        }
        if let restart = scalarString(service["restart"]) {
            var value = restart
            if restart == "on-failure",
               let attempts = deployRestartMaxAttempts(service) {
                value = "on-failure:\(attempts)"
            }
            flag(value, "--restart")
        }
        if let networkMode = scalarString(service["network_mode"]) {
            flag(networkMode, "--network")
        } else if let networks = service["networks"] as? [String: Any], !networks.isEmpty {
            // Map-form networks may carry addresses/aliases that a single
            // docker run command cannot express.
            for (_, config) in networks.sorted(by: { $0.key < $1.key }) {
                if let detail = config as? [String: Any] {
                    if detail["ipv4_address"] != nil || detail["ipv6_address"] != nil {
                        skipped.append("networks.ipv4/ipv6_address")
                    }
                    if let aliases = detail["aliases"], aliases != nil {
                        skipped.append("networks.aliases")
                    }
                }
            }
            flag(networks.keys.sorted().joined(separator: ","), "--network")
        } else if let networks = service["networks"] as? [Any], !networks.isEmpty {
            let names = networks.compactMap(scalarString)
            if !names.isEmpty {
                flag(names.joined(separator: ","), "--network")
            }
        }
        if let macAddress = scalarString(service["mac_address"]) {
            flag(macAddress, "--mac-address")
        }

        for envFile in stringList(service["env_file"]) ?? [] {
            flag(envFile, "--env-file")
        }
        for pair in environmentPairs(service["environment"]) {
            if pair.contains("=") {
                flag(pair, "-e")
            } else {
                flag(pair, "-e")
            }
        }
        for port in portArguments(service["ports"], skipped: &skipped) {
            flag(port, "-p")
        }
        for exposed in stringList(service["expose"]) ?? [] {
            flag(exposed, "--expose")
        }
        for volume in volumeArguments(service["volumes"], skipped: &skipped) {
            flag(volume, "-v")
        }
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
        if let limits = deployResourceLimits(service) {
            if let cpus = limits.cpus {
                flag(cpus, "--cpus")
            }
            if let memory = limits.memory {
                flag(memory, "-m")
            }
            if let pids = limits.pids {
                flag(pids, "--pids-limit")
            }
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

        appendHealthcheckArguments(service["healthcheck"], into: &args)
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
        if let command = stringList(service["command"]), !command.isEmpty {
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
        "privileged", "userns_mode", "group_add", "cpus", "mem_limit", "memory",
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

    private static func environmentPairs(_ value: Any?) -> [String] {
        if let list = stringList(value) {
            return list
        }
        if let map = value as? [String: Any] {
            return map.sorted { $0.key < $1.key }.map { key, raw in
                if let value = scalarString(raw) {
                    return "\(key)=\(value)"
                }
                return key
            }
        }
        return []
    }

    private static func labelPairs(_ value: Any?) -> [String] {
        environmentPairs(value)
    }

    private static func keyValueList(_ value: Any?) -> [String] {
        environmentPairs(value)
    }

    private static func portArguments(_ value: Any?, skipped: inout [String]) -> [String] {
        guard let list = value as? [Any] else {
            if value is [String: Any] {
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
            guard let long = item as? [String: Any] else { continue }
            let target = scalarString(long["target"])
            let published = scalarString(long["published"])
            let protocolName = scalarString(long["protocol"])
            if let mode = scalarString(long["mode"]), mode != "host" {
                skipped.append("ports.mode=\(mode)")
            }
            guard let target else { continue }
            if let published {
                result.append("\(published):\(target)\(protocolName.map { "/\($0)" } ?? "")")
            } else {
                result.append(target)
            }
        }
        return result
    }

    private static func volumeArguments(_ value: Any?, skipped: inout [String]) -> [String] {
        guard let list = value as? [Any] else { return [] }
        var result: [String] = []
        for item in list {
            if let short = scalarString(item) {
                result.append(short)
                continue
            }
            guard let long = item as? [String: Any] else { continue }
            let type = scalarString(long["type"]) ?? "volume"
            guard let target = scalarString(long["target"]) else { continue }
            if type == "tmpfs" {
                result.append(target)
                continue
            }
            guard let source = scalarString(long["source"]) else {
                skipped.append("volumes(匿名卷 \(target))")
                continue
            }
            let readOnly = long["read_only"] as? Bool == true
            result.append("\(source):\(target)\(readOnly ? ":ro" : "")")
        }
        return result
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

    private static func deployResourceLimits(_ service: [String: Any])
        -> (cpus: String?, memory: String?, pids: String?)?
    {
        guard let deploy = service["deploy"] as? [String: Any],
              let resources = deploy["resources"] as? [String: Any],
              let limits = resources["limits"] as? [String: Any] else {
            return nil
        }
        return (
            scalarString(limits["cpus"]),
            scalarString(limits["memory"]),
            scalarString(limits["pids"])
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

    private static func appendHealthcheckArguments(_ value: Any?, into args: inout [String]) {
        guard let healthcheck = value as? [String: Any] else { return }
        if healthcheck["disable"] as? Bool == true || healthcheck["disabled"] as? Bool == true {
            args.append("--no-healthcheck")
            return
        }
        if let test = healthcheck["test"] as? [Any],
           let joined = testSummary(fromList: test) {
            args.append("--health-cmd")
            args.append(shellToken(joined))
        }
        if let interval = scalarString(healthcheck["interval"]) {
            args.append("--health-interval")
            args.append(shellToken(interval))
        }
        if let timeout = scalarString(healthcheck["timeout"]) {
            args.append("--health-timeout")
            args.append(shellToken(timeout))
        }
        if let retries = scalarString(healthcheck["retries"]) {
            args.append("--health-retries")
            args.append(shellToken(retries))
        }
        if let startPeriod = scalarString(healthcheck["start_period"]) {
            args.append("--health-start-period")
            args.append(shellToken(startPeriod))
        }
    }

    private static func testSummary(fromList list: [Any]) -> String? {
        let parts = list.compactMap(scalarString)
        guard !parts.isEmpty else { return nil }
        if parts.first == "CMD-SHELL" {
            return parts.dropFirst().joined(separator: " ")
        }
        if parts.first == "CMD" || parts.first == "NONE" {
            return parts.dropFirst().joined(separator: " ")
        }
        return parts.joined(separator: " ")
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
