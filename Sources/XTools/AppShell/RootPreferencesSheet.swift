import AppKit
import SwiftUI
import XToolsDesign

struct RootPreferencesSheet: View {
    @Binding var themeName: String
    @Binding var autoResumeLastTool: Bool
    @ObservedObject var systemAppearanceSource: SystemAppearanceSource
    @Environment(\.dismiss) private var dismiss

    private var themePreference: AppThemePreference {
        AppThemePreference(preferenceValue: themeName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: ToolMetrics.Spacing.md) {
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xs) {
                    Text("设置")
                        .font(ToolTypography.sectionHeader)
                        .foregroundStyle(ToolTheme.textPrimary)
                    Text("调整 XTools 的外观和启动行为。")
                        .font(ToolTypography.bodyPlain)
                        .foregroundStyle(ToolTheme.textSecondary)
                }
                Spacer(minLength: 12)
                Button("完成") { dismiss() }
                    .buttonStyle(IndexButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
            }

            Rectangle()
                .fill(ToolTheme.border)
                .frame(height: ToolMetrics.Spacing.hairline)
                .padding(.vertical, ToolMetrics.Spacing.xxl)

            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.lg) {
                VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                    Text("外观")
                        .font(ToolTypography.label)
                        .foregroundStyle(ToolTheme.textSecondary)
                    IndexSegmentedControl(
                        items: [
                            (AppThemePreference.system.rawValue, "跟随系统"),
                            (AppThemePreference.light.rawValue, "浅色"),
                            (AppThemePreference.dark.rawValue, "深色")
                        ],
                        selection: $themeName
                    )
                    .accessibilityLabel("主题")
                }

                Toggle(isOn: $autoResumeLastTool) {
                    VStack(alignment: .leading, spacing: ToolMetrics.Spacing.xs) {
                        Text("启动时继续上次工具")
                            .font(ToolTypography.bodyMedium)
                            .foregroundStyle(ToolTheme.textPrimary)
                        Text("关闭时，XTools 会直接打开个人工作台。")
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textSecondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Spacer(minLength: 0)
            HStack(spacing: ToolMetrics.Spacing.fine) {
                Image(systemName: "lock.shield")
                Text("所有设置只保存在本机。")
            }
            .font(ToolTypography.caption)
            .foregroundStyle(ToolTheme.textTertiary)
        }
        .padding(ToolMetrics.Spacing.xxxl)
        .frame(width: 440, height: 300)
        .background(ToolTheme.panelBackground)
        .background(WindowAppearanceOwner(preference: themePreference))
        .appThemeEnvironment(preference: themePreference, source: systemAppearanceSource)
    }
}
