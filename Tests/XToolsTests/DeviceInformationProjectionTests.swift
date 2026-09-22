import XToolsCore
@testable import XTools
import Testing

struct DeviceInformationProjectionTests {
    @Test func projectsCompleteSnapshotInStableUserVisibleOrder() {
        let fields = DeviceInformationProjection.fields(from: Self.completeSnapshot)

        #expect(fields == [
            DeviceInformationField(label: "平台", value: "macOS"),
            DeviceInformationField(label: "系统版本", value: "macOS 15.0"),
            DeviceInformationField(label: "架构", value: "arm64"),
            DeviceInformationField(label: "机器型号", value: "Mac15,7"),
            DeviceInformationField(label: "CPU", value: "Apple M3"),
            DeviceInformationField(label: "设备名称", value: "Rena’s Mac"),
            DeviceInformationField(label: "主机名", value: "mac.local"),
            DeviceInformationField(label: "时区", value: "Asia/Shanghai"),
            DeviceInformationField(label: "CPU 核心", value: "10"),
            DeviceInformationField(label: "物理内存", value: "16 GB"),
            DeviceInformationField(label: "系统运行时间", value: "2 小时 3 分钟"),
            DeviceInformationField(label: "本机 IPv4 (en1)", value: "192.168.1.44/24"),
            DeviceInformationField(label: "显示器数量", value: "2"),
            DeviceInformationField(label: "主屏幕像素", value: "3024 × 1964"),
            DeviceInformationField(label: "显示器 1", value: "3024 × 1964 px · 主屏幕 · 内建 · 0°"),
            DeviceInformationField(label: "显示器 2", value: "2560 × 1440 px · 扩展屏幕 · 外接 · 90°")
        ])
    }

    @Test func copySummaryUsesTheVisibleFieldOrderAndStableLineFormat() {
        let summary = DeviceInformationProjection.copySummary(from: Self.completeSnapshot)

        #expect(summary == """
        平台: macOS
        系统版本: macOS 15.0
        架构: arm64
        机器型号: Mac15,7
        CPU: Apple M3
        设备名称: Rena’s Mac
        主机名: mac.local
        时区: Asia/Shanghai
        CPU 核心: 10
        物理内存: 16 GB
        系统运行时间: 2 小时 3 分钟
        本机 IPv4 (en1): 192.168.1.44/24
        显示器数量: 2
        主屏幕像素: 3024 × 1964
        显示器 1: 3024 × 1964 px · 主屏幕 · 内建 · 0°
        显示器 2: 2560 × 1440 px · 扩展屏幕 · 外接 · 90°
        """)
    }

    @Test func projectsStableFallbacksWithoutInventingPlatformFacts() {
        let snapshot = DeviceInformationSnapshot(
            operatingSystemVersion: "macOS",
            architecture: "未知",
            machineModel: nil,
            cpuName: nil,
            deviceName: nil,
            hostName: nil,
            timeZoneIdentifier: "UTC",
            processorCount: 0,
            physicalMemory: 0,
            systemUptime: 0,
            localNetworkAddress: nil,
            displays: []
        )

        let fields = DeviceInformationProjection.fields(from: snapshot)

        #expect(fields.map(\.label) == [
            "平台", "系统版本", "架构", "机器型号", "CPU", "设备名称", "主机名", "时区",
            "CPU 核心", "物理内存", "系统运行时间", "本机 IPv4", "显示器数量", "主屏幕像素"
        ])
        #expect(fields.first(where: { $0.label == "机器型号" })?.value == "未知")
        #expect(fields.first(where: { $0.label == "CPU" })?.value == "未知")
        #expect(fields.first(where: { $0.label == "设备名称" })?.value == "未知")
        #expect(fields.first(where: { $0.label == "主机名" })?.value == "未知")
        #expect(fields.first(where: { $0.label == "本机 IPv4" })?.value == "未检测到")
        #expect(fields.first(where: { $0.label == "显示器数量" })?.value == "0")
        #expect(fields.first(where: { $0.label == "主屏幕像素" })?.value == "0 × 0")
    }

    @Test func displayProjectionPreservesUnknownPlatformClassification() {
        let snapshot = DeviceInformationSnapshot(
            operatingSystemVersion: "macOS",
            architecture: "arm64",
            machineModel: nil,
            cpuName: nil,
            deviceName: nil,
            hostName: nil,
            timeZoneIdentifier: "UTC",
            processorCount: 1,
            physicalMemory: 1,
            systemUptime: 1,
            localNetworkAddress: nil,
            displays: [
                DeviceDisplaySnapshot(
                    pixelSize: DevicePixelSize(width: 1920, height: 1080),
                    role: .unknown,
                    connection: .unknown,
                    rotationDegrees: 0
                )
            ]
        )

        let fields = DeviceInformationProjection.fields(from: snapshot)

        #expect(fields.last == DeviceInformationField(
            label: "显示器 1",
            value: "1920 × 1080 px · 显示器 · 未知 · 0°"
        ))
    }


    @Test func primaryDisplaySummaryUsesFirstCapturedDisplay() {
        let snapshot = DeviceInformationSnapshot(
            operatingSystemVersion: "macOS",
            architecture: "arm64",
            machineModel: nil,
            cpuName: nil,
            deviceName: nil,
            hostName: nil,
            timeZoneIdentifier: "UTC",
            processorCount: 1,
            physicalMemory: 1,
            systemUptime: 1,
            localNetworkAddress: nil,
            displays: [
                DeviceDisplaySnapshot(
                    pixelSize: DevicePixelSize(width: 333, height: 444),
                    role: .extended,
                    connection: .external,
                    rotationDegrees: 0
                )
            ]
        )

        let fields = DeviceInformationProjection.fields(from: snapshot)

        #expect(fields.first(where: { $0.label == "主屏幕像素" })?.value == "333 × 444")
    }

    @Test @MainActor func sessionRefreshesFromInjectedCapture() {
        let first = Self.completeSnapshot
        let second = Self.snapshot(timeZoneIdentifier: "America/Los_Angeles")
        var snapshots = [first, second]
        let session = DeviceInformationSession {
            snapshots.removeFirst()
        }

        #expect(session.snapshot == first)
        session.refresh()
        #expect(session.snapshot == second)
        #expect(snapshots.isEmpty)
    }

    @Test @MainActor func collectorDecoderStopsAtFirstNullByte() {
        let buffer: [CChar] = [77, 97, 99, 0, 88]
        #expect(DeviceInspector.stringFromCStringBuffer(buffer) == "Mac")
    }

    private static var completeSnapshot: DeviceInformationSnapshot { snapshot() }

    private static func snapshot(timeZoneIdentifier: String = "Asia/Shanghai") -> DeviceInformationSnapshot {
        DeviceInformationSnapshot(
            operatingSystemVersion: "macOS 15.0",
            architecture: "arm64",
            machineModel: "Mac15,7",
            cpuName: "Apple M3",
            deviceName: "Rena’s Mac",
            hostName: "mac.local",
            timeZoneIdentifier: timeZoneIdentifier,
            processorCount: 10,
            physicalMemory: 17_179_869_184,
            systemUptime: 7_380,
            localNetworkAddress: DeviceNetworkAddress(
                interfaceName: "en1",
                address: "192.168.1.44",
                prefixLength: 24,
                family: .ipv4
            ),
            displays: [
                DeviceDisplaySnapshot(
                    pixelSize: DevicePixelSize(width: 3024, height: 1964),
                    role: .main,
                    connection: .builtIn,
                    rotationDegrees: 0
                ),
                DeviceDisplaySnapshot(
                    pixelSize: DevicePixelSize(width: 2560, height: 1440),
                    role: .extended,
                    connection: .external,
                    rotationDegrees: 90
                )
            ]
        )
    }
}
