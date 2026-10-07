import AppKit
import SwiftUI

/// User-selected appearance preference. `system` defers to macOS appearance
/// (the default); `light`/`dark` are explicit overrides.
enum AppThemePreference: String, CaseIterable {
    case system
    case light
    case dark

    init(preferenceValue: String) {
        self = AppThemePreference(rawValue: preferenceValue) ?? .system
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var next: AppThemePreference {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }

    var title: String {
        switch self {
        // 中文排版惯例：标签与值之间用全角冒号。
        case .system: return "主题：跟随系统"
        case .light: return "主题：浅色"
        case .dark: return "主题：深色"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var toastMessage: String {
        switch self {
        case .system: return "已切换为跟随系统外观"
        case .light: return "已切换到浅色"
        case .dark: return "已切换到深色"
        }
    }
}

enum SidebarVisibility: Equatable {
    case visible
    case hidden

    init(preferenceValue: String) {
        self = preferenceValue == "hidden" ? .hidden : .visible
    }

    var preferenceValue: String {
        self == .hidden ? "hidden" : "visible"
    }
}
