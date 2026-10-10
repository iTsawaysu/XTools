import XToolsCore
import Foundation

enum ToolPreferenceOutOfRangePolicy {
    case clamp
    case useDefault
}

@MainActor
struct ToolPreferenceKey<Value> {
    let rawKey: String
    let defaultValue: Value

    /// Internal (was fileprivate before the F5 key split) so the per-domain
    /// key files under Shared/Preferences/ can spell custom read/write/normalize
    /// closures via the memberwise initializer.
    let read: (UserDefaults, String) -> Value?
    let write: (UserDefaults, String, Value) -> Void
    let normalize: (Value) -> Value
}

extension ToolPreferenceKey where Value == Bool {
    static func bool(_ rawKey: String, default defaultValue: Bool) -> Self {
        Self(
            rawKey: rawKey,
            defaultValue: defaultValue,
            read: { defaults, key in
                defaults.object(forKey: key) as? Bool
            },
            write: { defaults, key, value in
                defaults.set(value, forKey: key)
            },
            normalize: { $0 }
        )
    }
}

extension ToolPreferenceKey where Value == Int {
    static func integer(
        _ rawKey: String,
        default defaultValue: Int,
        range: ClosedRange<Int>? = nil,
        outOfRangePolicy: ToolPreferenceOutOfRangePolicy = .clamp
    ) -> Self {
        if let range {
            precondition(range.contains(defaultValue))
        }

        return Self(
            rawKey: rawKey,
            defaultValue: defaultValue,
            read: { defaults, key in
                defaults.object(forKey: key) as? Int
            },
            write: { defaults, key, value in
                defaults.set(value, forKey: key)
            },
            normalize: { value in
                guard let range else { return value }
                guard !range.contains(value) else { return value }
                switch outOfRangePolicy {
                case .clamp:
                    return min(max(value, range.lowerBound), range.upperBound)
                case .useDefault:
                    return defaultValue
                }
            }
        )
    }
}

extension ToolPreferenceKey where Value == Double {
    static func double(
        _ rawKey: String,
        default defaultValue: Double,
        range: ClosedRange<Double>? = nil
    ) -> Self {
        if let range {
            precondition(range.contains(defaultValue))
        }

        return Self(
            rawKey: rawKey,
            defaultValue: defaultValue,
            read: { defaults, key in
                defaults.object(forKey: key) as? Double
            },
            write: { defaults, key, value in
                defaults.set(value, forKey: key)
            },
            normalize: { value in
                guard let range else { return value }
                return min(max(value, range.lowerBound), range.upperBound)
            }
        )
    }
}

extension ToolPreferenceKey where Value == String {
    static func string(
        _ rawKey: String,
        default defaultValue: String,
        allowedValues: Set<String>? = nil
    ) -> Self {
        if let allowedValues {
            precondition(allowedValues.contains(defaultValue))
        }

        return Self(
            rawKey: rawKey,
            defaultValue: defaultValue,
            read: { defaults, key in
                defaults.string(forKey: key)
            },
            write: { defaults, key, value in
                defaults.set(value, forKey: key)
            },
            normalize: { value in
                guard let allowedValues else { return value }
                return allowedValues.contains(value) ? value : defaultValue
            }
        )
    }
}

extension ToolPreferenceKey where Value: RawRepresentable, Value.RawValue == String {
    static func rawRepresentable(
        _ rawKey: String,
        default defaultValue: Value
    ) -> Self {
        Self(
            rawKey: rawKey,
            defaultValue: defaultValue,
            read: { defaults, key in
                guard let rawValue = defaults.string(forKey: key) else { return nil }
                return Value(rawValue: rawValue)
            },
            write: { defaults, key, value in
                defaults.set(value.rawValue, forKey: key)
            },
            normalize: { $0 }
        )
    }
}

@MainActor
final class ToolPreferenceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func value<Value>(for key: ToolPreferenceKey<Value>) -> Value {
        key.normalize(key.read(defaults, key.rawKey) ?? key.defaultValue)
    }

    func set<Value>(_ value: Value, for key: ToolPreferenceKey<Value>) {
        key.write(defaults, key.rawKey, key.normalize(value))
    }
}

@MainActor
enum AppShellPreferenceKeys {
    static let autoResumeLastTool = ToolPreferenceKey<Bool>.bool(
        "tools.shell.autoResumeLastTool.v1", default: false
    )
    static let selectedToolID = ToolPreferenceKey<String>.string(
        "tools.shell.selectedToolID.v1",
        default: ""
    )

    static let sidebarVisibility = ToolPreferenceKey<String>.string(
        "tools.shell.sidebarVisibility.v1",
        default: "visible",
        allowedValues: ["visible", "hidden"]
    )

    /// JSON-encoded palette launch ring (`PaletteRecentsStore`).
    static let paletteRecents = ToolPreferenceKey<String>.string(
        "tools.palette.recents.v1",
        default: "[]"
    )
}

// 跨工具偏好键按域拆分在 Shared/Preferences/ 下：
// SensitiveToolPreferenceKeys / MediaToolPreferenceKeys /
// SourceControlToolPreferenceKeys / TextDevelopmentToolPreferenceKeys。
