import SwiftUI
import XToolsCore

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

private struct IndexRomanWorkspaceContent: View {
    @ObservedObject var workspace: RomanNumeralToolWorkspaceModel

    private var output: String {
        (try? convert(workspace.input, mode: workspace.mode)) ?? IndexEmptyStateCopy.notAvailable
    }

    private var modeSelection: Binding<String> {
        Binding(get: { workspace.mode }, set: { changeMode(to: $0) })
    }

    var body: some View {
        IndexPage("罗马数字", subtitle: "阿拉伯数字与罗马数字互转。", workspaceSemantic: .naturalHeightShortResultPanel) {
            // 模式切换保留（正当选项），「清空」收进输入面板标题栏（SPEC §P5b）。
            IndexActionBar {
                IndexSegmentedControl(items: [("toRoman", "数字→罗马"), ("toNum", "罗马→数字")], selection: modeSelection)
            }
            IndexPanel("输入") {
                IndexTextInput(placeholder: "例如 2024 或 MMXXIV", text: $workspace.input, height: 42, autoFocus: true)
                    .onChange(of: workspace.input) { _ in normalizeRomanCase(); validate() }
                    .indexWorkspaceDiagnostic(workspace.error)
            } accessory: {
                IndexClearButton(isDisabled: workspace.input.isEmpty) {
                    clear()
                }
            }
            IndexPanel("结果") {
                IndexHeroStat(value: output, copyable: output != IndexEmptyStateCopy.notAvailable)
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
