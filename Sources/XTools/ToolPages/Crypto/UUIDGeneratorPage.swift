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

/// Prototype v3 (Clay 收敛) body: one parameter card row (数量 stepper, 版本
/// segments, 上次生成 meta, 全部复制, 生成 ⌘↩) above the value row list, which
/// scrolls internally while the parameters stay put. Every generation replays
/// the staggered row pop-in.
private struct IndexUUIDWorkspaceContent: View {
    @Environment(\.toolPageEntryGeneration) private var entryGeneration
    /// Prototype v3 parameter bounds (stepper clamps 1…32).
    private static let quantityRange = 1...32

    @ObservedObject var workspace: UUIDGeneratorToolWorkspaceModel
    @State private var motionGeneration = 0

    private static let generatedTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        IndexGeneratorWorkbench(
            metaText: workspace.lastGeneratedAt.map { "上次生成 " + Self.generatedTimeFormatter.string(from: $0) },
            copyText: allValuesText,
            copySuccessToast: ToolFeedbackCopy.copiedAll(noun: "UUID"),
            rows: resultRows,
            emptyText: IndexEmptyStateCopy.noResults,
            motionGeneration: motionGeneration,
            wrapsValues: false,
            generateHelp: "生成 UUID（⌘↩）",
            shortcutEnabled: entryGeneration > 0,
            generate: generate
        ) {
            parameters
        }
        .onAppear {
            if workspace.values.isEmpty { generate() }
        }
    }

    private var parameters: some View {
        HStack(spacing: 10) {
            IndexOptionLabel("数量")
            IndexStepperInput(value: $workspace.quantity, range: Self.quantityRange)
                .onChange(of: workspace.quantity) { _ in generate() }

            IndexOptionLabel("版本")
            IndexSegmentedControl(
                items: [("v4", "v4"), ("v7", "v7")],
                selection: versionSelection
            )
            .onChange(of: workspace.version) { _ in generate() }
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
