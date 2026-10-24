import XToolsCore
import SwiftUI
import XToolsDesign

struct IndexHashTextPage: View {
    var body: some View {
        ToolWorkspaceHost(key: HashTextToolWorkspaceModel.key) { workspace, _ in
            IndexHashTextWorkspaceContent(workspace: workspace)
        }
    }
}

/// 统一壳装配（page-rollout A0）：分段控件形态的标准配方——编码分段与
/// 显式计算按钮是影响当下计算的即时参数，归弹性参数区（分段裸项不带
/// 标签，保持旧纸头观感）；清空钮归输入 pane 尾部 ActionBar，复制归输出
/// pane 尾部 ActionBar（首个 copy 同步壳级 actions 注册 ⇧⌘C）；计算中
/// 进度归输出 pane 头附件（原 resultControls 槽）。
private struct IndexHashTextWorkspaceContent: View {
    @ObservedObject var workspace: HashTextToolWorkspaceModel
    @Environment(\.pageAvailableHeight) private var pageAvailableHeight

    private var inputViewportHeight: CGFloat {
        min(148, max(104, pageAvailableHeight * 0.18))
    }

    private var resultItems: [IndexResultCardItem] {
        workspace.digests.map { item in
            IndexResultCardItem(
                id: item.algorithm.rawValue,
                label: item.name,
                value: DigestEncoding.format(item.bytes, mode: workspace.encoding),
                badgeText: item.isCompatibilityOnly ? "仅兼容" : nil,
                badgeTone: .warning,
                copyHelp: "复制此摘要"
            )
        }
    }

    private var allDigestsText: String {
        resultItems.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
    }

    private var emptyResultText: String {
        guard !workspace.input.isEmpty else {
            return "输入文本后实时显示摘要"
        }
        if workspace.usesExplicitComputation, !workspace.isComputing {
            return "内容较大，点击输入区右上角的“计算摘要”后显示结果"
        }
        return "正在计算摘要…"
    }

    private var copyAction: WorkbenchActionBarAction {
        .copy(text: allDigestsText, title: "全部复制")
    }

    var body: some View {
        IndexPage(
            "Hash 文本",
            subtitle: "计算 SHA-2、SHA-3、RIPEMD-160 摘要；SHA-1 与 MD5 仅用于兼容校验。",
            workspaceSemantic: .queryListWorkspace
        ) {
            WorkbenchSurface(title: nil, shape: .inputOutput, actions: [copyAction], parameters: { parameterFlow }) {
                WorkbenchIOPair(
                    leadingTitle: "输入",
                    trailingTitle: "摘要结果",
                    leadingActions: [
                        .clear(enabled: !workspace.input.isEmpty, onPerform: { workspace.input = "" })
                    ],
                    trailingActions: [copyAction],
                    leadingAccessory: { EmptyView() },
                    leading: { inputPane },
                    trailingAccessory: { computingStatus },
                    trailing: {
                        IndexResultSurface(content: .list(resultItems), emptyText: emptyResultText)
                    }
                )
            }
        }
    }

    /// 弹性参数区：编码分段（即时参数，随选随算）与大输入的显式计算按钮。
    private var parameterFlow: some View {
        WorkbenchParameterFlow {
            WorkbenchParameterGroup {
                WorkbenchParameterItem {
                    IndexSegmentedControl(
                        items: [
                            ("hex", "Hex"),
                            ("binary", "Binary"),
                            ("base64", "Base64"),
                            ("base64url", "Base64url")
                        ],
                        selection: $workspace.encoding,
                        density: .compact
                    )
                }
                if workspace.usesExplicitComputation {
                    WorkbenchParameterItem {
                        explicitComputationButton
                    }
                }
            }
        }
    }

    /// 输入 pane 内容：受控 AppKit 编辑器填满 pane（双栏 pane 几何）。
    private var inputPane: some View {
        IndexWorkspaceTextArea(
            placeholder: "输入要计算摘要的文本…",
            text: $workspace.input,
            minHeight: inputViewportHeight,
            fillsHeight: true,
            autoFocus: true,
            embedsFlat: true,
            workspaceSemantic: .queryListWorkspace
        )
        .workbenchFocusTarget()
    }

    private var explicitComputationButton: some View {
        Button(action: workspace.computeExplicitly) {
            IndexProgressMotionLabel(
                title: workspace.isComputing ? "计算中" : (resultItems.isEmpty ? "计算摘要" : "重新计算"),
                systemImage: "function",
                isProcessing: workspace.isComputing,
                id: workspace.isComputing
            )
            .font(ToolTypography.buttonSmall)
        }
        .buttonStyle(IndexButtonStyle(compact: true))
        .disabled(workspace.isComputing)
    }

    /// 计算中进度（原 resultControls 槽投影，pane 头附件承载）。
    @ViewBuilder
    private var computingStatus: some View {
        if !workspace.usesExplicitComputation, workspace.isComputing {
            IndexProgressLabel(message: "计算中")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在计算摘要")
        }
    }
}
