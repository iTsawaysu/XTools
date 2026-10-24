import XToolsCore
import SwiftUI
import XToolsDesign

@MainActor
final class PasswordGeneratorToolWorkspaceModel: ObservableObject {
    struct GeneratedPassword {
        let value: String
    }

    static let key = ToolWorkspaceKey<PasswordGeneratorToolWorkspaceModel>(toolID: "generator", slot: "password") { preferences in
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

struct IndexPasswordGeneratorSegment: View {
    var body: some View {
        ToolWorkspaceHost(key: PasswordGeneratorToolWorkspaceModel.key) { workspace, _ in
            IndexPasswordGeneratorWorkspaceContent(workspace: workspace)
        }
    }
}

/// 统一壳 body（page-rollout Batch C，配方对齐 UUIDGeneratorPage）：弹性
/// 参数区（长度 + 数量 + 字符类别开关）在上，密码行列表在下并于壳级
/// `actions:` 挂「全部复制」（首个 copy 持 ⇧⌘C——.generator 形态走壳级
/// actions，⇧⌘C 挂载契约）；「生成」主操作持 ⌘↩。每次生成重播交错弹出
/// （30ms/行）。
private struct IndexPasswordGeneratorWorkspaceContent: View {
    @ObservedObject var workspace: PasswordGeneratorToolWorkspaceModel
    @State private var motionGeneration = 0

    var body: some View {
        WorkbenchSurface(
            title: nil,
            primaryAction: WorkbenchPrimaryAction(
                title: "生成",
                help: "生成密码（⌘↩）",
                perform: generate
            ),
            shape: .generator,
            actions: [
                .copy(
                    text: allPasswordsText,
                    title: "全部复制",
                    successToast: ToolFeedbackCopy.copiedAll(noun: "密码")
                )
            ],
            parameters: { parameters }
        ) {
            IndexGeneratedValueRowList(
                rows: passwordResultRows,
                emptyText: workspace.error ?? resultEmptyText,
                motionGeneration: motionGeneration,
                wrapsValues: true
            )
        }
        .onAppear {
            if !workspace.hasAttemptedGeneration { generate() }
        }
    }

    /// 弹性参数区：长度与数量都是影响当下生成的即时参数，换行承载（窄窗
    /// 不再横向滚动）。
    private var parameters: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterGroup {
                WorkbenchParameterItem("长度") {
                    IndexNumberInput(value: $workspace.length, range: 8...128)
                        .onChange(of: workspace.length) { generate() }
                }
                WorkbenchParameterItem("数量") {
                    IndexStepperInput(value: $workspace.quantity, range: 1...20)
                        .onChange(of: workspace.quantity) { generate() }
                }
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
                WorkbenchParameterItem {
                    IndexOptionSwitch(title: "排除易混淆", isOn: $workspace.excludeAmbiguous)
                        .onChange(of: workspace.excludeAmbiguous) { generate() }
                }
            }
        }
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
