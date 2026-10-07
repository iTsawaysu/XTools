import Foundation
import Yams

public enum DockerComposeToRunError: Error, Equatable, Sendable, LocalizedError {
    case invalidYAML(FormatDiagnostic)
    case missingServicesSection
    case noServices
    case unresolvedInterpolation(String)
    case configurationTooDeep

    /// 单一真相源在 `DockerComposeToRunDiagnostics`，避免页面与错误类型各写一份文案后漂移。
    public var errorDescription: String? {
        DockerComposeToRunDiagnostics.message(for: self)
    }
}

public struct DockerComposeToRunResult: Equatable, Sendable {
    /// One `docker run` command per service, in deterministic (sorted)
    /// service order.
    public let commands: [String]
    public let warnings: [String]
    public let warningDetails: [String]

    public init(commands: [String], warnings: [String], warningDetails: [String] = []) {
        self.commands = commands
        self.warnings = warnings
        self.warningDetails = warningDetails
    }
}

public enum DockerComposeToRunDiagnostics {
    static let invalidYAMLMessage = "无法解析 YAML：缩进或语法不合法。"
    static let missingServicesMessage = "未找到 services 段：Compose 文件需要顶级 services 键。"
    static let noServicesMessage = "services 段为空：至少需要一个服务定义。"

    /// 与 JSONDiffValidation / 顶栏横幅一致的可读上限；单条与合成共用。
    private static let maximumMessageCharacters = 180
    private static let collapsedFieldPreviewCount = 5

    static func safeFieldName(_ field: String) -> String {
        let suffixes = ["(结构无法映射)", "(exec-form 无法等价映射)", "(无法映射空命令)", "(值冲突)"]
        let suffix = suffixes.first(where: field.hasSuffix) ?? ""
        let path = suffix.isEmpty ? field : String(field.dropLast(suffix.count))
        guard path.utf8.count <= 96,
              path.range(of: #"^[A-Za-z0-9_.:/\[\]-]+$"#, options: .regularExpression) != nil else {
            return "未知字段"
        }
        return path + suffix
    }

    static func boundedDetails(_ details: [String]) -> [String] {
        var seen = Set<String>()
        let unique = details.filter { seen.insert($0).inserted }
        var visible = Array(unique.prefix(256))
        if unique.count > visible.count {
            visible.append("另有 \(unique.count - visible.count) 项转换提示，未展开显示。")
        }
        return visible
    }

    /// 服务内未映射字段的一句话归因；字段过多时折叠列表，保持事实型单段，
    /// 且不超横幅可读上限。字段路径保留 Compose 官方英文名——目标用户要
    /// 拿着它对照 Compose 文档；括号补充「无对应」的含义说明。
    static func unmappedFieldsMessage(service: String, fields: [String]) -> String {
        let lead = "服务 \(service) 未映射字段（无对应）："
        let list = fields.joined(separator: "、")
        if lead.count + list.count <= maximumMessageCharacters {
            return lead + list
        }

        // 折叠：只列前几个字段；不足预览数时全列（不写「前 N 个」措辞），
        // 让边界场景（四五条长路径恰好超限）仍能看到完整清单。
        let previewFields = Array(fields.prefix(collapsedFieldPreviewCount))
        let showsAll = previewFields.count == fields.count
        let previewList = previewFields.joined(separator: "、") + (showsAll ? "" : "…")
        let preview = "服务 \(service) 有 \(fields.count) 个未映射字段（无对应）：\(previewList)"
        if preview.count <= maximumMessageCharacters {
            return preview
        }
        return "服务 \(service) 有 \(fields.count) 个未映射字段（无对应）。"
    }

    /// 无法从底层错误获得更多信息时的兜底诊断。
    public static let invalidYAMLFallbackDiagnostic = FormatDiagnostic(
        formatName: "Compose 转换",
        message: invalidYAMLMessage,
        suggestion: "检查缩进、冒号后的空格、列表括号和引号是否闭合。"
    )

    public static func message(for error: DockerComposeToRunError) -> String {
        switch error {
        case .invalidYAML(let diagnostic):
            return diagnostic.workspaceMessage
        case .missingServicesSection:
            return missingServicesMessage
        case .noServices:
            return noServicesMessage
        case .unresolvedInterpolation(let field):
            return "`\(field)` 包含尚未求值的 Compose 插值，无法等价转换。"
        case .configurationTooDeep:
            return "Compose 配置嵌套超过 64 层，未进行转换。"
        }
    }

    public static func diagnostic(for error: DockerComposeToRunError) -> FormatDiagnostic {
        switch error {
        case .invalidYAML(let diagnostic):
            return diagnostic
        case .missingServicesSection:
            return FormatDiagnostic(
                formatName: "Compose 转换",
                message: missingServicesMessage,
                suggestion: "确认 YAML 包含合法的 version 或 services 服务定义块。"
            )
        case .noServices:
            return FormatDiagnostic(
                formatName: "Compose 转换",
                message: noServicesMessage,
                suggestion: "在 services 下至少定义一个服务，例如 web: {image: nginx}。"
            )
        case .unresolvedInterpolation, .configurationTooDeep:
            return FormatDiagnostic(
                formatName: "Compose 转换",
                message: message(for: error),
                suggestion: error == .configurationTooDeep
                    ? "请减少配置嵌套后重试。"
                    : "使用已解析的配置，或将需要保留的字面美元写成 $$；转换器不会读取本机环境。"
            )
        }
    }

    public static func warningMessage(for warnings: [String]) -> String? {
        guard !warnings.isEmpty else { return nil }
        if warnings.count == 1 {
            return warnings[0]
        }

        // 多条合成可能远超横幅可读上限；逐条累加到放得下的最后一条，
        // 其余折叠为计数——与 JSONDiffValidation 的超限退化策略同型。
        let prefix = "转换提示（\(warnings.count) 项）："
        var included: [String] = []
        for warning in warnings {
            let omittedCount = warnings.count - included.count - 1
            let suffix = omittedCount > 0 ? "；其余 \(omittedCount) 项已省略。" : ""
            let candidate = prefix + (included + [warning]).joined(separator: "；") + suffix
            guard candidate.count <= maximumMessageCharacters else { break }
            included.append(warning)
        }

        let omittedCount = warnings.count - included.count
        guard omittedCount > 0 else {
            return prefix + included.joined(separator: "；")
        }
        if included.isEmpty {
            // 防御：加前缀后连第一条都放不下时，直接返回第一条本身——
            // 单条已在源头保证不超上限，且条目自含服务主语。
            return warnings[0]
        }
        return prefix + included.joined(separator: "；") + "；其余 \(omittedCount) 项已省略。"
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
            // 复用 YAMLPrettifier 的 Yams problem 翻译表，让行内缩进/引号类
            // 错误带上行列与针对性建议，而不是一律报「缩进或语法不合法」。
            throw DockerComposeToRunError.invalidYAML(
                YAMLPrettifier.parsingDiagnostic(from: error, input: yamlText)
                    ?? DockerComposeToRunDiagnostics.invalidYAMLFallbackDiagnostic
            )
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
        var details: [String] = []
        var commands: [String] = []

        // Top-level definitions (networks/volumes/configs/secrets) cannot be
        // inlined into a single run command — the service references to them
        // ARE mapped, so they get an informational note instead of being
        // reported as skipped fields.
        let definitionNotes = ["networks", "volumes", "configs", "secrets"].filter { root[$0] != nil }
        if !definitionNotes.isEmpty {
            warnings.append("顶层 \(definitionNotes.joined(separator: "、")) 定义不会写入命令（服务内引用已映射，需预先创建）")
            details.append(contentsOf: warnings)
        }
        let ignoredTopLevel = root.keys
            .filter { !["services", "version", "name"].contains($0) && !definitionNotes.contains($0) }
            .filter { !$0.hasPrefix("x-") }
            .sorted()
        if !ignoredTopLevel.isEmpty {
            warnings.append("有 \(ignoredTopLevel.count) 个顶层字段未映射。")
            details.append(contentsOf: ignoredTopLevel.map { "顶层 \(DockerComposeToRunDiagnostics.safeFieldName($0))：未映射。" })
        }

        for (name, body) in services.sorted(by: { $0.key < $1.key }) {
            let safeName = DockerComposeToRunDiagnostics.safeFieldName(name)
            guard var service = body as? [String: Any] else {
                let warning = "服务 \(safeName) 结构无效"
                warnings.append(warning)
                details.append(warning)
                continue
            }
            let ignoredInterpolationPaths = inactiveInterpolationPaths(in: service)
            for key in service.keys.sorted() where handledKeys.contains(key) {
                if let value = service[key] {
                    service[key] = try DockerComposeInterpolation.literalValues(value, field: key, ignoredPaths: ignoredInterpolationPaths)
                }
            }
            guard let image = scalarString(service["image"]), !image.isEmpty else {
                let warning = "服务 \(safeName) 缺少 image"
                warnings.append(warning)
                details.append(warning)
                continue
            }
            commands.append(buildCommand(name: safeName, image: image, service: service, warnings: &warnings, details: &details))
        }

        guard !commands.isEmpty else {
            throw DockerComposeToRunError.noServices
        }

        // Identical lines collapse (repeated identical notes across services);
        // per-service lines are intentionally distinct for attribution.
        var seen = Set<String>()
        warnings.removeAll { !seen.insert($0).inserted }
        return DockerComposeToRunResult(
            commands: commands,
            warnings: warnings,
            warningDetails: DockerComposeToRunDiagnostics.boundedDetails(details)
        )
    }

    /// Keep interpolation aligned with branches consumed by command assembly.
    /// Inactive alternatives still reach its existing loss diagnostics unchanged.
    private static func inactiveInterpolationPaths(in service: [String: Any]) -> Set<String> {
        var paths = Set<String>()
        if scalarString(service["network_mode"]) != nil { paths.insert("networks") }
        if scalarString(service["mem_limit"]) != nil { paths.insert("memory") }
        if scalarString(service["cpuset"]) != nil { paths.insert("cpuset_cpus") }
        if scalarString(service["restart"]) == nil { paths.insert("deploy.restart_policy") }
        if scalarString(service["gpus"]) != nil { paths.insert("deploy.resources.reservations.devices") }
        if let healthcheck = service["healthcheck"] as? [String: Any] {
            if healthcheck["disable"] as? Bool == true || healthcheck["disabled"] as? Bool == true {
                paths.insert("healthcheck")
            } else if let test = healthcheck["test"] as? [Any],
                      let kind = test.first as? String, kind == "CMD" || (kind == "NONE" && test.count == 1) {
                // CMD is explicitly unsupported; NONE exits before interval fields.
                paths.insert("healthcheck")
            }
        }
        return paths
    }

    // MARK: - Command assembly


    static let handledKeys: Set<String> = [
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
}
