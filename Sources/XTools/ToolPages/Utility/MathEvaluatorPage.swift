import XToolsCore
import SwiftUI
import XToolsDesign

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

    private let execution = SupersedingExecutionSession(cancelInFlight: true)
    private let backgroundEvaluation: MathBackgroundEvaluation
    private let synchronousUTF8ByteLimit: Int

    convenience init() {
        self.init(
            backgroundEvaluation: { input, shouldCancel in
                try MathExpressionEvaluator.evaluateLiveInput(input, shouldCancel: shouldCancel)
            },
            synchronousUTF8ByteLimit: Self.synchronousUTF8ByteLimit
        )
    }

    init(
        backgroundEvaluation: @escaping MathBackgroundEvaluation,
        synchronousUTF8ByteLimit: Int
    ) {
        self.backgroundEvaluation = backgroundEvaluation
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
    }

    private func refreshEvaluation() {
        let input = expression
        guard input.utf8.prefix(synchronousUTF8ByteLimit + 1).count > synchronousUTF8ByteLimit else {
            execution.invalidate()
            evaluation = MathExpressionEvaluator.evaluateLiveInput(input)
            return
        }

        evaluation = .empty
        let backgroundEvaluation = self.backgroundEvaluation
        execution.schedule(operation: { shouldCancel in
            try backgroundEvaluation(input, shouldCancel)
        }) { [weak self] _, result in
            guard let self else { return }
            self.evaluation = result
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
            IndexInputResultWorkbench(
                inputTitle: "表达式",
                resultTitle: "结果"
            ) {
                HStack(spacing: ToolMetrics.Spacing.sm) {
                    Spacer(minLength: ToolMetrics.Spacing.sm)
                    IndexClearButton(
                        isDisabled: !workspace.hasAnyContent,
                        action: workspace.clear
                    )
                }
            } resultControls: {
                EmptyView()
            } input: {
                IndexTextInput(placeholder: "例如 (3 + 4) * 2 / sqrt(16)", text: $workspace.expression, height: 42, autoFocus: true)
                    .indexWorkspaceDiagnostic(diagnosticText)
                    .padding(.horizontal, ToolMetrics.Spacing.md)
                    .padding(.vertical, ToolMetrics.Spacing.sm)
            } result: {
                VStack(alignment: .leading, spacing: 0) {
                    IndexResultSurface(
                        content: .hero(
                            IndexResultHeroItem(
                                value: validResult ?? "",
                                copyable: validResult != nil
                            )
                        ),
                        emptyText: "输入表达式后显示结果"
                    )

                    ToolDivider()
                        .padding(.horizontal, ToolMetrics.Spacing.md)

                    VStack(alignment: .leading, spacing: ToolMetrics.Spacing.sm) {
                        mathHelpRow("运算符", "+  -  *  /  %  ^")
                        mathHelpRow("常量", "pi  e  phi")
                        mathHelpRow("函数", "sqrt  abs  round  floor  ceil  min  max  sin  cos  tan  asin  acos  atan  sinh  cosh  tanh  log  ln  exp  cbrt")
                        mathHelpRow("三角函数", "使用弧度，例如 sin(pi/2) = 1。")
                    }
                    .padding(ToolMetrics.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(alignment: .firstTextBaseline, spacing: ToolMetrics.Spacing.md) {
            Text(title)
                .font(ToolTypography.monoLabel)
                .foregroundStyle(ToolTheme.textPrimary)
                .frame(width: ToolMetrics.Control.labelColumn, alignment: .leading)

            Text(detail)
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
