import Foundation

extension DockerRunToDockerComposeService {
    static func dockerRunOccurrences(in command: String) -> Int {
        let chars = Array(command)
        var count = 0
        var quote: Character?
        var index = 0

        while index < chars.count {
            let character = chars[index]

            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                index += 1
                continue
            }

            if character == "\"" || character == "'" {
                quote = character
                index += 1
                continue
            }

            if matchesDockerRun(chars, at: index) {
                count += 1
                index += "docker".count
                continue
            }

            index += 1
        }

        return count
    }

    private static func matchesDockerRun(_ chars: [Character], at start: Int) -> Bool {
        let docker = Array("docker")
        let run = Array("run")

        guard start + docker.count <= chars.count else { return false }
        for offset in 0..<docker.count where chars[start + offset] != docker[offset] {
            return false
        }

        var cursor = start + docker.count
        var sawWhitespace = false
        while cursor < chars.count, chars[cursor].isWhitespace {
            sawWhitespace = true
            cursor += 1
        }
        guard sawWhitespace else { return false }

        guard cursor + run.count <= chars.count else { return false }
        for offset in 0..<run.count where chars[cursor + offset] != run[offset] {
            return false
        }
        return true
    }

    static func requireValue(after option: String, in tokens: [String], index: inout Int) throws -> String {
        let nextIndex = index + 1
        guard nextIndex < tokens.count else {
            throw DockerRunToDockerComposeError.missingOptionValue(option)
        }

        let value = tokens[nextIndex]
        guard !isLikelyOptionToken(value) else {
            throw DockerRunToDockerComposeError.missingOptionValue(option)
        }

        index = nextIndex + 1
        return value
    }

    /// `docker run` 中不接收值的布尔标志。真假由 `--flag` / `--flag=false` 表达。
    ///
    /// 这份清单是 `flagTakesValue` 与解析分支的唯一真相源：两边分开维护就会出现
    /// 「未知标志按有值处理、把镜像名当参数吞掉」的问题（`-P nginx` 曾经报「缺少镜像名称」）。
    static let booleanFlags: Set<String> = [
        "-d", "--detach",
        "-i", "--interactive",
        "-t", "--tty",
        "--rm",
        "--privileged",
        "--read-only",
        "--init",
        "--oom-kill-disable",
        "--sig-proxy",
        "-P", "--publish-all",
        "--disable-content-trust",
        "--no-healthcheck",
        "--help"
    ]

    /// `--network` 中表示「网络模式」而非外部网络名的取值。
    /// `none` 表示禁用网络、`container:<name>` 表示复用另一容器的网络命名空间，
    /// 它们都不是可以预先创建的外部网络。
    static func networkModeValue(for value: String) -> String? {
        switch value {
        case "host", "none", "bridge":
            return value
        default:
            return value.hasPrefix("container:") ? value : nil
        }
    }

    /// 识别 `C:\data:/data`、`c:/data:/data` 这类 Windows 盘符的宿主路径。
    ///
    /// 说明：本工具运行在 macOS，但输入是用户**粘贴的 docker 命令文本**，这类文本
    /// 常常来自 Windows 上写的文档、同事的命令或 CI 配置。直接按 `:` 切分会把盘符
    /// 当成具名卷，从而在顶层凭空生成 `volumes: C:`。
    ///
    /// 必须与「单字母具名卷」区分：`-v x:/data` 的 `x` 是具名卷，只有一个冒号；
    /// 盘符形态必须还有 `source:target` 的第二个冒号。
    static func isWindowsDrivePath(_ volume: String) -> Bool {
        let characters = Array(volume)
        guard characters.count >= 3,
              characters[0].isLetter,
              characters[1] == ":" else {
            return false
        }
        guard characters[2] == "\\" || characters[2] == "/" else {
            return false
        }
        return characters.dropFirst(2).contains(":")
    }

    /// docker run 的短选项别名。必须与长写保持完整对应，否则短写会被当成未知标志
    /// 而被静默丢弃（`-m 512m`、`-c 2` 曾经完全不出现在生成的 Compose 里），
    /// 而 Compose→Run 方向生成的正是 `-m`，造成两个方向不对称、往返丢字段。
    static let shortFlagAliases: [String: String] = [
        "-p": "--publish",
        "-v": "--volume",
        "-e": "--env",
        "-l": "--label",
        "-w": "--workdir",
        "-u": "--user",
        "-m": "--memory",
        "-c": "--cpu-shares"
    ]

    static let unsupportedValueFlags: Set<String> = [
        "--cidfile",
        "--cgroupns"
    ]

    static func parseOptionToken(_ token: String) -> (flag: String, value: String?) {
        for short in shortFlagAliases.keys where !token.hasPrefix("--") && token.hasPrefix(short) && token != short {
            let rawRemainder = String(token.dropFirst(short.count))
            let remainder = rawRemainder.hasPrefix("=") ? String(rawRemainder.dropFirst()) : rawRemainder
            let knownBooleanShorts: Set<Character> = ["d", "i", "t"]
            if remainder.allSatisfy({ knownBooleanShorts.contains($0) }) {
                continue
            }
            return (short, remainder)
        }

        if let separator = token.firstIndex(of: "=") {
            return (String(token[..<separator]), String(token[token.index(after: separator)...]))
        }

        return (token, nil)
    }

    static func flagTakesValue(_ flag: String) -> Bool {
        !booleanFlags.contains(flag)
    }

    static func isLikelyOptionToken(_ token: String) -> Bool {
        let exactOptions: Set<String> = [
            "--", "--name", "-p", "--publish", "-v", "--volume", "-e", "--env",
            "--env-file", "--restart", "--network", "--user", "-u", "--workdir", "-w",
            "--add-host", "--label", "-l", "-d", "--detach", "-i", "--interactive",
            "-t", "--tty", "--rm", "--privileged", "--device", "--cap-add",
            "--cap-drop", "--ipc", "--pid", "--uts", "--cgroupns",
            "--hostname", "--dns", "--entrypoint", "--expose", "--tmpfs",
            "--mount", "--memory", "--cpus", "--log-driver", "--security-opt"
        ]

        if exactOptions.contains(token) || token.hasPrefix("--") {
            return true
        }

        let shortOptionPrefixes = ["-p", "-v", "-e", "-l", "-w", "-u"]
        return shortOptionPrefixes.contains { prefix in
            token.hasPrefix(prefix) && token != prefix
        }
    }

    static func sanitizedServiceName(from raw: String) -> String {
        let normalized = raw
            .lowercased()
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "_", with: "-")

        let allowed = normalized.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return allowed.isEmpty ? "app" : allowed
    }

    static func normalizeVolumePath(_ volumeString: String) -> String {
        var normalized = volumeString.replacingOccurrences(of: "$(pwd)", with: "./")
        normalized = normalized.replacingOccurrences(of: "${PWD}", with: "./")
        normalized = normalized.replacingOccurrences(of: "$PWD", with: "./")

        normalized = normalized.replacingOccurrences(of: ".//", with: "./")

        return normalized
    }

    static func parseMount(_ mountString: String) -> (mount: ComposeMount?, unsupported: [String]) {
        var mountType: ComposeMount.Kind?
        var source: String?
        var target: String?
        var tmpfsSize: String?
        var tmpfsMode: String?
        var isReadonly = false
        var unsupported: [String] = []

        let parts = mountString.split(separator: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)

            if trimmed == "readonly" || trimmed == "ro" {
                isReadonly = true
                continue
            }
            if trimmed.hasPrefix("readonly=") {
                let value = String(trimmed.dropFirst("readonly=".count))
                if value == "true" {
                    isReadonly = true
                } else if value != "false" {
                    unsupported.append("readonly")
                }
                continue
            }

            let keyValue = trimmed.split(separator: "=", maxSplits: 1)
            guard keyValue.count == 2 else {
                unsupported.append("option")
                continue
            }

            let key = String(keyValue[0]).trimmingCharacters(in: .whitespaces)
            let value = String(keyValue[1]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "type":
                mountType = ComposeMount.Kind(rawValue: value)
                if mountType == nil {
                    unsupported.append("type")
                }
            case "source", "src":
                source = value
            case "target", "dst", "destination":
                target = value
            case "tmpfs-size":
                tmpfsSize = value
            case "tmpfs-mode":
                tmpfsMode = value
            default:
                unsupported.append(key)
            }
        }

        guard let mountType else {
            if !unsupported.contains("type") { unsupported.append("type") }
            return (nil, unsupported)
        }
        guard let target, !target.isEmpty else {
            unsupported.append("target")
            return (nil, unsupported)
        }
        if mountType != .tmpfs, source?.isEmpty != false {
            unsupported.append("source")
        }
        if mountType != .tmpfs, tmpfsSize != nil || tmpfsMode != nil {
            unsupported.append("tmpfs")
        }
        if mountType == .tmpfs, source != nil {
            unsupported.append("source")
        }
        guard unsupported.isEmpty else { return (nil, unsupported) }
        return (
            ComposeMount(
                kind: mountType,
                source: source,
                target: target,
                readOnly: isReadonly,
                size: tmpfsSize,
                mode: tmpfsMode
            ),
            []
        )
    }

    static func parseNetworkAttachment(_ value: String) -> (attachment: NetworkAttachment?, unsupported: [String]) {
        guard value.contains("=") else {
            return value.isEmpty ? (nil, ["name"]) : (NetworkAttachment(name: value), [])
        }

        var name: String?
        var aliases: [String] = []
        var ipv4Address: String?
        var ipv6Address: String?
        var unsupported: [String] = []
        for item in value.split(separator: ",") {
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, !pair[1].isEmpty else {
                unsupported.append("option")
                continue
            }
            switch pair[0] {
            case "name":
                name = pair[1]
            case "alias":
                aliases.append(pair[1])
            case "ip":
                ipv4Address = pair[1]
            case "ip6":
                ipv6Address = pair[1]
            default:
                unsupported.append(pair[0])
            }
        }

        guard let name, !name.isEmpty else {
            unsupported.append("name")
            return (nil, unsupported)
        }
        return (
            NetworkAttachment(
                name: name,
                aliases: aliases,
                ipv4Address: ipv4Address,
                ipv6Address: ipv6Address
            ),
            unsupported
        )
    }

    static func normalizePort(_ port: String) -> String {
        if port.hasSuffix("/tcp") {
            return String(port.dropLast(4))
        }

        if port.contains("/") {
            return port
        }

        if !port.contains(":") {
            return "\(port):\(port)"
        }

        return port
    }
}
