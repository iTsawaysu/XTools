import XToolsCore
import SwiftUI
import XToolsDesign

@MainActor
final class TokenGeneratorToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<TokenGeneratorToolWorkspaceModel>(toolID: "generator", slot: "token") { preferences in
        TokenGeneratorToolWorkspaceModel(preferences: preferences)
    }

    @Published var mode: TokenGenerationMode {
        didSet { preferences.set(mode, for: SensitiveToolPreferenceKeys.tokenMode) }
    }
    @Published var length: Int {
        didSet { preferences.set(length, for: SensitiveToolPreferenceKeys.tokenLength) }
    }
    @Published var lower: Bool {
        didSet { preferences.set(lower, for: SensitiveToolPreferenceKeys.tokenLowercaseEnabled) }
    }
    @Published var upper: Bool {
        didSet { preferences.set(upper, for: SensitiveToolPreferenceKeys.tokenUppercaseEnabled) }
    }
    @Published var numbers: Bool {
        didSet { preferences.set(numbers, for: SensitiveToolPreferenceKeys.tokenNumbersEnabled) }
    }
    @Published var symbols: Bool {
        didSet { preferences.set(symbols, for: SensitiveToolPreferenceKeys.tokenSymbolsEnabled) }
    }
    @Published var quantity: Int {
        didSet { preferences.set(quantity, for: SensitiveToolPreferenceKeys.tokenQuantity) }
    }
    @Published private(set) var tokens: [String] = []
    @Published private(set) var hasAttemptedGeneration = false
    @Published private(set) var error: String?

    var options: TokenGenerator.Options {
        switch mode {
        case .base64URL:
            return .base64URL(byteCount: length, quantity: quantity)
        case .hex:
            return .hex(byteCount: length, quantity: quantity)
        case .characterSet:
            return .characterSet(
                length: length,
                quantity: quantity,
                lower: lower,
                upper: upper,
                numbers: numbers,
                symbols: symbols
            )
        }
    }

    private let preferences: ToolPreferenceStore

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        mode = preferences.value(for: SensitiveToolPreferenceKeys.tokenMode)
        length = preferences.value(for: SensitiveToolPreferenceKeys.tokenLength)
        quantity = preferences.value(for: SensitiveToolPreferenceKeys.tokenQuantity)
        lower = preferences.value(for: SensitiveToolPreferenceKeys.tokenLowercaseEnabled)
        upper = preferences.value(for: SensitiveToolPreferenceKeys.tokenUppercaseEnabled)
        numbers = preferences.value(for: SensitiveToolPreferenceKeys.tokenNumbersEnabled)
        symbols = preferences.value(for: SensitiveToolPreferenceKeys.tokenSymbolsEnabled)

        if !lower && !upper && !numbers && !symbols {
            lower = true
            upper = true
            numbers = true
            symbols = false
            persistCharacterRecipe()
        }
    }

    func generate() {
        hasAttemptedGeneration = true
        let outcome = TokenGenerator.generate(options)
        switch outcome {
        case .produced(let values):
            error = nil
            tokens = values
        case .failed(let failure):
            tokens = []
            error = failure.errorDescription
        }
    }

    private func persistCharacterRecipe() {
        preferences.set(lower, for: SensitiveToolPreferenceKeys.tokenLowercaseEnabled)
        preferences.set(upper, for: SensitiveToolPreferenceKeys.tokenUppercaseEnabled)
        preferences.set(numbers, for: SensitiveToolPreferenceKeys.tokenNumbersEnabled)
        preferences.set(symbols, for: SensitiveToolPreferenceKeys.tokenSymbolsEnabled)
    }
}

struct IndexTokenGeneratorSegment: View {
    var body: some View {
        ToolWorkspaceHost(key: TokenGeneratorToolWorkspaceModel.key) { workspace, _ in
            IndexTokenWorkspaceContent(workspace: workspace)
        }
    }
}

/// 统一壳 body（page-rollout Batch C，配方对齐 UUIDGeneratorPage）：弹性
/// 参数区（格式分段 + 长度/字节数 + 数量 + 字符集类别开关，条件组随模式
/// 在场）在上，生成值行列表在下并于壳级 `actions:` 挂「全部复制」（首个
/// copy 持 ⇧⌘C——.generator 形态走壳级 actions，⇧⌘C 挂载契约）；「生成」
/// 主操作持 ⌘↩。每次生成重播交错弹出（30ms/行）。
private struct IndexTokenWorkspaceContent: View {
    @ObservedObject var workspace: TokenGeneratorToolWorkspaceModel
    @State private var motionGeneration = 0

    var body: some View {
        WorkbenchSurface(
            title: nil,
            primaryAction: WorkbenchPrimaryAction(
                title: "生成",
                help: "生成 Token（⌘↩）",
                perform: generate
            ),
            shape: .generator,
            actions: [
                .copy(
                    text: allTokensText,
                    title: "全部复制",
                    successToast: ToolFeedbackCopy.copiedAll(noun: "Token")
                )
            ],
            parameters: { parameters }
        ) {
            IndexGeneratedValueRowList(
                rows: resultRows,
                emptyText: workspace.error ?? resultEmptyText,
                motionGeneration: motionGeneration,
                wrapsValues: true
            )
        }
        .onAppear {
            if !workspace.hasAttemptedGeneration { generate() }
        }
    }

    /// 弹性参数区：配方与数量都是影响当下生成的即时参数，换行承载（窄窗
    /// 不再横向滚动）；字符集类别开关仅字符集模式在场（旧壳同条件）。
    private var parameters: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterGroup {
                WorkbenchParameterItem("格式") {
                    IndexSegmentedControl(
                        items: [
                            (TokenGenerationMode.characterSet.rawValue, "字符集"),
                            (TokenGenerationMode.base64URL.rawValue, "Base64url"),
                            (TokenGenerationMode.hex.rawValue, "Hex")
                        ],
                        selection: modeBinding
                    )
                    .onChange(of: workspace.mode) { generate() }
                }
                WorkbenchParameterItem(workspace.mode == .characterSet ? "长度" : "字节数") {
                    IndexNumberInput(value: $workspace.length, range: 1...512)
                        .onChange(of: workspace.length) { generate() }
                }
                WorkbenchParameterItem("数量") {
                    IndexStepperInput(value: $workspace.quantity, range: 1...20)
                        .onChange(of: workspace.quantity) { generate() }
                }
                if workspace.mode == .characterSet {
                    WorkbenchParameterItem {
                        IndexOptionSwitch(title: "a-z", isOn: $workspace.lower)
                            .onChange(of: workspace.lower) { generate() }
                    }
                    WorkbenchParameterItem {
                        IndexOptionSwitch(title: "A-Z", isOn: $workspace.upper)
                            .onChange(of: workspace.upper) { generate() }
                    }
                    WorkbenchParameterItem {
                        IndexOptionSwitch(title: "0-9", isOn: $workspace.numbers)
                            .onChange(of: workspace.numbers) { generate() }
                    }
                    WorkbenchParameterItem {
                        IndexOptionSwitch(title: "符号", isOn: $workspace.symbols)
                            .onChange(of: workspace.symbols) { generate() }
                    }
                }
            }
        }
        .toolAnimation(ToolMotion.Preset.orderedContent, value: workspace.mode)
    }

    private var modeBinding: Binding<String> {
        Binding(
            get: { workspace.mode.rawValue },
            set: { workspace.mode = TokenGenerationMode(rawValue: $0) ?? .characterSet }
        )
    }

    private var allTokensText: String {
        workspace.tokens.joined(separator: "\n")
    }

    private var resultEmptyText: String {
        workspace.hasAttemptedGeneration ? IndexEmptyStateCopy.noResults : IndexEmptyStateCopy.autoGenerate("格式")
    }

    private var resultRows: [IndexGeneratedValueRow] {
        workspace.tokens.enumerated().map { offset, token in
            IndexGeneratedValueRow(
                id: "slot-\(offset)",
                value: token,
                copyHelp: "复制此 Token"
            )
        }
    }

    private func generate() {
        workspace.generate()
        motionGeneration += 1
    }
}
