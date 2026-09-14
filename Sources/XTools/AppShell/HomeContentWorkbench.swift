import AppKit
import SwiftUI
import XToolsCore

@MainActor
struct HomeContentWorkbench: View {
    @ObservedObject var session: HomeContentSession
    @Binding var input: String
    @State private var measuredOutputHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            inputRow

            if hasInput {
                divider
                processingRow
            }

            if let failure = session.failure {
                divider
                diagnostic(failure)
            }

            if let result = session.result {
                divider
                resultSection(result)
            }
        }
        .background(
            ToolTheme.Workbench.surface,
            in: RoundedRectangle(cornerRadius: ToolMetrics.Workbench.groupCorner, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: ToolMetrics.Workbench.groupCorner, style: .continuous)
                .strokeBorder(ToolTheme.Workbench.border, lineWidth: 1)
        }
        .clipShape(
            RoundedRectangle(cornerRadius: ToolMetrics.Workbench.groupCorner, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("内容处理")
    }

    private var inputRow: some View {
        HStack(alignment: .top, spacing: 0) {
            IndexTextArea(
                placeholder: "粘贴 JSON、Base64 或 URL 编码内容…",
                text: $input,
                minHeight: ToolMetrics.Workbench.inputHeight,
                fillsHeight: false,
                renderingMode: .textKit2Viewport,
                embedsFlat: true
            )
            .frame(height: ToolMetrics.Workbench.inputHeight)
            .accessibilityLabel("待处理内容")
            .accessibilityIdentifier("dashboard.content.input")

            HStack(spacing: 3) {
                WorkbenchSecondaryButton(title: "粘贴", systemImage: "doc.on.clipboard", action: paste)
                    .accessibilityIdentifier("dashboard.content.paste")

                if !input.isEmpty {
                    WorkbenchSecondaryButton(title: nil, systemImage: "xmark", action: session.clear)
                        .help("清空输入")
                        .accessibilityLabel("清空输入")
                        .accessibilityIdentifier("dashboard.content.clear")
                }
            }
            .padding(9)
        }
    }

    private var processingRow: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("识别")
                    .font(ToolTypography.Workbench.caption)
                    .foregroundStyle(ToolTheme.Workbench.textFaint)
                Text(detectionTitle)
                    .font(ToolTypography.Workbench.body.weight(.medium))
                    .foregroundStyle(ToolTheme.Workbench.textPrimary)
            }

            Spacer(minLength: 12)
            actionMenu

            WorkbenchPrimaryButton(
                title: session.isProcessing ? "处理中…" : "处理",
                isEnabled: session.canRun,
                action: session.run
            )
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("dashboard.content.run")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 42)
    }

    private var actionMenu: some View {
        Menu {
            Button {
                session.useAutomaticActionSelection()
            } label: {
                menuItem("自动推荐", selected: session.usesAutomaticActionSelection)
            }

            Divider()

            ForEach(HomeContentAction.allCases, id: \.self) { action in
                Button {
                    session.selectedAction = action
                } label: {
                    menuItem(
                        action.title,
                        selected: !session.usesAutomaticActionSelection
                            && session.selectedAction == action
                    )
                }
            }
        } label: {
            Text(selectedActionTitle)
                .lineLimit(1)
                .font(ToolTypography.Workbench.caption)
                .foregroundStyle(ToolTheme.Workbench.textPrimary)
                .padding(.leading, 9)
                .padding(.trailing, 8)
                .frame(height: 30)
                .background(
                    ToolTheme.Workbench.surface,
                    in: RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous)
                        .strokeBorder(ToolTheme.Workbench.border, lineWidth: 1)
                }
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("处理方式")
        .accessibilityValue(selectedActionTitle)
        .accessibilityIdentifier("dashboard.content.action")
    }

    @ViewBuilder
    private func menuItem(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func diagnostic(_ message: String) -> some View {
        Text(message)
            .font(ToolTypography.Workbench.body)
            .foregroundStyle(ToolTheme.Workbench.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(ToolTheme.Workbench.dangerBackground)
            .accessibilityLabel(message)
    }

    private func resultSection(_ result: HomeContentResult) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("结果")
                    .font(ToolTypography.Workbench.body.weight(.semibold))
                    .foregroundStyle(ToolTheme.Workbench.textPrimary)

                if let warning = result.warning {
                    Text(warning)
                        .font(ToolTypography.Workbench.caption)
                        .foregroundStyle(ToolTheme.warning)
                        .lineLimit(1)
                        .help(warning)
                }

                Spacer(minLength: 8)

                IndexCopyButton(text: result.text, title: "复制", showsIcon: false)
                    .accessibilityIdentifier("dashboard.content.copy")

                Button(session.isOutputCollapsed ? "展开" : "收起") {
                    session.toggleOutputCollapsed()
                }
                .buttonStyle(IndexSmallButtonStyle())
                .accessibilityIdentifier("dashboard.content.collapse")
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 38)

            if !session.isOutputCollapsed {
                divider

                IndexOutputSurface(
                    text: result.text,
                    placeholder: "",
                    minHeight: 0,
                    scrollsInternally: true,
                    embedsFlat: true
                )
                .background(ToolTheme.Workbench.surfaceSecondary)
                .frame(height: outputHeight)
                .background {
                    outputHeightMeasurement(result.text)
                }
                .accessibilityIdentifier("dashboard.content.output")
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(ToolTheme.Workbench.border)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var outputHeight: CGFloat {
        min(
            ToolMetrics.Workbench.resultMaxHeight,
            max(54, measuredOutputHeight)
        )
    }

    private func outputHeightMeasurement(_ text: String) -> some View {
        Text(text)
            .font(ToolTypography.Workbench.input)
            .lineLimit(nil)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(12)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: WorkbenchOutputHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            }
            .hidden()
            .accessibilityHidden(true)
            .onPreferenceChange(WorkbenchOutputHeightPreferenceKey.self) { height in
                measuredOutputHeight = height
            }
    }

    private var hasInput: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedActionTitle: String {
        session.selectedAction?.title ?? "自动推荐"
    }

    private var detectionTitle: String {
        if session.isDetecting { return "正在识别…" }
        guard let detection = session.detection else { return "普通文本" }

        switch detection {
        case .json: return "JSON"
        case .base64: return "Base64"
        case .urlEncoded: return "URL 编码"
        case .jwt: return "JWT"
        case .html: return "HTML"
        case .xml: return "XML"
        case .cssColor: return "颜色"
        case .unixTimestamp: return "时间戳"
        case .dataURL: return "Data URL"
        }
    }

    private func paste() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            session.reportPasteboardUnavailable()
            return
        }
        input = text
    }
}

private struct WorkbenchOutputHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension HomeContentAction {
    var title: String {
        switch self {
        case .jsonFormat: return "JSON 格式化"
        case .base64Decode: return "Base64 解码"
        case .urlDecode: return "URL 解码"
        }
    }
}

private struct WorkbenchSecondaryButton: View {
    let title: String?
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(ToolTypography.Workbench.smallIcon)
                if let title { Text(title) }
            }
            .font(ToolTypography.Workbench.caption)
            .foregroundStyle(isHovering ? ToolTheme.Workbench.textPrimary : ToolTheme.Workbench.textSecondary)
            .padding(.horizontal, title == nil ? 9 : 10)
            .frame(height: 30)
            .background(
                isHovering ? ToolTheme.Workbench.surfaceSecondary : ToolTheme.Workbench.surface,
                in: RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous)
                    .strokeBorder(ToolTheme.Workbench.border, lineWidth: 1)
            }
            .contentShape(
                RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous)
            )
        }
        .buttonStyle(IndexBareButtonStyle())
        .focused($isFocused)
        .indexFocusRing(active: isFocused, cornerRadius: ToolMetrics.Workbench.compactCorner)
        .onHover { isHovering = $0 }
    }
}

private struct WorkbenchPrimaryButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ToolTypography.Workbench.caption.weight(.semibold))
                .foregroundStyle(ToolTheme.Workbench.onAction)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    ToolTheme.Workbench.action,
                    in: RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous)
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: ToolMetrics.Workbench.compactCorner, style: .continuous)
                )
        }
        .buttonStyle(IndexBareButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .focused($isFocused)
        .indexFocusRing(active: isFocused, cornerRadius: ToolMetrics.Workbench.compactCorner)
        .accessibilityLabel(title)
    }
}
