import SwiftUI

enum ToolFeedbackTone: Equatable {
    case success
    case error
    case warning
    case info

    var systemImage: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success:
            return ToolTheme.success
        case .error:
            return ToolTheme.error
        case .warning:
            return ToolTheme.warning
        case .info:
            return ToolTheme.info
        }
    }

    var softFill: Color {
        switch self {
        case .success:
            return ToolTheme.successSoft
        case .error:
            return ToolTheme.errorSoft
        case .warning:
            return ToolTheme.warningSoft
        case .info:
            return ToolTheme.accentSoft
        }
    }

    var accessibilityPrefix: String {
        switch self {
        case .success:
            return "成功"
        case .error:
            return "错误"
        case .warning:
            return "警告"
        case .info:
            return "信息"
        }
    }

    var defaultToastDuration: TimeInterval {
        switch self {
        case .success, .info:
            return 2.0
        case .warning, .error:
            return 4.0
        }
    }

    var workspaceDiagnosticPriority: Int {
        switch self {
        case .success:
            return 0
        case .info:
            return 1
        case .warning:
            return 2
        case .error:
            return 3
        }
    }
}
