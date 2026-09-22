import XToolsCore
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
    static let backgroundDebounce: Duration = .milliseconds(180)

    static let key = ToolWorkspaceKey<StringObfuscatorToolWorkspaceModel>(toolID: "string-obfuscator") { preferences in
        StringObfuscatorToolWorkspaceModel(preferences: preferences)
    }

    @Published var input = "" {
        didSet {
            guard input != oldValue else { return }
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
        guard replacementChar != limitedValue else { return }
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

private struct IndexStringObfuscatorWorkspaceContent: View {
    @ObservedObject var workspace: StringObfuscatorToolWorkspaceModel

    var body: some View {
        IndexPage("字符串遮蔽", subtitle: "保留首尾指定位数并遮蔽中部；遮蔽不是加密，仍可能泄露长度和结构。", workspaceSemantic: .securityTransformWorkspace) {
            IndexWorkbenchControlBar {
                HStack(spacing: 8) {
                    obfuscationControls
                }
                .fixedSize(horizontal: true, vertical: false)
            } compactControls: {
                IndexFlowLayout(spacing: 8, lineSpacing: 8) {
                    obfuscationControls
                }
            }

            IndexTextConversionWorkbench(
                inputTitle: "输入",
                outputTitle: "遮蔽后",
                placeholder: "输入要遮蔽的字符串…",
                input: $workspace.input,
                output: workspace.output,
                outputProcessingText: workspace.isProcessing ? "正在更新遮蔽结果…" : nil,
                outputPresentation: workspace.usesNativeOutput ? .nativeReadOnlyText : .standard,
                inputCountPresentation: .charactersOrUTF8Size(
                    largeTextByteLimit: StringObfuscatorToolWorkspaceModel.synchronousInputByteLimit
                ),
                onClear: clear,
                clearDisabled: workspace.input.isEmpty && workspace.output.isEmpty,
                inputRenderingMode: .textKit2Viewport,
                workspaceSemantic: .securityTransformWorkspace
            )
        }
    }

    @ViewBuilder
    private var obfuscationControls: some View {
        IndexOptionGroup {
            IndexOptionLabel("保留首")
            IndexNumberInput(value: $workspace.keepFirst, range: 0...20, fieldWidth: 36)
        }

        IndexOptionGroup {
            IndexOptionLabel("保留尾")
            IndexNumberInput(value: $workspace.keepLast, range: 0...20, fieldWidth: 36)
        }

        IndexOptionGroup {
            IndexSwitch(title: "保留空格", isOn: $workspace.keepSpaces)
        }

        IndexOptionGroup {
            HStack(spacing: 6) {
                IndexOptionLabel("替换字符")
                IndexTextInput(
                    placeholder: "*",
                    text: Binding(
                        get: { workspace.replacementChar },
                        set: { workspace.setReplacementCharacter($0) }
                    ),
                    height: 30
                )
                    .frame(width: 44)
            }
        }
    }

    private func clear() {
        workspace.clear()
    }

}
