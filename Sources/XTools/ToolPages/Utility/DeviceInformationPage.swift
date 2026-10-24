import AppKit
import SwiftUI
import XToolsDesign

struct IndexDeviceInfoPage: View {
    @Environment(\.toolPageEntryGeneration) private var entryGeneration
    @StateObject private var session = DeviceInformationSession()

    private var rows: [(String, String, Color?)] {
        DeviceInformationProjection.fields(from: session.snapshot).map { field in
            (field.label, field.value, nil)
        }
    }

    private var copySummary: String {
        DeviceInformationProjection.copySummary(from: session.snapshot)
    }

    var body: some View {
        // 统一壳装配（page-rollout D3）：.result 形态，「刷新」是页面级动作
        // 归标题行 titleAccessory（旧纸头 controls 槽原位等价）；「复制全部」
        // 走壳级 actions 的 .copy（.result 标准挂载点 = 内容区底部 ActionBar，
        // 首个 copy 持 ⇧⌘C——快捷键为新增能力，对照表标注授权）；KV 行内
        // 复制与屏变刷新生命周期逐字保留。
        IndexPage("设备信息", subtitle: "读取 macOS 系统、硬件与显示器信息。", workspaceSemantic: .queryListWorkspace) {
            WorkbenchSurface(
                title: "macOS 设备信息",
                shape: .result,
                actions: [
                    .copy(text: copySummary, title: "复制全部")
                ],
                titleAccessory: { refreshButton }
            ) {
                ScrollView {
                    IndexKV(rows: rows, emptyText: "加载设备信息中…", copyable: true)
                }
            }
        }
        .onReceive(screenParametersChanged) { _ in
            if entryGeneration > 0 { session.refresh() }
        }
        .onAppear { session.enterPage(generation: entryGeneration) }
        .onChange(of: entryGeneration) {
            session.enterPage(generation: entryGeneration)
        }
    }

    private var refreshButton: some View {
        Button {
            session.refresh()
        } label: {
            Label("刷新", systemImage: IndexActionSymbol.refresh)
                .font(ToolTypography.buttonSmall)
        }
        .buttonStyle(IndexButtonStyle(compact: true))
        .accessibilityLabel("刷新设备信息")
    }

    private var screenParametersChanged: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
    }
}
