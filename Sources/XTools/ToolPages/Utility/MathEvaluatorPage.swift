import XToolsCore
import SwiftUI

@MainActor
final class MathToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<MathToolWorkspaceModel>(toolID: "math-evaluator") { _ in
        MathToolWorkspaceModel()
    }

    @Published var expression = ""
    @Published var evaluation = MathExpressionEvaluator.LiveEvaluation.empty

    var hasAnyContent: Bool {
        if !expression.isEmpty {
            return true
        }
        if case .empty = evaluation {
            return false
        }
        return true
    }

    func clear() {
        expression = ""
        evaluation = .empty
    }
}

struct IndexMathPage: View {
    var body: some View {
        ToolWorkspaceHost(key: MathToolWorkspaceModel.key) { workspace, _ in
            IndexMathWorkspaceContent(workspace: workspace)
        }
    }
}

private struct IndexMathWorkspaceContent: View {
    @ObservedObject var workspace: MathToolWorkspaceModel

    var body: some View {
        IndexPage("数学计算", subtitle: "输入数学表达式即时求值。", workspaceSemantic: .naturalHeightShortResultPanel) {
            IndexPanel("表达式") {
                IndexTextInput(placeholder: "例如 (3 + 4) * 2 / sqrt(16)", text: $workspace.expression, height: 42, autoFocus: true)
                    .onChange(of: workspace.expression) { _ in evaluate() }
                    .indexWorkspaceDiagnostic(diagnosticText)
            } accessory: {
                IndexClearButton(
                    isDisabled: !workspace.hasAnyContent,
                    action: workspace.clear
                )
            }
            IndexHeroStat(value: resultText, copyable: validResult != nil)
            IndexPanel("说明") {
                VStack(alignment: .leading, spacing: 8) {
                    mathHelpRow("运算符", "+  -  *  /  %  ^")
                    mathHelpRow("常量", "pi  e  phi")
                    mathHelpRow("函数", "sqrt  abs  round  floor  ceil  min  max  sin  cos  tan  asin  acos  atan  sinh  cosh  tanh  log  ln  exp  cbrt")
                    mathHelpRow("三角函数", "使用弧度，例如 sin(pi/2) = 1。")
                }
            }
        }
    }

    private var validResult: String? {
        if case .valid(let result) = workspace.evaluation {
            return result
        }
        return nil
    }

    private var resultText: String {
        validResult ?? IndexEmptyStateCopy.notAvailable
    }

    private var diagnosticText: String? {
        if case .invalid(let error) = workspace.evaluation { return error.errorDescription }
        return nil
    }

    private func mathHelpRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(ToolTypography.monoLabel)
                .foregroundStyle(ToolTheme.accentHover)
                .frame(width: 70, alignment: .leading)

            Text(detail)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func evaluate() {
        let trimmed = workspace.expression.trimmingCharacters(in: .whitespacesAndNewlines)
        workspace.evaluation = MathExpressionEvaluator.evaluateLiveInput(trimmed)
    }
}
