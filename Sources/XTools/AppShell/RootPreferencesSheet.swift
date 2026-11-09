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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
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

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("外观")
                        .font(ToolTypography.label)
                        .foregroundStyle(ToolTheme.textSecondary)
                    HStack(alignment: .center, spacing: 12) {
                        Text("主题")
                            .font(ToolTypography.bodyMedium)
                            .foregroundStyle(ToolTheme.textPrimary)
                        Spacer(minLength: 12)
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
                }

                Rectangle()
                    .fill(ToolTheme.border)
                    .frame(height: 0.5)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("启动时继续上次工具")
                            .font(ToolTypography.bodyMedium)
                            .foregroundStyle(ToolTheme.textPrimary)
                        Text("关闭时，XTools 会直接打开个人工作台。")
                            .font(ToolTypography.caption)
                            .foregroundStyle(ToolTheme.textSecondary)
                    }
                    Spacer(minLength: 12)
                    IndexOptionSwitch(
                        title: "启动时继续上次工具",
                        style: .standalone,
                        showsLabel: false,
                        isOn: $autoResumeLastTool
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("所有设置只保存在本机。")
                Spacer(minLength: 12)
                Text("版本 \(appVersion)")
                Button("关于 XTools") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ToolTheme.textSecondary)
            }
            .font(ToolTypography.caption)
            .foregroundStyle(ToolTheme.textTertiary)
        }
        .padding(24)
        .frame(width: 440, height: 280)
        .background(ToolTheme.panelBackground)
        .background(WindowAppearanceOwner(preference: themePreference))
        .appThemeEnvironment(preference: themePreference, source: systemAppearanceSource)
    }
}
