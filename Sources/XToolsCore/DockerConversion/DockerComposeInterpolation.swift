import Foundation

enum DockerComposeInterpolation {
    /// Decode only Compose value interpolation. YAML mapping keys are literal.
    /// A converter has no .env / shell environment context, so it must not freeze
    /// an unresolved expression into a quoted docker run argument.
    static func literalValues(_ value: Any, field: String, path: String? = nil, depth: Int = 0, ignoredPaths: Set<String> = []) throws -> Any {
        guard depth <= 64 else { throw DockerComposeToRunError.configurationTooDeep }
        let path = path ?? field
        guard !ignoredPaths.contains(path) else { return value }
        if let string = value as? String {
            return try literalString(string, field: field)
        }
        if let list = value as? [Any] {
            if path == "deploy.resources.reservations.devices" {
                // The existing command assembler consumes only the first GPU
                // reservation. Later entries do not participate in interpolation.
                guard let first = list.first as? [String: Any] else { return value }
                var result = list
                result[0] = try literalValues(first, field: field, path: path + "[]", depth: depth + 1, ignoredPaths: ignoredPaths)
                return result
            }
            return try list.map { try literalValues($0, field: field, path: path + "[]", depth: depth + 1, ignoredPaths: ignoredPaths) }
        }
        if let map = value as? [String: Any] {
            var result = map
            for (key, child) in map {
                guard let childPath = mappedChildPath(key, at: path) else { continue }
                result[key] = try literalValues(child, field: field, path: childPath, depth: depth + 1, ignoredPaths: ignoredPaths)
            }
            return result
        }
        return value
    }

    /// Mirrors the nested fields actually read by command assembly. Unknown
    /// fields still produce loss diagnostics; they cannot block mapped output
    /// merely because their unused values contain an interpolation expression.
    private static func mappedChildPath(_ key: String, at path: String) -> String? {
        switch path {
        case "environment", "labels", "sysctls", "logging.options":
            return path + ".value"
        case "networks", "ulimits":
            return path + ".entry"
        default:
            guard mappedChildren[path]?.contains(key) == true else { return nil }
            return path + "." + key
        }
    }

    private static let mappedChildren: [String: Set<String>] = [
        "ports[]": ["target", "published", "protocol", "host_ip", "mode"],
        "volumes[]": ["type", "source", "target", "read_only", "tmpfs"],
        "volumes[].tmpfs": ["size", "mode"],
        "networks.entry": ["aliases", "ipv4_address", "ipv6_address"],
        "ulimits.entry": ["soft", "hard"],
        "healthcheck": ["test", "interval", "timeout", "retries", "start_period", "start_interval"],
        "logging": ["driver", "options"],
        "deploy": ["resources", "restart_policy"],
        "deploy.resources": ["limits", "reservations"],
        "deploy.resources.limits": ["cpus", "memory", "pids"],
        "deploy.resources.reservations": ["memory", "devices"],
        "deploy.resources.reservations.devices[]": ["count"],
        "deploy.restart_policy": ["condition", "max_attempts"],
        "blkio_config": ["weight", "device_read_bps", "device_write_bps", "device_read_iops", "device_write_iops"],
        "blkio_config.device_read_bps[]": ["path", "rate"],
        "blkio_config.device_write_bps[]": ["path", "rate"],
        "blkio_config.device_read_iops[]": ["path", "rate"],
        "blkio_config.device_write_iops[]": ["path", "rate"]
    ]

    private static func literalString(_ value: String, field: String) throws -> String {
        guard value.contains("$") else { return value }
        let scalars = Array(value.unicodeScalars)
        var result = ""
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "$", index + 1 < scalars.count {
                let next = scalars[index + 1]
                if next == "$" {
                    result.append("$")
                    index += 2
                    continue
                }
                if next == "{" || DockerRunToDockerComposeService.isShellNameStart(next) {
                    throw DockerComposeToRunError.unresolvedInterpolation(field)
                }
            }
            result.unicodeScalars.append(scalar)
            index += 1
        }
        return result
    }
}
