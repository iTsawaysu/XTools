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

    static let shortFlagAliases: [String: String] = [
        "-p": "--publish",
        "-v": "--volume",
        "-e": "--env",
        "-l": "--label",
        "-w": "--workdir",
        "-u": "--user"
    ]

    static let unsupportedValueFlags: Set<String> = [
        "--cidfile",
        "--cgroupns"
    ]

    static let unsupportedBooleanFlags: Set<String> = [
        "--publish-all"
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
        let booleanFlags: Set<String> = [
            "-d", "--detach", "-i", "--interactive", "-t", "--tty", "--rm",
            "--privileged", "--read-only", "--sig-proxy", "--publish-all",
            "--oom-kill-disable", "--init"
        ]

        if booleanFlags.contains(flag) {
            return false
        }

        return true
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

    static func parseMountToVolume(_ mountString: String) -> (volume: String?, tmpfs: String?) {
        var mountType = ""
        var source = ""
        var target = ""
        var tmpfsSize = ""
        var isReadonly = false

        let parts = mountString.split(separator: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)

            if trimmed == "readonly" || trimmed == "ro" {
                isReadonly = true
                continue
            }
            if trimmed.hasPrefix("readonly=") {
                isReadonly = !trimmed.hasSuffix("false")
                continue
            }

            let keyValue = trimmed.split(separator: "=", maxSplits: 1)
            guard keyValue.count == 2 else { continue }

            let key = String(keyValue[0]).trimmingCharacters(in: .whitespaces)
            let value = String(keyValue[1]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "type":
                mountType = value
            case "source", "src":
                source = value
            case "target", "dst", "destination":
                target = value
            case "tmpfs-size":
                tmpfsSize = value
            default:
                break
            }
        }

        if mountType == "tmpfs" {
            if !tmpfsSize.isEmpty {
                return (nil, "\(target):size=\(tmpfsSize)")
            }
            return (nil, target)
        }

        if !source.isEmpty && !target.isEmpty {
            let volumeString = isReadonly ? "\(source):\(target):ro" : "\(source):\(target)"
            return (volumeString, nil)
        } else if !target.isEmpty {
            return (target, nil)
        }

        return (mountString, nil)
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
