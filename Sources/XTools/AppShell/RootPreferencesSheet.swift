import AppKit
import SwiftUI

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
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
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
                .frame(height: 0.5)
                .padding(.vertical, 20)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("外观")
                        .font(ToolTypography.label)
                        .foregroundStyle(ToolTheme.textSecondary)
                    Picker("主题", selection: $themeName) {
                        Text("跟随系统").tag(AppThemePreference.system.rawValue)
                        Text("浅色").tag(AppThemePreference.light.rawValue)
                        Text("深色").tag(AppThemePreference.dark.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("主题")
                }

                Toggle(isOn: $autoResumeLastTool) {
                    VStack(alignment: .leading, spacing: 3) {
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
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("所有设置只保存在本机。")
            }
            .font(ToolTypography.caption)
            .foregroundStyle(ToolTheme.textTertiary)
        }
        .padding(24)
        .frame(width: 440, height: 300)
        .background(ToolTheme.panelBackground)
        .background(WindowAppearanceOwner(preference: themePreference))
        .appThemeEnvironment(preference: themePreference, source: systemAppearanceSource)
    }
}
