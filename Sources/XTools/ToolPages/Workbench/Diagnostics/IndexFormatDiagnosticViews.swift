import SwiftUI
import XToolsCore

/// Summary and bounded safe details deliberately exclude source excerpts.
/// The same projection backs the visible detail view and its copy action.
struct IndexDiagnosticPresentation {
    // Docker supplies at most 256 facts plus one explicit omission notice.
    static let maximumDetails = 257
    static let maximumDetailCharacters = 512
    let summary: String
    let suggestion: String?
    let details: [String]
    let omittedCount: Int
    let location: String?

    init(diagnostic: FormatDiagnostic?, message: String) {
        summary = Self.bounded(message)
        suggestion = diagnostic?.suggestion.flatMap { $0.isEmpty ? nil : Self.bounded($0) }
        let sourceDetails = diagnostic?.details ?? []
        details = sourceDetails.prefix(Self.maximumDetails).map(Self.bounded)
        omittedCount = max(0, sourceDetails.count - details.count)
        location = diagnostic?.line.map { line in
            if let column = diagnostic?.column { return "第 \(line) 行，第 \(column) 列" }
            return "第 \(line) 行"
        }
    }

    var copyPayload: String {
        var lines = [summary]
        if let location { lines.append(location) }
        if let suggestion { lines.append(suggestion) }
        lines.append(contentsOf: details)
        if omittedCount > 0 { lines.append("另有 \(omittedCount) 项未展示。") }
        return lines.joined(separator: "\n")
    }

    private static func bounded(_ text: String) -> String {
        let prefix = text.prefix(maximumDetailCharacters)
        return prefix.endIndex == text.endIndex ? text : String(prefix) + "…"
    }
}

/// One stable summary row; longer guidance lives in a popover so it cannot
/// resize the editors or move their primary actions.
struct IndexDiagnosticBanner: View {
    let diagnostic: FormatDiagnostic?
    let message: String
    var tone: ToolFeedbackTone = .error
    var onLocate: (() -> Void)? = nil
    @State private var showsDetails = false

    private var presentation: IndexDiagnosticPresentation {
        IndexDiagnosticPresentation(diagnostic: diagnostic, message: message)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tone.systemImage)
                .font(.system(size: ToolMetrics.IconSize.medium, weight: .semibold))
                .foregroundStyle(tone.tint)
                .accessibilityHidden(true)
            if let line = diagnostic?.line {
                Text("行 \(line)")
                    .font(ToolTypography.monoLabel)
                    .foregroundStyle(tone.tint)
                    .fixedSize()
            }
            Text(presentation.summary)
                .font(ToolTypography.label)
                .foregroundStyle(ToolTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityLabel("\(tone.accessibilityPrefix)：\(presentation.summary)")
            Spacer(minLength: 0)
            if let onLocate {
                Button("定位", action: onLocate)
                    .buttonStyle(IndexSmallButtonStyle())
                    .accessibilityLabel("定位问题，\(presentation.location ?? "当前输入")")
            }
            Button("详情") { showsDetails.toggle() }
                .buttonStyle(IndexSmallButtonStyle())
                .accessibilityLabel("查看诊断详情")
                .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(presentation.summary).font(ToolTypography.label)
                            if let location = presentation.location {
                                Text(location).font(ToolTypography.monoLabel).foregroundStyle(tone.tint)
                            }
                            if let suggestion = presentation.suggestion {
                                Text(suggestion).font(ToolTypography.caption)
                            }
                            ForEach(Array(presentation.details.enumerated()), id: \.offset) { _, detail in
                                Text(detail).font(ToolTypography.caption)
                            }
                            if presentation.omittedCount > 0 {
                                Text("另有 \(presentation.omittedCount) 项未展示。")
                                    .font(ToolTypography.caption).foregroundStyle(ToolTheme.textSecondary)
                            }
                            IndexCopyButton(text: presentation.copyPayload, title: "复制诊断", showsIcon: false, framed: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(14)
                    }
                    .frame(width: 380, height: 250)
                }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .leading)
        .background(tone.softFill)
        .overlay(alignment: .bottom) {
            Rectangle().fill(tone.tint.opacity(0.25)).frame(height: 0.5)
        }
        .onChange(of: message) { _ in showsDetails = false }
    }
}

/// The one sanctioned container for a workbench diagnostic status row.
/// Call sites declare whether a row is currently needed and what it shows;
/// this component owns the structural decisions that regressed three times
/// when each workbench reimplemented them: conditional presence (an inactive
/// slot reserves no blank space), the bounded 36pt row, and the shared
/// diagnostic motion. Presence rides one always-mounted clipped height track
/// (the `IndexResultPresence` pattern): an `.animation(value:)` that lives
/// inside the appearing branch cannot animate its own insertion, so the
/// track itself observes the flip and reveals/collapses the row through the
/// shared diagnostic transition even when nothing upstream animates.
/// Pair it with `IndexDiagnosticBanner`.
struct IndexDiagnosticStatusSlot<Content: View>: View {
    private let isActive: Bool
    private let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        isActive: Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isActive = isActive
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            if isActive {
                content()
                    .toolTransition(ToolMotion.Transition.diagnostic, reduceMotion: reduceMotion)
            }
        }
        // One bounded status row (the banner self-bounds to 36); 0pt reserves
        // no blank space while the track itself stays mounted to animate.
        .frame(height: isActive ? 36 : 0, alignment: .top)
        .frame(maxWidth: .infinity)
        .clipped()
        .toolAnimation(ToolMotion.Preset.diagnostic, value: isActive)
    }
}
