import SwiftUI

public enum IndexEmptyStateDensity: Sendable {
    case panel // Large, used for whole panels
    case list // Used in lists
    case output // Used for output areas
}

public enum IndexEmptyStateCopy {
    public static func autoCalculate(_ source: String) -> String { "输入\(source)后自动换算" }
    public static func autoShow(_ source: String) -> String { "输入\(source)后自动显示" }
    public static func autoGenerate(_ what: String) -> String { "选择\(what)后自动生成" }
    public static func autoParse(_ source: String) -> String { "输入\(source)后自动解析" }
    public static let noResults = "暂无匹配结果"
    public static let noParsedResult = "暂无解析结果"
    public static let noRecords = "暂无记录"
    public static let outputWillShowHere = "输出将显示在这里"
    public static let notAvailable = "暂无数据"
}

public struct IndexEmptyState: View {
    public let title: String
    public let systemImage: String?
    public let message: String?
    public let density: IndexEmptyStateDensity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        title: String,
        systemImage: String? = nil,
        message: String? = nil,
        density: IndexEmptyStateDensity = .panel
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.density = density
    }

    public var body: some View {
        VStack(alignment: .center, spacing: density == .panel ? 12 : 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize))
                    .foregroundStyle(ToolTheme.textTertiary)
                    .frame(width: iconBoxSize, height: iconBoxSize)
                    .background(ToolTheme.panelBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                    .toolMotionIconSwap(id: systemImage)
            }

            VStack(alignment: .center, spacing: 4) {
                Text(title)
                    .font(density == .panel ? ToolTypography.sectionTitle : ToolTypography.bodyMedium)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .toolMotionTextSwap(id: title)

                if let message {
                    Text(message)
                        .font(ToolTypography.bodyPlain)
                        .foregroundStyle(ToolTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .toolMotionTextSwap(id: message)
                }
            }
        }
        .padding(.horizontal, density == .panel ? 18 : 12)
        .padding(.vertical, density == .panel ? 16 : 12)
        .frame(maxWidth: density == .panel ? 360 : .infinity)
        .frame(maxWidth: .infinity, maxHeight: density == .list ? nil : .infinity)
        .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
    }
    
    private var iconSize: CGFloat {
        switch density {
        case .panel: return ToolMetrics.IconSize.display
        case .list, .output: return ToolMetrics.IconSize.large
        }
    }
    
    private var iconBoxSize: CGFloat {
        switch density {
        case .panel: return 44
        case .list, .output: return 32
        }
    }
}
