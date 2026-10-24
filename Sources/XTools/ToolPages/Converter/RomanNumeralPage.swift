import SwiftUI
import XToolsCore
import XToolsDesign

@MainActor
final class RomanNumeralToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<RomanNumeralToolWorkspaceModel>(toolID: "roman-numeral-converter") { _ in
        RomanNumeralToolWorkspaceModel()
    }

    @Published var mode = "toRoman"
    @Published var input = ""
    @Published var error: String?
}

struct IndexRomanPage: View {
    var body: some View {
        ToolWorkspaceHost(key: RomanNumeralToolWorkspaceModel.key) { workspace, _ in
            IndexRomanWorkspaceContent(workspace: workspace)
        }
    }
}

/// 统一壳装配（page-rollout A1）：单行输入 + hero 结果 → .result 形态。
/// 换向分段是页面级模式（数字→罗马 / 罗马→数字，双向回填），归标题行
/// titleAccessory（Base64File 编码/解码分段先例）；数值字段归弹性参数区
/// （统一轴线 36pt）；清空归内容区底部 ActionBar。hero 呈现与空态逐字
/// 保留，语义不变。
private struct IndexRomanWorkspaceContent: View {
    @ObservedObject var workspace: RomanNumeralToolWorkspaceModel

    private var output: String {
        (try? convert(workspace.input, mode: workspace.mode)) ?? IndexEmptyStateCopy.notAvailable
    }

    private var displayOutput: String {
        guard !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              output != IndexEmptyStateCopy.notAvailable else {
            return ""
        }
        return output
    }

    private var modeSelection: Binding<String> {
        Binding(get: { workspace.mode }, set: { changeMode(to: $0) })
    }

    var body: some View {
        IndexPage("罗马数字", subtitle: "阿拉伯数字与罗马数字互转。", workspaceSemantic: .naturalHeightShortResultPanel) {
            WorkbenchSurface(
                title: nil,
                primaryAction: nil,
                shape: .result,
                actions: [
                    .clear(enabled: !workspace.input.isEmpty, onPerform: clear)
                ],
                titleAccessory: {
                    IndexSegmentedControl(
                        items: [("toRoman", "数字→罗马"), ("toNum", "罗马→数字")],
                        selection: modeSelection
                    )
                },
                parameters: { parameterFlow }
            ) {
                IndexResultSurface(
                    content: .hero(
                        IndexResultHeroItem(
                            value: displayOutput,
                            copyable: displayOutput != IndexEmptyStateCopy.notAvailable
                        )
                    ),
                    emptyText: "输入数字后显示结果"
                )
            }
        }
    }

    /// 弹性参数区：数值输入行（参数区统一轴线 36pt）。
    private var parameterFlow: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterItem {
                IndexTextInput(placeholder: "例如 2024 或 MMXXIV", text: $workspace.input, height: ToolMetrics.Control.row, autoFocus: true)
                    .onChange(of: workspace.input) { normalizeRomanCase(); validate() }
                    .indexWorkspaceDiagnostic(workspace.error)
                    .workbenchFocusTarget()
            }
        }
    }

    private func changeMode(to newMode: String) {
        guard newMode != workspace.mode else {
            return
        }

        let nextInput = ConverterModeBackfill.currentValidOutput(
            input: workspace.input,
            currentMode: workspace.mode,
            hasError: workspace.error != nil,
            isEmptyInput: { normalizedInput($0, mode: workspace.mode).isEmpty },
            convert: convert
        )

        workspace.mode = newMode
        if let nextInput {
            workspace.input = nextInput
        }
        normalizeRomanCase()
        validate()
    }

    private func clear() {
        workspace.input = ""
        workspace.error = nil
    }

    private func normalizeRomanCase() {
        guard workspace.mode == "toNum" else { return }
        let uppercased = workspace.input.uppercased()
        if uppercased != workspace.input {
            workspace.input = uppercased
        }
    }

    private func normalizedInput(_ value: String, mode _: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func convert(_ value: String, mode currentMode: String) throws -> String {
        let normalized = normalizedInput(value, mode: currentMode)
        guard !normalized.isEmpty else {
            throw IndexConverterFailure.invalidInput
        }

        if currentMode == "toRoman" {
            return try RomanNumeralConverter.validatedRoman(fromArabic: normalized)
        }

        if currentMode == "toNum" {
            return String(try RomanNumeralConverter.validatedNumber(fromRoman: normalized))
        }

        throw IndexConverterFailure.invalidInput
    }

    private func validate() {
        guard !workspace.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            workspace.error = nil
            return
        }
        do {
            _ = try convert(workspace.input, mode: workspace.mode)
            workspace.error = nil
        } catch let issue as RomanNumeralConverter.ValidationIssue {
            workspace.error = issue.errorDescription
        } catch {
            workspace.error = "罗马数字转换失败。"
        }
    }

}
