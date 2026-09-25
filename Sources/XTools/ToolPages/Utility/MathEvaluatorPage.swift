import XToolsCore
import SwiftUI

typealias MathBackgroundEvaluation = @Sendable (
    _ expression: String,
    _ shouldCancel: @escaping @Sendable () -> Bool
) throws -> MathExpressionEvaluator.LiveEvaluation

@MainActor
final class MathToolWorkspaceModel: ObservableObject {
    static let synchronousUTF8ByteLimit = 4 * 1_024

    static let key = ToolWorkspaceKey<MathToolWorkspaceModel>(toolID: "math-evaluator") { _ in
        MathToolWorkspaceModel()
    }

    @Published var expression = "" {
        didSet {
            guard expression != oldValue else { return }
            refreshEvaluation()
        }
    }
    @Published var evaluation = MathExpressionEvaluator.LiveEvaluation.empty
    @Published private(set) var isEvaluating = false

    private let execution = SupersedingExecutionSession(cancelInFlight: true)
    private let backgroundEvaluation: MathBackgroundEvaluation
    private let debounce: Duration
    private let synchronousUTF8ByteLimit: Int

    convenience init() {
        self.init(
            backgroundEvaluation: { input, shouldCancel in
                try MathExpressionEvaluator.evaluateLiveInput(input, shouldCancel: shouldCancel)
            },
            debounce: .milliseconds(120),
            synchronousUTF8ByteLimit: Self.synchronousUTF8ByteLimit
        )
    }

    init(
        backgroundEvaluation: @escaping MathBackgroundEvaluation,
        debounce: Duration,
        synchronousUTF8ByteLimit: Int
    ) {
        self.backgroundEvaluation = backgroundEvaluation
        self.debounce = debounce
        self.synchronousUTF8ByteLimit = max(0, synchronousUTF8ByteLimit)
    }

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
        isEvaluating = false
    }

    private func refreshEvaluation() {
        let input = expression
        guard input.utf8.prefix(synchronousUTF8ByteLimit + 1).count > synchronousUTF8ByteLimit else {
            execution.invalidate()
            isEvaluating = false
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            evaluation = MathExpressionEvaluator.evaluateLiveInput(trimmed)
            return
        }

        evaluation = .empty
        isEvaluating = true
        let backgroundEvaluation = self.backgroundEvaluation
        execution.schedule(debounce: debounce, operation: { shouldCancel in
            try backgroundEvaluation(input, shouldCancel)
        }) { [weak self] _, result in
            guard let self else { return }
            self.evaluation = result
            self.isEvaluating = false
        }
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
}
