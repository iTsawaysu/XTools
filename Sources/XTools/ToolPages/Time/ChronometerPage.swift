import XToolsCore
import Foundation
import SwiftUI
import XToolsDesign

@MainActor
final class ChronometerToolWorkspaceModel: ObservableObject {
    static let key = ToolWorkspaceKey<ChronometerToolWorkspaceModel>(toolID: "chronometer") { _ in
        ChronometerToolWorkspaceModel()
    }

    @Published var chronometer = ChronometerState()
}

struct IndexChronometerPage: View {
    var body: some View {
        ToolWorkspaceHost(key: ChronometerToolWorkspaceModel.key) { _, bindings in
            IndexChronometerWorkspaceContent(chronometer: bindings.chronometer)
        }
    }
}

private struct IndexChronometerWorkspaceContent: View {
    @Binding var chronometer: ChronometerState
    @Environment(\.toolPageEntryGeneration) private var entryGeneration

    private var lapRows: [IndexScrollableKVRow] {
        chronometer.laps.enumerated().map { offset, lap in
            let lapNumber = chronometer.laps.count - offset
            return IndexScrollableKVRow(
                id: "lap-\(lapNumber)",
                key: "#\(lapNumber)",
                value: "本次 \(ChronometerFormatter.format(lap.interval)) · 累计 \(ChronometerFormatter.format(lap.split))",
                color: nil
            )
        }
    }

    private var primaryActionTitle: String {
        chronometer.isRunning ? "暂停" : (chronometer.hasElapsed ? "继续" : "开始")
    }

    private var primaryActionIcon: String {
        chronometer.isRunning ? "pause.fill" : "play.fill"
    }

    var body: some View {
        // 统一壳装配（page-rollout D2）：IndexStackedWorkbench 的两段 bands
        // 归位到 .canvas 内容区（纸几何/诊断槽职责归 WorkbenchSurface；本页
        // 无参数区与诊断，走最小壳装配）。秒表 TimelineView(.animation) 节拍
        // 与计次逻辑零改动；秒表/计次两带的 pane 头形态由共享 IndexWorkbenchPane
        // 承载（新壳 pane 件，IOPair 同款），暂停/计次/重置三钮原位保留——
        // 均非 ActionBar 六种声明动作，不迁移（等价原位）。
        IndexPage("计时器", subtitle: "秒表计时，支持计次与暂停。", layout: .scroll) {
            WorkbenchSurface(title: nil, shape: .canvas) {
                VStack(alignment: .leading, spacing: 0) {
                    IndexWorkbenchPane(title: "秒表", stretchContent: false) {
                        VStack(spacing: ToolMetrics.Spacing.sm) {
                            TimelineView(
                                .animation(minimumInterval: 0.01, paused: !chronometer.isRunning || entryGeneration == 0)
                            ) { context in
                                Text(ChronometerFormatter.format(currentTime(tick: context.date)))
                                    .font(ToolTypography.giantValueRounded)
                                    .foregroundStyle(ToolTheme.accentHover)
                                    .frame(maxWidth: .infinity)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("已用时间")
                                    .accessibilityValue(ChronometerFormatter.format(currentTime(tick: context.date)))
                            }
                            HStack(spacing: ToolMetrics.Spacing.sm) {
                                Button { toggle() } label: {
                                    Label {
                                        Text(primaryActionTitle)
                                            .toolMotionTextSwap(id: primaryActionTitle)
                                    } icon: {
                                        Image(systemName: primaryActionIcon)
                                            .toolMotionIconSwap(id: primaryActionIcon)
                                    }
                                }
                                    .buttonStyle(IndexButtonStyle(primary: true))
                                Button { _ = chronometer.recordLap(at: monotonicNow()) } label: { Text("计次") }
                                    .buttonStyle(IndexButtonStyle())
                                    .disabled(!chronometer.canRecordLap)
                                Button { reset() } label: { Label("重置", systemImage: IndexActionSymbol.reset) }
                                    .buttonStyle(IndexButtonStyle())
                                    .disabled(!chronometer.canReset)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    IndexWorkbenchPane(title: "计次记录") {
                        IndexScrollableKV(rows: lapRows, emptyText: IndexEmptyStateCopy.noRecords, copyable: false, valueMotion: .immediate)
                    }
                }
            }
        }
    }

    private func currentTime(tick _: Date) -> TimeInterval {
        chronometer.elapsed(at: monotonicNow())
    }

    private func toggle() {
        chronometer.toggle(at: monotonicNow())
    }

    private func reset() {
        chronometer.reset()
    }

    private func monotonicNow() -> TimeInterval {
        ChronometerContinuousTime.now()
    }
}

private enum ChronometerContinuousTime {
    private static let clock = ContinuousClock()
    private static let origin = clock.now

    static func now() -> TimeInterval {
        let duration = origin.duration(to: clock.now)
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
