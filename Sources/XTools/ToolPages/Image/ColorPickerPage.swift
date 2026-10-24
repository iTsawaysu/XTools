import AppKit
import SwiftUI
import XToolsCore
import XToolsDesign

func colorSliderValueText(_ value: Double, suffix: String) -> String {
    "\(Int(value.rounded()))\(suffix)"
}

@MainActor
final class ColorToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<ColorToolWorkspaceModel>(toolID: "color-picker") { _ in
        ColorToolWorkspaceModel()
    }

    @Published private(set) var state = CSSColorWorkspaceState()

    func send(_ action: CSSColorWorkspaceAction) {
        var next = state
        CSSColorWorkspaceReducer.reduce(state: &next, action: action)
        if next != state { state = next }
    }
}

struct IndexColorPage: View {
    var body: some View {
        ToolWorkspaceHost(key: ColorToolWorkspaceModel.key) { workspace, _ in
            IndexColorWorkspaceContent(workspace: workspace)
        }
    }
}

private struct IndexColorWorkspaceContent: View {
    @ObservedObject var workspace: ColorToolWorkspaceModel
    @State private var showsSystemColorPicker = false
    @State private var showsAdvancedFormats = false

    private var values: [CSSColorFormattedValue] { workspace.state.formattedValues }
    private var commonValues: [CSSColorFormattedValue] { values.filter { $0.group == .common } }
    private var perceptualValues: [CSSColorFormattedValue] { values.filter { $0.group == .perceptual } }
    private var extendedValues: [CSSColorFormattedValue] { values.filter { $0.group == .extended } }
    private var advancedValues: [CSSColorFormattedValue] { perceptualValues + extendedValues }

    var body: some View {
        IndexPage(
            "颜色转换",
            subtitle: "解析现代 CSS 颜色，统一转换为带 Alpha 的多种格式。",
            workspaceSemantic: .queryListWorkspace
        ) {
            // 统一壳装配（page-rollout A2，design.md「取色器进参数区（弹性）；
            // 自绘滑杆保留」）：取色按钮 + CSS 颜色字段归弹性参数区（RegexTester
            // pattern 行先例，统一轴线 36pt）；预览色板与自绘 HSL/Alpha 滑杆
            // 留输入 pane（canvas 语义自由内容，组件逐字保留）；格式结果行与
            // 「更多颜色空间」折叠区留输出 pane。双栏需固定高度，语义切
            // queryList（DateTime 先例授权）。
            WorkbenchSurface(title: nil, shape: .inputOutput, parameters: { parameterFlow }) {
                WorkbenchIOPair(
                    leadingTitle: "输入与预览",
                    trailingTitle: "转换结果"
                ) {
                    leadingPane
                } trailing: {
                    VStack(alignment: .leading, spacing: 0) {
                        resultRows(commonValues, emptyText: IndexEmptyStateCopy.autoShow("有效 CSS 颜色"))

                        Divider()

                        advancedFormatsDisclosure
                    }
                }
            }
        }
    }

    /// 弹性参数区：取色按钮与 CSS 颜色字段（页面首个输入）。
    private var parameterFlow: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterItem {
                HStack(spacing: ToolMetrics.Spacing.sm) {
                    colorPickerButton

                    IndexTextInput(
                        placeholder: "#7C8CFF、oklch(65% 0.2 40)、color(display-p3 1 0.2 0.1 / 0.8)",
                        text: Binding(
                            get: { workspace.state.draft },
                            set: { workspace.send(.draftChanged($0)) }
                        ),
                        height: ToolMetrics.Control.row
                    )
                    .accessibilityLabel("CSS 颜色")
                    .accessibilityHint("输入 HEX、命名颜色或现代 CSS 颜色函数")
                    .indexWorkspaceDiagnostic(workspace.state.diagnostic?.message)
                    .workbenchFocusTarget()
                }
            }
        }
    }

    /// 输入 pane 内容（canvas 语义自由内容）：预览色板 + 提示 + 自绘滑杆。
    private var leadingPane: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: ToolMetrics.Spacing.lg) { canvasBody }
            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.lg) { canvasBody }
        }
    }

    private var canvasBody: some View {
        Group {
            RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)
                .fill(ToolTheme.editorBackground)
                .overlay { Rectangle().fill(Color(nsColor: previewColor)).clipShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field, style: .continuous)) }
                .frame(width: ToolMetrics.Control.preview, height: ToolMetrics.Control.preview)
                .overlay { RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.field).strokeBorder(ToolTheme.border, lineWidth: ToolMetrics.Spacing.hairline) }
                .accessibilityElement()
                .accessibilityLabel("颜色预览")
                .accessibilityValue(previewAccessibilityValue)

            VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
                if workspace.state.isUsingLastValidResult {
                    Text("结果基于上次有效颜色，当前输入仍未完成或无效。")
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.warning)
                        .accessibilityLabel("上次有效颜色提示")
                }

                hslControls
            }
            .frame(maxWidth: ToolMetrics.Control.readingWide)
        }
    }

    /// 系统取色器触发钮（原 pickerBody 内行首控件，随取色器进参数区）。
    private var colorPickerButton: some View {
        Button {
            showsSystemColorPicker.toggle()
        } label: {
            Label("取色", systemImage: "eyedropper")
                .font(ToolTypography.buttonSmall)
        }
        .buttonStyle(IndexButtonStyle(compact: true))
        .help("打开系统取色器（包含透明度）")
        .accessibilityLabel("打开系统取色器")
        .popover(isPresented: $showsSystemColorPicker, arrowEdge: .bottom) {
            systemColorPicker
        }
    }

    private var hslControls: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.md) {
            if workspace.state.isMappedToSRGB {
                Text("超出 sRGB；HSL 调整将从映射后的显示颜色开始。")
                    .font(ToolTypography.caption)
                    .foregroundStyle(ToolTheme.warning)
                    .accessibilityLabel("当前颜色超出 sRGB，HSL 调整将从映射后的显示颜色开始")
            }

            slider(
                title: "色相",
                value: hslBinding(index: 0),
                range: 0...360,
                suffix: "°",
                track: .gradient(hueTrack),
                accessibilityName: "色相"
            )
            slider(
                title: "饱和度",
                value: hslBinding(index: 1),
                range: 0...100,
                suffix: "%",
                track: .gradient(saturationTrack),
                accessibilityName: "饱和度"
            )
            slider(
                title: "亮度",
                value: hslBinding(index: 2),
                range: 0...100,
                suffix: "%",
                track: .gradient(brightnessTrack),
                accessibilityName: "亮度"
            )

            Divider()

            slider(
                title: "Alpha",
                value: Binding(
                    get: { workspace.state.alpha * 100 },
                    set: { workspace.send(.alphaChanged($0 / 100)) }
                ),
                range: 0...100,
                suffix: "%",
                track: .alpha(color: alphaTrackColor),
                accessibilityName: "Alpha 透明度"
            )
        }
        .padding(ToolMetrics.Spacing.md)
        .indexSurface(.field, fill: ToolTheme.editorBackground, border: ToolTheme.border)
        .accessibilityElement(children: .contain)
    }

    private var advancedFormatsDisclosure: some View {
        IndexDisclosure(
            title: "更多颜色空间",
            isExpanded: $showsAdvancedFormats,
            collapsedSummary: advancedFormatsSummary
        ) {
            resultRows(advancedValues, emptyText: IndexEmptyStateCopy.autoShow("有效 CSS 颜色"))
        }
        .inline()
    }

    private var advancedFormatsSummary: String {
        guard !advancedValues.isEmpty else { return "输入颜色后显示 Lab、OKLCH、color() 等格式" }
        return "Lab、OKLCH、color() 等 \(advancedValues.count) 种格式"
    }

    private var systemColorPicker: some View {
        VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
            Text("系统取色器")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
            ColorPicker("颜色", selection: Binding(
                get: { Color(nsColor: previewColor) },
                set: { color in
                    guard let value = NSColor(color).usingColorSpace(.sRGB) else { return }
                    workspace.send(.systemColorPicked(
                        red: value.redComponent,
                        green: value.greenComponent,
                        blue: value.blueComponent,
                        alpha: value.alphaComponent
                    ))
                }
            ), supportsOpacity: true)
            .frame(width: ToolMetrics.Control.colorWell)
            .accessibilityLabel("系统颜色和透明度")
        }
        .padding(ToolMetrics.Spacing.md)
    }

    private func hslBinding(index: Int) -> Binding<Double> {
        Binding(
            get: { workspace.state.hsl[index] },
            set: { newValue in
                var values = workspace.state.hsl
                values[index] = newValue
                workspace.send(.hslChanged(hue: values.x, saturation: values.y, lightness: values.z))
            }
        )
    }

    private func slider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String = "",
        track: IndexSliderTrack = .fill,
        accessibilityName: String
    ) -> some View {
        HStack(spacing: ToolMetrics.Spacing.md) {
            Text(title)
                .font(ToolTypography.bodyPlain)
                .foregroundStyle(ToolTheme.textSecondary)
                .frame(width: ToolMetrics.Control.thumbnail, alignment: .leading)
            IndexSlider(value: value, range: range, step: 1, track: track)
                .accessibilityLabel(accessibilityName)
                .accessibilityValue(colorSliderValueText(value.wrappedValue, suffix: suffix))
            Text(colorSliderValueText(value.wrappedValue, suffix: suffix))
                .font(ToolTypography.monoLabel)
                .foregroundStyle(ToolTheme.textPrimary)
                .frame(width: ToolMetrics.Control.swatch, alignment: .trailing)
        }
    }

    // MARK: Slider tracks (Clay Warmth: perceptual gradients under each axis)

    private var hueTrack: LinearGradient {
        LinearGradient(
            colors: (0...6).map { step in
                Color(hue: Double(step) / 6, saturation: 1, brightness: 1)
            },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var mappedHSL: SIMD3<Double> {
        workspace.state.hsl
    }

    private var saturationTrack: LinearGradient {
        LinearGradient(
            colors: [0.0, 100.0].map {
                hslTrackColor(hue: mappedHSL.x, saturation: $0, lightness: mappedHSL.z)
            },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var brightnessTrack: LinearGradient {
        LinearGradient(
            colors: [0.0, 50.0, 100.0].map {
                hslTrackColor(hue: mappedHSL.x, saturation: mappedHSL.y, lightness: $0)
            },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func hslTrackColor(hue: Double, saturation: Double, lightness: Double) -> Color {
        guard let color = try? CSSColor(
            components: SIMD3(hue, saturation, lightness), space: .hsl, alpha: 1
        ) else { return .clear }
        let mapped = CSSColorGamutMapping.sRGB(for: color)
        return Color(.sRGB, red: mapped.components.x, green: mapped.components.y, blue: mapped.components.z)
    }

    private var alphaTrackColor: Color {
        Color(nsColor: previewColor)
    }

    @ViewBuilder
    private func resultRows(_ values: [CSSColorFormattedValue], emptyText: String) -> some View {
        if values.isEmpty {
            IndexEmptyState(
                title: "无结果",
                systemImage: "paintpalette",
                message: emptyText
            )
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
        } else {
            // 这里必须是普通 VStack：结果列表嵌在 ToolDisclosureBody 里，由它
            // 测量内容高度后裁剪展开；LazyVStack 依赖外层滚动视口实现行复用，
            // 在自测量容器里首帧高度失真，展开后要滚动一次才会触发重新布局。
            VStack(spacing: 0) {
                ForEach(values) { value in
                    ColorFormatResultRow(value: value)
                    if value.id != values.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var previewColor: NSColor {
        guard let color = workspace.state.visibleColor else { return .controlBackgroundColor }
        let mapped = CSSColorGamutMapping.sRGB(for: color)
        return NSColor(
            srgbRed: mapped.components.x,
            green: mapped.components.y,
            blue: mapped.components.z,
            alpha: mapped.alpha
        )
    }

    private var previewAccessibilityValue: String {
        guard let color = workspace.state.visibleColor else { return "尚未输入颜色" }
        let alpha = String(format: "%.0f%%", color.alpha * 100)
        return "Alpha \(alpha)\(workspace.state.isMappedToSRGB ? "，已映射到 sRGB" : "")"
    }
}

private struct ColorFormatResultRow: View {
    let value: CSSColorFormattedValue

    var body: some View {
        HStack(alignment: .center, spacing: ToolMetrics.Spacing.compact) {
            Text(value.label)
                .font(ToolTypography.micro)
                .foregroundStyle(ToolTheme.textTertiary)
                .lineLimit(1)
                .frame(width: ToolMetrics.Control.valueColumn, alignment: .leading)

            valueText
                .layoutPriority(1)

            if value.mappingStatus == .mappedToSRGB {
                IndexBadge("映射到 sRGB", tone: .warning)
                    .fixedSize(horizontal: true, vertical: false)
            }

            IndexCopyButton(text: value.text, title: "复制 \(value.label)", iconOnly: true)
        }
        .padding(.horizontal, ToolMetrics.Spacing.sm)
        .padding(.vertical, ToolMetrics.Spacing.sm)
    }

    /// Rows show one-decimal HSL/HWB precision; the copy button keeps the
    /// full-precision text.
    private var displayText: String {
        guard value.label == "HSL" || value.label == "HWB" else { return value.text }
        return value.text.replacingOccurrences(
            of: #"(\.\d)\d+"#,
            with: "$1",
            options: .regularExpression
        )
    }

    @ViewBuilder
    private var valueText: some View {
        Text(indexWrappingAttributedText(displayText, lineBreakMode: .byCharWrapping))
            .font(ToolTypography.monoLabel)
            .foregroundStyle(ToolTheme.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(value.label) 结果")
            .accessibilityValue(value.text)
    }
}
