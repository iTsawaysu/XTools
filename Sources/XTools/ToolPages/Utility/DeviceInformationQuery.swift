import XToolsCore
import Foundation

struct DevicePixelSize: Equatable {
    let width: Int
    let height: Int
}

enum DeviceDisplayRole: Equatable {
    case main
    case extended
    case unknown
}

enum DeviceDisplayConnection: Equatable {
    case builtIn
    case external
    case unknown
}

struct DeviceDisplaySnapshot: Equatable {
    let pixelSize: DevicePixelSize
    let role: DeviceDisplayRole
    let connection: DeviceDisplayConnection
    let rotationDegrees: Int
}

struct DeviceInformationSnapshot: Equatable {
    let operatingSystemVersion: String
    let architecture: String
    let machineModel: String?
    let cpuName: String?
    let deviceName: String?
    let hostName: String?
    let timeZoneIdentifier: String
    let processorCount: Int
    let physicalMemory: UInt64
    let systemUptime: TimeInterval
    let localNetworkAddress: DeviceNetworkAddress?
    let displays: [DeviceDisplaySnapshot]
}

struct DeviceInformationField: Equatable {
    let label: String
    let value: String
}

enum DeviceInformationProjection {
    static func fields(from snapshot: DeviceInformationSnapshot) -> [DeviceInformationField] {
        var fields = [
            DeviceInformationField(label: "平台", value: "macOS"),
            DeviceInformationField(label: "系统版本", value: snapshot.operatingSystemVersion),
            DeviceInformationField(label: "架构", value: snapshot.architecture),
            DeviceInformationField(label: "机器型号", value: snapshot.machineModel ?? "未知"),
            DeviceInformationField(label: "CPU", value: snapshot.cpuName ?? "未知"),
            DeviceInformationField(label: "设备名称", value: snapshot.deviceName ?? "未知"),
            DeviceInformationField(label: "主机名", value: snapshot.hostName ?? "未知"),
            DeviceInformationField(label: "时区", value: snapshot.timeZoneIdentifier),
            DeviceInformationField(label: "CPU 核心", value: "\(snapshot.processorCount)"),
            DeviceInformationField(label: "物理内存", value: ByteSizeFormatter.format(bytes: snapshot.physicalMemory)),
            DeviceInformationField(label: "系统运行时间", value: DeviceInfoFormatter.formatUptime(snapshot.systemUptime))
        ]

        if let address = snapshot.localNetworkAddress {
            fields.append(
                DeviceInformationField(
                    label: DeviceInfoFormatter.localNetworkAddressLabel(address),
                    value: DeviceInfoFormatter.formatLocalNetworkAddress(address)
                )
            )
        } else {
            fields.append(DeviceInformationField(label: "本机 IPv4", value: "未检测到"))
        }

        fields.append(DeviceInformationField(label: "显示器数量", value: "\(snapshot.displays.count)"))
        let primaryDisplay = snapshot.displays.first?.pixelSize ?? DevicePixelSize(width: 0, height: 0)
        fields.append(
            DeviceInformationField(
                label: "主屏幕像素",
                value: "\(primaryDisplay.width) × \(primaryDisplay.height)"
            )
        )

        fields.append(contentsOf: snapshot.displays.enumerated().map { offset, display in
            let size = "\(display.pixelSize.width) × \(display.pixelSize.height) px"
            let details = [
                size,
                roleLabel(display.role),
                connectionLabel(display.connection),
                "\(display.rotationDegrees)°"
            ]
            return DeviceInformationField(
                label: "显示器 \(offset + 1)",
                value: details.joined(separator: " · ")
            )
        })
        return fields
    }

    static func copySummary(from snapshot: DeviceInformationSnapshot) -> String {
        fields(from: snapshot)
            .map { "\($0.label): \($0.value)" }
            .joined(separator: "\n")
    }

    private static func roleLabel(_ role: DeviceDisplayRole) -> String {
        switch role {
        case .main:
            return "主屏幕"
        case .extended:
            return "扩展屏幕"
        case .unknown:
            return "显示器"
        }
    }

    private static func connectionLabel(_ connection: DeviceDisplayConnection) -> String {
        switch connection {
        case .builtIn:
            return "内建"
        case .external:
            return "外接"
        case .unknown:
            return "未知"
        }
    }
}
