import Darwin
import Foundation

struct NetworkInterfaceSnapshot: Equatable {
    let name: String
    let family: DeviceNetworkAddress.Family
    let address: String
    let prefixLength: Int?
    let isUp: Bool
    let isLoopback: Bool
}

public enum DeviceInspector {
    public static func localNetworkAddress(
        interfaceName: String? = nil,
        family: DeviceNetworkAddress.Family = .ipv4
    ) -> DeviceNetworkAddress? {
        let interfaces = networkInterfaceSnapshots()
        guard let interfaceName else {
            return selectPreferredLocalNetworkAddress(from: interfaces, family: family)
        }

        return selectLocalNetworkAddress(
            from: interfaces,
            interfaceName: interfaceName,
            family: family
        )
    }

    static func selectPreferredLocalNetworkAddress(
        from interfaces: [NetworkInterfaceSnapshot],
        family targetFamily: DeviceNetworkAddress.Family
    ) -> DeviceNetworkAddress? {
        interfaces
            .enumerated()
            .compactMap { offset, interface -> (DeviceNetworkAddress, Int, Int)? in
                guard interface.family == targetFamily,
                      interface.isUp,
                      !interface.isLoopback,
                      isUsefulLocalAddress(interface.address, family: interface.family) else {
                    return nil
                }

                return (
                    DeviceNetworkAddress(
                        interfaceName: interface.name,
                        address: interface.address,
                        prefixLength: interface.prefixLength,
                        family: interface.family
                    ),
                    interfacePriority(interface.name),
                    offset
                )
            }
            .min { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 < rhs.1
                }
                return lhs.2 < rhs.2
            }?
            .0
    }

    static func selectLocalNetworkAddress(
        from interfaces: [NetworkInterfaceSnapshot],
        interfaceName targetInterfaceName: String,
        family targetFamily: DeviceNetworkAddress.Family
    ) -> DeviceNetworkAddress? {
        for interface in interfaces {
            guard interface.name == targetInterfaceName,
                  interface.family == targetFamily,
                  interface.isUp,
                  !interface.isLoopback,
                  isUsefulLocalAddress(interface.address, family: interface.family) else {
                continue
            }

            return DeviceNetworkAddress(
                interfaceName: interface.name,
                address: interface.address,
                prefixLength: interface.prefixLength,
                family: interface.family
            )
        }

        return nil
    }

    private static func networkInterfaceSnapshots() -> [NetworkInterfaceSnapshot] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return []
        }
        defer { freeifaddrs(interfaces) }

        var snapshots: [NetworkInterfaceSnapshot] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstInterface

        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            guard let socketAddress = current.pointee.ifa_addr,
                  let family = DeviceNetworkAddress.Family(socketFamily: socketAddress.pointee.sa_family) else {
                continue
            }

            let length = socketLength(for: socketAddress.pointee.sa_family)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(socketAddress, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard status == 0 else {
                continue
            }

            let flags = Int32(current.pointee.ifa_flags)
            snapshots.append(
                NetworkInterfaceSnapshot(
                    name: String(cString: current.pointee.ifa_name),
                    family: family,
                    address: stringFromCStringBuffer(host),
                    prefixLength: prefixLength(from: current.pointee.ifa_netmask, family: socketAddress.pointee.sa_family),
                    isUp: flags & IFF_UP != 0,
                    isLoopback: flags & IFF_LOOPBACK != 0
                )
            )
        }

        return snapshots
    }

    private static func socketLength(for family: sa_family_t) -> socklen_t {
        Int32(family) == AF_INET
            ? socklen_t(MemoryLayout<sockaddr_in>.size)
            : socklen_t(MemoryLayout<sockaddr_in6>.size)
    }

    private static func isUsefulLocalAddress(_ address: String, family: DeviceNetworkAddress.Family) -> Bool {
        switch family {
        case .ipv4:
            return address != "0.0.0.0"
                && address != "255.255.255.255"
                && !address.hasPrefix("127.")
                && !address.hasPrefix("169.254.")
        case .ipv6:
            let lowercased = address.lowercased()
            return lowercased != "::"
                && lowercased != "::1"
                && !lowercased.hasPrefix("fe80:")
        }
    }

    private static func interfacePriority(_ name: String) -> Int {
        if name == "en0" { return 0 }
        if name.hasPrefix("en") { return 1 }
        if name.hasPrefix("bridge") { return 2 }
        if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp") { return 3 }
        if name.hasPrefix("awdl") || name.hasPrefix("llw") { return 4 }
        return 5
    }

    private static func prefixLength(from netmask: UnsafeMutablePointer<sockaddr>?, family: sa_family_t) -> Int? {
        guard let netmask else {
            return nil
        }

        if Int32(family) == AF_INET {
            let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                UInt32(bigEndian: pointer.pointee.sin_addr.s_addr)
            }
            return mask.nonzeroBitCount
        }

        if Int32(family) == AF_INET6 {
            return netmask.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                withUnsafeBytes(of: pointer.pointee.sin6_addr) { bytes in
                    bytes.reduce(0) { count, byte in count + byte.nonzeroBitCount }
                }
            }
        }

        return nil
    }

    public static func stringFromCStringBuffer(_ buffer: [CChar]) -> String {
        let endIndex = buffer.firstIndex(of: 0) ?? buffer.endIndex
        let bytes = buffer[..<endIndex].map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

private extension DeviceNetworkAddress.Family {
    init?(socketFamily: sa_family_t) {
        switch Int32(socketFamily) {
        case AF_INET:
            self = .ipv4
        case AF_INET6:
            self = .ipv6
        default:
            return nil
        }
    }
}
