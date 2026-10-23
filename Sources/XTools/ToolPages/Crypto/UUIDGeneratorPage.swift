import XToolsCore
import SwiftUI
import XToolsDesign

@MainActor
final class UUIDGeneratorToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<UUIDGeneratorToolWorkspaceModel>(toolID: "generator", slot: "uuid") { preferences in
        UUIDGeneratorToolWorkspaceModel(preferences: preferences)
    }

    @Published var version: UUIDGenerationVersion {
        didSet { preferences.set(version, for: SensitiveToolPreferenceKeys.uuidVersion) }
    }
    @Published var quantity: Int {
        didSet { preferences.set(quantity, for: SensitiveToolPreferenceKeys.uuidQuantity) }
    }
    @Published private(set) var values: [String] = []
    @Published private(set) var error: String?
    @Published private(set) var lastGeneratedAt: Date?

    private let preferences: ToolPreferenceStore
    private var generator: UUIDGenerator

    init(preferences: ToolPreferenceStore) {
        self.preferences = preferences
        version = preferences.value(for: SensitiveToolPreferenceKeys.uuidVersion)
        quantity = preferences.value(for: SensitiveToolPreferenceKeys.uuidQuantity)
        generator = UUIDGenerator()
    }

    func generate() {
        do {
            values = try generator.generate(version, quantity: quantity)
            error = nil
        } catch let failure as UUIDGenerator.Failure {
            values = []
            error = failure.errorDescription
        } catch {
            values = []
            self.error = UUIDGenerator.Failure.randomSourceUnavailable.errorDescription
        }
        lastGeneratedAt = Date()
    }
}

struct IndexUUIDGeneratorSegment: View {
    var body: some View {
        ToolWorkspaceHost(key: UUIDGeneratorToolWorkspaceModel.key) { workspace, _ in
            IndexUUIDWorkspaceContent(workspace: workspace)
        }
    }
}

/// 统一壳 body（unified-workbench B2）：弹性参数区（条数 stepper + 版本
/// 分段 + 标题行「上次生成」meta 与「生成 ⌘↩」主操作）在上，生成值行
/// 列表在下并于内容区底部挂「全部复制」（首个 copy 持 ⇧⌘C）；行列表
/// 内部滚动而参数行保持固定。每次生成重播交错弹出（30ms/行）。
private struct IndexUUIDWorkspaceContent: View {
    @ObservedObject var workspace: UUIDGeneratorToolWorkspaceModel
    @State private var motionGeneration = 0

    /// 批量条数范围（PRD 决策 10：默认 10、1–100；偏好键同步持有）。
    private static let quantityRange = 1...100

    private static let generatedTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        WorkbenchSurface(
            title: nil,
            primaryAction: WorkbenchPrimaryAction(
                title: "生成",
                help: "生成 UUID（⌘↩）",
                perform: generate
            ),
            shape: .generator,
            actions: [
                .copy(
                    text: allValuesText,
                    title: "全部复制",
                    successToast: ToolFeedbackCopy.copiedAll(noun: "UUID")
                )
            ],
            titleAccessory: { generationMeta },
            parameters: { parameters }
        ) {
            IndexGeneratedValueRowList(
                rows: resultRows,
                emptyText: IndexEmptyStateCopy.noResults,
                motionGeneration: motionGeneration,
                wrapsValues: false
            )
        }
        .onAppear {
            if workspace.values.isEmpty { generate() }
        }
    }

    /// 标题行次级信息（原 44pt 纸头的 metaText 投影）。
    @ViewBuilder
    private var generationMeta: some View {
        if let lastGeneratedAt = workspace.lastGeneratedAt {
            Text("上次生成 " + Self.generatedTimeFormatter.string(from: lastGeneratedAt))
                .font(ToolTypography.caption)
                .monospacedDigit()
                .foregroundStyle(ToolTheme.textTertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// 弹性参数区：条数与版本都是影响当下生成的即时参数，换行承载
    /// （窄窗不再横向滚动）。
    private var parameters: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterGroup {
                WorkbenchParameterItem("条数") {
                    IndexStepperInput(value: $workspace.quantity, range: Self.quantityRange)
                        .onChange(of: workspace.quantity) { generate() }
                }
                WorkbenchParameterItem("版本") {
                    IndexSegmentedControl(
                        items: [("v4", "v4"), ("v7", "v7")],
                        selection: versionSelection
                    )
                    .onChange(of: workspace.version) { generate() }
                }
            }
        }
    }

    private var allValuesText: String {
        workspace.values.joined(separator: "\n")
    }

    private var versionSelection: Binding<String> {
        Binding(
            get: { workspace.version.rawValue },
            set: { workspace.version = UUIDGenerationVersion(rawValue: $0) ?? .v4 }
        )
    }

    private var resultRows: [IndexGeneratedValueRow] {
        workspace.values.enumerated().map { offset, value in
            IndexGeneratedValueRow(
                id: "slot-\(offset)",
                value: value,
                copyHelp: "复制此 UUID"
            )
        }
    }

    private func generate() {
        workspace.generate()
        motionGeneration += 1
    }
}
