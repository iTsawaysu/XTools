import XToolsCore
import XToolsDesign
import SwiftUI

typealias IntegerBasePreparedRenderer = @Sendable (
    _ prepared: IntegerBaseConverter.PreparedInput
) -> IntegerBaseConverter.Conversions

typealias IntegerBaseBackgroundRenderer = @Sendable (
    _ prepared: IntegerBaseConverter.PreparedInput
) async -> IntegerBaseConverter.Conversions

@MainActor
final class IntegerBaseToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<IntegerBaseToolWorkspaceModel>(toolID: "integer-base-converter") { preferences in
        IntegerBaseToolWorkspaceModel(preferences: preferences)
    }

    @Published var base: String {
        didSet {
            preferences.set(base, for: TextDevelopmentToolPreferenceKeys.integerBase)
            refresh()
        }
    }
    @Published var input = "" {
        didSet { refresh() }
    }
    @Published private(set) var conversions: IntegerBaseConverter.Conversions?
    @Published private(set) var error: String?
    @Published private(set) var isProcessing = false

    private let preferences: ToolPreferenceStore
    private let synchronousDigitLimit: Int
    private let backgroundDebounce: Duration
    private let renderer: IntegerBasePreparedRenderer
    private let backgroundRenderer: IntegerBaseBackgroundRenderer
    private let workGate = AsyncWorkGate()

    init(
        preferences: ToolPreferenceStore,
        synchronousDigitLimit: Int = 128,
        backgroundDebounce: Duration = IndexDebouncer.keystrokeDebounce,
        renderer: @escaping IntegerBasePreparedRenderer = IntegerBaseConverter.conversions(from:),
        backgroundRenderer: IntegerBaseBackgroundRenderer? = nil
    ) {
        self.preferences = preferences
        self.synchronousDigitLimit = synchronousDigitLimit
        self.backgroundDebounce = backgroundDebounce
        self.renderer = renderer
        self.backgroundRenderer = backgroundRenderer ?? { prepared in
            await Task.detached(priority: .userInitiated) {
                IntegerBaseConverter.conversions(from: prepared)
            }.value
        }
        base = preferences.value(for: TextDevelopmentToolPreferenceKeys.integerBase)
    }

    func clear() {
        input = ""
    }

    private func refresh() {
        workGate.invalidate()

        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            conversions = nil
            error = nil
            isProcessing = false
            return
        }

        guard let fromBase = Int(base) else {
            conversions = nil
            error = IntegerBaseConverter.ValidationIssue.unsupportedBase.errorDescription
            isProcessing = false
            return
        }

        let prepared: IntegerBaseConverter.PreparedInput
        do {
            prepared = try IntegerBaseConverter.prepare(input: input, fromBase: fromBase)
        } catch let issue as IntegerBaseConverter.ValidationIssue {
            conversions = nil
            error = issue.errorDescription
            isProcessing = false
            return
        } catch {
            conversions = nil
            self.error = "无法转换当前输入。"
            isProcessing = false
            return
        }

        error = nil
        if prepared.digitCount <= synchronousDigitLimit {
            conversions = renderer(prepared)
            isProcessing = false
            return
        }

        conversions = nil
        isProcessing = true
        let token = workGate.token
        workGate.schedule(debounce: backgroundDebounce) { [weak self] in
            guard let self, self.workGate.isCurrent(token) else { return }
            let result = await backgroundRenderer(prepared)
            guard self.workGate.isCurrent(token) else { return }
            self.conversions = result
            self.error = nil
            self.isProcessing = false
        }
    }
}

struct IndexBaseConverterPage: View {
    var body: some View {
        ToolWorkspaceHost(key: IntegerBaseToolWorkspaceModel.key) { workspace, _ in
            IndexBaseConverterWorkspaceContent(workspace: workspace)
        }
    }
}

/// 统一壳装配（page-rollout A1）：单行输入 + 窄 KV 结果 → .result 形态。
/// 进制分段与数值字段都是影响当下换算的即时参数，归弹性参数区（数值
/// 字段独占一行，参数区统一轴线 36pt，RegexTester pattern 行先例）；清空
/// 归内容区底部 ActionBar（.result 标准挂载点）。KV/进度呈现与空态逐字
/// 保留，语义不变（自然高度结果面板继续走页面滚动）。
private struct IndexBaseConverterWorkspaceContent: View {
    @ObservedObject var workspace: IntegerBaseToolWorkspaceModel

    private var resultItems: [IndexResultKVItem] {
        guard let result = workspace.conversions else { return [] }
        return [
            IndexResultKVItem(key: "二进制 (2)", value: result.binary),
            IndexResultKVItem(key: "八进制 (8)", value: result.octal),
            IndexResultKVItem(key: "十进制 (10)", value: result.decimal),
            IndexResultKVItem(key: "十六进制 (16)", value: result.hex)
        ]
    }

    var body: some View {
        IndexPage("进制转换", subtitle: "在二进制、八进制、十进制、十六进制之间转换。", workspaceSemantic: .naturalHeightShortResultPanel) {
            WorkbenchSurface(
                title: nil,
                shape: .result,
                actions: [
                    .clear(
                        enabled: !(workspace.input.isEmpty && workspace.error == nil),
                        onPerform: { workspace.clear() }
                    )
                ],
                parameters: { parameterFlow }
            ) {
                Group {
                    if workspace.isProcessing {
                        IndexProgressLabel(message: "正在换算…")
                            .frame(maxWidth: .infinity, minHeight: 70)
                            .padding(ToolMetrics.Spacing.md)
                    } else {
                        IndexResultSurface(
                            content: .kv(resultItems),
                            emptyText: IndexEmptyStateCopy.autoCalculate("数值")
                        )
                    }
                }
            }
        }
    }

    /// 弹性参数区：进制分段（旧 IndexOptionLabel + 分段）与数值输入行。
    private var parameterFlow: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterItem("进制") {
                IndexSegmentedControl(
                    items: [("2", "二进制"), ("8", "八进制"), ("10", "十进制"), ("16", "十六进制")],
                    selection: $workspace.base,
                    density: .compact
                )
            }
            WorkbenchParameterItem {
                IndexTextInput(placeholder: "输入数值…", text: $workspace.input, height: ToolMetrics.Control.row, autoFocus: true)
                    .indexWorkspaceDiagnostic(workspace.error)
                    .workbenchFocusTarget()
            }
        }
    }
}
