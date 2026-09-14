import XToolsCore
import SwiftUI

struct IndexHashTextPage: View {
    var body: some View {
        ToolWorkspaceHost(key: HashTextToolWorkspaceModel.key) { workspace, _ in
            IndexHashTextWorkspaceContent(workspace: workspace)
        }
    }
}

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

    var body: some View {
        IndexPage(
            "Hash 文本",
            subtitle: "计算 SHA-2、SHA-3、RIPEMD-160 摘要；SHA-1 与 MD5 仅用于兼容校验。",
            workspaceSemantic: .boundedLongTextInput
        ) {
            IndexActionBar {
                IndexSegmentedControl(
                    items: [
                        ("hex", "Hex"),
                        ("binary", "Binary"),
                        ("base64", "Base64"),
                        ("base64url", "Base64url")
                    ],
                    selection: $workspace.encoding
                )
            }
            IndexPanel("输入") {
                IndexWorkspaceTextArea(
                    placeholder: "输入要计算摘要的文本…",
                    text: $workspace.input,
                    minHeight: inputViewportHeight,
                    autoFocus: true,
                    workspaceSemantic: .boundedLongTextInput
                )
            } accessory: {
                HStack(spacing: 8) {
                    if workspace.usesExplicitComputation {
                        explicitComputationButton
                    }

                    IndexClearButton(isDisabled: workspace.input.isEmpty) {
                        workspace.input = ""
                    }
                }
            }
            .withoutDiagnosticStatusSlot()
            // 八行摘要属于短派生结果，自然展开并按可用宽度换行。
            IndexPanel("摘要结果") {
                IndexDerivedResultCardList(items: resultItems, emptyText: emptyResultText)
            } accessory: {
                resultPanelAccessory
            }
            .withoutDiagnosticStatusSlot()
        }
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
        .buttonStyle(IndexSmallButtonStyle())
        .disabled(workspace.isComputing)
        .help(workspace.isComputing ? "正在计算摘要" : "计算当前大文本的全部摘要")
    }

    @ViewBuilder
    private var resultPanelAccessory: some View {
        HStack(spacing: 8) {
            if !workspace.usesExplicitComputation, workspace.isComputing {
                IndexProgressLabel(message: "计算中")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在计算摘要")
            }

            IndexCopyButton(text: allDigestsText, title: "全部复制")
        }
    }
}
