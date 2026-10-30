import AppKit
import SwiftUI

/// 单侧对比面板：固定高度的图像舞台 + 浮动标签 + 固定高度信息脚注。
///
/// 舞台高度由调用方给定（两侧传同一值），脚注高度恒定，因此两张并排时
/// 图顶、图底与脚注行完全同线，不随图片比例或脚注行数漂移。标签浮在图
/// 像左上角而不是独占一条卡头，把纵向空间留给画面本身。
struct IndexImageComparisonPane<Footer: View>: View {
    let title: String
    var badgeText: String? = nil
    var badgeTone: IndexBadgeTone = .neutral
    let image: NSImage?
    let accessibilityLabel: String
    let accessibilityValue: String
    let placeholder: String
    var isProcessing = false
    let stageHeight: CGFloat
    private let footer: Footer

    static var footerHeight: CGFloat { 40 }

    init(
        title: String,
        badgeText: String? = nil,
        badgeTone: IndexBadgeTone = .neutral,
        image: NSImage?,
        accessibilityLabel: String,
        accessibilityValue: String,
        placeholder: String,
        isProcessing: Bool = false,
        stageHeight: CGFloat,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.badgeText = badgeText
        self.badgeTone = badgeTone
        self.image = image
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.placeholder = placeholder
        self.isProcessing = isProcessing
        self.stageHeight = stageHeight
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                IndexImagePreviewStage(
                    image: image,
                    accessibilityLabel: accessibilityLabel,
                    accessibilityValue: accessibilityValue,
                    placeholder: isProcessing ? "" : placeholder,
                    maxDisplayWidth: 640,
                    maxDisplayHeight: max(stageHeight - 16, 120)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                if isProcessing {
                    // 处理中浮在图片上方：给一个不透明胶囊底，避免浅色画面
                    // 上只剩一枚看不清的转圈。
                    HStack(spacing: 7) {
                        IndexProgressSpinner()
                        Text("处理中…")
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: ToolMetrics.ControlHeight.small)
                    .background(
                        ToolTheme.panelBackground.opacity(0.94),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule().strokeBorder(ToolTheme.border, lineWidth: 0.5)
                    }
                    .toolShadow(ToolTheme.Shadow.keycap)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .accessibilityElement(children: .combine)
                    .transition(ToolMotion.Transition.statusChip)
                }

                HStack(spacing: 6) {
                    Text(title)
                        .font(ToolTypography.fieldLabel)
                        .foregroundStyle(ToolTheme.textPrimary)
                        .padding(.horizontal, 8)
                        .frame(height: ToolMetrics.ControlHeight.compact)
                        .background(
                            ToolTheme.panelBackground,
                            in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                                .strokeBorder(ToolTheme.border, lineWidth: 0.5)
                        }
                        .toolShadow(ToolTheme.Shadow.keycap)

                    if let badgeText {
                        IndexBadge(badgeText, tone: badgeTone, isCapsule: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
            .frame(height: stageHeight)
            .imageCanvasSurface()
            .clipped()
            .toolAnimation(ToolMotion.Preset.panelReveal, value: isProcessing)

            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: 0.5)

            footer
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: Self.footerHeight, maxHeight: Self.footerHeight, alignment: .leading)
                .background(ToolTheme.panelBackground)
        }
    }
}

// MARK: - Image canvas surface

extension View {
    /// 图片工作区统一的 clay 画布：暖白面板上落一层 clay，顶边用 12pt
    /// 落影交代层级。对比舞台、单图预览、队列与部署包共用这一套表面，
    /// 避免同类功能出现白底 / clay 底两套风格。
    func imageCanvasSurface() -> some View {
        background {
            ZStack(alignment: .top) {
                ToolTheme.editorBackground

                LinearGradient(
                    colors: [
                        ToolTheme.cardShadow,
                        ToolTheme.cardShadow.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 12)
            }
        }
    }
}
