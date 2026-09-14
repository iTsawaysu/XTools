import Foundation

public struct DeviceNetworkAddress: Equatable {
    public enum Family: Equatable {
        case ipv4
        case ipv6
    }

    public let interfaceName: String
    public let address: String
    public let prefixLength: Int?
    public let family: Family

    public init(interfaceName: String, address: String, prefixLength: Int?, family: Family) {
        self.interfaceName = interfaceName
        self.address = address
        self.prefixLength = prefixLength
        self.family = family
    }
}

public enum DeviceInfoFormatter {
    public static func formatUptime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let units = [
            ("天", totalSeconds / 86_400),
            ("小时", (totalSeconds % 86_400) / 3_600),
            ("分钟", (totalSeconds % 3_600) / 60),
            ("秒", totalSeconds % 60)
        ].filter { $0.1 > 0 }

        guard !units.isEmpty else {
            return "0 秒"
        }

        return units.prefix(2).map { "\($0.1) \($0.0)" }.joined(separator: " ")
    }

    public static func localNetworkAddressLabel(_ address: DeviceNetworkAddress) -> String {
        let family = address.family == .ipv4 ? "IPv4" : "IPv6"
        return "本机 \(family) (\(address.interfaceName))"
    }

    public static func formatLocalNetworkAddress(_ address: DeviceNetworkAddress) -> String {
        guard let prefixLength = address.prefixLength else {
            return address.address
        }

        return "\(address.address)/\(prefixLength)"
    }
}
