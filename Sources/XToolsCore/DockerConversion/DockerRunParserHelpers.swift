import Foundation

enum DockerMountFields {
    // Docker parses the argument as a single CSV record before reading key=value.
    static func encode(_ fields: [String]) -> String {
        fields.map { field in
            guard field.unicodeScalars.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
            else { return field }
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }.joined(separator: ",")
    }

    static func decode(_ argument: String) -> [String]? {
        enum State { case unquoted, quoted, afterQuote }
        var state = State.unquoted
        var fields: [String] = []
        var field = ""
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.replacingOccurrences(of: "\r\n", with: "\n")
        for scalar in normalized.unicodeScalars {
            switch scalar {
            case "\"":
                switch state {
                case .unquoted:
                    guard field.isEmpty else { return nil }
                    state = .quoted
                case .quoted:
                    state = .afterQuote
                case .afterQuote:
                    field.append("\"")
                    state = .quoted
                }
            case "," where state != .quoted:
                fields.append(field)
                field = ""
                state = .unquoted
            default:
                guard state != .afterQuote, state == .quoted || scalar != "\n" else { return nil }
                field.unicodeScalars.append(scalar)
            }
        }
        guard state != .quoted else { return nil }
        fields.append(field)
        return fields
    }

    static func modeBits(octal: String) -> UInt32? {
        guard octal.utf8.allSatisfy({ (48...55).contains($0) }) else { return nil }
        return UInt32(octal, radix: 8)
    }

    static func preservesPath(_ path: String) -> Bool {
        // The CLI rejects edge whitespace and its CSV reader converts CRLF to LF.
        path.unicodeScalars.first?.properties.isWhitespace == false &&
            path.unicodeScalars.last?.properties.isWhitespace == false &&
            !path.contains("\r\n") && !path.utf8.contains(0)
    }
}

extension DockerRunToDockerComposeService {
    /// 仅识别相邻、未引用的完整 docker/run 词元；不猜测普通参数中的子串。
    /// 扫描保留 tokenizer 的引号/反斜杠规则，续行不形成词元边界。
    static func dockerRunOccurrences(in command: String) -> Int {
        let chars = Array(command.unicodeScalars)
        var count = 0
        var quote: Unicode.Scalar?
        var index = 0
        var word = ""
        var isPlain = true
        var previousDocker = false

        func finishWord() {
            if previousDocker && isPlain && word == "run" { count += 1 }
            previousDocker = isPlain && word == "docker"
            word = ""
            isPlain = true
        }

        while index < chars.count {
            let character = chars[index]
            if let activeQuote = quote {
                if activeQuote == "\"", character == "\\", index + 1 < chars.count {
                    let next = chars[index + 1]
                    if next == "$" || next == "`" || next == "\"" || next == "\\" || next == "\n" {
                        index += 2
                        continue
                    }
                }
                if character == activeQuote { quote = nil }
                index += 1
                continue
            }

            if character == "\\", index + 1 < chars.count {
                let next = chars[index + 1]
                if next == "\n" {
                    index += 2
                    continue
                }
                // 与粘贴输入 tokenizer 相同：普通 Windows 路径保留反斜杠。
                if next == "\"" || next == "'" || next == "\\" || next == "$" || next == "`" || Character(next).isWhitespace {
                    isPlain = false
                    index += 2
                    continue
                }
            }
            if character == "\"" || character == "'" {
                isPlain = false
                quote = character
            } else if Character(character).isWhitespace {
                if !word.isEmpty || !isPlain { finishWord() }
            } else if character == ";" || character == "|" || character == "&" {
                // 保留无空格 shell 连接符后的第二条命令拒绝，不把两边合成参数。
                if !word.isEmpty || !isPlain { finishWord() }
                previousDocker = false
            } else {
                word.unicodeScalars.append(character)
            }
            index += 1
        }
        if !word.isEmpty || !isPlain { finishWord() }
        return count
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

    /// parseMount 第一步收集到的原始字段（尚未做必填/组合校验）。
    private struct MountOptions {
        var type: ComposeMount.Kind?
        var source: String?
        var target: String?
        var tmpfsSize: String?
        var tmpfsMode: UInt32?
        var isReadonly = false
        var unsupported: [String] = []
    }

    static func parseMount(_ mountString: String) -> (mount: ComposeMount?, unsupported: [String]) {
        var options = collectMountOptions(mountString)

        guard let mountType = options.type else {
            if !options.unsupported.contains("type") { options.unsupported.append("type") }
            return (nil, options.unsupported)
        }
        guard let target = options.target, !target.isEmpty else {
            options.unsupported.append("target")
            return (nil, options.unsupported)
        }
        // Anonymous volumes have no source; bind mounts still require one.
        // An explicitly empty source is not the omitted-source form.
        if (mountType == .bind && options.source?.isEmpty != false) ||
            (mountType == .volume && options.source?.isEmpty == true) {
            options.unsupported.append("source")
        }
        if mountType != .tmpfs, options.tmpfsSize != nil || options.tmpfsMode != nil {
            options.unsupported.append("tmpfs")
        }
        if mountType == .tmpfs, options.source != nil {
            options.unsupported.append("source")
        }
        guard options.unsupported.isEmpty else { return (nil, options.unsupported) }
        return (
            ComposeMount(
                kind: mountType,
                source: options.source,
                target: target,
                readOnly: options.isReadonly,
                size: options.tmpfsSize,
                mode: options.tmpfsMode
            ),
            []
        )
    }

    /// 识别 `--mount` 的 CSV 字段，将未识别的键记入 unsupported。
    private static func collectMountOptions(_ mountString: String) -> MountOptions {
        var options = MountOptions()
        guard let parts = DockerMountFields.decode(mountString) else {
            options.unsupported.append("option")
            return options
        }
        for part in parts {
            let keyValue = part.unicodeScalars.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = (keyValue.first.map { String($0) } ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            if key == "readonly" || key == "ro" {
                switch keyValue.count == 2 ? String(keyValue[1]) : "true" {
                case "1", "t", "T", "true", "TRUE", "True": options.isReadonly = true
                case "0", "f", "F", "false", "FALSE", "False": options.isReadonly = false
                default: options.unsupported.append(key)
                }
                continue
            }
            guard keyValue.count == 2, !key.isEmpty, !keyValue[1].isEmpty else {
                options.unsupported.append("option")
                continue
            }

            let rawValue = String(keyValue[1])
            let value = rawValue.trimmingCharacters(in: .whitespaces)

            switch key {
            case "type":
                options.type = ComposeMount.Kind(rawValue: value)
                if options.type == nil {
                    options.unsupported.append("type")
                }
            case "source", "src":
                if DockerMountFields.preservesPath(rawValue) {
                    options.source = rawValue
                } else {
                    options.unsupported.append("source")
                }
            case "target", "dst", "destination":
                if DockerMountFields.preservesPath(rawValue) {
                    options.target = rawValue
                } else {
                    options.unsupported.append("target")
                }
            case "tmpfs-size":
                options.tmpfsSize = value
            case "tmpfs-mode":
                if let mode = DockerMountFields.modeBits(octal: value) {
                    options.tmpfsMode = mode
                } else {
                    options.unsupported.append(key)
                }
            default:
                options.unsupported.append(key)
            }
        }
        return options
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

        return port
    }
}
