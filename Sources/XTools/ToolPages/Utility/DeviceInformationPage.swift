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
        IndexPage("设备信息", subtitle: "读取 macOS 系统、硬件与显示器信息。", workspaceSemantic: .queryListWorkspace) {
            IndexResultWorkbench(title: "macOS 设备信息") {
                HStack(spacing: ToolMetrics.Spacing.sm) {
                    Button {
                        session.refresh()
                    } label: {
                        Label("刷新", systemImage: IndexActionSymbol.refresh)
                            .font(ToolTypography.buttonSmall)
                    }
                    .buttonStyle(IndexButtonStyle(compact: true))
                    .accessibilityLabel("刷新设备信息")

                    IndexCopyButton(text: copySummary, title: "复制全部")
                }
            } content: {
                ScrollView {
                    IndexKV(rows: rows, emptyText: "加载设备信息中…", copyable: true)
                }
            }
        }
        .onReceive(screenParametersChanged) { _ in
            if entryGeneration > 0 { session.refresh() }
        }
        .onAppear { session.enterPage(generation: entryGeneration) }
        .onChange(of: entryGeneration) { generation in
            session.enterPage(generation: generation)
        }
    }

    private var screenParametersChanged: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
    }
}
