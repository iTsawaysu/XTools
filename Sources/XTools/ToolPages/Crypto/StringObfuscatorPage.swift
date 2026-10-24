import XToolsCore
import XToolsDesign
import SwiftUI

struct StringObfuscationRequest: Equatable, Sendable {
    let input: String
    let keepFirst: Int
    let keepLast: Int
    let keepSpaces: Bool
    let replacementCharacter: Character

    var inputByteCount: Int {
        input.utf8.count
    }
}

typealias StringObfuscationRenderer = @Sendable (
    _ request: StringObfuscationRequest,
    _ shouldCancel: @escaping @Sendable () -> Bool
) -> String?

typealias StringObfuscationBackgroundRenderer = @Sendable (
    _ request: StringObfuscationRequest
) async -> String?

@MainActor
final class StringObfuscatorToolWorkspaceModel: ObservableObject {
    static let synchronousInputByteLimit = 64 * 1_024
    // 档位收口：键盘输入类防抖统一走 IndexDebouncer.keystrokeDebounce（200ms）。
    static let backgroundDebounce: Duration = IndexDebouncer.keystrokeDebounce

    static let key = ToolWorkspaceKey<StringObfuscatorToolWorkspaceModel>(toolID: "string-obfuscator") { preferences in
        StringObfuscatorToolWorkspaceModel(preferences: preferences)
    }

    @Published var input = "" {
        didSet {
            guard !ExactUTF8Identity.isExactlyEqual(input, oldValue) else { return }
            refresh()
        }
    }
    @Published private(set) var output = ""
    @Published private(set) var isProcessing = false
    @Published private(set) var usesNativeOutput = false
    @Published var keepFirst: Int {
        didSet {
            guard keepFirst != oldValue else { return }
            preferences.set(keepFirst, for: SensitiveToolPreferenceKeys.obfuscatorKeepFirst)
            refresh()
        }
    }
    @Published var keepLast: Int {
        didSet {
            guard keepLast != oldValue else { return }
            preferences.set(keepLast, for: SensitiveToolPreferenceKeys.obfuscatorKeepLast)
            refresh()
        }
    }
    @Published var keepSpaces: Bool {
        didSet {
            guard keepSpaces != oldValue else { return }
            preferences.set(keepSpaces, for: SensitiveToolPreferenceKeys.obfuscatorKeepSpaces)
            refresh()
        }
    }
    @Published private(set) var replacementChar: String

    private let preferences: ToolPreferenceStore
    private let synchronousInputByteLimit: Int
    private let debounce: Duration
    private let renderer: StringObfuscationRenderer
    private let backgroundRenderer: StringObfuscationBackgroundRenderer
    private let workGate = AsyncWorkGate()

    init(
        preferences: ToolPreferenceStore,
        synchronousInputByteLimit: Int = StringObfuscatorToolWorkspaceModel.synchronousInputByteLimit,
        debounce: Duration = StringObfuscatorToolWorkspaceModel.backgroundDebounce,
        renderer: @escaping StringObfuscationRenderer = { request, shouldCancel in
            StringObfuscator.obfuscate(
                request.input,
                keepFirst: request.keepFirst,
                keepLast: request.keepLast,
                keepSpaces: request.keepSpaces,
                replacementCharacter: request.replacementCharacter,
                shouldCancel: shouldCancel
            )
        },
        backgroundRenderer: StringObfuscationBackgroundRenderer? = nil
    ) {
        self.preferences = preferences
        self.synchronousInputByteLimit = max(0, synchronousInputByteLimit)
        self.debounce = debounce
        self.renderer = renderer
        self.backgroundRenderer = backgroundRenderer ?? { request in
            await Self.renderInBackground(request)
        }
        keepFirst = preferences.value(for: SensitiveToolPreferenceKeys.obfuscatorKeepFirst)
        keepLast = preferences.value(for: SensitiveToolPreferenceKeys.obfuscatorKeepLast)
        keepSpaces = preferences.value(for: SensitiveToolPreferenceKeys.obfuscatorKeepSpaces)

        let storedReplacement = preferences.value(for: SensitiveToolPreferenceKeys.obfuscatorReplacementCharacter)
        replacementChar = storedReplacement.count == 1 ? storedReplacement : "*"
    }

    func setReplacementCharacter(_ newValue: String) {
        let limitedValue = String(newValue.prefix(1))
        guard !ExactUTF8Identity.isExactlyEqual(replacementChar, limitedValue) else { return }
        replacementChar = limitedValue
        preferences.set(limitedValue, for: SensitiveToolPreferenceKeys.obfuscatorReplacementCharacter)
        refresh()
    }

    func clear() {
        guard !input.isEmpty else {
            invalidateCurrentRequest()
            clearDerivedState()
            return
        }
        input = ""
    }

    private func refresh() {
        invalidateCurrentRequest()

        guard !input.isEmpty else {
            clearDerivedState()
            return
        }

        let request = StringObfuscationRequest(
            input: input,
            keepFirst: keepFirst,
            keepLast: keepLast,
            keepSpaces: keepSpaces,
            replacementCharacter: replacementChar.first ?? "*"
        )

        guard request.inputByteCount > synchronousInputByteLimit else {
            output = renderer(request) { false } ?? ""
            isProcessing = false
            usesNativeOutput = false
            return
        }

        output = ""
        isProcessing = true
        usesNativeOutput = true
        scheduleBackgroundRender(for: request)
    }

    private func scheduleBackgroundRender(for request: StringObfuscationRequest) {
        let token = workGate.token
        workGate.schedule(debounce: debounce) { [weak self] in
            guard let self, self.workGate.isCurrent(token) else { return }

            let result = await backgroundRenderer(request)

            guard self.workGate.isCurrent(token) else { return }
            self.output = result ?? ""
            self.isProcessing = false
        }
    }

    private func invalidateCurrentRequest() {
        workGate.invalidate()
    }

    private func clearDerivedState() {
        output = ""
        isProcessing = false
        usesNativeOutput = false
    }

    nonisolated private static func renderInBackground(
        _ request: StringObfuscationRequest
    ) async -> String? {
        let task = Task.detached(priority: .userInitiated) {
            StringObfuscator.obfuscate(
                request.input,
                keepFirst: request.keepFirst,
                keepLast: request.keepLast,
                keepSpaces: request.keepSpaces,
                replacementCharacter: request.replacementCharacter,
                shouldCancel: { Task.isCancelled }
            )
        }

        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

struct IndexStringObfuscatorPage: View {
    var body: some View {
        ToolWorkspaceHost(key: StringObfuscatorToolWorkspaceModel.key) { workspace, _ in
            IndexStringObfuscatorWorkspaceContent(workspace: workspace)
        }
    }
}

/// 统一壳装配（page-rollout D1）：保留首/尾、保留空格、替换字符是影响当下
/// 遮蔽的即时参数，归弹性参数区（旧 headControls 的 AnyView 逃生口消灭；
/// IndexOptionLabel 行首标签改由 WorkbenchParameterItem 供给，popover 网格
/// 逻辑无、开关 standalone 形态原样）；清空归输入 pane 尾 ActionBar，复制
/// 归输出 pane 尾 ActionBar（⇧⌘C 由 IOPair 根部代理持有，页面只在 IOPair
/// 声明一次）。本页无方向语义（遮蔽无逆向操作），不接 `.swap`、不声明
/// primaryAction（实时计算）；异步后台渲染的 processing/nativeReadOnly 双
/// 呈现与 64KB 同步阈值语义逐字保留。
private struct IndexStringObfuscatorWorkspaceContent: View {
    @ObservedObject var workspace: StringObfuscatorToolWorkspaceModel

    var body: some View {
        IndexPage("字符串遮蔽", subtitle: "保留首尾指定位数并遮蔽中部；遮蔽不是加密，仍可能泄露长度和结构。", workspaceSemantic: .securityTransformWorkspace) {
            WorkbenchSurface(
                title: nil,
                shape: .inputOutput,
                parameters: { parameterFlow }
            ) {
                WorkbenchIOPair(
                    leadingTitle: "输入",
                    trailingTitle: "遮蔽后",
                    leadingActions: [
                        .clear(
                            enabled: !(workspace.input.isEmpty && workspace.output.isEmpty),
                            onPerform: { workspace.clear() }
                        )
                    ],
                    leadingAccessory: { stdinCluster },
                    leading: { inputPane },
                    trailingAccessory: { stdoutBadge },
                    trailing: { outputPane }
                )
            }
        }
    }

    /// 弹性参数区：旧 headControls 四组参数等价平移（标签字号/墨色随参数项
    /// 统一轴线；替换字符字段行高 30→36 对齐参数区统一轴线）。
    private var parameterFlow: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterGroup {
                WorkbenchParameterItem("保留首") {
                    IndexNumberInput(value: $workspace.keepFirst, range: 0...20, fieldWidth: 36)
                }
                WorkbenchParameterItem("保留尾") {
                    IndexNumberInput(value: $workspace.keepLast, range: 0...20, fieldWidth: 36)
                }
                WorkbenchParameterItem {
                    IndexOptionSwitch(title: "保留空格", style: .standalone, isOn: $workspace.keepSpaces)
                }
                WorkbenchParameterItem("替换字符") {
                    IndexTextInput(
                        placeholder: "*",
                        text: replacementCharacterBinding,
                        height: ToolMetrics.Control.row
                    )
                    .frame(width: ToolMetrics.Control.thumb)
                }
            }
        }
    }

    private var replacementCharacterBinding: Binding<String> {
        Binding(
            get: { workspace.replacementChar },
            set: { workspace.setReplacementCharacter($0) }
        )
    }

    /// 输入 pane 头附件：STDIN 徽章 + 字符/UTF-8 尺寸计数（超 64KB 阈值换算
    /// 字节呈现的旧语义逐字保留）。
    private var stdinCluster: some View {
        HStack(spacing: ToolMetrics.Spacing.fine) {
            IndexBadge("STDIN", tone: .neutral, isCapsule: true)
            IndexInputCountLabel(
                text: IndexInputCountPresentation.charactersOrUTF8Size(
                    largeTextByteLimit: StringObfuscatorToolWorkspaceModel.synchronousInputByteLimit
                ).label(for: workspace.input)
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var stdoutBadge: some View {
        IndexBadge("STDOUT", tone: .neutral, isCapsule: true)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// 输入 pane 内容（旧壳 input 槽投影）：TextKit2 视口渲染模式保留。
    private var inputPane: some View {
        IndexWorkspaceTextArea(
            placeholder: "输入要遮蔽的字符串…",
            text: $workspace.input,
            fillsHeight: true,
            autoFocus: true,
            inputRenderingMode: .textKit2Viewport,
            workspaceSemantic: .securityTransformWorkspace
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 焦点契约（阶段③ C3）：页面首个输入 = 输入编辑器。
        .workbenchFocusTarget()
    }

    /// 输出 pane 内容（旧壳 output 槽投影）：处理中 → 居中进度面；后台渲染
    /// 产物 → native 只读文本（无描边框），同步产物 → standard 呈现。
    @ViewBuilder
    private var outputPane: some View {
        if workspace.isProcessing {
            IndexTextConversionProcessingSurface(text: "正在更新遮蔽结果…")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if workspace.usesNativeOutput {
            IndexOutputSurface(
                text: workspace.output,
                placeholder: IndexEmptyStateCopy.outputWillShowHere,
                presentation: .plain,
                lineNumbers: false,
                fillsHeight: true,
                workspaceSemantic: .securityTransformWorkspace
            )
        } else {
            IndexOutputSurface(
                text: workspace.output,
                placeholder: IndexEmptyStateCopy.outputWillShowHere,
                lineNumbers: false,
                fillsHeight: true,
                workspaceSemantic: .securityTransformWorkspace
            )
        }
    }
}
