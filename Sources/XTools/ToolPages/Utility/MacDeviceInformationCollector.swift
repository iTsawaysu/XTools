import AppKit
import Darwin
import XToolsCore
import Foundation

@MainActor
enum MacDeviceInformationCollector {
    static func capture() -> DeviceInformationSnapshot {
        let process = ProcessInfo.processInfo
        let host = Host.current()
        let screens = NSScreen.screens

        return DeviceInformationSnapshot(
            operatingSystemVersion: process.operatingSystemVersionString,
            architecture: architectureName,
            machineModel: sysctlString("hw.model"),
            cpuName: sysctlString("machdep.cpu.brand_string"),
            deviceName: host.localizedName,
            hostName: host.name,
            timeZoneIdentifier: TimeZone.current.identifier,
            processorCount: process.processorCount,
            physicalMemory: process.physicalMemory,
            systemUptime: process.systemUptime,
            localNetworkAddress: DeviceInspector.localNetworkAddress(family: .ipv4),
            displays: screens.map(Self.displaySnapshot)
        )
    }

    private static var architectureName: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "未知"
        #endif
    }

    private static func displaySnapshot(_ screen: NSScreen) -> DeviceDisplaySnapshot {
        let displayID = displayID(for: screen)
        let role: DeviceDisplayRole
        let connection: DeviceDisplayConnection

        if let displayID {
            role = CGDisplayIsMain(displayID) != 0 ? .main : .extended
            connection = CGDisplayIsBuiltin(displayID) != 0 ? .builtIn : .external
        } else {
            role = .unknown
            connection = .unknown
        }

        return DeviceDisplaySnapshot(
            pixelSize: pixelSize(screen),
            role: role,
            connection: connection,
            rotationDegrees: displayID.map { Int(CGDisplayRotation($0)) } ?? 0
        )
    }

    private static func pixelSize(_ screen: NSScreen) -> DevicePixelSize {
        let logicalSize = screen.frame.size
        let scale = screen.backingScaleFactor
        return DevicePixelSize(
            width: Int(logicalSize.width * scale),
            height: Int(logicalSize.height * scale)
        )
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return screenNumber.map { CGDirectDisplayID(truncating: $0) }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            return nil
        }

        let string = DeviceInspector.stringFromCStringBuffer(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }
}
