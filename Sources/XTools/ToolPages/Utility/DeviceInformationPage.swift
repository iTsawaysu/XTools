import AppKit
import SwiftUI

struct IndexDeviceInfoPage: View {
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
            IndexPanel("macOS 设备信息") {
                ScrollView {
                    IndexKV(rows: rows, emptyText: "加载设备信息中…", copyable: true)
                }
            } accessory: {
                HStack(spacing: 8) {
                    Button {
                        session.refresh()
                    } label: {
                        Label("刷新", systemImage: IndexActionSymbol.refresh)
                            .font(ToolTypography.buttonSmall)
                    }
                    .buttonStyle(IndexSmallButtonStyle())
                    .help("刷新设备信息")
                    .accessibilityLabel("刷新设备信息")

                    IndexCopyButton(text: copySummary, title: "复制全部")
                }
            }
            .verticallyFilling()
            .withoutDiagnosticStatusSlot()
        }
        .onReceive(screenParametersChanged) { _ in
            session.refresh()
        }
    }

    private var screenParametersChanged: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
    }
}
