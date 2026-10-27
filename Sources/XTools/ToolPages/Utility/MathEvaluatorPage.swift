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

    /// 追加片段，供快捷按钮使用，用户不必背语法。
    func insert(_ snippet: String) {
        expression += snippet
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

// MARK: - 快捷片段

private struct MathSnippetGroup: Identifiable {
    let id: String
    let title: String
    let items: [String]

    static let groups: [MathSnippetGroup] = [
        MathSnippetGroup(id: "operator", title: "运算符", items: ["+", "-", "*", "/", "%", "^", "(", ")"]),
        MathSnippetGroup(id: "constant", title: "常量", items: ["pi", "e", "phi"]),
        MathSnippetGroup(
            id: "function",
            title: "函数",
            // 不带右括号：插入后光标落在括号内，用户直接输入参数再补 `)`，
            // 与计算器的用法一致。自带 `()` 会让下一个字符落到括号外。
            items: [
                "sqrt(", "abs(", "round(", "floor(", "ceil(", "min(", "max(",
                "sin(", "cos(", "tan(", "asin(", "acos(", "atan(",
                "sinh(", "cosh(", "tanh(", "log(", "ln(", "exp(", "cbrt("
            ]
        )
    ]
}

private struct IndexMathWorkspaceContent: View {
    @ObservedObject var workspace: MathToolWorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusRequestToken = 0

    private var validResult: String? {
        if case .valid(let result) = workspace.evaluation {
            return result
        }
        return nil
    }

    private var diagnosticText: String? {
        if case .invalid(let error) = workspace.evaluation { return error.errorDescription }
        return nil
    }

    private var trimmedExpression: String {
        workspace.expression.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 还在输入中的表达式（`sqrt(`、`3+`）不是错误：求值器返回 `.incomplete`
    /// 正是为了把“没输完”和“输错了”分开，界面不该把前者报成后者。
    ///
    /// 只有真正拿到 `.invalid` 才显示“无法求值”。`.incomplete` 与后台求值
    /// 期间的 `.empty` 都属于“还没结果”，不能报成错误。
    private var showsErrorState: Bool {
        if case .invalid = workspace.evaluation { return true }
        return false
    }

    var body: some View {
        IndexPage(
            "数学计算",
            subtitle: "输入数学表达式即时求值；三角函数按弧度计算。",
            workspaceSemantic: .naturalHeightShortResultPanel
        ) {
            IndexPanel("表达式") {
                VStack(alignment: .leading, spacing: 10) {
                    IndexTextInput(
                        placeholder: "例如 (3 + 4) * 2 / sqrt(16)",
                        text: $workspace.expression,
                        autoFocus: true,
                        focusRequestToken: focusRequestToken
                    )
                    .indexWorkspaceDiagnostic(diagnosticText)

                    snippetBar
                }
            } accessory: {
                IndexClearButton(
                    isDisabled: !workspace.hasAnyContent,
                    action: workspace.clear
                )
            }

            resultPanel

            IndexPanel("用法") {
                VStack(alignment: .leading, spacing: 8) {
                    usageRow("运算符", "+  -  *  /  %  ^，括号按常规优先级求值")
                    usageRow("常量", "pi ≈ 3.14159、e ≈ 2.71828、phi ≈ 1.61803")
                    usageRow("函数", "sqrt  abs  round  floor  ceil  min  max  log  ln  exp  cbrt")
                    usageRow("三角函数", "sin / cos / tan 及反函数、双曲函数均按弧度，例如 sin(pi/2) = 1")
                }
            } accessory: {
                IndexBadge("实时求值", tone: .neutral)
            }
            .withoutDiagnosticStatusSlot()
        }
    }

    // MARK: - 结果

    private var resultPanel: some View {
        IndexPanel("结果") {
            if let result = validResult {
                resultReadout(result)
            } else {
                IndexEmptyState(
                    title: showsErrorState ? "无法求值" : "等待输入",
                    systemImage: showsErrorState ? "exclamationmark.triangle" : "function",
                    message: showsErrorState
                        ? "修正上方表达式后自动求值。"
                        : "输入完整的表达式后自动求值。",
                    density: .list
                )
                .frame(minHeight: 96)
                .toolTransition(ToolMotion.Transition.modeContent, reduceMotion: reduceMotion)
            }
        } accessory: {
            if let result = validResult {
                IndexCopyButton(text: result, title: "复制结果")
            }
        }
        .withoutDiagnosticStatusSlot()
    }

    private func resultReadout(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("计算结果")
                .font(ToolTypography.caption)
                .foregroundStyle(ToolTheme.textTertiary)

            Text(result)
                .font(ToolTypography.heroValue)
                .foregroundStyle(ToolTheme.accentHover)
                .textSelection(.enabled)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .toolMotionTextSwap(id: result)

            Text(trimmedExpression)
                .font(ToolTypography.monoCaption)
                .foregroundStyle(ToolTheme.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .indexSurface(.field, fill: ToolTheme.editorBackground, border: ToolTheme.border)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("计算结果")
        .accessibilityValue(result)
    }

    // MARK: - 片段与说明

    private var snippetBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(MathSnippetGroup.groups) { group in
                HStack(alignment: .top, spacing: 10) {
                    Text(group.title)
                        .font(ToolTypography.caption)
                        .foregroundStyle(ToolTheme.textTertiary)
                        .frame(width: 44, alignment: .leading)
                        .padding(.top, 5)

                    IndexFlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(group.items, id: \.self) { item in
                            snippetButton(item)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func snippetButton(_ item: String) -> some View {
        Button {
            workspace.insert(item)
            // 片段是输入辅助：点完要能继续在表达式里打字，而不是把焦点
            // 停在按钮上。
            focusRequestToken &+= 1
        } label: {
            Text(item)
                .font(ToolTypography.monoCaption)
                .foregroundStyle(ToolTheme.textSecondary)
                .padding(.horizontal, 7)
                .frame(height: ToolMetrics.ControlHeight.compact)
        }
        .buttonStyle(IndexSnippetButtonStyle())
        .accessibilityLabel("插入 \(item)")
    }

    private func usageRow(_ title: String, _ detail: String) -> some View {
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

/// 片段胶囊：静置只有发丝描边，悬停填充。高度走 compact 档；不点亮 accent，
/// 它们是输入辅助而非页面动作。
private struct IndexSnippetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .background(
                    configuration.isPressed
                        ? ToolTheme.activeFill
                        : (isHovering ? ToolTheme.hoverFill : Color.clear),
                    in: RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous)
                        .strokeBorder(ToolTheme.border, lineWidth: 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: ToolMetrics.CornerRadius.nestedControl, style: .continuous))
                .onHover { isHovering = $0 }
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: isHovering)
                .toolAnimation(ToolMotion.Preset.controlFeedback, value: configuration.isPressed)
        }
    }
}
