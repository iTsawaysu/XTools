import Foundation

extension DockerRunToDockerComposeService {
    static func appendRuntimeSections(for service: ComposeService, to lines: inout [String]) {
        if let shmSize = service.shmSize {
            lines.append("    shm_size: \(yamlScalar(shmSize))")
        }

        // Sysctls & Ulimits
        if !service.sysctls.isEmpty {
            lines.append("    sysctls:")
            for sysctl in service.sysctls {
                let parts = sysctl.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    lines.append("      \(parts[0]): \(yamlScalar(String(parts[1])))")
                }
            }
        }

        if !service.ulimits.isEmpty {
            lines.append("    ulimits:")
            for ulimit in service.ulimits {
                let parts = ulimit.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let name = String(parts[0])
                    let limits = String(parts[1])
                    if limits.contains(":") {
                        let softHard = limits.split(separator: ":")
                        if softHard.count == 2 {
                            lines.append("      \(name):")
                            lines.append("        soft: \(softHard[0])")
                            lines.append("        hard: \(softHard[1])")
                        }
                    } else {
                        lines.append("      \(name): \(limits)")
                    }
                }
            }
        }

        // Namespace sharing
        if let pid = service.pid {
            lines.append("    pid: \(yamlScalar(pid))")
        }
        if let uts = service.uts {
            lines.append("    uts: \(yamlScalar(uts))")
        }
        if let ipc = service.ipc {
            lines.append("    ipc: \(yamlScalar(ipc))")
        }

        let hasCustomHealthcheck =
            service.healthCmd != nil
            || service.healthInterval != nil
            || service.healthTimeout != nil
            || service.healthRetries != nil
            || service.healthStartPeriod != nil
            || service.healthStartInterval != nil

        // Healthcheck
        if service.healthcheckDisabled == true {
            lines.append("    healthcheck:")
            lines.append("      disable: true")
        } else if hasCustomHealthcheck {
            lines.append("    healthcheck:")
            if let cmd = service.healthCmd {
                // Use recommended CMD-SHELL format for healthcheck test
                lines.append("      test: [\"CMD-SHELL\", \(yamlScalar(cmd))]")
            }
            if let interval = service.healthInterval {
                lines.append("      interval: \(yamlScalar(interval))")
            }
            if let timeout = service.healthTimeout {
                lines.append("      timeout: \(yamlScalar(timeout))")
            }
            if let retries = service.healthRetries {
                lines.append("      retries: \(retries)")
            }
            if let startPeriod = service.healthStartPeriod {
                lines.append("      start_period: \(yamlScalar(startPeriod))")
            }
            if let startInterval = service.healthStartInterval {
                lines.append("      start_interval: \(yamlScalar(startInterval))")
            }
        }

        // Logging
        if service.logDriver != nil || !service.logOptions.isEmpty {
            lines.append("    logging:")
            if let driver = service.logDriver {
                lines.append("      driver: \(yamlScalar(driver))")
            }
            if !service.logOptions.isEmpty {
                lines.append("      options:")
                for logOpt in service.logOptions {
                    let parts = logOpt.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        lines.append("        \(parts[0]): \(yamlScalar(String(parts[1])))")
                    }
                }
            }
        }

        // Misc
        if let restart = service.restart {
            lines.append("    restart: \(yamlScalar(restart))")

            // If max_attempts is specified, add deploy.restart_policy
            if let maxAttempts = service.restartMaxAttempts {
                appendDeployRestartPolicy(
                    condition: restart,
                    maxAttempts: maxAttempts,
                    to: &lines
                )
            }
        }

        if let stopSignal = service.stopSignal {
            lines.append("    stop_signal: \(yamlScalar(stopSignal))")
        }

        if let stopGrace = service.stopGracePeriod {
            // stopGracePeriod is already a number (e.g., "30"), we need to append "s"
            // but avoid double-quoting like "30"s which is invalid
            if stopGrace.hasSuffix("s") || stopGrace.hasSuffix("m") || stopGrace.hasSuffix("h") {
                lines.append("    stop_grace_period: \(yamlScalar(stopGrace))")
            } else {
                lines.append("    stop_grace_period: \(stopGrace)s")
            }
        }

        if let workingDir = service.workingDir {
            lines.append("    working_dir: \(yamlScalar(workingDir))")
        }

        if let user = service.user {
            lines.append("    user: \(yamlScalar(user))")
        }

        if let readOnly = service.readOnly, readOnly {
            lines.append("    read_only: true")
        }

        // Interactive flags
        if let stdinOpen = service.stdinOpen, stdinOpen {
            lines.append("    stdin_open: true")
        }

        if let tty = service.tty, tty {
            lines.append("    tty: true")
        }

        // OOM kill disable
        if let oomKillDisable = service.oomKillDisable, oomKillDisable {
            lines.append("    oom_kill_disable: true")
        }

        // GPU support - must be in deploy.resources.reservations
        if let gpus = service.gpus {
            appendGPUReservation(count: gpus, to: &lines)
        }
    }

    private static func appendDeployRestartPolicy(
        condition: String,
        maxAttempts: Int,
        to lines: inout [String]
    ) {
        let policyLines = [
            "      restart_policy:",
            "        condition: \(yamlScalar(condition))",
            "        max_attempts: \(maxAttempts)"
        ]

        insertIntoDeploy(policyLines, to: &lines)
    }

    private static func appendGPUReservation(count: String, to lines: inout [String]) {
        let deployIndex = ensureDeploySection(in: &lines)
        let resourcesIndex = ensureChildSection(
            "      resources:",
            parentIndex: deployIndex,
            childIndent: 6,
            to: &lines
        )
        let reservationsIndex = ensureChildSection(
            "        reservations:",
            parentIndex: resourcesIndex,
            childIndent: 8,
            to: &lines
        )

        let insertIndex = sectionEnd(after: reservationsIndex, childIndent: 10, in: lines)
        let gpuLines = [
            "          devices:",
            "            - driver: nvidia",
            "              count: \(count == "all" ? "all" : yamlScalar(count))",
            "              capabilities: [gpu]"
        ]

        lines.insert(contentsOf: gpuLines, at: insertIndex)
    }

    private static func insertIntoDeploy(_ newLines: [String], to lines: inout [String]) {
        let deployIndex = ensureDeploySection(in: &lines)
        let insertIndex = deploySectionEnd(startingAt: deployIndex, in: lines)
        lines.insert(contentsOf: newLines, at: insertIndex)
    }

    @discardableResult
    private static func ensureDeploySection(in lines: inout [String]) -> Int {
        if let deployIndex = lines.lastIndex(where: { $0 == "    deploy:" }) {
            return deployIndex
        }

        lines.append("    deploy:")
        return lines.count - 1
    }

    @discardableResult
    private static func ensureChildSection(
        _ sectionLine: String,
        parentIndex: Int,
        childIndent: Int,
        to lines: inout [String]
    ) -> Int {
        let parentEnd = sectionEnd(after: parentIndex, childIndent: childIndent, in: lines)
        if parentIndex + 1 < parentEnd,
           let existingIndex = (parentIndex + 1..<parentEnd).first(where: { lines[$0] == sectionLine }) {
            return existingIndex
        }

        lines.insert(sectionLine, at: parentEnd)
        return parentEnd
    }

    private static func deploySectionEnd(startingAt deployIndex: Int, in lines: [String]) -> Int {
        sectionEnd(after: deployIndex, childIndent: 6, in: lines)
    }

    private static func sectionEnd(after sectionIndex: Int, childIndent: Int, in lines: [String]) -> Int {
        var index = sectionIndex + 1

        while index < lines.count {
            let line = lines[index]
            if line.isEmpty {
                break
            }
            if leadingSpaceCount(line) < childIndent {
                break
            }
            index += 1
        }

        return index
    }

    private static func leadingSpaceCount(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }
}
