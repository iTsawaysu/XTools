import XToolsCore
import SwiftUI

@MainActor
final class TokenGeneratorToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<TokenGeneratorToolWorkspaceModel>(toolID: "token-generator") { preferences in
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

struct IndexTokenPage: View {
    var body: some View {
        ToolWorkspaceHost(key: TokenGeneratorToolWorkspaceModel.key) { workspace, _ in
            IndexTokenWorkspaceContent(workspace: workspace)
        }
    }
}

/// Prototype v3 generator body (UUID-style): one wrapping parameter card with
/// the recipe facts and generation actions, above wrapped value rows. Token
/// values reach 512 characters, so rows wrap instead of truncating.
private struct IndexTokenWorkspaceContent: View {
    @ObservedObject var workspace: TokenGeneratorToolWorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motionGeneration = 0

    var body: some View {
        IndexPage("Token 生成器", subtitle: "使用系统安全随机数生成 Base64url、Hex 或字符集 Token。", workspaceSemantic: .queryListWorkspace) {
            VStack(spacing: ToolMetrics.Spacing.md) {
                parameterCard

                IndexGeneratedValueRowList(
                    rows: resultRows,
                    emptyText: workspace.error ?? resultEmptyText,
                    motionGeneration: motionGeneration,
                    wrapsValues: true
                )
                .indexSurface(.card, fill: ToolTheme.panelBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if !workspace.hasAttemptedGeneration { generate() }
            else if motionGeneration == 0 {
                motionGeneration += 1
            }
        }
    }

    private var parameterCard: some View {
        HStack(alignment: .top, spacing: ToolMetrics.Spacing.base) {
            IndexFlowLayout(spacing: ToolMetrics.Spacing.sm, lineSpacing: ToolMetrics.Spacing.sm) {
                IndexOptionLabel("格式")
                IndexSegmentedControl(
                    items: [
                        (TokenGenerationMode.characterSet.rawValue, "字符集"),
                        (TokenGenerationMode.base64URL.rawValue, "Base64url"),
                        (TokenGenerationMode.hex.rawValue, "Hex")
                    ],
                    selection: modeBinding
                )
                .onChange(of: workspace.mode) { _ in generate() }

                IndexOptionLabel(workspace.mode == .characterSet ? "长度" : "字节数")
                IndexNumberInput(value: $workspace.length, range: 1...512)
                    .onChange(of: workspace.length) { _ in generate() }

                IndexOptionLabel("数量")
                IndexStepperInput(value: $workspace.quantity, range: 1...20)
                    .onChange(of: workspace.quantity) { _ in generate() }

                if workspace.mode == .characterSet {
                    IndexOptionSwitch(title: "a-z", isOn: $workspace.lower)
                        .onChange(of: workspace.lower) { _ in generate() }
                    IndexOptionSwitch(title: "A-Z", isOn: $workspace.upper)
                        .onChange(of: workspace.upper) { _ in generate() }
                    IndexOptionSwitch(title: "0-9", isOn: $workspace.numbers)
                        .onChange(of: workspace.numbers) { _ in generate() }
                    IndexOptionSwitch(title: "符号", isOn: $workspace.symbols)
                        .onChange(of: workspace.symbols) { _ in generate() }
                }
            }
            .toolAnimation(ToolMotion.Preset.orderedContent, value: workspace.mode)
            .frame(maxWidth: .infinity, alignment: .leading)

            generationActions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .indexSurface(.card, fill: ToolTheme.panelBackground)
    }

    /// Shares the parameter row's 30pt height so the actions center against
    /// the controls instead of riding the wrapped flow's full height.
    private var generationActions: some View {
        HStack(spacing: 6) {
            IndexCopyButton(
                text: allTokensText,
                title: "全部复制",
                showsIcon: false,
                framed: true,
                successToast: ToolFeedbackCopy.copiedAll(noun: "Token")
            )

            IndexPrimaryActionButton(
                title: "生成",
                hint: "⌘↩",
                help: "生成 Token（⌘↩）",
                action: generate
            )
            .keyboardShortcut(.return, modifiers: .command)
        }
        .frame(height: 30, alignment: .center)
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
