import XToolsCore
import Foundation
import Testing

struct DeviceInfoFormatterTests {
    @Test func formatsUptimeSeconds() {
        let formatted = DeviceInfoFormatter.formatUptime(45)
        #expect(formatted == "45 秒")
    }

    @Test func formatsUptimeMinutes() {
        let formatted = DeviceInfoFormatter.formatUptime(150)
        #expect(formatted == "2 分钟 30 秒")
    }

    @Test func formatsUptimeHours() {
        let formatted = DeviceInfoFormatter.formatUptime(7380)
        #expect(formatted == "2 小时 3 分钟") // drops seconds
    }

    @Test func formatsUptimeDays() {
        let formatted = DeviceInfoFormatter.formatUptime(90061)
        #expect(formatted == "1 天 1 小时") // drops minutes
    }

    @Test func formatsZeroUptime() {
        let formatted = DeviceInfoFormatter.formatUptime(0)
        #expect(formatted == "0 秒")
    }

    @Test func formatsLocalNetworkAddressWithPrefix() {
        let address = DeviceNetworkAddress(interfaceName: "en0", address: "192.168.1.3", prefixLength: 24, family: .ipv4)

        #expect(DeviceInfoFormatter.formatLocalNetworkAddress(address) == "192.168.1.3/24")
        #expect(DeviceInfoFormatter.localNetworkAddressLabel(address) == "本机 IPv4 (en0)")
    }

    @Test func formatsLocalNetworkAddressWithoutPrefix() {
        let address = DeviceNetworkAddress(interfaceName: "utun4", address: "fd00::1234", prefixLength: nil, family: .ipv6)

        #expect(DeviceInfoFormatter.formatLocalNetworkAddress(address) == "fd00::1234")
        #expect(DeviceInfoFormatter.localNetworkAddressLabel(address) == "本机 IPv6 (utun4)")
    }
}
