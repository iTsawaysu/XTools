import Foundation

extension DockerRunToDockerComposeService {
    struct ComposeService {
        var name: String = "app"
        var image = ""
        var platform: String?
        var containerName: String?
        var command: [String] = []
        var entrypoint: [String] = []
        var environment: [String] = []
        var ports: [String] = []
        var volumes: [String] = []
        var networks: [String] = []
        var restart: String?
        var workingDir: String?
        var user: String?
        var hostname: String?
        var dns: [String] = []
        var envFiles: [String] = []
        var extraHosts: [String] = []
        var labels: [String] = []
        var expose: [String] = []
        var tmpfs: [String] = []

        // Security & Capabilities
        var capAdd: [String] = []
        var capDrop: [String] = []
        var securityOpt: [String] = []
        var privileged: Bool?
        var userns: String?
        var groupAdd: [String] = []

        // Resource limits
        var cpus: String?
        var cpuShares: String?
        var cpuPeriod: String?
        var cpuQuota: String?
        var cpusetCpus: String?
        var memory: String?
        var memoryReservation: String?
        var memorySwap: String?
        var memorySwappiness: String?
        var pidsLimit: String?
        var blkioWeight: String?
        var shmSize: String?
        var oomScoreAdj: String?

        // Device I/O limits
        var deviceReadBps: [String] = []
        var deviceWriteBps: [String] = []
        var deviceReadIops: [String] = []
        var deviceWriteIops: [String] = []

        // Sysctls & Ulimits
        var sysctls: [String] = []
        var ulimits: [String] = []

        // Network config
        var networkMode: String?
        var ipv4Address: String?
        var ipv6Address: String?
        var macAddress: String?
        var networkAliases: [String] = []
        var dnsOpt: [String] = []
        var dnsSearch: [String] = []
        var links: [String] = []

        // Namespace sharing
        var pid: String?
        var uts: String?
        var ipc: String?

        // Healthcheck
        var healthCmd: String?
        var healthInterval: String?
        var healthTimeout: String?
        var healthRetries: String?
        var healthStartPeriod: String?
        var healthcheckDisabled: Bool?

        // Logging
        var logDriver: String?
        var logOptions: [String] = []

        // Devices
        var devices: [String] = []

        // GPU support
        var gpus: String?

        // Misc
        var stopSignal: String?
        var stopGracePeriod: String?
        var `init`: Bool?
        var readOnly: Bool?
        var stdinOpen: Bool?
        var tty: Bool?
        var oomKillDisable: Bool?
        var restartMaxAttempts: Int?
    }
}
