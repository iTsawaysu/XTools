import XToolsCore
import SwiftUI

@MainActor
final class ChmodToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<ChmodToolWorkspaceModel>(toolID: "chmod-calculator") { _ in
        ChmodToolWorkspaceModel()
    }

    @Published private(set) var mode: ChmodMode
    @Published private(set) var octalDraft: String
    @Published private(set) var error: String?

    init(mode: ChmodMode = .standard644) {
        self.mode = mode
        octalDraft = mode.octalString
    }

    func updateOctalDraft(_ draft: String) {
        octalDraft = draft

        do {
            mode = try ChmodMode(octal: draft)
            error = nil
        } catch let issue {
            self.error = issue.localizedDescription
        }
    }

    func set(_ value: Bool, for keyPath: WritableKeyPath<ChmodMode, Bool>) {
        var updated = mode
        updated[keyPath: keyPath] = value
        mode = updated
        octalDraft = updated.octalString
        error = nil
    }

    var u1: Bool {
        get { mode.owner.execute }
        set { set(newValue, for: \ChmodMode.owner.execute) }
    }

    var o4: Bool {
        get { mode.other.read }
        set { set(newValue, for: \ChmodMode.other.read) }
    }
}

struct IndexChmodPage: View {
    var body: some View {
        ToolWorkspaceHost(key: ChmodToolWorkspaceModel.key) { workspace, _ in
            IndexChmodWorkspaceContent(workspace: workspace)
        }
    }
}

private struct IndexChmodWorkspaceContent: View {
    @ObservedObject var workspace: ChmodToolWorkspaceModel

    private var octalBinding: Binding<String> {
        Binding(
            get: { workspace.octalDraft },
            set: workspace.updateOctalDraft
        )
    }

    var body: some View {
        IndexPage("Chmod 计算器", subtitle: "在八进制与 rwx（含特殊权限位）之间双向换算。", workspaceSemantic: .naturalHeightShortResultPanel) {
            IndexPanel("八进制权限") {
                IndexTextInput(placeholder: "644 或 4755", text: octalBinding, height: 44, alignment: .center)
                    .font(ToolTypography.valueMedium)
                    .accessibilityLabel("Chmod 八进制权限")
                    .accessibilityHint("输入三位 rwx 权限或四位特殊权限模式")
                    .indexWorkspaceDiagnostic(workspace.error)
            }

            IndexPanel("权限矩阵") {
                VStack(alignment: .leading, spacing: 14) {
                    chmodRow(
                        "所有者",
                        r: permissionBinding(\ChmodMode.owner.read),
                        w: permissionBinding(\ChmodMode.owner.write),
                        x: permissionBinding(\ChmodMode.owner.execute)
                    )
                    chmodRow(
                        "所属组",
                        r: permissionBinding(\ChmodMode.group.read),
                        w: permissionBinding(\ChmodMode.group.write),
                        x: permissionBinding(\ChmodMode.group.execute)
                    )
                    chmodRow(
                        "其他",
                        r: permissionBinding(\ChmodMode.other.read),
                        w: permissionBinding(\ChmodMode.other.write),
                        x: permissionBinding(\ChmodMode.other.execute)
                    )

                    Divider().overlay(ToolTheme.border)

                    IndexFlowLayout(spacing: 14, lineSpacing: 8) {
                        IndexOptionSwitch(title: "setuid", style: .standalone, isOn: permissionBinding(\ChmodMode.setuid))
                            .help("显示所有者 s/S")
                            .accessibilityHint("控制 setuid 特殊权限位")
                        IndexOptionSwitch(title: "setgid", style: .standalone, isOn: permissionBinding(\ChmodMode.setgid))
                            .help("显示所属组 s/S")
                            .accessibilityHint("控制 setgid 特殊权限位")
                        IndexOptionSwitch(title: "sticky", style: .standalone, isOn: permissionBinding(\ChmodMode.sticky))
                            .help("显示其他用户 t/T")
                            .accessibilityHint("控制 sticky 特殊权限位")
                    }
                }
            }

            IndexPanel("结果") {
                VStack(spacing: 8) {
                    Text(workspace.mode.octalString)
                        .font(ToolTypography.heroValue)
                        .foregroundStyle(ToolTheme.accentHover)
                        .textSelection(.enabled)
                        .toolMotionTextSwap(id: workspace.mode.octalString)
                    Text("chmod \(workspace.mode.octalString)  ·  \(workspace.mode.symbolicString)")
                        .font(ToolTypography.monoCaption)
                        .foregroundStyle(ToolTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .toolMotionTextSwap(id: workspace.mode.symbolicString)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, ToolMetrics.Spacing.lg)
            } accessory: {
                IndexCopyButton(text: workspace.mode.octalString, title: "复制八进制", iconOnly: true)
            }
        }
    }

    private func permissionBinding(_ keyPath: WritableKeyPath<ChmodMode, Bool>) -> Binding<Bool> {
        Binding(
            get: { workspace.mode[keyPath: keyPath] },
            set: { workspace.set($0, for: keyPath) }
        )
    }

    private func chmodRow(_ title: String, r: Binding<Bool>, w: Binding<Bool>, x: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(ToolTypography.bodyPlain)
                .foregroundStyle(ToolTheme.textSecondary)
                .frame(width: 70, alignment: .leading)
            IndexOptionSwitch(title: "读 r", style: .standalone, isOn: r)
            IndexOptionSwitch(title: "写 w", style: .standalone, isOn: w)
            IndexOptionSwitch(title: "执行 x", style: .standalone, isOn: x)
        }
    }
}
