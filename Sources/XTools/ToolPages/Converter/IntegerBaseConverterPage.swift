import XToolsCore
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
        backgroundDebounce: Duration = .milliseconds(180),
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

private struct IndexBaseConverterWorkspaceContent: View {
    @ObservedObject var workspace: IntegerBaseToolWorkspaceModel

    private var rows: [(String, String, Color?)] {
        guard let result = workspace.conversions else { return [] }
        return [
            ("二进制 (2)", result.binary, nil),
            ("八进制 (8)", result.octal, nil),
            ("十进制 (10)", result.decimal, nil),
            ("十六进制 (16)", result.hex, nil)
        ]
    }

    var body: some View {
        IndexPage("进制转换", subtitle: "在二进制、八进制、十进制、十六进制之间转换。", workspaceSemantic: .naturalHeightShortResultPanel) {
            IndexActionBar {
                IndexOptionGroup {
                    IndexOptionLabel("输入进制")
                    IndexOptionPicker(
                        items: [("2", "二进制"), ("8", "八进制"), ("10", "十进制"), ("16", "十六进制")],
                        selection: $workspace.base
                    )
                }
            }
            IndexPanel("输入数值") {
                IndexTextInput(placeholder: "输入数值…", text: $workspace.input, height: 38, autoFocus: true)
                    .indexWorkspaceDiagnostic(workspace.error)
            } accessory: {
                IndexClearButton(isDisabled: workspace.input.isEmpty && workspace.error == nil) {
                    workspace.clear()
                }
            }
            IndexPanel("各进制结果") {
                resultContent
            }
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        if workspace.isProcessing {
            IndexWorkspaceResultSurface {
                IndexKVSurface {
                    IndexProgressLabel(message: "正在换算…")
                        .frame(minHeight: 70)
                }
            }
        } else {
            IndexShortResultKV(rows: rows, emptyText: IndexEmptyStateCopy.autoCalculate("数值"), valueMotion: .immediate)
        }
    }
}
