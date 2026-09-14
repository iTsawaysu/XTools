import XToolsCore
import SwiftUI

@MainActor
final class UUIDGeneratorToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<UUIDGeneratorToolWorkspaceModel>(toolID: "uuid-generator") { preferences in
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

struct IndexUUIDPage: View {
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
        IndexPage("UUID 生成器", subtitle: "批量生成 UUID v4 或按时间排序的 UUID v7，支持单个复制与全部复制。", workspaceSemantic: .queryListWorkspace) {
            VStack(spacing: ToolMetrics.Spacing.md) {
                parameterBar

                IndexGeneratedValueRowList(
                    rows: resultRows,
                    emptyText: IndexEmptyStateCopy.noResults,
                    motionGeneration: motionGeneration
                )
                .indexSurface(.card, fill: ToolTheme.panelBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if workspace.values.isEmpty {
                generate()
            } else if motionGeneration == 0 {
                // Session-restored values: replay the arrival pop once.
                motionGeneration += 1
            }
        }
    }

    private var parameterBar: some View {
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

            Spacer(minLength: ToolMetrics.Spacing.md)

            if let lastGeneratedAt = workspace.lastGeneratedAt {
                Text("上次生成 " + Self.generatedTimeFormatter.string(from: lastGeneratedAt))
                    .font(ToolTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(ToolTheme.textTertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            IndexCopyButton(
                text: allValuesText,
                title: "全部复制",
                showsIcon: false,
                successToast: ToolFeedbackCopy.copiedAll(noun: "UUID")
            )

            IndexPrimaryActionButton(
                title: "生成",
                hint: "⌘↩",
                help: "生成 UUID（⌘↩）",
                action: generate
            )
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .indexSurface(.card, fill: ToolTheme.panelBackground)
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
