import SwiftUI

enum IndexEmptyStateDensity: Sendable {
    case panel // Large, used for whole panels
    case list
    case output
}

enum IndexEmptyStateCopy {
 static func autoCalculate(_ source: String) -> String { "输入\(source)后自动换算" }
 static func autoShow(_ source: String) -> String { "输入\(source)后自动显示" }
 static func autoGenerate(_ what: String) -> String { "选择\(what)后自动生成" }
 static func autoParse(_ source: String) -> String { "输入\(source)后自动解析" }
 static let noResults = "暂无匹配结果"
 static let noParsedResult = "暂无解析结果"
 static let noRecords = "暂无记录"
 static let outputWillShowHere = "输出将显示在这里"
 static let notAvailable = "暂无数据"
}

struct IndexEmptyState: View {
 let title: String
 let systemImage: String?
 let message: String?
 let density: IndexEmptyStateDensity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Wave 2 empty-state arrival: flips once on appear; per-element
    /// animations stage the reveal (icon spring first, text follows).
    @State private var arrivalStage = false

 init(
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

 var body: some View {
        VStack(alignment: .center, spacing: density == .panel ? 12 : 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize))
                    .foregroundStyle(ToolTheme.textTertiary)
                    .frame(width: iconBoxSize, height: iconBoxSize)
                    .background(ToolTheme.panelBackground, in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.control, style: .continuous))
                    .toolMotionIconSwap(id: systemImage)
                    .opacity(arrivalStage ? 1 : 0)
                    .offset(y: arrivalStage ? 0 : ToolMotion.EmptyArrival.iconRiseDistance)
                    .animation(reduceMotion ? nil : ToolMotion.EmptyArrival.iconRise, value: arrivalStage)
            }

            VStack(alignment: .center, spacing: 4) {
                Text(title)
                    .font(density == .panel ? ToolTypography.sectionTitle : ToolTypography.bodyMedium)
                    .foregroundStyle(ToolTheme.textPrimary)
                    .toolMotionTextSwap(id: title)
                    .opacity(arrivalStage ? 1 : 0)
                    .offset(y: arrivalStage ? 0 : ToolMotion.EmptyArrival.textRiseDistance)
                    .animation(reduceMotion ? nil : ToolMotion.EmptyArrival.textFollow, value: arrivalStage)

                if let message {
                    Text(message)
                        .font(ToolTypography.bodyPlain)
                        .foregroundStyle(ToolTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .toolMotionTextSwap(id: message)
                        .opacity(arrivalStage ? 1 : 0)
                        .offset(y: arrivalStage ? 0 : ToolMotion.EmptyArrival.textRiseDistance)
                        .animation(reduceMotion ? nil : ToolMotion.EmptyArrival.messageFollow, value: arrivalStage)
                }
            }
        }
        .padding(.horizontal, density == .panel ? 18 : 12)
        .padding(.vertical, density == .panel ? 16 : 12)
        .frame(maxWidth: density == .panel ? 360 : .infinity)
        .frame(maxWidth: .infinity, maxHeight: density == .list ? nil : .infinity)
        .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
        .onAppear {
            arrivalStage = true
        }
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
