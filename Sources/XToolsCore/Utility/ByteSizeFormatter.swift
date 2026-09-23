import Foundation

public enum ByteSizeFormatter {
    public static func format(bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(bytes) B"
        }

        let roundedValue = value.rounded()
        if value >= 10 || roundedValue == value {
            return "\(Int(roundedValue)) \(units[unitIndex])"
        }

        return String(format: "%.1f %@", value, units[unitIndex])
    }

    public static func format(bytes: Int) -> String {
        guard bytes >= 1024 else {
            return "\(bytes) B"
        }

        return format(bytes: UInt64(bytes))
    }

    public static func format(bytes: Int64) -> String {
        guard bytes >= 1024 else {
            return "\(bytes) B"
        }

        return format(bytes: UInt64(bytes))
    }
}
