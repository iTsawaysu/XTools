import XToolsCore
import Foundation
import SwiftUI

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

    private var primaryActionHelp: String {
        if chronometer.isRunning { return "暂停计时" }
        return chronometer.hasElapsed ? "继续计时" : "开始计时"
    }

    var body: some View {
        IndexPage("计时器", subtitle: "秒表计时，支持计次与暂停。", layout: .scroll) {
            IndexPanel("秒表") {
                VStack(spacing: 8) {
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
                    HStack(spacing: 8) {
                        IndexPrimaryActionButton(
                            title: primaryActionTitle,
                            systemImage: primaryActionIcon,
                            help: primaryActionHelp,
                            action: toggle
                        )
                        Button { _ = chronometer.recordLap(at: monotonicNow()) } label: { Text("计次") }
                            .buttonStyle(IndexButtonStyle())
                            .disabled(!chronometer.canRecordLap)
                        Button { reset() } label: { Label("重置", systemImage: IndexActionSymbol.reset) }
                            .buttonStyle(IndexButtonStyle())
                            .disabled(!chronometer.canReset)
                    }
                }
            }
            .withoutDiagnosticStatusSlot()
            // SPEC §P6：计次记录可无限增长，结果面板吃满剩余高度，超长在面板内部滚动。
            IndexPanel("计次记录") {
                IndexScrollableKV(rows: lapRows, emptyText: IndexEmptyStateCopy.noRecords, copyable: false, valueMotion: .immediate)
            }
            .verticallyFilling()
            .withoutDiagnosticStatusSlot()
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
