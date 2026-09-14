import XToolsCore
import SwiftUI

@MainActor
final class PasswordGeneratorToolWorkspaceModel: ObservableObject {
    struct GeneratedPassword {
        let value: String
    }

    static let key = ToolWorkspaceKey<PasswordGeneratorToolWorkspaceModel>(toolID: "password-generator") { preferences in
        PasswordGeneratorToolWorkspaceModel(preferences: preferences)
    }

    @Published var length: Int {
        didSet { preferences.set(length, for: SensitiveToolPreferenceKeys.passwordLength) }
    }
    @Published var lower: Bool {
        didSet { preferences.set(lower, for: SensitiveToolPreferenceKeys.passwordLowercaseEnabled) }
    }
    @Published var upper: Bool {
        didSet { preferences.set(upper, for: SensitiveToolPreferenceKeys.passwordUppercaseEnabled) }
    }
    @Published var numbers: Bool {
        didSet { preferences.set(numbers, for: SensitiveToolPreferenceKeys.passwordNumbersEnabled) }
    }
    @Published var symbols: Bool {
        didSet { preferences.set(symbols, for: SensitiveToolPreferenceKeys.passwordSymbolsEnabled) }
    }
    @Published var excludeAmbiguous: Bool {
        didSet { preferences.set(excludeAmbiguous, for: SensitiveToolPreferenceKeys.passwordExcludeAmbiguous) }
    }
    @Published var quantity: Int {
        didSet { preferences.set(quantity, for: SensitiveToolPreferenceKeys.passwordQuantity) }
    }
    @Published private(set) var passwords: [GeneratedPassword] = []
    @Published private(set) var hasAttemptedGeneration = false
    @Published private(set) var error: String?

    private let preferences: ToolPreferenceStore

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        length = preferences.value(for: SensitiveToolPreferenceKeys.passwordLength)
        quantity = preferences.value(for: SensitiveToolPreferenceKeys.passwordQuantity)
        lower = preferences.value(for: SensitiveToolPreferenceKeys.passwordLowercaseEnabled)
        upper = preferences.value(for: SensitiveToolPreferenceKeys.passwordUppercaseEnabled)
        numbers = preferences.value(for: SensitiveToolPreferenceKeys.passwordNumbersEnabled)
        symbols = preferences.value(for: SensitiveToolPreferenceKeys.passwordSymbolsEnabled)
        excludeAmbiguous = preferences.value(for: SensitiveToolPreferenceKeys.passwordExcludeAmbiguous)

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
        let outcome = PasswordGenerator.generate(
            PasswordGenerator.Options(
                length: length,
                quantity: quantity,
                lower: lower,
                upper: upper,
                numbers: numbers,
                symbols: symbols,
                excludeAmbiguous: excludeAmbiguous
            )
        )
        switch outcome {
        case .produced(let values):
            error = nil
            passwords = values.map { item in
                GeneratedPassword(value: item)
            }
        case .failed(let failure):
            passwords = []
            error = failure.errorDescription
        }
    }

    private func persistCharacterRecipe() {
        preferences.set(lower, for: SensitiveToolPreferenceKeys.passwordLowercaseEnabled)
        preferences.set(upper, for: SensitiveToolPreferenceKeys.passwordUppercaseEnabled)
        preferences.set(numbers, for: SensitiveToolPreferenceKeys.passwordNumbersEnabled)
        preferences.set(symbols, for: SensitiveToolPreferenceKeys.passwordSymbolsEnabled)
    }
}

struct IndexPasswordGeneratorPage: View {
    var body: some View {
        ToolWorkspaceHost(key: PasswordGeneratorToolWorkspaceModel.key) { workspace, _ in
            IndexPasswordGeneratorWorkspaceContent(workspace: workspace)
        }
    }
}

/// Prototype v3 generator body (UUID-style): one wrapping parameter card with
/// the recipe facts and generation actions, above wrapped password rows.
private struct IndexPasswordGeneratorWorkspaceContent: View {
    @ObservedObject var workspace: PasswordGeneratorToolWorkspaceModel
    @State private var motionGeneration = 0

    var body: some View {
        IndexPage("密码生成器", subtitle: "生成网站兼容的随机密码，可设置长度与字符类别。", workspaceSemantic: .queryListWorkspace) {
            VStack(spacing: ToolMetrics.Spacing.md) {
                parameterCard

                IndexGeneratedValueRowList(
                    rows: passwordResultRows,
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
                IndexOptionLabel("长度")
                IndexNumberInput(value: $workspace.length, range: 8...128)
                    .onChange(of: workspace.length) { _ in generate() }

                IndexOptionLabel("数量")
                IndexStepperInput(value: $workspace.quantity, range: 1...20)
                    .onChange(of: workspace.quantity) { _ in generate() }

                IndexOptionSwitch(title: "a-z", isOn: $workspace.lower)
                    .onChange(of: workspace.lower) { _ in generate() }
                IndexOptionSwitch(title: "A-Z", isOn: $workspace.upper)
                    .onChange(of: workspace.upper) { _ in generate() }
                IndexOptionSwitch(title: "0-9", isOn: $workspace.numbers)
                    .onChange(of: workspace.numbers) { _ in generate() }
                IndexOptionSwitch(title: "符号", isOn: $workspace.symbols)
                    .onChange(of: workspace.symbols) { _ in generate() }
                IndexOptionSwitch(title: "排除易混淆", isOn: $workspace.excludeAmbiguous)
                    .onChange(of: workspace.excludeAmbiguous) { _ in generate() }
            }
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
                text: allPasswordsText,
                title: "全部复制",
                showsIcon: false,
                framed: true,
                successToast: ToolFeedbackCopy.copiedAll(noun: "密码")
            )

            IndexPrimaryActionButton(
                title: "生成",
                hint: "⌘↩",
                help: "生成密码（⌘↩）",
                action: generate
            )
            .keyboardShortcut(.return, modifiers: .command)
        }
        .frame(height: 30, alignment: .center)
    }

    private var allPasswordsText: String {
        workspace.passwords.map(\.value).joined(separator: "\n")
    }

    private var resultEmptyText: String {
        workspace.hasAttemptedGeneration ? IndexEmptyStateCopy.noResults : IndexEmptyStateCopy.autoGenerate("字符集")
    }

    private var passwordResultRows: [IndexGeneratedValueRow] {
        workspace.passwords.enumerated().map { offset, password in
            IndexGeneratedValueRow(
                id: "slot-\(offset)",
                value: password.value,
                copyHelp: "复制此密码"
            )
        }
    }

    private func generate() {
        workspace.generate()
        motionGeneration += 1
    }
}
