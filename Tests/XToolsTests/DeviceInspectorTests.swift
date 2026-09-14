import Testing
@testable import XToolsCore

struct DeviceInspectorTests {
    @Test func selectsTargetInterfaceAddress() {
        let selected = DeviceInspector.selectLocalNetworkAddress(
            from: [
                Self.snapshot(name: "en1", address: "10.0.0.5"),
                Self.snapshot(address: "192.168.1.3")
            ],
            interfaceName: "en0",
            family: .ipv4
        )

        #expect(selected == DeviceNetworkAddress(interfaceName: "en0", address: "192.168.1.3", prefixLength: 24, family: .ipv4))
    }

    @Test func matchesRequestedFamily() {
        let selected = DeviceInspector.selectLocalNetworkAddress(
            from: [
                Self.snapshot(address: "192.168.1.3"),
                Self.snapshot(family: .ipv6, address: "fd00::1234", prefixLength: 64)
            ],
            interfaceName: "en0",
            family: .ipv6
        )

        #expect(selected == DeviceNetworkAddress(interfaceName: "en0", address: "fd00::1234", prefixLength: 64, family: .ipv6))
    }

    @Test func ignoresInterfacesThatAreDown() {
        let selected = DeviceInspector.selectLocalNetworkAddress(
            from: [
                Self.snapshot(address: "192.168.1.3", isUp: false)
            ],
            interfaceName: "en0",
            family: .ipv4
        )

        #expect(selected == nil)
    }

    @Test func ignoresLoopbackInterfaces() {
        let selected = DeviceInspector.selectLocalNetworkAddress(
            from: [
                Self.snapshot(address: "192.168.1.3", isLoopback: true)
            ],
            interfaceName: "en0",
            family: .ipv4
        )

        #expect(selected == nil)
    }

    @Test func ignoresUnusableIPv4Addresses() {
        let selected = DeviceInspector.selectLocalNetworkAddress(
            from: [
                Self.snapshot(address: "127.0.0.1"),
                Self.snapshot(address: "169.254.12.8")
            ],
            interfaceName: "en0",
            family: .ipv4
        )

        #expect(selected == nil)
    }

    @Test func ignoresUnusableIPv6Addresses() {
        let selected = DeviceInspector.selectLocalNetworkAddress(
            from: [
                Self.snapshot(family: .ipv6, address: "::1", prefixLength: 128),
                Self.snapshot(family: .ipv6, address: "fe80::1234", prefixLength: 64)
            ],
            interfaceName: "en0",
            family: .ipv6
        )

        #expect(selected == nil)
    }

    @Test func returnsFirstMatchingAddressInInputOrder() {
        let selected = DeviceInspector.selectLocalNetworkAddress(
            from: [
                Self.snapshot(address: "192.168.1.3"),
                Self.snapshot(address: "192.168.1.4")
            ],
            interfaceName: "en0",
            family: .ipv4
        )

        #expect(selected == DeviceNetworkAddress(interfaceName: "en0", address: "192.168.1.3", prefixLength: 24, family: .ipv4))
    }

    @Test func preferredAddressFallsBackBeyondEn0() {
        let selected = DeviceInspector.selectPreferredLocalNetworkAddress(
            from: [
                Self.snapshot(name: "en0", address: "192.168.1.3", isUp: false),
                Self.snapshot(name: "en5", address: "10.0.0.12")
            ],
            family: .ipv4
        )

        #expect(selected == DeviceNetworkAddress(interfaceName: "en5", address: "10.0.0.12", prefixLength: 24, family: .ipv4))
    }

    @Test func preferredAddressUsesInterfacePriorityBeforeInputOrder() {
        let selected = DeviceInspector.selectPreferredLocalNetworkAddress(
            from: [
                Self.snapshot(name: "utun4", address: "10.8.0.2"),
                Self.snapshot(name: "en1", address: "192.168.1.44")
            ],
            family: .ipv4
        )

        #expect(selected == DeviceNetworkAddress(interfaceName: "en1", address: "192.168.1.44", prefixLength: 24, family: .ipv4))
    }

    @Test func preferredAddressCanSelectIPv6() {
        let selected = DeviceInspector.selectPreferredLocalNetworkAddress(
            from: [
                Self.snapshot(address: "192.168.1.3"),
                Self.snapshot(name: "en1", family: .ipv6, address: "fd00::1234", prefixLength: 64)
            ],
            family: .ipv6
        )

        #expect(selected == DeviceNetworkAddress(interfaceName: "en1", address: "fd00::1234", prefixLength: 64, family: .ipv6))
    }

    @Test func returnsNilWhenNoInterfacesMatch() {
        let selected = DeviceInspector.selectLocalNetworkAddress(
            from: [
                Self.snapshot(name: "en1", address: "10.0.0.5")
            ],
            interfaceName: "en0",
            family: .ipv4
        )

        #expect(selected == nil)
    }

    private static func snapshot(
        name: String = "en0",
        family: DeviceNetworkAddress.Family = .ipv4,
        address: String,
        prefixLength: Int? = 24,
        isUp: Bool = true,
        isLoopback: Bool = false
    ) -> NetworkInterfaceSnapshot {
        NetworkInterfaceSnapshot(
            name: name,
            family: family,
            address: address,
            prefixLength: prefixLength,
            isUp: isUp,
            isLoopback: isLoopback
        )
    }
}
